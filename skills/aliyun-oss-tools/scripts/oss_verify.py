#!/usr/bin/env python3
"""阿里云 OSS 权限与连通性校验工具。

probe / oss 带 --write-test 时会覆盖目标前缀下的 ci-test.txt；其余子命令均为只读。
"""
import argparse
import base64
import getpass
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
from email.utils import formatdate
from urllib.parse import urlsplit

OSS_SECRETS = {"OSS_ACCESS_KEY_ID", "OSS_ACCESS_KEY_SECRET"}


def need(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args, **kwargs):
    return subprocess.check_output(args, **kwargs)


def gh(*args, **kwargs):
    return json.loads(run("gh", *args, **kwargs))


def read_json(file):
    return json.loads(Path(file).read_text(encoding="utf-8"))


def validate_target(bucket, endpoint, prefix):
    need(re.fullmatch(r"[a-z0-9][a-z0-9-]+", bucket), "桶名无效")
    need(re.fullmatch(r"oss-[a-z0-9-]+\.aliyuncs\.com", endpoint), "需要阿里云 OSS 公网地域端点（如 oss-cn-beijing.aliyuncs.com）")
    need(bool(prefix) and all(re.fullmatch(r"[a-zA-Z0-9_-]+", part) for part in prefix.split("/")), "目标前缀无效（不带首尾斜杠）")


def build_ram_policy(region, owner, bucket, prefix):
    need(re.fullmatch(r"oss-[a-z0-9-]+|\*", region), "地域格式无效（应为 oss-cn-<地域> 或 *）")
    need(re.fullmatch(r"[0-9]{10,20}|\*", owner), "主账号 UID 格式无效（应为主账号数字 ID 或 *）")
    need(re.fullmatch(r"[a-z0-9][a-z0-9-]+", bucket), "桶名无效")
    need(bool(prefix) and all(re.fullmatch(r"[a-zA-Z0-9_-]+", part) for part in prefix.split("/")), "目标前缀无效（不带首尾斜杠）")
    return {
        "Version": "1",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": ["oss:PutObject"],
                "Resource": [f"acs:oss:{region}:{owner}:{bucket}/{prefix}/*"],
            }
        ],
    }


def render_policy(p):
    ram_policy = build_ram_policy(p.region, p.owner, p.bucket, p.prefix)
    print("# 1. RAM 自定义写策略（仅 PutObject，无删除权限）")
    print(json.dumps(ram_policy, ensure_ascii=False, indent=2))
    print()
    print("# 2. Bucket Policy 匿名只读参考（仅需公开下载/边缘拉包的前缀追加）")
    bucket_policy = {
        "Version": "1",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": ["*"],
                "Action": ["oss:GetObject"],
                "Resource": [f"acs:oss:*:{p.owner}:{p.bucket}/{p.prefix}/*"],
            }
        ],
    }
    print(json.dumps(bucket_policy, ensure_ascii=False, indent=2))


def check_policy(p):
    need(re.fullmatch(r"oss-[a-z0-9-]+|\*", p.region), "地域格式无效（应为 oss-cn-<地域> 或 *）")
    need(re.fullmatch(r"[0-9]{10,20}|\*", p.owner), "主账号 UID 格式无效（应为主账号数字 ID 或 *）")
    need(re.fullmatch(r"[a-z0-9][a-z0-9-]+", p.bucket), "桶名无效")
    need(bool(p.prefix) and all(re.fullmatch(r"[a-zA-Z0-9_-]+", part) for part in p.prefix.split("/")), "目标前缀无效")

    resources = {
        f"acs:oss:{region}:{owner}:{p.bucket}/{p.prefix}/*"
        for region in (p.region, "*")
        for owner in (p.owner, "*")
    }

    def items(value):
        return value if isinstance(value, list) else [value]

    def grant(file, action, public):
        for s in read_json(file)["Statement"]:
            principal = s.get("Principal")
            if isinstance(principal, dict):
                principal = principal.get("RAM")
            if (
                s.get("Effect") == "Allow"
                and action in items(s.get("Action"))
                and resources.intersection(items(s.get("Resource")))
                and (not public or "*" in items(principal))
            ):
                return
        raise ValueError(f"策略中未找到 {action} 对目标前缀的明确授权，请核对导出策略格式和范围")

    grant(p.ram, "oss:PutObject", False)
    if not getattr(p, "no_public_read", False):
        need(bool(getattr(p, "policy", None)), "检查公开读前缀时必须提供 --policy（私有写前缀请加 --no-public-read）")
        grant(p.policy, "oss:GetObject", True)
    print("已匹配声明；附加条件、授权绑定及最终生效结果由上传回读实测。")


