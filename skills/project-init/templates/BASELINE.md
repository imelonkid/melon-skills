# 项目基线 v2

> 2026-10-14（2026-10-21 增补）· 规范（要求）在运维仓库 `docs/01-standard.md`；**项目基线是规范在项目里的落地**：一份新项目照着就能满足规范的文件集合与约定。所有项目都对照本基线，**不以任何具体业务项目为样板**。
>
> 项目根目录的 `.melon-baseline` 记录它按哪一版接入；`scripts/check.sh` 按本文逐项检查并报告。

## 按项目类型

| 项 | 服务 | 静态站 | 库或工具 | 规范 |
|---|---|---|---|---|
| git + GitHub（默认私有，`main`，提交信息 `<类型>(<范围>): <中文>`）；**PR 一律以 `main` 为目标**，不开叠加 PR（PR 的目标是另一个 PR 的分支：前一个合并后后一个会落空或冲突） | ✓ | ✓ | ✓ | §5.1 |
| `.gitignore`（`templates/gitignore`）：`.env`、`data/`、数据库、私钥不进 git | ✓ | ✓ | ✓ | §5.4、§5.5 |
| `README.md`（`templates/README.md`，含上线准入、GitHub production 环境清单） | ✓ | ✓ | ✓ | — |
| `CLAUDE.md`（`templates/CLAUDE.md`）且有「边界（强制）」 | ✓ | ✓ | ✓ | — |
| `.melon-baseline`（`templates/melon-baseline`） | ✓ | ✓ | ✓ | — |
| `deploy/Dockerfile`（`stacks/<栈>/Dockerfile`）：钉版本、`APP_VERSION` 烘进镜像 | ✓ | ✓ | | §5.1 |
| `deploy/docker-compose.prod.yml`（`templates/docker-compose.prod.yml`）：`mem_limit` / `healthcheck` / `restart`、只绑 127.0.0.1、`env_file: .env`、数据只在 `./data` | ✓ | ✓ | | §5.5、§5.6、§6.5 |
| `.env.example`（`templates/env.example`） | ✓ | 有配置才要 | | §5.4 |
| 健康检查 `GET /health` → `{"ok", "version"}`，`version` = 本次 tag（`stacks/<栈>/health.*`；静态站在 Caddyfile）。**发布流水线用它验收**：门户 `server-release` 的最后一步探 `/health`，版本 = 本次 tag 且健康、稳定 20 秒才算上线完成 | ✓ | ✓ | | §8、§9.3 |
| **发布与回滚只在内网门户上点**（门户「发布」对话框；GitHub「发布 / 回滚 / 状态」表单 `templates/workflows/` 兜底）；**项目里没有部署脚本**。版本号：只修 bug → patch；有新功能 → minor；不兼容（接口、数据、配置要跟着改）→ major。应急用运维终端的 `melon status / rollback / config`（运维仓库 `workstation/bin/melon`，不构建、不产生新版本） | ✓ | ✓ | | §5.1、§9.3 |
| `scripts/ci-test.sh`（`stacks/<栈>/ci-test.sh`）：不碰外网和真实数据，含 /health 冒烟 | ✓ | ✓ | 有测试就要 | §9 |
| `.github/workflows/`（`templates/workflows/`）：`ci`（melon-ci pr-check，自带读私有包的令牌）、`release`、`rollback`、`status` | ✓ | ✓ | `ci`；Node 库另加发布表单（melon-ci `npm-release`，发到 GitHub Packages，`package.json` 的 `version` 固定 `0.0.0`、版本号按 tag 注入） | §9.3 |
| **镜像必须进镜像仓库**：CI 构建 → 推镜像仓库（用哪家是平台事实，见运维仓库 `registry/sites.yaml`）→ 节点部署入口按摘要拉取（melon-ci `@v2` 没配就失败，不再经 SSH 上传） | ✓ | ✓ | | §5.1 |
| GitHub 仓库设置（`templates/github/settings.json`，`scripts/github-apply.sh` 应用 / `--check` 核对）：分支保护、合并方式、production 环境 | ✓ | ✓ | | §9.3 |
| 注册表 `registry/services/<名>.yaml`（字段以 `_schema.yaml` 为准） | ✓ | ✓ | | §1、§9.1 |
| 登记到门户（运维仓库 `portal/config.json`）：每一端按端类型选发布流水线 `ends[].pipelines.release.use`——服务端 `server-release`、桌面端 `desktop-release`、小程序 `mp-release` | ✓ | ✓ | | §9.3 |
| 可观测：JSON 日志带 trace_id、OTel（`OTEL_*` 由 compose 注入）、指标命名 `<服务>_<领域>_<事件>_total` | ✓ | | | §8 |
| 运营后台 / 管理界面：只在内网（`<服务>.in.melonkid.cn`，经网关统一认证：设备 + 门户会话 + 门户分配的项目权限），**不做自己的账号密码**——凭网关转来的门户身份（请求头 `X-Melon-Uid` / `X-Melon-User` / `X-Melon-Emp` / `X-Melon-Name` / `X-Melon-Role`）统一登录，按门户账号 id 关联、第一次进来自动建；公网入口清掉 `X-Melon-*`、管理路径 404；样板：yuxian `admin/auth/sso`（运维规范 §6.6） | ✓ | | | §6 |
| 日志与错误上报（运维仓库 `docs/11-logging.md`）：stdout 一行一条 JSON（`ts` / `level` / `service` / `version` / `trace_id` / `event` / `msg`），请求日志一请求一条；追踪号 `X-Request-Id`（响应头回传，错误响应体带 `traceId`）；密码、token、手机号等脱敏；客户端只报 warn / error，gzip 批量发 `POST /api/v1/client-logs`。Node 服务端、浏览器、uni-app **用公共包 `@imelonkid/common`**（钉确切版本；各端 `.npmrc` 指向 GitHub Packages、令牌走 `NODE_AUTH_TOKEN`；Dockerfile 用 BuildKit secret `npm_token`；发布表单加 `packages: read`；包设置里授予本仓库读权限）。其他技术栈按规范自行实现 | ✓ | | | §8 |
| **第三方镜像**（数据库、缓存等）：也从镜像仓库拉，写 `<镜像仓库>/<命名空间>/<名>:<版本>@sha256:…`。先在运维仓库 `registry/mirror-images.txt` 登记，「同步第三方镜像」用 skopeo 复制到镜像仓库；**摘要以同步结果（同步摘要页）为准**，不一定等于 Docker Hub 上的（个别官方镜像镜像仓库只收 linux/amd64）。**不直接用 Docker Hub**：国内节点拉不动，旧摘要会被回收，灾备重建会失败 | ✓ | ✓ | | §5.1、§5.2 |
| **用户上传的文件**（头像、图片等）一律放对象存储（OSS / COS，S3 兼容接口），**不存服务的数据目录**；子账号按前缀最小权限（只能读写本服务的前缀）、**没有删除权限**；阿里云 RAM 策略的资源用新版 ARN `acs:oss:oss-<地域>:<主账号ID>:<桶>/<前缀>/*`，配完先实测上传 | ✓ | | | §5.8 |


