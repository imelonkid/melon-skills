# __NAME__

__一句话说明：是什么、给谁用__

## 本地运行

```bash
__本地启动命令__
```

## 发布与回滚

发布和回滚都以 git tag 为单位，没有 tag 的代码不上线。**发布与回滚只在内网门户上点**（「发布」对话框 / 「回滚」）；门户不可用时用 GitHub Actions 的「发布」「回滚」表单兜底。

版本号：只修 bug → patch；有新功能 → minor；不兼容（接口、数据、配置要跟着改）→ major。

发新版只在 08–23 点，窗口外勾「紧急变更」并在 24 小时内补复盘；回滚不受限。健康检查 60 秒不过自动切回上一版；门户最后探 `/health`，版本 = 本次 tag 且健康、稳定 20 秒才算上线完成。

GitHub 或门户不可用时，在运维终端用应急指令（不构建、不产生新版本）：

```bash
melon status __NAME__          # 线上版本与最近的部署事件
melon rollback __NAME__        # 切回上一次上线前的版本（服务器保留最近 5 版，秒级）
pbpaste | melon config __NAME__  # 下发 .env（来自 1Password）
```

## GitHub production 环境

发布流水线只在 production 环境里拿得到下面这些值（环境只允许 `main`）。GitHub 上的变量和 Secret 没有备注，**用途和对应关系只记在这里**：增删改任何一项都同步改这张表。Secret 的值写进去就读不出来，丢了只能重新生成。

| 名字 | 类型 | 用途 | 对应运维侧（`$OPS_REPO`） | 谁写入 |
|---|---|---|---|---|
| `DEPLOY_HOST` | 变量 | 部署入口：`deploy@<主机 IP>` | `agent/services/<主机>/__NAME__.conf` | 接入时配置 |
| `DEPLOY_KNOWN_HOSTS` | 变量 | 部署主机的 SSH 主机公钥（防中间人；和本机已信任的核对过再写） | 同上 | 接入时配置 |
| `DEPLOY_SSH_KEY` | Secret | 流水线连部署入口的钥匙，只能操作 `__NAME__` | `agent/authorized/ci-__NAME__.pub` | 接入时生成，本地不留 |
| `ACR_REGISTRY`、`ACR_USERNAME` | 变量 | 镜像仓库地址与推送账号 | — | 接入时配置 |
| `ACR_PASSWORD` | Secret | 镜像仓库推送密码（1Password 里镜像仓库推送账号的 Registry 密码） | — | 用户本人 |

查看：仓库 Settings → Environments → production，或 `gh variable list --env production` / `gh secret list --env production`（只有名字）。

## 上线准入（运维规范 §9.2）

- [ ] 代码在 GitHub，线上版本是一个 tag（`melon status __NAME__`）
- [ ] `.env.example` 齐全；1Password 有 `ops/__NAME__/prod`
- [ ] 注册表 `registry/services/__NAME__.yaml` 通过字段检查
- [ ] T0/T1 资产首次备份成功，**做过一次恢复验证**；备份心跳接入 Gatus
- [ ] Gatus 有探活，告警实测触发过
- [ ] 容器有 `mem_limit` / `healthcheck` / `restart`
- [ ] 主、备站点已完成 ICP 接入；DNS TTL ≤ 300
- [ ] `panel` 索引、主机档案已更新，注册表 `status: active`

## 已知缺口

见注册表 `known_gaps`。
