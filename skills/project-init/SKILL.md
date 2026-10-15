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
| 7 | **必须有 `CLAUDE.md`，且有「## 边界（强制）」一节**：本项目负责什么、不负责什么（归谁）、与其他项目的关系。它是 Claude 在本项目开发的强制约束，越界的需求先停下来确认。**业务项目只写自己的边界**（如产品与它依赖的引擎各管什么），不写平台分工；**平台项目**（melon-ops、melon-portal、melon-vine、melon-ci、melon-skills）的边界以 ops 仓库 `docs/09-projects.md` 为准 | — |

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
| 边界 | 负责什么、不负责什么（容易被误放进来的东西归谁）、依赖或被谁依赖。能从用户描述和目录推出来就不问，写进确认摘要 |

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

### 3. 骨架（按项目基线）

**项目基线**定义在 [`templates/BASELINE.md`](templates/BASELINE.md)：每类项目必须有哪些文件、对应规范哪一条、check.sh 怎么查。**以基线为准，不以任何具体业务项目为样板**；基线缺的东西先补进基线（升版本），再用到项目里。技术栈相关的文件取 `templates/stacks/<栈>/`（python / node / static）。

所有类型：

| 文件 | 来源 |
|---|---|
| `README.md` | `templates/README.md`（含「上线准入」清单） |
| `CLAUDE.md` | `templates/CLAUDE.md`，**必须**填好「边界（强制）」一节（硬性要求 7）；纳管已有项目时也要补上 |
| `.gitignore` | 第 2 步 |
| `.melon-baseline` | `templates/melon-baseline`（记录按哪一版基线接入） |

**服务**另加：

| 文件 | 来源 | 要点 |
|---|---|---|
| `deploy/Dockerfile` | `templates/stacks/<栈>/Dockerfile` | 多阶段构建；基础镜像**钉版本**；`ARG APP_VERSION` + `ENV APP_VERSION=$APP_VERSION`（版本号烘进镜像）；最终镜像要有 `wget` 或 `curl`（健康检查用）|
| `deploy/docker-compose.prod.yml` | `templates/docker-compose.prod.yml` | 见「容器规范」|
| `deploy/docker-compose.yml` | 按需 | 本地开发 |
| `.env.example` | `templates/env.example` | 全部变量 + 注释，值留空或示例 |
| `.github/workflows/ci.yml` | `templates/workflows/ci.yml` | 调用 `imelonkid/melon-ci` 的 pr-check：密钥扫描、运维规范、测试、镜像构建 |
| `scripts/ci-test.sh` | `templates/stacks/<栈>/ci-test.sh` | CI 的测试入口（含 /health 冒烟）：桩服务 + 临时目录，不碰外网和真实数据；依赖版本与 Dockerfile 一致 |
| `GET /health` | 代码，示例 `templates/stacks/<栈>/health.*` | 200 = 能正常服务；顺带检查数据库连接；返回体带 `version`（读 `APP_VERSION`）|

**静态站**：**也按镜像发布**（`templates/stacks/static/`：构建 → Caddy 提供，`/health` 返回版本），与服务走同一条 tag 发布 / 回滚路径；构建产物不进 git。线上若有不在 git 里的内容（例如由 Obsidian 同步的文章），挂成数据卷并写进注册表 `assets` 与 `known_gaps`，**不要对干净 checkout 用 `rsync --delete`**。

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

#### 发布与回滚：一律走 tag，只在线上（§5.1、§9.3）

线上版本永远等于某个 git tag。**发布只在线上**（项目基线 v2）：GitHub 的「发布 / 回滚 / 状态」表单（`templates/workflows/`，调用 melon-ci `@v2`），或内网门户的流水线页。**项目里不放部署脚本**——本机发版会绕过门禁、不进执行记录，还和线上逻辑走偏。

| 场景 | 怎么做 |
|---|---|
| 发新版 | 表单「发布」选 patch / minor / major：门禁（发布窗口、main 的 CI 绿）→ 打 tag → 从 tag 构建 → 推镜像仓库 → 部署入口按摘要拉取上线 |
| 回滚 | 表单「回滚」（留空 = 上一次上线前的版本，或填 tag） |
| GitHub / 门户不可用 | 运维终端：`melon rollback <名> [tag]`、`melon status <名>`（不构建，切到服务器上已有的版本） |
| 下发配置 | `pbpaste \| melon config <名>`（.env 来自 1Password，不经 GitHub） |

服务器侧的规则（部署入口 deploy-agent 执行）：

