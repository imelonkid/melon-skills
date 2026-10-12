---
name: project-init
description: 按 melonkid 多云运维规范（melon-ops）初始化项目。用于"新建项目 / 初始化工程 / 起一个新服务 / new project"，以及"把已有项目纳入规范 / 补 git / 准备上线"。负责 git + GitHub 托管、目录骨架、部署模板、密钥约定、可观测接入、服务注册与上线准入检查。
---

# 项目初始化

目标：项目从第一天起就满足运维规范，将来上线时**不用返工**。

## 0. 先读规范（每次都读，不凭记忆）

规范与事实在私有仓库 `$OPS_REPO`（环境变量，定义在 `~/.zsh/conf.d/ops.zsh`；下称 ops 仓库）。**动手前先读这几份，以它们为准**——本 skill 与它们冲突时，听 ops 仓库的，并在交付时提醒用户更新本 skill：

| 读什么 | 在哪 | 用来决定 |
|---|---|---|
| 规范 | `docs/01-standard.md` | 数据分级 §2、灾备等级 §3、可重建性 §5、备份 §7、可观测 §8、准入与变更 §9 |
| 站点 | `registry/sites.yaml` | 每个站点的 `purpose` / `roles` / `icp_access`；`standby_pairs` |
| 服务清单字段 | `registry/services/_schema.yaml` + 同目录现有服务 | 注册表怎么写 |
| 主机基线 | `registry/baseline.toml` | 目标主机的 Docker / Compose 版本、日志轮转、cgroup |
| 部署新服务清单 | `docs/04-runbook.md`「部署新服务」 | 上线时还要改哪些地方 |

```bash
zsh -ic 'echo $OPS_REPO'      # 为空或目录不存在 → 只做第 1–3 步，跳过注册，交付时说明"未注册"
```

本 skill 在**公开仓库**里：不要把 IP、端口、密钥、面板路径、服务器上的具体路径写进本 skill 或模板。

## 硬性要求

| # | 要求 | 规范 |
|---|---|---|
| 1 | **所有项目必须由 git 托管，远端必须是 GitHub**（`github.com/imelonkid/<名>`）。不用跑在业务服务器上的自建托管（Gitea 等）——服务器挂了，代码和数据一起没。构建依赖的兄弟仓库同样要在 GitHub | §5.1 |
| 2 | 第一次提交前 `.gitignore` 就位：`.env`、`data/`、数据库文件、私钥不进 git | §5.4、§5.5 |
| 3 | 新仓库**默认私有**；用户明确说公开才公开 | — |
| 4 | 默认分支 `main`；提交信息 `<类型>(<范围>): <中文描述>` | — |
| 5 | **发布与回滚一律走 tag**：每次发版打新的 `vX.Y.Z`，线上版本永远是某个 tag；回滚 = 上线一个旧 tag。没有 tag 的代码不上线 | §5.1、§9.3 |
| 6 | **服务必须注册**：不在 `registry/services/` 里的服务不允许上线 | §1、§9.1 |

## 流程

### 1. 问清楚并定级

先看用户已经说了什么、目录里已有什么，**只问推不出来的**，一次问完（AskUserQuestion）：

| 项 | 规则 |
|---|---|
| 项目名 | kebab-case；同时是 GitHub 仓库名、compose 项目名、容器名、服务器目录 `/opt/<名>`、1Password 条目 `ops/<名>/prod` |
| 类型 | **服务**（要部署）/ **静态站** / **库或工具**（不部署，不注册） |
| 技术栈 | 按用户说的；没说就问 |
| 可见性 | 私有（默认）/ 公开 |
| 对外域名 | 服务 / 静态站才问；默认 `<名>.melonkid.cn` |

然后**由 Claude 按规范推出**下列各项，写进给用户的确认摘要，用户可改：

- **数据等级（§2）**：有用户数据（账号、订单、消息、对话）→ **T0**；用户上传的媒体、业务配置 → T1；能从代码或公开来源重建 → T2。服务的等级取所有资产里最高的。
- **灾备等级（§3）**：T0 有状态 → **L2**（温备 + 持续复制）；T1 → L1；无状态 → L3。
- **主站点**：读 `sites.yaml` 每个站点的 `purpose` 和 `roles`。只放 `roles` 含 `compute` 的站点；`purpose` 写着某业务"专用"的站点不放其他项目；`roles` 是 `ops` / `standby` 的站点**不放新业务**（§4.4 监控独立）。
- **备站点与裁判**：从 `standby_pairs` 里 `primary` = 主站点的那一条直接取 `standby` 和 `witness`，不自己发明。
- **ICP**：主站点和备站点的 `icp_access` 都要是 `true` 才能对外（§4.7）；`pending` 的写进 `known_gaps`。
- **数据库选型**：没有明确理由就用 **SQLite（WAL）**，单文件放 `data/`，能直接上 Litestream 做 L2；确需 MySQL / Postgres，备份用只读账号 `mysqldump --single-transaction` / `pg_dump`，L2 走 binlog / WAL 复制。

