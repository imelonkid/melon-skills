"""验证 aliyun-oss-tools 技能、校验脚本行为、公开仓脱敏及跨 skill 复用。"""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "skills/aliyun-oss-tools/scripts/oss_verify.py"
spec = importlib.util.spec_from_file_location("oss_verify", SCRIPT)
oss_verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oss_verify)


class AliyunOssToolsTests(unittest.TestCase):
    def test_skill_docs_and_registration(self):
        skill = ROOT / "skills/aliyun-oss-tools/SKILL.md"
        self.assertTrue(skill.is_file())
        text = skill.read_text(encoding="utf-8")
        self.assertRegex(text, r"^---\nname:\s*aliyun-oss-tools\ndescription:\s*.+\n---")
        for keyword in ("render-policy", "policy", "probe", "oss:PutObject", "oss:GetObject", "gh secret set"):
            self.assertIn(keyword, text)
        self.assertTrue((ROOT / "site/aliyun-oss-tools.html").is_file())
        self.assertIn("id: 'aliyun-oss-tools'", (ROOT / "site/site.js").read_text(encoding="utf-8"))
        self.assertIn("skills/aliyun-oss-tools/SKILL.md", (ROOT / "README.md").read_text(encoding="utf-8"))
        self.assertIn("site/aliyun-oss-tools.html", (ROOT / "index.html").read_text(encoding="utf-8"))

    def test_cross_skill_references(self):
        self.assertIn("aliyun-oss-tools", (ROOT / "skills/macos-desktop-launch/SKILL.md").read_text(encoding="utf-8"))
        self.assertIn("aliyun-oss-tools", (ROOT / "skills/hero-pages/SKILL.md").read_text(encoding="utf-8"))

    def test_public_repo_safety(self):
        for rel in ("skills/aliyun-oss-tools/SKILL.md", "site/aliyun-oss-tools.html"):
            text = (ROOT / rel).read_text(encoding="utf-8")
            self.assertNotRegex(text, r"/www/sites/|/opt/1panel/www/sites/", msg=f"{rel} 含有服务器绝对路径")
            self.assertNotRegex(text, r"\b10\.\d+\.\d+\.\d+\b", msg=f"{rel} 含有内网 IP")
            self.assertNotRegex(text, r"\bLTAI[0-9A-Za-z]{12,}", msg=f"{rel} 含有真实 AK")

    def test_build_and_check_policy(self):
        policy = oss_verify.build_ram_policy("oss-cn-beijing", "1234567890123456", "example-bucket", "demo/page")
        self.assertEqual(
            policy["Statement"][0]["Resource"],
            ["acs:oss:oss-cn-beijing:1234567890123456:example-bucket/demo/page/*"],
        )
        with tempfile.TemporaryDirectory() as tmp:
            ram = Path(tmp) / "ram.json"
            bkt = Path(tmp) / "bucket.json"
            ram.write_text(json.dumps(policy), encoding="utf-8")
            bkt.write_text(json.dumps({
                "Version": "1",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": ["*"],
                    "Action": ["oss:GetObject"],
                    "Resource": ["acs:oss:*:1234567890123456:example-bucket/demo/page/*"],
                }],
            }), encoding="utf-8")
            oss_verify.check_policy(SimpleNamespace(
                ram=str(ram), policy=str(bkt), no_public_read=False,
                region="oss-cn-beijing", owner="1234567890123456",
                bucket="example-bucket", prefix="demo/page",
            ))
            # Private write-only prefix check without bucket policy
            oss_verify.check_policy(SimpleNamespace(
                ram=str(ram), policy=None, no_public_read=True,
                region="oss-cn-beijing", owner="1234567890123456",
                bucket="example-bucket", prefix="demo/page",
            ))

    def test_probe_put_and_anonymous_get(self):
        upload = MagicMock()
        download = MagicMock()
        upload.getresponse.return_value.status = 200
        upload.getresponse.return_value.getheader.return_value = "req-put"
        download.getresponse.return_value.status = 200
        download.getresponse.return_value.getheader.return_value = "req-get"
        download.getresponse.return_value.read.side_effect = lambda _: upload.request.call_args.args[2]

        stdin = MagicMock(isatty=MagicMock(return_value=True))
        conn_factory = MagicMock(side_effect=[upload, download])
        oss_verify.probe_oss(
            SimpleNamespace(
                write_test=True, bucket="example-bucket", endpoint="oss-cn-beijing.aliyuncs.com",
                prefix="demo/page", read_base=None, skip_read=False,
            ),
            stdin=stdin,
            getpass_fn=lambda _: "fixture",
            connection_cls=conn_factory,
        )
        self.assertEqual(upload.request.call_args.args[:2], ("PUT", "/demo/page/ci-test.txt"))
        download.request.assert_called_once_with("GET", "/demo/page/ci-test.txt", None, {})

    def test_probe_skip_read_only_puts(self):
        upload = MagicMock()
        upload.getresponse.return_value.status = 200
        upload.getresponse.return_value.getheader.return_value = "req-put"
        stdin = MagicMock(isatty=MagicMock(return_value=True))
        conn_factory = MagicMock(side_effect=[upload])
        oss_verify.probe_oss(
            SimpleNamespace(
                write_test=True, bucket="example-bucket", endpoint="oss-cn-beijing.aliyuncs.com",
                prefix="private/data", read_base=None, skip_read=True,
            ),
            stdin=stdin,
            getpass_fn=lambda _: "fixture",
            connection_cls=conn_factory,
        )
        self.assertEqual(conn_factory.call_count, 1)

    def test_probe_403_gives_actionable_hint(self):
        upload = MagicMock()
        upload.getresponse.return_value.status = 403
        upload.getresponse.return_value.getheader.return_value = "req-403"
        stdin = MagicMock(isatty=MagicMock(return_value=True))
        with self.assertRaisesRegex(ValueError, "主账号 UID"):
            oss_verify.probe_oss(
                SimpleNamespace(
                    write_test=True, bucket="example-bucket", endpoint="oss-cn-beijing.aliyuncs.com",
                    prefix="demo/page", read_base=None, skip_read=False,
                ),
                stdin=stdin,
                getpass_fn=lambda _: "fixture",
                connection_cls=MagicMock(side_effect=[upload]),
            )


if __name__ == "__main__":
    unittest.main()
