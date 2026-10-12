# melon-skills

@AGENTS.md

要点（详见上面引用的 AGENTS.md）：

1. **公开仓库，零敏感信息。** 主机、IP、端口、路径、密钥一律走环境变量；pre-commit 扫描不许绕过。
2. **改代码同一个提交里同步改文档**：`SKILL.md`、`README.md`、`site/site.js`、`site/<skill>.html`、`index.html`。
3. 主机事实只写进私有仓库 `$OPS_REPO`（melon-ops），不写进这里。
