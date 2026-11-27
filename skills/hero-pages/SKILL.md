---
name: hero-pages
description: 维护与接入产品 Hero 宣传页（统一托管在私有仓库 imelonkid/melon-pages）：修改现有落地页、新增产品 Hero 页、按 30 天缓存规则升级静态资源版本、完成桌面/平板/手机响应式与中英切换 QA、校验打包约束并提交 PR。当用户说「改 Hero 页」「更新官网/宣传页」「新增产品落地页」「维护 melon-pages」「hero page」时使用。
---

# Hero 宣传页维护与接入

用于维护统一托管在私有仓库 `imelonkid/melon-pages` 下的各产品纯静态 Hero 宣传页（产品介绍、特性展示、桌面安装包下载引导）。适用范围：**纯公开静态页面及资源**，不含后端接口、用户数据、登录态或运行密钥。

> **公开仓库安全红线**：本 skill 位于公开仓库 `melon-skills`，不写私有 IP、端口、密钥、面板路径或服务器绝对部署路径。实际节点名、证书路径、`<站点目录>` 与线上配置运行时从私有运维仓库 `$OPS_REPO` 读取。

## 0. 动手前先读的事实

先确认本机已检出目标仓库与运维仓库（`$OPS_REPO` 定义在 `~/.zsh/conf.d/ops.zsh`）：

| 读什么 | 在哪 | 用来确认 |
|---|---|---|
| 站点注册表 | `melon-pages/sites.yaml` | 已接入域名、`routing_mode`（`pure-hero` / `hybrid`）、`assets_version`、`download_manifest`、状态 |
| 仓库指南与边界 | `melon-pages/README.md`、`melon-pages/CLAUDE.md` | 更新流程、离线检查、目录边界与技术选型例外 |
| 服务登记 | `$OPS_REPO/registry/services/melon-pages.yaml` | 部署节点、`<站点目录>`、公网端点清单 |
| 边缘路由 | `$OPS_REPO/network/edge/<节点>/hero-pages.conf` 与 `<域名>.conf` | 纯 Hero 白名单映射与混合域名静态/后端分流 |
| 门户与探活 | `$OPS_REPO/portal/config.json`、`$OPS_REPO/monitoring/gatus/config.yaml` | 门户 `page-release` 登记、`online` 版本探针与公网探活 |

## 1. 统一仓库模型（`imelonkid/melon-pages`）

所有产品的 Hero 宣传页统一收口到私有仓库 `imelonkid/melon-pages`，共用一条门户 `page-release` 交付链路，不为每个产品单独起容器或维护多套发布配置：

```text
melon-pages/
├── .melon-baseline               # 项目基线版本
├── CLAUDE.md                     # 强制边界（只管纯公开静态 Hero 页）
├── README.md                     # 站点清单、更新与新增指南、production 环境表
├── sites.yaml                    # 结构化站点注册表（所有已接入域名与元数据）
├── scripts/
│   └── ci-test.sh                # 离线校验：根/子站 index.html、零软链接、体积、本地资源引用
├── .github/workflows/
│   ├── ci.yml                    # melon-ci pr-check@v2
│   └── release-page.yml          # melon-ci page-release@v2（project: melon-pages, page-dir: site）
└── site/                         # 打包发布目录（上线后原子切换至 <站点目录>/current/）
    ├── index.html                # 根目录索引页（打包与检查强校验，不可删除）
    ├── shared/                   # 跨站共享静态资源（经 Nginx alias 挂载，禁止软链接）
    └── <domain>/                 # 各产品独立目录，如 memocat.melonkid.cn/
        ├── index.html
        └── assets/               # 带版本号的静态资源（hero-v1.css、hero-v1.js、download-v1.js 等）
```

`sites.yaml` 每个站点条目须维护以下字段：

| 字段 | 说明 |
|---|---|
| `domain` | 公网域名，且与 `site/<domain>/` 目录名一致 |
| `name` / `product` | 站点显示名与对应产品名 |
| `source_repo` | 产品主仓库（如 `imelonkid/<产品>`） |
| `routing_mode` | `pure-hero`（纯 Hero 域名）或 `hybrid`（与后端 API 共用域名） |
| `download_manifest` | 安装包版本清单地址（如混合模式同源路径或登记的公开清单 URL；无下载可留空/`null`） |
| `assets_version` | 当前静态资源版本（如 `v1`），修改 `assets/` 后递增 |
| `status` / `notes` | 接入状态与备注 |