## 技术栈（`templates/stacks/`）

| 栈 | 文件 | 约定 |
|---|---|---|
| `python` | `Dockerfile`、`health.py`、`ci-test.sh` | `python:3.13-alpine`；入口 `app/main.py --data /data --port 8080`；只用标准库时不要 requirements.txt |
| `node` | `Dockerfile`、`health.js`、`ci-test.sh`、`npmrc` | `node:22-alpine` + pnpm 10.32.1（corepack）；入口 `src/server.js`；依赖 `@imelonkid/common`（钉确切版本）：`npmrc` 复制为 `.npmrc`，Dockerfile 安装依赖那一步挂 BuildKit secret `npm_token`（令牌不进镜像层） |
| `static` | `Dockerfile`、`Caddyfile`、`ci-test.sh` | 构建产物在 `dist/`，Caddy 提供并在 `/health` 返回版本；**静态站也按镜像发布**，与服务同一条 tag 发布 / 回滚路径 |

新增技术栈 = 在 `stacks/` 加一个目录（三件套：Dockerfile、健康检查示例、ci-test.sh），并在本表登记。

## 多端（服务端 + 网页 + 桌面 + 手机，同一仓库）

在「服务」基础上加 `templates/multi-end/`：各端独立 tag（`server-v` / `desktop-v` / `harmony-v`），网页界面由服务端提供，`/api/health` 带 `minClient`，客户端发布脚本共用 `lib-release.sh`。细则见 `SKILL.md`「多端项目」。

