"""Exercise the actual Git update command against a temporary main branch."""
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import install_project_init as installer


class ProjectInitInstallTest(unittest.TestCase):
    def test_shared_main_updates_without_touching_old_installations(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "user"
            upstream = root / "upstream"
            subprocess.run(["git", "init", "-q", "-b", "main", str(upstream)], check=True)
            skill = upstream / "skills/project-init"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text("old")
            self.commit(upstream)
            codex = home / ".codex/skills/project-init"
            codex.mkdir(parents=True)
            (codex / "local.txt").write_text("preserve")
            claude = home / ".claude/skills/project-init"
            claude.parent.mkdir(parents=True)
            claude.symlink_to(skill, target_is_directory=True)

            env = {"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                   "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": f"url.{upstream}.insteadOf",
                   "GIT_CONFIG_VALUE_0": installer.REMOTE}
            with patch.dict(os.environ, env), patch.object(installer, "LAUNCHCTL", "/usr/bin/true"):
                installer.install(home)
                self.assertTrue(codex.samefile(claude))
                self.assertFalse(claude.samefile(skill))
                plist = home / "Library/LaunchAgents" / f"{installer.LABEL}.plist"
                job = plistlib.loads(plist.read_bytes())
                self.assertTrue(job["RunAtLoad"])
                self.assertEqual(job["StartInterval"], 900)
                (skill / "SKILL.md").write_text("merged")
                self.commit(upstream)
                subprocess.run(job["ProgramArguments"], check=True)
                for link in (codex, claude):
                    self.assertEqual((link / "SKILL.md").read_text(), "merged")
                installer.install(home)
                for name in (".codex", ".claude"):
                    backups = list((home / name / "skills-backup").glob("*/project-init"))
                    self.assertEqual(len(backups), 1)
                    if name == ".codex":
                        self.assertEqual((backups[0] / "local.txt").read_text(), "preserve")
                    else:
                        self.assertEqual(backups[0].readlink(), skill)
                upstream.rename(root / "offline")
                result = subprocess.run(job["ProgramArguments"], stderr=subprocess.PIPE)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((codex / "SKILL.md").read_text(), "merged")

    @staticmethod
    def commit(repo):
        subprocess.run(["git", "-C", str(repo), "add", "skills"], check=True)
        subprocess.run(["git", "-C", str(repo), "-c", "user.name=Test", "-c",
                        "user.email=test@example.com", "commit", "-qm", "fixture"], check=True)
