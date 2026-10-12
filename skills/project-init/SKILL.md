---
name: project-init
description: 按 melonkid 多云运维规范初始化项目。用于"新建项目 / 初始化工程 / 起一个新服务 / new project"，以及"把已有项目纳入规范 / 补 git / 准备上线"。负责 git + GitHub 托管、目录骨架、部署模板、密钥约定、服务注册与上线准入检查。
---

# 项目初始化

目标：项目从第一天起就满足运维规范，将来上线时**不用返工**。

规范原文与主机事实在私有仓库 `~/Workspace/melon-ops`（下称 ops 仓库）：

| 读什么 | 在哪 |
|---|---|
| 规范（数据分级、灾备等级、可重建性、准入清单） | `docs/01-standard.md` |
| 站点与分工 | `registry/sites.yaml`、`docs/02-sites.md` |
| 服务清单字段 | `registry/services/_schema.yaml`，参考同目录现有服务 |

**ops 仓库不在本机时**：照常做第 1–3 步，跳过第 4 步，结束时提醒用户"未注册"。本 skill 在公开仓库里，**不要把 IP、密钥、面板路径写进本 skill 或模板**。

## 硬性要求

1. **所有项目必须由 git 托管，远端必须是 GitHub**（`github.com/imelonkid/<名>`）。
   不用自建 Gitea 等任何跑在业务服务器上的托管：服务器挂了，代码和数据会一起没（规范 §5.1）。
2. 第一次提交之前 `.gitignore` 就要就位：`.env`、`data/`、`*.db`、私钥一律不进 git。
3. 新仓库**默认私有**；用户明确说公开才公开。
4. 默认分支 `main`；提交信息 `<类型>(<范围>): <中文描述>`，类型用 feat / fix / docs / chore / refactor。

## 流程

### 0. 先问清楚

先看用户已经说了什么、当前目录里已有什么，**只问推不出来的**，一次问完（AskUserQuestion）：

| 项 | 选项 / 默认 |
|---|---|
| 项目名 | kebab-case；同时是 GitHub 仓库名、compose 项目名、容器名、`/opt/<名>` |
| 类型 | **服务**（要部署）/ **静态站** / **库或工具**（不部署）|
| 技术栈 | 按用户说的；没说就问 |
| 仓库可见性 | 私有（默认）/ 公开 |
| 只对"服务" | 主站点、数据等级（T0/T1/T2）、对外域名 |

站点怎么选（以 ops 仓库 `docs/02-sites.md` 为准）：重点业务（小程序）→ ali；个人项目 → tx；jd 是运维中心 + 温备，**不放新业务**。
数据等级：有用户数据（账号、订单、消息、对话）就是 **T0**；用户上传的媒体是 T1；能从代码或公开来源重建的是 T2。

### 1. 本地目录与 git

- 位置：`~/Workspace/<名>`，用户另有指定除外。
- 已有项目：先 `git status`，有 git 就保留历史，只补缺的；**不要重写历史**。
- 发现已提交的密钥或数据库文件：停下来告诉用户，别自己 `filter-repo`。

```bash
git init -b main
cp <skill>/templates/gitignore .gitignore     # 再按技术栈追加 node_modules、__pycache__ 等
```

### 2. 骨架

所有类型都要：

| 文件 | 来源 |
|---|---|
| `README.md` | 一句话说明 + 本地运行 + 部署（服务类）|
| `CLAUDE.md` | `templates/CLAUDE.md`，填好占位符 |
| `.gitignore` | 第 1 步 |

**服务**再加：

| 文件 | 来源 | 要点 |
|---|---|---|
| `deploy/Dockerfile` | 按技术栈写 | 多阶段构建；最终镜像里要有 `wget` 或 `curl`（健康检查用）|
| `deploy/docker-compose.prod.yml` | `templates/docker-compose.prod.yml` | 见下方「容器规范」|
| `deploy/docker-compose.yml` | 按需 | 本地开发用 |
| `.env.example` | `templates/env.example` | 列出全部变量，值留空或给示例 |
| `scripts/deploy.sh` | `templates/deploy.sh` | 本地构建 → 传镜像 → 重建 → 健康检查 → 不过就回滚 |
| 健康检查接口 | 代码里 | `GET /health` 返回 200；能顺带检查数据库连接更好 |