## 2. 零额外进程的边缘路由模型

上线采用 `TYPE=page` 静态交付，**不起容器、不增进程**，由边缘节点 OpenResty 直接读 `<站点目录>/current/`，按域名分为两种模式：

| 模式 | 边缘配置（`$OPS_REPO/network/edge/<节点>/`） | 路由要点 |
|---|---|---|
| **纯 Hero（`pure-hero`）** | 统一 `hero-pages.conf` | 使用显式白名单 `map $host $hero_site_dir` 映射域名到目录；未命中白名单（`$hero_site_dir = ""`）直接 `return 404`；`root <站点目录>/current/$hero_site_dir;`。切入后移除该域名旧的独立 `.conf`，避免 `server_name` 冲突 |
| **混合 API + Hero（`hybrid`）** | 各自 `<域名>.conf`（如 `memocat.melonkid.cn.conf`） | 保留 `/v1/`、`/health` 等接口转发至本机后端（清掉 `X-Melon-*` 请求头，内部/管理路径返回 `404`）；页面静态路由指向 `<站点目录>/current/<域名>` |

两种模式都必须具备以下 Nginx 规则（具体 `<站点目录>` 与证书路径见 `$OPS_REPO`）：

- **线上版本探针（关键）**：精确匹配暴露发布元数据，供门户 `online` 核对当前上线 tag：
  ```nginx
  location = /.page-release.json {
      alias <站点目录>/current/.page-release.json;
      default_type application/json;
      add_header Cache-Control "no-store";
      add_header Strict-Transport-Security "max-age=31536000" always;
  }
  ```
- **隐藏文件屏蔽**：`location ~ /\. { return 404; }`（精确匹配 `location = /.page-release.json` 优先级高于正则，不受影响）。
- **缓存分层**：`location = /index.html` 设为 `Cache-Control "no-cache"`；`location /assets/` 设为 30 天长缓存（`expires 30d`）。
- **共享资源挂载**：`location /shared/` 使用 `alias <站点目录>/current/shared/;`（对应仓库内的 `site/shared/`），绝不靠目录内软链接复用。

## 3. 打包约束与缓存规则

交付链路使用 `melon-ci` 的 `page-release@v2`（`page_artifact.py` 打包），提交前必须全部满足：

1. **全站总大小 ≤ 64 MiB**：硬上限覆盖 `site/` 下**全部站点与共享目录之和**；`scripts/ci-test.sh` 将预警阈值设在 `< 60 MiB`。图片应按展示尺寸压缩（优先 WebP/优化 PNG），禁止把 DMG 安装包、大视频或原始设计稿放进 `site/`。
2. **零软链接、零路径穿越**：`site/` 下只允许普通文件与目录，禁止任何 symlink 或 `..` 引用；跨站复用统一走 `/shared/` 的 Nginx `alias`。
3. **根目录 `site/index.html` 必需**：`page_artifact.py`、节点拉取脚本和 `check-hero.py` 均强校验 `site/index.html` 存在，不得删改缺失。
4. **禁止提交 `.page-release.json`**：该文件由部署入口在上线切换时生成，仓库 `site/` 内不得包含它。
5. **静态资源版本化（30 天缓存强制要求）**：`/index.html` 不缓存，但 `/assets/` 有 30 天强缓存。凡修改 CSS / JS / 图片内容，**必须更换文件名版本号**（例如 `hero-v1.css` → `hero-v2.css`、`hero-v1.js` → `hero-v2.js`、`download-v1.js` → `download-v2.js`），删除废弃旧文件，并同步更新该站 `index.html` 引用与 `sites.yaml` 的 `assets_version`。
6. **无 GitHub SSH 凭据**：`release-page.yml` 只上传 OSS 版本制品，不配置、不使用任何 `DEPLOY_*` 凭据。

## 4. 设计规范与上线前 QA 清单

每次修改或新增 Hero 页，合并 PR 前逐项核对：