### 2. 本地目录与 git

- 位置：`~/Workspace/<名>`，用户另有指定除外。
- **已有项目 = 纳管模式**：先跑 `scripts/check.sh` 拿到差距清单，保留全部历史，只补缺的；**不改写历史**。发现已提交的密钥或数据库文件：停下来告诉用户（先轮换密钥，再决定是否清理历史），别自己 `filter-repo`。

```bash
git init -b main
cp <skill>/templates/gitignore .gitignore     # 再按技术栈追加
```

### 3. 骨架

所有类型：

| 文件 | 来源 |
|---|---|
| `README.md` | `templates/README.md`（含「上线准入」清单） |
| `CLAUDE.md` | `templates/CLAUDE.md` |
| `.gitignore` | 第 2 步 |

**服务**另加：

| 文件 | 来源 | 要点 |
|---|---|---|
| `deploy/Dockerfile` | 按技术栈写 | 多阶段构建；基础镜像**钉版本**；`ARG APP_VERSION` + `ENV APP_VERSION=$APP_VERSION`（版本号烘进镜像）；最终镜像要有 `wget` 或 `curl`（健康检查用）|
| `deploy/docker-compose.prod.yml` | `templates/docker-compose.prod.yml` | 见「容器规范」|
| `deploy/docker-compose.yml` | 按需 | 本地开发 |
| `.env.example` | `templates/env.example` | 全部变量 + 注释，值留空或示例 |
| `scripts/deploy.sh` | `templates/deploy.sh` | 见「发布」|
| `GET /health` | 代码 | 200 = 能正常服务；顺带检查数据库连接；返回体带 `version`（读 `APP_VERSION`）|

**静态站**：同样按 tag 发布——从 tag 的内容构建，上线后在服务器记 `RELEASE` 与 `deploy.log`；构建产物不进 git；部署只同步构建目录，**不要对干净 checkout 用 `rsync --delete`**（线上可能有不在 git 里的内容，比如由 Obsidian 同步的文章，这种情况写进 `known_gaps`）。

#### 容器规范（§5、§6）

- 每个容器都有 `mem_limit`、`healthcheck`、`restart: unless-stopped`（§5.6）。
- 端口只绑 `127.0.0.1`，对外统一经反向代理走 HTTPS；**不开新的安全组端口**（§6.5）。
- 持久化数据只在 `./data/`，服务器上即 `/opt/<名>/data/`；不在里面堆手工 `.bak`（§5.5）。
- 配置用服务内的 `env_file: .env`，**不靠 `--env-file` 插值**——后者不进容器标签，灾备重建会漏（真实踩过）。
- **不写 `logging:`**：日志轮转由主机基线统一配置（json-file 10m × 3）。
- 第三方镜像**钉版本**（最好钉 digest），不用 `latest`。
- 对象存储走 **S3 兼容接口**，不用 `oss2` 等厂商专有 SDK（§5.8）；做不到写进 `known_gaps`。
- compose 语法不超过基线里最低的 Compose 版本（`baseline.toml` 的 `compose_min`）。

#### 可观测（§8）

- 日志：JSON 到 stdout，带 `trace_id`；**密码、token、手机号必须脱敏**。
- 埋点：OpenTelemetry SDK。`OTEL_SERVICE_NAME` 与 `deployment.environment` 由 compose 注入；`service.version` 在代码初始化 SDK 时取 `APP_VERSION`（= tag，烘在镜像里，灾备重建也不会丢）；`cloud.provider` 由各主机的 Collector 补（同一份 compose 在主、备站点都要能跑，不能写死厂商）；`OTEL_EXPORTER_OTLP_ENDPOINT` 为空时 SDK 不导出，等运维中心的 Collector 就位再填。
- 业务指标命名 `<服务>_<领域>_<事件>_total`；**标签禁止高基数值**（user_id、URL 原文）。
- 采样在 Collector 做，代码里不写死采样率。

#### 密钥（§5.4）

- 真实值只在 1Password `ops/<名>/prod`，**由用户本人创建和填写**，Claude 不经手密钥值。
- 服务器上的 `/opt/<名>/.env` 只是副本，部署脚本不碰它。

#### 发布与回滚：一律走 tag（§5.1、§9.3）

线上版本永远等于某个 git tag。`scripts/deploy.sh`（模板 `templates/deploy.sh`）：

| 命令 | 做什么 |
|---|---|
| `deploy.sh patch\|minor\|major` | 发新版：在已推送到 `origin/main` 的干净 HEAD 打下一个 `vX.Y.Z`，**先推 tag 到 GitHub**，再从 tag 的内容（`git archive`）构建、上线 |
| `deploy.sh vX.Y.Z` | 上线指定的已有 tag：比线上旧 = 回滚，相同 = 重新部署 |
| `deploy.sh rollback` | 回滚到上一个成功上线的 tag |
| `deploy.sh status` | 线上版本（服务器 `RELEASE`）与最近的部署事件 |