- 镜像 `<名>:<tag>`，compose 取自同一个 tag（服务器 `releases/<tag>.yml`）；上线 = 把该 tag 切成 `:prod` 并 `up -d`。
- 服务器保留最近 5 个版本，回滚到其中任何一个**不重新构建**，秒级完成。
- 健康检查 60 秒不过，自动切回上线前的版本（镜像和 compose 一起切）。
- T0 服务发新版前先跑 `/opt/<名>/pre-deploy.sh` 备份（回滚不跑）。
- 每次部署往 `/opt/<名>/deploy.log` 追加一行：时间、tag、类型（release / rollback / redeploy / auto-rollback）、操作人、结果。
- 发新版只在 **08–23 点**，窗口外勾「紧急变更」并在 24 小时内补复盘；**回滚不受窗口限制**。
- 数据库迁移必须**向后兼容**（先扩展、再收缩），保证回滚到上一个 tag 仍能跑。
- **不要**在服务器上手动改镜像标签、compose 或 `docker run`——否则 `RELEASE` 和 `deploy.log` 就不可信了。

#### 多端项目（服务端 + 网页 + 桌面 + 手机，一个仓库）

目录约定：`apps/server`、`apps/web`、`apps/desktop`、`apps/harmony`（按实际有的端）。模板在 `templates/multi-end/`。

| 端 | tag | 产物与渠道 | 回滚 |
|---|---|---|---|
| 服务端 | `server-vX.Y.Z` | 镜像，「发布服务端」表单（`tag-prefix: server-v`） | 「回滚服务端」表单或 `melon rollback`，秒级 |
| 网页界面 | 随服务端 | 服务端在 `/app/` 提供，**界面与服务端同版本** | 跟着服务端回滚 |
| 桌面（Electron） | `desktop-vX.Y.Z` | `scripts/release-desktop.sh`：从 tag 构建 dmg → 下载站 `/download/desktop/`（`latest.json` 最后上传）→ GitHub Release 存档 | 装出去收不回来：修复后发 patch |
| 鸿蒙 | `harmony-vX.Y.Z` | `scripts/release-harmony.sh`：版本号与签名**构建时注入**（不改源码）→ GitHub Release → AGC | 应用市场不能回滚，只能发更高版本 |

规则：

- **各端独立 tag**，节奏互不绑架；端与端之间靠 API 版本对齐。
- **网页界面放服务端**：改界面只发服务端、秒级回滚；桌面端只是打开 `<服务端>/app/` 的壳，加载失败时退回安装包自带的那份界面；主窗口只允许本地文件和当前服务端两个来源。
- **兼容契约**：`/api/health` 返回 `version`（= tag）、`apiVersion`、`minClient`（各端最低版本，示例 `templates/multi-end/compat.example.js`）。服务端至少兼容上一个 API 版本；只有新版客户端已发布后才提高 `minClient`。
- **桌面更新**：客户端启动 10 秒后、之后每 6 小时读 `<服务端>/download/desktop/latest.json` 和 `minClient`，有新版弹窗提示下载；低于 `minClient` 必须升级。没有 Apple 开发者签名时做不了静默自动更新（electron-updater 在 macOS 要求签名），写进 `known_gaps`。
- **鸿蒙签名分档**：调试证书 + 登记设备（开发者自测，hdc 安装）→ 发布证书 + AGC 邀请测试（灰度，不需要软著）→ 正式上架（软著、App 备案）。发布证书本身不要求软著，灰度阶段就可以申请。
- **构建要带兄弟仓库**（如引擎）：写 `deploy/prepare-context.sh`（模板 `templates/multi-end/prepare-context.sh`），兄弟仓库版本固定在 `deploy/<依赖>.ref`（它的 tag），不用 `link:` 相对路径直接构建。
- **版本号一律构建时注入**：服务端 build-arg `APP_VERSION`；Electron `-c.extraMetadata.version`；鸿蒙改解包副本里的 `app.json5`（versionCode = (X+1)·1000000 + Y·1000 + Z，只增不减）。
- **客户端发布脚本共用** `templates/multi-end/lib-release.sh`：tag 规则、发布窗口、版本说明、GitHub Release 存档。

#### 桌面应用（独立客户端，没有自己的服务端）

按 `templates/BASELINE.md`「桌面应用」：`templates/desktop/` 的 `release-desktop.sh`（`__PRODUCT__` / `__NAME__` 换掉）、`release-desktop.yml`、`ci-test.sh`，加 `templates/multi-end/lib-release.sh`；`package.json` 的 `version` 固定 `0.0.0`。对象存储前缀 `<名>/desktop/`：用户本人建只能写这个前缀的子账号、给前缀开公共读，再 `gh secret set OSS_ACCESS_KEY_ID / OSS_ACCESS_KEY_SECRET --env production`；`OSS_BUCKET`、`OSS_ENDPOINT` 是环境变量。不登记注册表。