- **视觉与品牌一致**：延续产品自身的温暖克制视觉语言，首屏层级清晰、主 CTA 明确，不引入外网不稳定 CDN，资源自包含。
- **三端响应式实测**：在桌面 `1280px`、平板 `728px`、手机 `390px` 三个宽度下打开本地预览逐一验证：
  - 零横向滚动溢出（`scrollWidth <= clientWidth`）
  - 浏览器控制台零报错、零 404 资源
  - 图片全部正常加载、比例自然无裁切
  - 交互元素（如明信片翻面、场景切换、导航与下载按钮）点击响应正常
- **中英双语切换（ZH / EN）**：语言切换控件位置整洁，标题、正文、按钮、辅助说明与 `aria-label` 等双语文案完整一致，无残留已下线入口（如暂停的网页版入口）或占位词。
- **下载链接严格校验**：若页面通过 JS 读取下载清单（如混合模式同源 `/v1/downloads/desktop/latest.json` 或登记的公开清单 URL），必须用 `new URL()` 严格校验解析出的安装包链接：
  - 协议必须为 `https:`
  - 必须严格匹配该产品登记的 OSS 公开下载前缀且以 `.dmg`（或对应安装包后缀）结尾
  - 拒绝带 `username` / `password`、`search`、`hash` 或非白名单域名/路径的 URL
  - 校验不通过或请求失败时安全降级，不跳转未知地址
- **合规页脚**：公网页面底部必须包含 ICP 备案号 `京ICP备16017845号-2` 与品牌署名 `Made by melonkid ↗`。

## 5. 工作流

### 场景 A：更新已有 Hero 页

1. 在 `melon-pages` 拉取最新 `origin/main` 并开新分支（如 `feat/<产品>-hero-...` 或 `fix/<产品>-hero-...`；PR 合并后分支作废，不复用旧分支）。
2. 编辑 `site/<domain>/index.html` 与 `assets/`；若改动了 `assets/` 下的文件，按第 3 节升级文件名版本号并清理旧文件，同时更新 `sites.yaml` 的 `assets_version`。
3. 本地预览并完成第 4 节全部 QA（1280 / 728 / 390、ZH/EN、交互、下载校验、页脚）。
4. 运行离线检查与密钥扫描：
   ```bash
   bash scripts/ci-test.sh
   gitleaks git . --redact
   ```
5. 使用约定式中文提交信息提交，推送分支并提 PR 到 `main`（**不合并**）。

### 场景 B：接入新产品 Hero 页

1. **在 `imelonkid/melon-pages` 开 PR（目标 `main`）**：
   - 新建 `site/<domain>/index.html` 与版本化 `site/<domain>/assets/`（如 `hero-v1.css`、`hero-v1.js`、`download-v1.js`）。
   - 在 `sites.yaml` 新增一条完整站点记录，并在 `README.md` 站点表格中同步登记。
   - 确认 `scripts/ci-test.sh` 自动覆盖新域名目录及所有本地 `href`/`src` 资产引用。
   - 完成第 4 节全部 QA、跑通 `bash scripts/ci-test.sh` 与 `gitleaks git . --redact`。
2. **在私有运维仓库 `$OPS_REPO` 另开 PR（目标 `main`）**：
   - `routing_mode: pure-hero`：在 `network/edge/<节点>/hero-pages.conf` 的 `map $host $hero_site_dir` 与 `server_name` 白名单中加入 `<domain>`（若有旧独立 `<domain>.conf` 一并移除）；确认证书与 DNS 已就绪。
   - `routing_mode: hybrid`：在 `network/edge/<节点>/<domain>.conf` 保留后端接口转发，静态部分指向 `<站点目录>/current/<domain>`，并补齐 `location = /.page-release.json`、点文件屏蔽、`/index.html`、`/assets/` 与 `/shared/`。
   - 更新 `registry/services/melon-pages.yaml` 的 `endpoints` 与 `monitoring/gatus/config.yaml` 探活条目。
   - 跑通 `$OPS_REPO` 的全部检查与 `gitleaks git . --redact`。
3. 如该产品仓库曾遗留临时 `site/` 或未启用的单仓 `release-page.yml`，在确认迁入 `melon-pages` 后按需清理，避免双份维护。

### 场景 C：首次初始化统一 Hero 仓库 / 新建独立 Hero 仓库（一次性步骤）