- 镜像 `<名>:<tag>`，compose 也取自同一个 tag（服务器 `releases/<tag>.yml`）；上线 = 把该 tag 切成 `:prod` 并 `up -d`。
- 服务器保留最近 5 个版本，回滚到其中任何一个**不重新构建**，秒级完成。
- 健康检查 60 秒不过，自动切回上线前的版本（镜像和 compose 一起切）。
- T0 服务发新版前先跑 `/opt/<名>/pre-deploy.sh` 备份（回滚不跑）。
- 每次部署往 `/opt/<名>/deploy.log` 追加一行：时间、tag、类型（release / rollback / redeploy / auto-rollback）、操作人、结果。
- 发新版只在 **08–23 点**，窗口外必须 `EMERGENCY=1` 并在 24 小时内补复盘；**回滚不受窗口限制**。
- 数据库迁移必须**向后兼容**（先扩展、再收缩），保证回滚到上一个 tag 仍能跑。
- **不要**在服务器上手动改镜像标签、compose 或 `docker run`——一切经 `deploy.sh`，否则 `RELEASE` 和 `deploy.log` 就不可信了。

### 4. 首次提交并推到 GitHub

```bash
git add -A && git status            # 逐个确认没有密钥和数据
git commit -m "chore: 按运维规范初始化项目"
gh repo create imelonkid/<名> --private --source . --remote origin --push   # 用户选公开才换 --public
git remote set-url origin git@github.com:imelonkid/<名>.git                 # 之后走 1Password SSH Agent
```

首次上线也是 `scripts/deploy.sh minor`（得到 `v0.1.0`），由上线环节做，初始化阶段不碰服务器。

已有远端但不在 GitHub：新增 GitHub 远端并推送全部分支和标签，**旧远端先保留**，告诉用户迁完再删。

### 5. 注册（服务与静态站）

在 ops 仓库新建 `registry/services/<名>.yaml`，以 `templates/service.yaml` 为底，逐字段对照 `_schema.yaml`：

- `status: building`，上线后改 `active`；`tier` / `dr_level` / `site` / `failover_site` / `witness_site` 用第 1 步推出的值。
- `code.repo` 用 GitHub SSH 地址；有兄弟仓库依赖写 `depends_on`。
- `deploy.up` 写**完整**的启动命令——灾备重建、存储迁移都以它为准。
- `endpoints.url` 写**公网域名**的健康检查地址：业务探活走真实用户路径，顺带验 DNS / 证书 / 反代。
- **每份持久化数据一条 `assets`**——备份任务从这里生成（§7）：SQLite 写 `kind: sqlite` 和库文件路径；T0 `interval: 6h`、T1 `24h`；T2 必须写 `rebuild`；密钥文件写一条 `tier: S`。
- 做不到的条款写进 `known_gaps`（描述 + 替代路径 + 计划阶段），**不要假装满足**。纳管模式下，check.sh 的 ✗ 若一时修不了，也写进来，并在 `docs/06-roadmap.md` 差距表加一行。

然后在 ops 仓库提交（`feat(registry): 登记 <名>`）。**推不推送问用户**。

### 6. 检查

```bash
<skill>/scripts/check.sh <项目目录>
```

只读。✗ 必须修；△ 是上线前要补的，写进 README 的「上线准入」。

### 7. 交付

告诉用户：

1. 仓库地址、可见性、已推送的提交；定级结果（tier / dr_level / 主·备·裁判站点）；
2. check.sh 结果；
3. **需要用户本人做的事**：
   - 1Password 创建 `ops/<名>/prod`；
   - 服务器建目录（sudo 要密码的主机由用户执行）：`sudo mkdir -p /opt/<名>/data`；
   - 域名：确认主、备站点 ICP 接入；DNS TTL ≤ 300；反向代理与证书；
4. **上线时**（用 server-ops skill，初始化阶段不碰服务器），按规范 §9.2 + 运维手册「部署新服务」逐项完成：
   - 首次备份成功 + 做过一次恢复验证；备份任务的心跳接 Gatus；
   - Gatus 探活（`monitoring/gatus/config.yaml`）+ 告警实测触发过；
   - `panel` 索引、`docs/03-hosts.md`、注册表 `status: active`；
   - 若开了安全组，规则写描述和日期。

## 不要做

- 初始化阶段不 ssh 服务器、不改安全组、不改 DNS。
- 不替用户在 1Password、云控制台录入任何东西。
- 不 `push --force`，不改已有项目的提交历史。
- 用户没说公开就不建公开仓库。
- 不跳过注册：没有注册表条目的服务，不帮它上线。
