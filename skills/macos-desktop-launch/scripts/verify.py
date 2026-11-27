#!/usr/bin/env python3
"""macOS 桌面上线检查。oss --write-test 会覆盖指定前缀的 ci-test.txt；其他命令只读。"""
import argparse
import getpass
import http.client
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

OSS_SECRETS = {"OSS_ACCESS_KEY_ID", "OSS_ACCESS_KEY_SECRET"}
SIGNING = {"MACOS_CERT_P12_BASE64", "MACOS_CERT_P12_PASSWORD",
           "NOTARY_KEY_P8_BASE64", "NOTARY_KEY_ID", "NOTARY_ISSUER_ID"}


def _load_oss_tools():
    tool_path = Path(__file__).resolve().parents[2] / "aliyun-oss-tools/scripts/oss_verify.py"
    spec = importlib.util.spec_from_file_location("aliyun_oss_verify", tool_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


OSS_TOOLS = _load_oss_tools()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args, **kwargs):
    return subprocess.check_output(args, **kwargs)


def gh(*args, **kwargs):
    return json.loads(run("gh", *args, **kwargs))


def read_json(file):
    return json.loads(Path(file).read_text())


def project(p):
    opts = gh("variable", "list", "-R", p.repo, "--env", "production", "--json", "name,value")
    values = {v["name"]: v["value"] for v in opts}
    need(values.get("OSS_BUCKET") == p.bucket, "production OSS_BUCKET 与目标不符")
    need(values.get("OSS_ENDPOINT") == p.endpoint, "production OSS_ENDPOINT 与目标不符")
    if p.cmd == "secrets":
        required = OSS_SECRETS | SIGNING
        if p.mode == "deploy":
            required = required | {"DEPLOY_SSH_KEY"}
            need(all(values.get(k) for k in ("DEPLOY_HOST", "DEPLOY_KNOWN_HOSTS")), "缺清单部署变量")
        have = {s["name"] for s in gh("secret", "list", "-R", p.repo, "--env", "production", "--json", "name")}
        missing = sorted(required - have)
        need(not missing, "缺 production Secret：" + ", ".join(missing))


def vault(p):
    refs = read_json(p.refs)
    fields = ("ak_id", "ak_secret", "p12", "p12_password", "p8", "key_id", "issuer_id")
    for field in fields:
        ref = refs.get(field, "")
        need(isinstance(ref, str) and ref.startswith("op://"), "缺少 1Password 引用：" + field)
        need(bool(run("op", "read", ref)), "1Password 项为空：" + field)
        print(field, "可读取")


def identity_scope(p):
    OSS_TOOLS.check_policy(p)


def portal_token(p):
    need(sys.stdin.isatty(), "请在本机交互终端输入门户凭据")
    token = getpass.getpass("门户使用的 GitHub token（隐藏输入）：")
    need(token, "未提供门户身份")
    env = dict(os.environ, GH_TOKEN=token)
    result = gh("api", f"repos/{p.repo}/actions/workflows?per_page=1", env=env)
    need("total_count" in result, "门户身份无法读取目标 Actions")
    print("已确认门户身份可读取仓库 Actions；实际调度在发布时验证。")


def oss(p):
    OSS_TOOLS.probe_oss(
        p,
        stdin=sys.stdin,
        getpass_fn=getpass.getpass,
        connection_cls=http.client.HTTPSConnection,
    )


def prs(p):
    for url in p.urls:
        data = gh("pr", "view", url, "--json", "url,state,baseRefName,isDraft")
        need(data["baseRefName"] == p.base, "PR 目标分支不符：" + url)
        if p.stage == "opened":
            need(data["state"] in ("OPEN", "MERGED"), "PR 已关闭：" + url)
        elif p.stage == "ready":
            need(data["state"] == "OPEN" and not data["isDraft"], "PR 未就绪：" + url)
            run("gh", "pr", "checks", url, "--required")
        else:
            need(data["state"] == "MERGED", "PR 尚未合并：" + url)
        print(p.stage, url)