> **仅首次建仓需要执行一次**；如果 `imelonkid/melon-pages` 已经完成初始化，日常**新增产品 Hero 站点**（场景 B）或**更新页面**（场景 A）直接复用已有环境，**不需要重复执行本节**。将来若需要另建一个新的 Hero 仓库，可按本节完整复用。

1. **应用 GitHub 仓库基线**（仅 Squash 合并、自动删分支、`main` 分支保护 + 4 项必过 CI 检查、创建仅允许 `main` 部署的 `production` 环境）：
   ```bash
   bash skills/project-init/scripts/github-apply.sh imelonkid/<仓库名> --kind desktop
   ```
2. **准备 OSS 最小权限（复用现有公开下载桶 `melon-download`，不新建桶）**：
   - 在阿里云 RAM 新建专属子账号（如 `oss-<仓库名>`），仅授予目标前缀 `<项目名>/page/*` 的 `oss:PutObject`（无删除权限），AccessKey 存入 1Password `ops/<仓库名>/prod`。
   - 在 `melon-download` 的 Bucket 授权策略（Bucket Policy）中**新增授权**（保留既有规则）：指定资源 `<项目名>/page/*`、所有账号 `*`、仅 `oss:GetObject`，供目标边缘节点免密下载页面包。
3. **实测 OSS 读写权限通畅（必做，避免首次发版撞 403）**：
   复用 `macos-desktop-launch` 既有校验脚本，通过隐藏输入填入刚创建的子账号 AccessKey，一次性验证指定前缀的 `PutObject` 写入与匿名 `GetObject` 回读（若导出了策略 JSON，也可先用同脚本 `policy` 子命令静态校验）：
   ```bash
   python3 skills/macos-desktop-launch/scripts/verify.py \
     oss --bucket melon-download \
         --endpoint oss-cn-beijing.aliyuncs.com \
         --prefix melon-pages/page \
         --write-test
   ```
   确认 PUT 写入（200）与匿名 GET 逐字节回读（200）均通过后再继续。
4. **写入 GitHub `production` 环境变量与密钥**（Secret 走交互输入，不留进终端历史；不配置任何 `DEPLOY_*` 主机 SSH 凭据）：
   ```bash
   # 1. 写入两个非敏感环境变量
   gh variable set OSS_BUCKET --repo imelonkid/melon-pages --env production --body "melon-download"
   gh variable set OSS_ENDPOINT --repo imelonkid/melon-pages --env production --body "oss-cn-beijing.aliyuncs.com"

   # 2. 交互写入两个 OSS 密钥（运行后直接粘贴并回车）
   gh secret set OSS_ACCESS_KEY_ID --repo imelonkid/melon-pages --env production
   gh secret set OSS_ACCESS_KEY_SECRET --repo imelonkid/melon-pages --env production
   ```
   （新建其他独立 Hero 仓库时，将 `--repo imelonkid/melon-pages` 与 `--prefix melon-pages/page` 替换为目标仓库与前缀。）
5. **复检基线与门户权限**：
   ```bash
   bash skills/project-init/scripts/github-apply.sh imelonkid/melon-pages --check --kind desktop
   ```
   确认全部打 `✓`，并确保内网门户使用的 GitHub 细粒度令牌已勾选该仓库的访问权限；随后按 `$OPS_REPO` 文档完成部署入口登记、受限内网 `page-worker` 安装与 `portal/push.sh`。

## 6. 发布纪律与红线

- **PR 是 Agent 的终点**：改动只提 PR 到 `main`，等待用户审阅并合并。
- **禁止 Agent 自行发版或碰主机**：不推送 `page-v*` tag、不手动触发生产发布、不 SSH 到服务器拷贝文件或修改线上配置。
- **门户人工发布**：用户合并 PR 后（如涉及新域名或路由变更，先完成 `$OPS_REPO` 合并与边缘配置下发），在**内网门户**选中 `melon-pages` 的 `hero` 端手动触发发布；出现异常时在门户使用 `internal:page-rollback` 秒级回滚至已保留的历史版本（不重跑 GitHub 构建）。
- **交付时给出版本增量建议**：
  - `patch`：文案调整、样式/交互微修、同结构图片替换、小 bug 修复
  - `minor`：新增产品 Hero 站点、页面大改版或新增功能区块
  - `major`：站点目录契约或路由结构发生不兼容变更
