# 项目基线 v1

> 2026-10-14 · 规范（要求）在运维仓库 `docs/01-standard.md`；**项目基线是规范在项目里的落地**：一份新项目照着就能满足规范的文件集合与约定。所有项目都对照本基线，**不以任何具体业务项目为样板**。
>
> 项目根目录的 `.melon-baseline` 记录它按哪一版接入；`scripts/check.sh` 按本文逐项检查并报告。

## 按项目类型

| 项 | 服务 | 静态站 | 库或工具 | 规范 |
|---|---|---|---|---|
| git + GitHub（默认私有，`main`，提交信息 `<类型>(<范围>): <中文>`） | ✓ | ✓ | ✓ | §5.1 |
| `.gitignore`（`templates/gitignore`）：`.env`、`data/`、数据库、私钥不进 git | ✓ | ✓ | ✓ | §5.4、§5.5 |
| `README.md`（`templates/README.md`，含上线准入） | ✓ | ✓ | ✓ | — |
| `CLAUDE.md`（`templates/CLAUDE.md`）且有「边界（强制）」 | ✓ | ✓ | ✓ | — |
| `.melon-baseline`（`templates/melon-baseline`） | ✓ | ✓ | ✓ | — |
| `deploy/Dockerfile`（`stacks/<栈>/Dockerfile`）：钉版本、`APP_VERSION` 烘进镜像 | ✓ | ✓ | | §5.1 |
| `deploy/docker-compose.prod.yml`（`templates/docker-compose.prod.yml`）：`mem_limit` / `healthcheck` / `restart`、只绑 127.0.0.1、`env_file: .env`、数据只在 `./data` | ✓ | ✓ | | §5.5、§5.6、§6.5 |
| `.env.example`（`templates/env.example`） | ✓ | 有配置才要 | | §5.4 |
| 健康检查 `GET /health` → `{"ok", "version"}`（`stacks/<栈>/health.*`；静态站在 Caddyfile） | ✓ | ✓ | | §8 |
| `scripts/deploy.sh`（`templates/deploy.sh`）：按 tag 发布 / 回滚 / 状态 / 配置，经主机部署入口 | ✓ | ✓ | | §5.1、§9.3 |
| `scripts/ci-test.sh`（`stacks/<栈>/ci-test.sh`）：不碰外网和真实数据，含 /health 冒烟 | ✓ | ✓ | 有测试就要 | §9 |
| `.github/workflows/`（`templates/workflows/`）：`ci`（melon-ci pr-check）、`release`、`rollback`、`status` | ✓ | ✓ | `ci` | §9.3 |
| **镜像必须进镜像仓库**：CI 构建 → 推 ACR → 主机部署入口按摘要拉取（melon-ci `@v2` 没配就失败，不再经 SSH 上传） | ✓ | ✓ | | §5.1 |
| GitHub 仓库设置（`templates/github/settings.json`，`scripts/github-apply.sh` 应用 / `--check` 核对）：分支保护、合并方式、production 环境 | ✓ | ✓ | | §9.3 |
| 注册表 `registry/services/<名>.yaml`（字段以 `_schema.yaml` 为准） | ✓ | ✓ | | §1、§9.1 |
| 可观测：JSON 日志带 trace_id、OTel（`OTEL_*` 由 compose 注入）、指标命名 `<服务>_<领域>_<事件>_total` | ✓ | | | §8 |

## 技术栈（`templates/stacks/`）

| 栈 | 文件 | 约定 |
|---|---|---|
| `python` | `Dockerfile`、`health.py`、`ci-test.sh` | `python:3.13-alpine`；入口 `app/main.py --data /data --port 8080`；只用标准库时不要 requirements.txt |
| `node` | `Dockerfile`、`health.js`、`ci-test.sh` | `node:22-alpine` + pnpm 10.32.1（corepack）；入口 `src/server.js` |
| `static` | `Dockerfile`、`Caddyfile`、`ci-test.sh` | 构建产物在 `dist/`，Caddy 提供并在 `/health` 返回版本；**静态站也按镜像发布**，与服务同一条 tag 发布 / 回滚路径 |

新增技术栈 = 在 `stacks/` 加一个目录（三件套：Dockerfile、健康检查示例、ci-test.sh），并在本表登记。

## 多端（服务端 + 网页 + 桌面 + 手机，同一仓库）

在「服务」基础上加 `templates/multi-end/`：各端独立 tag（`server-v` / `desktop-v` / `harmony-v`），网页界面由服务端提供，`/api/health` 带 `minClient`，客户端发布脚本共用 `lib-release.sh`。细则见 `SKILL.md`「多端项目」。

## 基线升级

- 基线只在本仓库（melon-skills）升级：改模板 → 升版本号（`templates/melon-baseline` 与本文标题）→ 在下方「变更」写明新增 / 改动了什么、已有项目怎么跟进
- 已有项目跟进后改自己的 `.melon-baseline`；`check.sh` 会对落后的项目给出 △

## 变更

- **v1**（2026-10-14）：首版。技术栈模板（python / node / static）、CLAUDE.md「边界（强制）」、`.melon-baseline`、GitHub 仓库设置（`templates/github/settings.json` + `scripts/github-apply.sh`）、**镜像必须进镜像仓库**（流水线表单改用 melon-ci `@v2`）