def probe_oss(p, *, stdin=None, getpass_fn=None, connection_cls=None):
    need(p.write_test, "写入测试对象必须显式指定 --write-test")
    validate_target(p.bucket, p.endpoint, p.prefix)
    stdin = stdin or sys.stdin
    getpass_fn = getpass_fn or getpass.getpass
    connection_cls = connection_cls or http.client.HTTPSConnection

    key = f"{p.prefix}/ci-test.txt"
    host = f"{p.bucket}.{p.endpoint}"
    print(f"将写入 https://{host}/{key}", flush=True)
    need(stdin.isatty(), "请在本机交互终端输入 OSS 凭据")
    ak = getpass_fn("AccessKey ID（非 RAM UID）：").strip()
    sk = getpass_fn("AccessKey Secret：").strip()
    need(ak and sk, "缺少凭据")

    body = ("oss-probe " + secrets.token_hex(16) + "\n").encode()
    date = formatdate(usegmt=True)
    canonical = f"PUT\n\ntext/plain\n{date}\n/{p.bucket}/{key}".encode()
    signature = base64.b64encode(hmac.digest(sk.encode(), canonical, "sha1")).decode()

    skip_read = bool(getattr(p, "skip_read", False))
    methods = ("PUT",) if skip_read else ("PUT", "GET")
    read_base = getattr(p, "read_base", None)
    url = urlsplit((read_base or f"https://{host}/{p.prefix}").rstrip("/") + "/ci-test.txt")
    if not skip_read:
        need(
            url.scheme == "https" and url.hostname and not url.username and not url.query and not url.fragment,
            "匿名下载入口需要 HTTPS 目录地址",
        )

    for method in methods:
        headers = (
            {"Content-Type": "text/plain", "Date": date, "Authorization": f"OSS {ak}:{signature}"}
            if method == "PUT"
            else {}
        )
        conn = connection_cls(host if method == "PUT" else url.netloc, timeout=30)
        try:
            conn.request(method, "/" + key if method == "PUT" else url.path, body if method == "PUT" else None, headers)
            response = conn.getresponse()
            req_id = response.getheader("x-oss-request-id", "-")
            print(method, response.status, "Request ID", req_id)
            if response.status != 200:
                hint = ""
                if method == "PUT" and response.status == 403:
                    hint = "（请核对 RAM 策略中的主账号 UID / oss-地域 / 前缀路径、策略是否已挂到子账号，以及 AccessKey 是否正确）"
                elif method == "GET" and response.status in (403, 404):
                    hint = "（请核对 Bucket Policy 匿名 oss:GetObject 是否覆盖该前缀，以及下载入口路径是否正确）"
                raise ValueError(f"{method} 失败：HTTP {response.status}{hint}")
            if method == "GET":
                need(response.read(len(body) + 1) == body, "读回内容与本次写入不符")
        finally:
            conn.close()


def check_env(p):
    opts = gh("variable", "list", "-R", p.repo, "--env", p.env, "--json", "name,value")
    values = {v["name"]: v["value"] for v in opts}
    need(values.get("OSS_BUCKET") == p.bucket, f"{p.env} OSS_BUCKET 与目标不符（实际：{values.get('OSS_BUCKET')!r}）")
    need(values.get("OSS_ENDPOINT") == p.endpoint, f"{p.env} OSS_ENDPOINT 与目标不符（实际：{values.get('OSS_ENDPOINT')!r}）")
    have = {s["name"] for s in gh("secret", "list", "-R", p.repo, "--env", p.env, "--json", "name")}
    missing = sorted(OSS_SECRETS - have)
    need(not missing, f"缺 {p.env} Secret：" + ", ".join(missing))
    print(f"已确认 {p.repo} ({p.env}) 的 OSS 变量与密钥名称齐备。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="cmd", required=True)

    rp = subs.add_parser("render-policy", help="生成最小权限 RAM 写策略与 Bucket 匿名读参考 JSON")
    rp.add_argument("--region", required=True, help="OSS 地域，如 oss-cn-beijing")
    rp.add_argument("--owner", required=True, help="阿里云主账号数字 UID")
    rp.add_argument("--bucket", required=True, help="OSS 桶名")
    rp.add_argument("--prefix", required=True, help="目标前缀（不带首尾斜杠）")
    rp.set_defaults(callback=render_policy)

    pol = subs.add_parser("policy", help="静态核对导出的 RAM 策略与 Bucket Policy JSON")
    pol.add_argument("--ram", required=True, help="导出的 RAM 自定义策略 JSON 文件")
    pol.add_argument("--policy", help="导出的 Bucket Policy JSON 文件（私有前缀加 --no-public-read 可省略）")
    pol.add_argument("--no-public-read", action="store_true", help="仅检查 RAM 写权限，不检查匿名读")
    pol.add_argument("--region", required=True, help="OSS 地域，如 oss-cn-beijing")
    pol.add_argument("--owner", required=True, help="阿里云主账号数字 UID")
    pol.add_argument("--bucket", required=True, help="OSS 桶名")
    pol.add_argument("--prefix", required=True, help="目标前缀（不带首尾斜杠）")
    pol.set_defaults(callback=check_policy)

    for alias in ("probe", "oss"):
        pr = subs.add_parser(alias, help="实测目标前缀的 PUT 写入与匿名 GET 回读")
        pr.add_argument("--bucket", required=True, help="OSS 桶名")
        pr.add_argument("--endpoint", required=True, help="OSS 地域端点，如 oss-cn-beijing.aliyuncs.com")
        pr.add_argument("--prefix", required=True, help="目标前缀（不带首尾斜杠）")
        pr.add_argument("--write-test", action="store_true", help="显式允许写入并覆盖 <prefix>/ci-test.txt")
        pr.add_argument("--read-base", help="自定义匿名下载目录（如 CDN 域名路径）")
        pr.add_argument("--skip-read", action="store_true", help="私有写前缀：仅测 PUT，跳过匿名 GET")
        pr.set_defaults(callback=probe_oss)

    ev = subs.add_parser("env", help="只读核对 GitHub 环境的 OSS 变量值与密钥名称")
    ev.add_argument("--repo", required=True, help="GitHub 仓库，如 imelonkid/melon-pages")
    ev.add_argument("--bucket", required=True, help="期望的 OSS_BUCKET")
    ev.add_argument("--endpoint", required=True, help="期望的 OSS_ENDPOINT")
    ev.add_argument("--env", default="production", help="GitHub Environment 名（默认 production）")
    ev.set_defaults(callback=check_env)

    p = parser.parse_args()
    p.callback(p)
    print("✓", p.cmd)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as exc:
        sys.exit(f"检查失败：{exc}")
