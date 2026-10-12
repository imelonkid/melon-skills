# melon-skills

我的 [Claude Code](https://claude.com/claude-code) skills。以后新写的 skill 都放这里。

| Skill | 用途 |
|---|---|
| [`project-init`](skills/project-init/SKILL.md) | 按 melon-ops 运维规范初始化新项目（或纳管已有项目）：GitHub 托管、自动定级（数据 / 灾备 / 主备裁判）、部署与可观测模板、服务注册、上线准入检查 |
| [`server-ops`](skills/server-ops/SKILL.md) | 多云服务器运维：巡检、排障、部署、基线收敛、灾备。坐标来自环境变量，事实在私有仓库 |
| [`article-review`](skills/article-review/SKILL.md) | 博客文章发布前审阅：错别字、语病、文笔、标签、图片；产出待审 commit 与逐字 diff |

图文介绍：用浏览器打开仓库根目录的 [`index.html`](index.html)，顶部菜单可跳到每个 skill 的介绍页。

## 安装

```bash
git clone git@github.com:imelonkid/melon-skills.git ~/Workspace/melon-skills
~/Workspace/melon-skills/install.sh
```

`install.sh` 把 `skills/*` 逐个软链到 `~/.claude/skills/`，并启用提交前的敏感信息扫描；幂等，同名的已有目录先挪到 `~/.claude/skills-backup/<时间>/`。
本机的 skill 都是软链接，**改它就是改仓库**，改完提交推送。

## 规则

这是**公开仓库**，维护规范见 [`AGENTS.md`](AGENTS.md)。要点：

- **零敏感信息**：IP、端口、面板入口、部署路径、密钥、token、手机号、证件一律不进仓库。依赖的数据走环境变量（定义在私有仓库 `melon-ops` 的 `ops.zsh`），skill 只写变量名。
- **提交前自动扫描**：`scripts/scan-secrets.sh`，连同本机环境变量的实际值一起比对。
- **改代码同步改文档**：`SKILL.md`、本 README、`site/site.js`、`site/<skill>.html`、`index.html`。

## License

MIT
