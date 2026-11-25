"""Desktop probes must use the selected prefix and verify this run's bytes."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch


script = Path(__file__).resolve().parents[1] / "skills/macos-desktop-launch/scripts/verify.py"
spec = importlib.util.spec_from_file_location("desktop_verify", script)
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class DesktopProbeTest(unittest.TestCase):
    def setUp(self):
        self.target = SimpleNamespace(write_test=True, bucket="example-bucket",
                                      endpoint="oss-cn-beijing.aliyuncs.com",
                                      prefix="sample/desktop", read_base="https://cdn.example.com/files")
        self.upload = MagicMock()
        self.download = MagicMock()
        self.upload.getresponse.return_value.status = 200
        self.download.getresponse.return_value.status = 200
        self.download.getresponse.return_value.read.side_effect = (
            lambda size: self.upload.request.call_args.args[2])
        for mock in (patch.object(verify.sys.stdin, "isatty", return_value=True),
                     patch.object(verify.getpass, "getpass", return_value="fixture")):
            mock.start()
            self.addCleanup(mock.stop)
        connections = patch.object(verify.http.client, "HTTPSConnection", side_effect=[self.upload, self.download])
        self.connect = connections.start()
        self.addCleanup(connections.stop)

    def test_download_is_anonymous_at_player_url(self):
        verify.oss(self.target)
        self.assertEqual(self.upload.request.call_args.args[:2], ("PUT", "/sample/desktop/ci-test.txt"))
        self.assertEqual(self.connect.call_args_list[-1].args, ("cdn.example.com",))
        self.download.request.assert_called_once_with("GET", "/files/ci-test.txt", None, {})

    def test_stale_read_is_rejected(self):
        self.download.getresponse.return_value.read.side_effect = lambda size: b"old"
        with self.assertRaisesRegex(ValueError, "读回内容"):
            verify.oss(self.target)

    def test_failed_write_does_not_read_existing_object(self):
        self.upload.getresponse.return_value.status = 403
        with self.assertRaisesRegex(ValueError, "PUT"):
            verify.oss(self.target)
        self.download.request.assert_not_called()
