# melon-skills

我的 [Claude Code](https://claude.com/claude-code) skills。以后新写的 skill 都放这里。

| Skill | 用途 |
|---|---|
| [`project-init`](skills/project-init/SKILL.md) | 按 melon-ops 运维规范与**项目基线**（`templates/BASELINE.md`）初始化新项目（或纳管已有项目）：GitHub 托管、自动定级（数据 / 灾备 / 主备裁判）、部署与可观测模板、CLAUDE.md 边界（强制）、服务注册、Hero 端登记与内网制品交付、上线准入检查 |
| [`macos-desktop-launch`](skills/macos-desktop-launch/SKILL.md) | 通过门户发布 macOS 桌面 App，验证 OSS 读写、Developer ID 签名、公证、版本清单和最终安装包 |
| [`server-ops`](skills/server-ops/SKILL.md) | 多云服务器运维：巡检、排障、部署、基线收敛、灾备。坐标来自环境变量，事实在私有仓库 |
| [`article-review`](skills/article-review/SKILL.md) | 博客文章发布前审阅：错别字、语病、文笔、标签、图片；产出待审 commit 与逐字 diff |

图文介绍：用浏览器打开仓库根目录的 [`index.html`](index.html)，顶部菜单可跳到每个 skill 的介绍页。

## 安装

```bash
git clone git@github.com:imelonkid/melon-skills.git ~/Workspace/melon-skills
~/Workspace/melon-skills/install.sh
```

在 macOS 上，Codex 和 Claude 的 `project-init` 都链接到独立的 `~/.local/share/melon-skills/main/skills/project-init`。CI 每次运行会读取本仓库的默认分支 `main`。本机登录时和每 15 分钟由用户 LaunchAgent 快进更新同一分支，离线时可继续用上次成功取到的版本。仅安装建项基线可运行 `/usr/bin/python3 scripts/install_project_init.py`。更新失败时查看 `~/Library/Logs/cn.melonkid.project-init-sync.log`。

已有建项入口各自备份到 `~/.codex/skills-backup/` 或 `~/.claude/skills-backup/` 的时间目录。开发基线请编辑工作区并提交 PR。业务仓库的 `.melon-baseline` 在项目完成适配后更新。

完整安装还会把其余 Claude skills 链接到开发工作区，并启用提交前的敏感信息扫描。其他系统沿用原有的 Claude 工作区链接。

## 规则

这是**公开仓库**，维护规范见 [`AGENTS.md`](AGENTS.md)。要点：

- **零敏感信息**：IP、端口、面板入口、部署路径、密钥、token、手机号、证件一律不进仓库。依赖的数据走环境变量（定义在私有仓库 `melon-ops` 的 `ops.zsh`），skill 只写变量名。
- **提交前自动扫描**：`scripts/scan-secrets.sh`，连同本机环境变量的实际值一起比对。
- **改代码同步改文档**：`SKILL.md`、本 README、`site/site.js`、`site/<skill>.html`、`index.html`。

## License

MIT
