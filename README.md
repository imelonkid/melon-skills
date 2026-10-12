# melon-skills

我的 [Claude Code](https://claude.com/claude-code) skills。以后新写的 skill 都放这里。

| Skill | 用途 |
|---|---|
| [`project-init`](skills/project-init/SKILL.md) | 按多云运维规范初始化新项目（或把已有项目纳入规范）：git + GitHub、目录骨架、部署模板、服务注册、准入检查 |

## 安装

```bash
git clone git@github.com:imelonkid/melon-skills.git ~/Workspace/melon-skills
~/Workspace/melon-skills/install.sh
```

`install.sh` 把 `skills/*` 逐个软链到 `~/.claude/skills/`，幂等；同名的已有目录先挪到 `~/.claude/skills-backup/<时间>/`。
本机的 skill 都是软链接，**改它就是改仓库**，改完提交推送。

## 规则

这是**公开仓库**：

- **不放**：IP、密码、密钥、Token、面板入口路径、手机号、身份证号、内部域名之外的任何可用于攻击的坐标。
- 依赖具体主机事实的 skill（如 `server-ops`）留在私有运维仓库 `melon-ops`；本仓库的 skill 需要这些事实时，**运行时**去读 `~/Workspace/melon-ops`，读不到就提示，不内置。
- 每个 skill 一个目录：`skills/<名>/SKILL.md`（必需）+ `templates/`、`scripts/`、`references/`（按需）。
- 新增 skill 后在上表登记一行，跑一遍 `install.sh`。

## License

MIT
