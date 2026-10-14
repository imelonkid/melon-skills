---
name: server-ops
description: melonkid 的多云服务器运维（阿里云、腾讯云、京东云）。查看主机与容器状态、业务探活、排查故障、部署服务、初始化新主机、核查安全基线、备份与灾备、ICP 接入时使用。涉及 1Panel、Beszel、Gatus、WireGuard、SSH 隧道、云厂商安全组、docker compose 的操作都归这里。
---

# 多云服务器运维

## 先拿到坐标

本 skill 在**公开仓库**里，不含任何主机事实。事实分两处，**动手前先读**：

| 什么 | 在哪 |
|---|---|
| 主机别名、IP、面板端口、容器基线 | 环境变量，定义在 `~/.zsh/conf.d/ops.zsh`（私有仓库的软链） |
| 规范、站点规划、主机档案、手册、注册表、运维基线 | 私有仓库 `$OPS_REPO`（通常 `~/Workspace/melon-ops`）|

```bash
zsh -ic 'env | grep -E "^(OPS|ALI|TX|JD|BLOG)_" | grep -v ENTRY | sort'   # 坐标（面板入口路径是敏感值，不要打印）
```

`OPS_SITES` 是站点前缀列表（如 `ALI TX JD`），每个前缀 `P` 有 `P_SSH`（ssh 别名）、`P_IP`，可选 `P_CONTAINERS`、`P_PANEL_PORT`。`OPS_SSH` / `OPS_IP` 指向运维中心。

**第一次接手或要全景**：读 `$OPS_REPO/docs/whitepaper.html`（白皮书）。按需再读：

| 文件（`$OPS_REPO/docs/`）| 内容 |
|---|---|
| `01-standard.md` | 规范：数据分级、L1–L4 灾备、多云与裁判、可重建性、主机基线、备份、可观测、服务注册与发布 |
| `02-sites.md` | 站点规划：分工、主备与裁判、共享依赖（域名 / DNS / 备案）|
| `03-hosts.md` | 每台主机：系统、登录用户、sudo 是否要密码、服务、端口、安全组 |
| `04-runbook.md` | 新主机初始化、运维基线、SSH 加固、排障、博客发布、ICP 接入、失去运维终端 |
| `05-gotchas.md` | 踩过的坑，每条带原因 |
| `06-roadmap.md` | 对照规范的差距与路线 |
| `07-wireguard.md` | 内网方案与白名单 |
| `release-platform.html` | 开发发布平台：CI、发布 / 回滚、部署入口、镜像仓库 |
| `backup-plan.html` | 数据备份方案 |

服务清单在 `$OPS_REPO/registry/services/`，站点在 `registry/sites.yaml`，主机基线在 `registry/baseline.toml`。

`$OPS_REPO` 不存在：说明这台电脑还没初始化运维终端，按 `melon-ops/workstation/README.md` 来，**不要凭记忆操作服务器**。

## 写回规则

- **改机器先改 `$OPS_REPO/registry/`，再改 `docs/`**，改完在私有仓库提交推送。
- 新坑追加到 `05-gotchas.md`，注明日期。
- 新增 / 下线容器：同步改 `ops.zsh` 里对应的 `<P>_CONTAINERS`。
- 密码、AK/SK、面板安全入口、身份证件**不进任何仓库**；只在 1Password 与本机 `~/.zsh/conf.d/ops.secrets.zsh`。
- **本 skill 只写流程和红线**。主机事实只写进私有仓库，绝不写进本 skill。

## 先跑这个

```bash
$SKILLS_REPO/skills/server-ops/scripts/status.sh     # 全景：主机 + 容器 + 探活 + 漂移检测
$SKILLS_REPO/skills/server-ops/scripts/audit.sh      # 安全核查（含从本机探测公网端口）+ 运维基线
$OPS_REPO/baseline/check.py                          # 对照 registry/baseline.toml（--quiet 只看偏离）
```

全部只读。缺环境变量时脚本会直接说缺哪个。

用户自己在终端用 `panel`：`panel` 看索引、`panel ps` 看容器、`panel health` 看探活、`panel <站点>` 开 1Panel 隧道、`panel beszel|gatus` 开监控隧道。

**改主机环境一律走基线**：`$OPS_REPO/baseline/apply.py <主机> <步骤>`。root 主机直接执行；sudo 要密码的主机，apply.py 会把脚本传到 `/tmp/ops-apply/` 并打印一条 `ssh -t <主机> 'sudo bash …'`，**交给用户执行**——这是刻意保留的人工确认关卡。做完用 `check.py <主机>` 复核。

**业务发布与回滚只经主机上的部署入口 `deploy-agent`**（`$OPS_REPO/agent/`，手册「部署入口」）：
- 日常：项目仓库 GitHub Actions 的「发布服务端 / 回滚服务端 / 发布桌面端」（流水线在公开仓库 `imelonkid/melon-ci`）；应急：项目里的 `scripts/deploy.sh <patch|tag|rollback|status>`。两条路走同一个入口。
- 查线上版本：`ssh <主机>-deploy status <服务>`（deploy 用户 + 强制命令，只能调用入口，打不开 shell）。
- **不要在服务器上手动改镜像标签、compose 或 `docker run`**，否则 `RELEASE` / `deploy.log` 就不可信了；还没改造成 tag 发布的项目，先按 project-init 改造。
- 新服务接入入口：写 `$OPS_REPO/agent/services/<主机>/<服务>.conf` → `$OPS_REPO/agent/install.sh <主机>`；CI 钥匙放 `agent/authorized/ci-<服务>.pub`（自动只能操作该服务）。
- 1Password 授权：`<主机>-deploy` 首次连接会弹窗；连续失败报 `communication with agent failed` 时请用户在 1Password 点允许。

**重点业务机分段改**：先做低风险、不重启的 → 复核 → 再动存储 / 内核 → 用户确认后手动重启。重建业务容器以注册表里该服务的 `deploy.up` 为准（有的服务依赖 `--env-file`，漏了会起错配置）。

## 红线

违反这几条会造成真实损失，**没有例外**：

1. **管理面板绝不对公网开放。** 1Panel / Beszel / Gatus 只走 SSH 隧道或 WireGuard 内网。要开安全组先问用户。
2. **改 sshd 配置**：有数据的机器先打云盘快照 → 确认 VNC 可用 → 保持现有会话不关 → `sshd -t` → `sshd -T` 看合并后的生效值 → `reload`（不是 restart）→ 新窗口验证密钥能登、密码被拒，**再**关旧会话。
3. **root 密码不能删、不能乱改。** VNC 救援要用它，那是不依赖 SSH 的唯一通道。
4. **1Panel 托管的容器从面板卸载**，直接 `docker rm` 会留残留。判断：`docker inspect <名> -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'` 在 `/opt/1panel/` 下。
5. **删任何东西前先 `docker stop` + `docker update --restart no` 观察几天**，确认没影响再 `rm`。
6. **安全组规则必须写描述和创建日期。**
7. **不要把 `panel` 的隧道端口和服务端口搞混**；改了转发要 `panel stop` 重开。
8. **重点业务（尤其数据库）的任何变更都先确认**：先备份（`mysqldump --single-transaction`），再动。
9. **有状态服务不允许多站点同时写。** 切换主备必须先隔离旧主，由第三站点裁判。
10. **线上内容可能不在 git 里**（博客文章来自 Obsidian 同步）。不要从干净的 checkout 构建后 `rsync --delete`，先 diff 线上。
11. **用户的密码、验证码、证件只由用户本人输入。** 需要 sudo 密码的命令交给用户跑。