### 小程序端（多端项目里的一端，2026-10-15）

适用：服务端 + 微信小程序（uni-app 等）同一仓库，如 yuxian。小程序装在用户手机上、要过微信审核、收不回来，所以和服务端分开发布。模板 `templates/multi-end/release-mp.sh`、`release-mp.yml`。

| 项 | 要求 |
|---|---|
| 目录与 tag | `apps/miniapp`；tag `mp-vX.Y.Z`，与 `server-v` 各自独立 |
| 发布 | 门户「发布」（流水线 `mp-release`；GitHub「发布小程序」表单兜底）→ melon-ci `mp-release@v2`：门禁（发布窗口、main 的 CI 全绿）→ 打 tag → 从 tag 构建 → **经部署入口在固定 IP 的主机上上传为体验版**（`deploy-agent mp-upload`，用 `miniprogram-ci`，机器人号固定）→ GitHub Release 记录版本说明 |
| 上传密钥 | 微信「代码上传密钥」只放在上传主机（运维仓库登记，root 所有、部署入口可读），**不进 GitHub**；微信后台开 IP 白名单，只放上传主机的 IP |
| 提审与上线 | 微信没有提审 / 查线上版本的接口：体验版测过后在微信后台提审、审核通过后全量发布；门户流水线「提审」「发布上线」两个节点由人在门户上确认（记在发布说明里） |
| 回滚 | 微信后台「版本回退」（只能回到上一个线上版本）；不行就修复后发 patch |
| 版本号 | 构建时注入（`VITE_APP_VERSION` = tag 去掉前缀），不改源码；上传时 `version` 同 tag，`desc` 是版本说明 |
| 环境 | 接口域名等按构建模式注入（`.env.production` 只放非秘密的公开地址）；**小程序代码里不放任何密钥**（AppSecret、商户密钥只在服务端） |
| 兼容 | 服务端 `/api/health` 带 `minClient.mp`；小程序启动时比对，低于就用 `wx.getUpdateManager` 强制更新。服务端至少兼容上一个小程序版本，新小程序全量后才提高 `minClient.mp` |
| 上线准入 | 合法域名（request / uploadFile / downloadFile）只配 HTTPS 正式域名；隐私保护指引与实际收集的信息一致；类目、备案、微信认证（`docs/` 里一张清单） |

## 桌面应用（独立客户端，没有自己的服务端）

适用：只有桌面端、靠别的平台接口工作的客户端（如内网接入客户端 Vine）。和服务有自己的发布方式；与「多端」里的桌面端区别是：没有服务端下载站，版本清单也放对象存储。模板在 `templates/desktop/`。

| 项 | 要求 |
|---|---|
| 技术栈 | Electron + electron-builder（Mac arm64 先行）；`package.json` 的 `version` 固定 `0.0.0`，**版本号构建时注入**（`-c.extraMetadata.version`） |
| 发布 | `.github/workflows/release-desktop.yml`（模板）→ melon-ci `desktop-release@v2`，`tag-prefix: v`、`manifest: oss`；tag `vX.Y.Z`；门禁同服务（发布窗口、main 的 CI 全绿） |
| 发布脚本 | `scripts/release-desktop.sh`（模板，`build` / `publish` / `oss-test`）+ `scripts/lib-release.sh`（`templates/multi-end/`）；构建前要编译的东西放 `scripts/prebuild.sh`；**打包后检查产物放 `scripts/verify-build.sh`**（随应用分发的文件缺一个就不发布）。脚本里变量后紧跟全角字符一律写 `${…}` |
| 分发 | 安装包与 `latest.json`（含 sha256）都在对象存储 `<名>/desktop/`，安装包先传、清单最后传；GitHub Release 存档。子账号**只能写**这个前缀，公网**只读**也只开这个前缀 |
| 更新 | 客户端启动后与每 6 小时读 `latest.json`，有新版提示下载（没有 Apple 开发者签名做不了静默更新，写进 README 的已知限制） |
| production 环境 | 变量 `OSS_BUCKET`、`OSS_ENDPOINT`；Secret `OSS_ACCESS_KEY_ID`、`OSS_ACCESS_KEY_SECRET`（用户本人 `gh secret set … --env production`）。不需要部署入口 |
| CI | `ci.yml`（pr-check）+ `scripts/ci-test.sh`（模板：语法检查 + `node --test`，不下载 Electron） |
| 注册表 | 不部署到服务器，不登记 `registry/services/`；它依赖的服务端接口写进 CLAUDE.md「契约」 |

