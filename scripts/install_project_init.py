"""Install the shared project-init skill and its per-user macOS update job."""
import os
import plistlib
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

REMOTE = "https://github.com/imelonkid/melon-skills.git"
LABEL = "cn.melonkid.project-init-sync"
GIT = "/usr/bin/git"
LAUNCHCTL = "/bin/launchctl"


def install_link(tool, target):
    destination = tool / "skills/project-init"
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink() and destination.readlink() == target:
        return

    with tempfile.TemporaryDirectory(dir=destination.parent) as staging:
        link = Path(staging) / "project-init"
        link.symlink_to(target, target_is_directory=True)
        backup = None
        if destination.exists() or destination.is_symlink():
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            backup = tool / "skills-backup" / stamp / "project-init"
            backup.parent.mkdir(parents=True)
            destination.rename(backup)
            print(f"已备份 {destination} → {backup}")
        try:
            link.replace(destination)
        except OSError:
            if backup is not None:
                backup.rename(destination)
            raise
    print(f"已连接 {destination} → {target}")


def install_agent(home, pull):
    domain = f"gui/{os.getuid()}"
    job = f"{domain}/{LABEL}"
    plist = home / "Library/LaunchAgents" / f"{LABEL}.plist"
    plist.parent.mkdir(parents=True, exist_ok=True)
    logs = home / "Library/Logs"
    logs.mkdir(parents=True, exist_ok=True)
    content = plistlib.dumps({
        "Label": LABEL,
        "ProgramArguments": pull,
        "EnvironmentVariables": {"GIT_TERMINAL_PROMPT": "0"},
        "RunAtLoad": True,
        "StartInterval": 900,
        "StandardErrorPath": str(logs / f"{LABEL}.log"),
    })
    loaded = subprocess.run([LAUNCHCTL, "print", job], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL).returncode == 0
    if plist.exists() and plist.read_bytes() == content and loaded:
        return
    if loaded:
        subprocess.run([LAUNCHCTL, "bootout", job], check=True)
    with tempfile.NamedTemporaryFile(dir=plist.parent, delete=False) as staged:
        staged.write(content)
    os.replace(staged.name, plist)
    subprocess.run([LAUNCHCTL, "bootstrap", domain, str(plist)], check=True)


def install(home):
    checkout = home / ".local/share/melon-skills/main"
    git = [GIT, "-c", "core.hooksPath=/dev/null"]
    pull = [*git, "-C", str(checkout), "pull", "--quiet", "--ff-only", "--no-rebase", "origin", "main"]
    checkout.parent.mkdir(parents=True, exist_ok=True)
    if checkout.exists():
        def read_git(*args):
            return subprocess.check_output([*git, "-C", str(checkout), *args], text=True).strip()
        if read_git("config", "--get", "remote.origin.url") != REMOTE or read_git("branch", "--show-current") != "main":
            raise SystemExit(f"安装目录已被其他来源或分支占用：{checkout}")
        subprocess.run(pull, check=True)
    else:
        with tempfile.TemporaryDirectory(dir=checkout.parent) as staging:
            clone = Path(staging) / "main"
            subprocess.run([*git, "clone", "--quiet", "--single-branch", "--branch", "main",
                            REMOTE, str(clone)], check=True)
            clone.rename(checkout)

    target = checkout / "skills/project-init"
    if not (target / "SKILL.md").is_file():
        raise SystemExit(f"main 缺少 project-init 入口：{target}")
    install_agent(home, pull)
    for name in (".codex", ".claude"):
        install_link(home / name, target)


if __name__ == "__main__":
    if sys.platform != "darwin":
        raise SystemExit("自动更新使用 macOS 用户登录服务。")
    install(Path.home())