**静态站**：构建产物不进 git；部署脚本用 `rsync` 时只同步构建目录，**不要对干净 checkout 用 `--delete`**（会删掉线上未进 git 的文件）。

#### 容器规范（规范 §5）

- 每个容器都要有 `mem_limit`、`healthcheck`、`restart: unless-stopped`。
- 端口只绑 `127.0.0.1`，对外统一经反向代理走 HTTPS；**不开新的安全组端口**。
- 持久化数据只放 `./data/`（服务器上即 `/opt/<名>/data/`），不在里面堆手工 `.bak`。
- 配置用服务内的 `env_file: .env`，**不要**靠 `--env-file` 插值：后者不会记进容器标签，灾备重建时容易漏掉。
- 日志写 stdout，JSON 格式；密码、token、手机号必须脱敏。
- SQLite 开 WAL；备份只用 `sqlite3 .backup`，不要直接 `cp`。
- 对象存储走 **S3 兼容接口**（boto3 / aws-sdk），不要用 `oss2` 这类厂商专有 SDK：主云出事时，要能切到另一朵云的副本。
- 镜像在本机构建 `linux/amd64`，经 `docker save | ssh docker load` 传上去；服务器上不构建。镜像标签用 `git describe`，线上版本要能追溯到 commit。

#### 密钥

- 真实值只放 1Password，条目名 `ops/<名>/prod`。**由用户自己创建和填写**，Claude 不经手密钥值。
- 服务器上的 `/opt/<名>/.env` 只是副本，部署脚本不碰它。

### 3. 首次提交并推到 GitHub

```bash
git add -A && git status            # 逐个看一眼要提交的文件，确认没有密钥和数据
git commit -m "chore: 按运维规范初始化项目"
gh repo create imelonkid/<名> --private --source . --remote origin --push   # 用户选公开才换成 --public
```

- 远端用 SSH 地址：`git remote set-url origin git@github.com:imelonkid/<名>.git`（密钥在 1Password SSH Agent，推送时会弹授权）。
- 已有远端但不在 GitHub（比如自建 Gitea）：新增 GitHub 远端并推送全部分支和标签，**旧远端先保留**，告诉用户迁移后再删。

### 4. 注册（只对服务）

在 ops 仓库新建 `registry/services/<名>.yaml`，以 `templates/service.yaml` 为底，字段对照 `_schema.yaml`：

- `status: building`，上线后改 `active`；
- `tier`、`dr_level`：T0 有状态服务填 L2，T1 填 L1，无状态填 L3；
- `site` / `failover_site` / `witness_site` 按 `sites.yaml` 里的 `standby_pairs` 填；
- `deploy.up` 写完整的启动命令，灾备重建就靠它；
- 每份持久化数据写一条 `assets`；T2 必须写 `rebuild`；
- 做不到的规范条款写进 `known_gaps`，不要假装满足。

然后在 ops 仓库提交（`feat(registry): 登记 <名>`）。**推不推送问用户**。

### 5. 检查

```bash
<skill>/scripts/check.sh <项目目录>
```

只读。✗ 必须修；△ 是上线前要补的，写进 README 的「上线前待办」。

### 6. 交付时告诉用户

1. 仓库地址、可见性、已推送的提交；
2. check.sh 的结果；
3. **需要用户本人做的事**：
   - 在 1Password 创建 `ops/<名>/prod`；
   - 服务器上建目录（ali 上需要 sudo）：`sudo mkdir -p /opt/<名>/data && sudo chown <部署用户> /opt/<名>`；
   - 对外域名：确认承接站点已完成 ICP 接入；DNS 记录 TTL ≤ 300；反向代理与 HTTPS 证书；
4. 上线前还缺的准入项（规范 §9.2）：首次备份与恢复验证、Gatus 探活、告警。这些放到上线时用 server-ops skill 做，**初始化阶段不要碰服务器**。

## 不要做

- 不要在初始化阶段 ssh 到服务器、改安全组、改 DNS。
- 不要替用户在 1Password、云控制台里录入任何东西。
- 不要用 `git push --force`，不要改已有项目的提交历史。
- 不要创建公开仓库，除非用户明确要求。