## 基线升级

- **例外**（登记在项目的注册表 `known_gaps`）：鸿蒙客户端暂时只能本机构建签名（`scripts/release-harmony.sh`），等 AGC 证书与 CI 就位后上线上
- 基线只在本仓库（melon-skills）升级：改模板 → 升版本号（`templates/melon-baseline` 与本文标题）→ 在下方「变更」写明新增 / 改动了什么、已有项目怎么跟进
- 已有项目跟进后改自己的 `.melon-baseline`；`check.sh` 会对落后的项目给出 △

## 变更

- **v2 增补**（2026-10-21）：对齐已上线的平台事实——发布 / 回滚只在内网门户上点（GitHub 表单兜底），版本号 patch / minor / major 口径；门户按端类型选流水线（`server-release` 用 `/health` 的 `version` = tag 验收、`desktop-release`、`mp-release` 两个人工确认）；日志规范要点与公共包 `@imelonkid/common` 的接入（`templates/stacks/node/` 加 `npmrc`、Dockerfile 挂 `npm_token`，发布表单加 `packages: read`）；运营后台身份头加 `X-Melon-Role`；第三方镜像摘要以同步结果为准；**用户上传文件一律对象存储**；**PR 一律以 main 为目标**；Node 库用 melon-ci `npm-release`。`check.sh` 新增几条 △（Node 端是否接公共包及其 `.npmrc` / 读包令牌、小程序端发布表单）。不升版本号；已有项目：按 △ 补，用户上传还存在数据目录的写进 `known_gaps` 并迁到对象存储

- **v2 增补**（2026-10-19）：**第三方镜像也必须来自镜像仓库**（钉版本 + 摘要，登记在运维仓库 `registry/mirror-images.txt`）；`check.sh` 拒绝 Docker Hub 镜像。基线文字不写具体云（「镜像仓库」「对象存储」，选型在运维仓库 `sites.yaml`）。现有项目没有第三方镜像的不用跟进；有的按上面改 compose

- **v2 增补**（2026-10-17）：README 模板加「GitHub production 环境」清单（每个变量 / Secret 的用途、对应运维侧哪条登记、谁写入）；GitHub 上没有备注字段。已有项目按实际情况补一张

- **v2 增补**（2026-10-15）：多端里新增「小程序端」（`templates/multi-end/release-mp.*`，melon-ci `mp-release`，部署入口 `mp-upload`）。不影响已有项目

- **v2 增补**（2026-10-15）：新增「桌面应用」类型（`templates/desktop/`，melon-ci `desktop-release` 的 `manifest: oss`）。只是加了一类项目，已有项目不用跟进，不升版本号

- **v2**（2026-10-14）：**本机不发版**——删掉 `templates/deploy.sh`，项目不再有 `scripts/deploy.sh`；发布走线上（表单或门户），应急只用 `melon status / rollback / config`；桌面端发布脚本去掉本机发版模式。跟进：删掉项目里的 `scripts/deploy.sh`，README / CLAUDE.md 的发布说明改为线上 + `melon`，`.melon-baseline` 改为 `v2`

- **v1**（2026-10-14）：首版。技术栈模板（python / node / static）、CLAUDE.md「边界（强制）」、`.melon-baseline`、GitHub 仓库设置（`templates/github/settings.json` + `scripts/github-apply.sh`）、**镜像必须进镜像仓库**（流水线表单改用 melon-ci `@v2`）