### 4. 首次提交并推到 GitHub

**推送前必须扫 git 历史**：先提交，再 `gitleaks git . --redact`，确认命中都是误报（测试向量、冒烟测试的假 key）再推。不要用 `gitleaks dir`，它会把被忽略的 `.env`、构建缓存也算进去，干净与否看不出来。已有项目要扫**全部历史**，不只是当前版本。

```bash
git add -A && git status            # 逐个确认没有密钥和数据
git commit -m "chore: 按运维规范初始化项目"
gh repo create imelonkid/<名> --private --source . --remote origin --push   # 用户选公开才换 --public
git remote set-url origin git@github.com:imelonkid/<名>.git                 # 之后走 1Password SSH Agent
```

首次上线也走「发布」表单（minor，得到 `v0.1.0`），由上线环节做，初始化阶段不碰服务器。

已有远端但不在 GitHub：旧远端改名（如 `gitea`）保留，GitHub 作为新的 `origin`，推送全部分支和标签；告诉用户迁完再删旧远端。

**历史里有密钥时：**
- 从没推送过的仓库：先 `git bundle create ~/.ops-backup/git/<名>-pre-filter.bundle --all` 备份，再用 `git filter-repo --replace-text` 清掉值，然后复扫。
- 已经推送过的：**先轮换密钥**（旧值作废后，历史里的就无害了），再由用户决定要不要改写历史。

**鸿蒙项目的签名配置**：DevEco 自动签名会把 storePassword / keyPassword / 证书路径写进 `build-profile.json5`。仓库里这个文件的 `signingConfigs` 必须是 `[]`。本机的签名版本先备份到 `~/.ops-backup/git/`，提交后恢复，再执行 `git update-index --skip-worktree <文件>`，并在 CLAUDE.md 写明这个约定。新电脑在 DevEco 里重新自动签名即可。

### 4b. 接入发布流水线（服务）

发布与回滚在 GitHub 上点（手机也行），流水线本体在公开仓库 `imelonkid/melon-ci`，项目只放三个表单：
`templates/workflows/{release,rollback,status}.yml` → `.github/workflows/`（`__NAME__` 换成服务名，多端项目 `tag-prefix: server-v`）。

一次性设置（需要 GitHub Pro：私有仓库的分支保护与 Environments）：

1. **仓库设置按基线应用**：`scripts/github-apply.sh imelonkid/<名>`（定义在 `templates/github/settings.json`：main 必须走 PR、四项检查全绿、管理员也受约束、线性历史、只允许 squash、production 环境只允许 main）；`--check` 只核对。**不要从别的项目抄设置**。
2. **production 环境的变量与密钥**（环境本身由上一步建好）：环境变量 `DEPLOY_HOST`（`deploy@<IP>`）、`DEPLOY_KNOWN_HOSTS`（`ssh-keyscan -t ed25519 <IP>`）。
   **镜像仓库（必需，项目基线 v1）**：环境变量 `ACR_REGISTRY`（实例专属域名）、`ACR_USERNAME`，环境 Secret `ACR_PASSWORD`（用户本人 `gh secret set … --env production` 写入）；ACR 里建好 `<命名空间>/<服务>` 私有仓库；主机上 deploy 用户 `docker login` 一次；服务 conf 写 `REGISTRY=<域名>/<命名空间>`。melon-ci `@v2` 没配镜像仓库直接失败——**所有镜像都进镜像仓库，不经 SSH 上传**（从 GitHub 海外传国内实测 100MB / 50 分钟）。
3. **CI 部署钥匙**：本机生成 ed25519 → 私钥 `gh secret set DEPLOY_SSH_KEY --env production < 私钥` 后立即删除本地文件（不显示、不进对话）→ 公钥存为运维仓库 `agent/authorized/ci-<服务>.pub`（入口自动限定 `--only <服务>`）→ `agent/install.sh <主机>`。
4. 主机上登记服务：`agent/services/<主机>/<服务>.conf` → `agent/install.sh <主机>`（会生成只读部署密钥并登记到仓库）。

注意：用 `GITHUB_TOKEN` 推的 tag 不会触发其他流水线，所以发布是「门禁 → 打 tag → 构建 → 部署」在同一条流水线里接力；表单要显式授予权限（`contents: write, checks: read, deployments: write`），可复用流水线不能自己提权。

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