def registration(p):
    services = read_json(p.config)["services"]
    ends = [e for s in services if s.get("repo", "").lower() == p.repo.lower()
            for e in s.get("ends", []) if e["end"] == "desktop"]
    need(len(ends) == 1, "桌面端登记数量不为一")
    end = ends[0]
    need(end.get("prefix") == p.tag_prefix and end.get("release") == p.workflow, "标签或工作流不匹配")
    need(end.get("online", {}).get("url") == p.manifest, "线上清单地址不匹配")


def release_run(p):
    workflow = gh("api", f"repos/{p.repo}/actions/workflows/{p.workflow}")
    record = gh("api", f"repos/{p.repo}/actions/runs/{p.run_id}")
    need(record["workflow_id"] == workflow["id"], "run 所属工作流不符")
    need(record["conclusion"] == "success", "发布未成功：" + str(record["conclusion"]))
    commit = gh("api", f"repos/{p.repo}/commits/{p.tag}")
    need(record["head_sha"] == commit["sha"], "本次调度的提交与目标 tag 不一致，请核对门禁输出")
    print(p.tag, commit["sha"], record["html_url"])


def delivery(p):
    release = gh("release", "view", p.tag, "-R", p.repo, "--json", "tagName,isDraft,assets")
    need(not release["isDraft"] and release["tagName"] == p.tag, "Release 尚未正式归档")
    need(p.tag == p.tag_prefix + p.version, "验收版本与标签不一致")
    need(urlsplit(p.manifest).scheme == "https", "清单需要 HTTPS")
    manifest = json.loads(run("curl", "-qfsS", "--proto", "=https", p.manifest))
    need(manifest["tag"] == p.tag and manifest["version"] == p.version, "线上清单版本不符")
    need(set(manifest["files"]) == set(manifest["sha256"]) and manifest["files"], "清单架构或摘要缺失")
    base = p.download_base.rstrip("/") + "/"
    need(urlsplit(base).scheme == "https", "下载地址需要 HTTPS")
    cached = {}
    with tempfile.TemporaryDirectory() as work:
        for arch, url in manifest["files"].items():
            leaf = url[len(base):]
            need(url.startswith(base) and re.fullmatch(r"[^/?#%\\]+\.dmg", leaf), "安装包 URL 偏离目标项目目录")
            need(leaf in {a["name"] for a in release["assets"]}, "Release 缺对应 DMG")
            if url not in cached:
                file = Path(work) / leaf
                run("curl", "-qfsS", "--proto", "=https", url, "-o", str(file))
                digest = run("shasum", "-a", "256", str(file)).decode().split()[0]
                need(digest == manifest["sha256"][arch], "安装包 SHA-256 不符")
                run("bash", str(Path(__file__).with_name("verify-dmg.sh")), str(file), p.version)
                cached[url] = digest
            need(cached[url] == manifest["sha256"][arch], f"{arch} 摘要不符")
            print(arch, "通过")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="cmd", required=True)
    def command(name, callback, *fields):
        sub = subs.add_parser(name)
        for field in fields:
            sub.add_argument("--" + field, required=True)
        sub.set_defaults(callback=callback)
        return sub

    command("environment", project, "repo", "bucket", "endpoint")
    command("policy", identity_scope, "ram", "policy", "region", "owner", "bucket", "prefix")
    command("vault", vault, "refs")
    command("secrets", project, "repo", "bucket", "endpoint").add_argument("--mode", choices=("oss", "deploy"), required=True)
    command("portal-token", portal_token, "repo")
    osstest = command("oss", oss, "bucket", "endpoint", "prefix")
    osstest.add_argument("--write-test", action="store_true")
    osstest.add_argument("--read-base", help="玩家端的 HTTPS 下载目录，可用于 CDN")
    sub = command("prs", prs)
    sub.add_argument("stage", choices=("opened", "ready", "merged"))
    sub.add_argument("urls", nargs="+")
    sub.add_argument("--base", default="main")
    command("registration", registration, "config", "repo", "tag-prefix", "workflow", "manifest")
    command("release-run", release_run, "repo", "workflow", "run-id", "tag")
    command("delivery", delivery, "repo", "tag-prefix", "tag", "version", "manifest", "download-base")
    p = parser.parse_args()
    p.callback(p)
    print("✓", p.cmd)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as exc:
        sys.exit(f"检查失败：{exc}")
