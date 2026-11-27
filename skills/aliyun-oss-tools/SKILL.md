---
name: aliyun-oss-tools
description: 阿里云 OSS 权限与接入工具：创建最小权限 RAM 子账号与自定义写策略、配置 Bucket 匿名只读授权、静态核对策略 JSON、实测目标前缀的 PUT 写入与匿名 GET 回读、排查 403/SignatureDoesNotMatch，以及写入 GitHub production 环境的 OSS 变量与密钥。当用户说「建 OSS 子账号」「配 OSS 权限」「校验 OSS 读写」「排查 OSS 403」「阿里云 OSS 工具」时使用。
---

# 阿里云 OSS 工具

为各项目（桌面端分发、Hero 静态页制品交付、业务媒体/备份上传）提供统一的阿里云 OSS 最小权限配置流程与校验脚本。

> **公开仓库安全红线**：本 skill 位于公开仓库 `melon-skills`，不写主账号 UID、真实 AccessKey、私有 IP 或服务器部署路径。AccessKey 仅由凭据持有人在本机隐藏终端输入，原件保存在 1Password。

以下为 zsh 或 bash 命令，将 `OSS_SKILL` 设为本技能目录（例如 `~/Workspace/melon-skills/skills/aliyun-oss-tools`）：

```bash
oss_tool() { python3 "$OSS_SKILL/scripts/oss_verify.py" "$@"; }
```

## 1. 创建最小权限 RAM 子账号流程（云账号管理员）

原则：**按项目与用途隔离前缀**，只授 `oss:PutObject`，**不授 `oss:DeleteObject` / `oss:ListObjects` / `AliyunOSSFullAccess`**，不开通控制台密码登录。

1. **生成标准最小权限策略 JSON**（只读输出，方便直接复制到阿里云控制台）：
   ```bash
   oss_tool render-policy --region oss-cn-beijing --owner <主账号数字UID> --bucket <桶名> --prefix <项目/前缀>
   ```
   - `<主账号数字UID>` 必须是**阿里云主账号的数字 ID**（控制台右上角头像 → 账号中心可见），**不是** RAM 子账号 UID，也不是 `LTAI...` AccessKey ID。
   - 地域段必须带 `oss-` 前缀（如 `oss-cn-beijing`），不要写成 `cn-beijing`。
   - 前缀不带首尾斜杠，如 `memocat/desktop` 或 `melon-pages/page`。
2. **创建自定义策略**：
   - 阿里云 RAM 控制台 → 权限管理 → 权限策略 → 创建权限策略 → **脚本编辑**。
   - 推荐策略名：`oss-<项目>-<用途>-write`（如 `oss-melon-pages-page-write`）。
   - 粘贴第 1 步生成的 JSON：
     ```json
     {
       "Version": "1",
       "Statement": [
         {
           "Effect": "Allow",
           "Action": ["oss:PutObject"],
           "Resource": ["acs:oss:oss-cn-beijing:<主账号数字UID>:<桶名>/<前缀>/*"]
         }
       ]
     }
     ```
3. **创建或复用 RAM 子账号并附加策略**：
   - 独立新仓库建议新建子账号（如 `oss-<项目>`）；同仓库已有子账号且明确复用时，仅**追加**新策略、保留既有策略不动。
   - 访问方式只勾选 **「使用永久 AccessKey 访问（OpenAPI）」**，不开启控制台登录。
   - 进入子账号 → **权限管理 → 新增授权**，附加第 2 步创建的自定义策略。
   - 立即将生成的 `AccessKey ID` 与 `AccessKey Secret` 保存到 1Password `ops/<项目>/prod`。

## 2. 配置 Bucket 匿名只读授权（公开下载 / 边缘拉包场景）

仅在目标前缀需要公开下载（如桌面 DMG、Hero 静态页版本包）时执行；**私有业务桶 / 备份桶跳过本节**。

1. OSS 控制台 → 目标 Bucket（如公开制品桶 `melon-download`）→ **权限控制 → Bucket 授权策略**。
2. 点击 **「新增授权」**（**不要**整份覆盖已有策略，保留其他项目的前缀规则）：
   - **授权资源**：指定资源 `<前缀>/*`（如 `melon-pages/page/*`）
   - **授权用户**：所有账号（`*`）
   - **授权操作**：高级自定义，仅勾选 `oss:GetObject`（或简单设置选「只读（不含列举）」）
3. 无需预先创建空目录；首次上传对象时自动显现前缀路径。

## 3. 权限校验脚本（必做，先验通再发版）

### 3.1 静态核对导出的策略 JSON（可选，只读）

若从控制台导出了 RAM 策略和 Bucket Policy JSON，可先做静态范围校验：

```bash
oss_tool policy \
  --ram "$RAM_POLICY_FILE" \
  --policy "$BUCKET_POLICY_FILE" \
  --region oss-cn-beijing \
  --owner <主账号数字UID> \
  --bucket <桶名> \
  --prefix <项目/前缀>
```

> 私有写前缀（无匿名读）可省略 `--policy` 并加 `--no-public-read`。

### 3.2 实测 PUT 写入与匿名 GET 回读（强烈推荐每次改权限后必跑）

脚本会在终端以隐藏输入读取 `AccessKey ID` / `AccessKey Secret`，向 `<前缀>/ci-test.txt` 写入一次性随机内容，再匿名 GET 逐字节比对并打印 `x-oss-request-id`（会覆盖该前缀下的 `ci-test.txt`，需显式传 `--write-test`）：

```bash
oss_tool probe \
  --bucket <桶名> \
  --endpoint oss-cn-beijing.aliyuncs.com \
  --prefix <项目/前缀> \
  --write-test
```

常用可选参数：
- `--read-base https://<CDN或自定义下载域名>/<目录>`：当外部通过 CDN 或独立下载域名回读时，从实际下载入口验证匿名读。
- `--skip-read`：仅验证私有前缀的 `PUT` 写入权限，不执行匿名 `GET` 回读。

只有本次 `PUT 200` 且 `GET 200`（内容逐字节匹配，非历史旧文件）均通过，才记为权限打通。

## 4. 写入 GitHub `production` 环境变量与密钥（首次接入一次性）

仅在仓库首次接入 OSS 交付时执行一次；Secret 采用交互隐藏输入，不留进终端历史：

```bash
# 1. 写入非敏感环境变量
gh variable set OSS_BUCKET --repo imelonkid/<仓库名> --env production --body "<桶名>"
gh variable set OSS_ENDPOINT --repo imelonkid/<仓库名> --env production --body "oss-cn-beijing.aliyuncs.com"

# 2. 交互写入 OSS 密钥（粘贴后回车）
gh secret set OSS_ACCESS_KEY_ID --repo imelonkid/<仓库名> --env production
gh secret set OSS_ACCESS_KEY_SECRET --repo imelonkid/<仓库名> --env production
```

核对 GitHub `production` 环境是否配齐（只读）：

```bash
oss_tool env --repo imelonkid/<仓库名> --bucket <桶名> --endpoint oss-cn-beijing.aliyuncs.com
```

## 5. 常见 HTTP 403 / 失败排障清单

| 现象 | 优先排查项 |
|---|---|
| `PUT 403 AccessDenied` | ① RAM 策略 `Resource` 里的 `<主账号数字UID>` 是否误填为子账号 UID 或保留了占位符；② 地域段是否漏写 `oss-`（应为 `oss-cn-beijing` 或 `*`）；③ 路径是否与 `<桶名>/<前缀>/*` 一致；④ 自定义策略是否真的已附加到该 RAM 子账号（权限生效约需 10–30 秒） |
| `PUT 403 SignatureDoesNotMatch` | ① `AccessKey Secret` 粘贴时前后混入空格/换行；② `OSS_ACCESS_KEY_ID` 与 `OSS_ACCESS_KEY_SECRET` 填反；③ 本机系统时间偏差过大 |
| `PUT 200` 但 `GET 403` / `404` | ① Bucket Policy 匿名 `oss:GetObject` 未覆盖目标 `<前缀>/*`；② Bucket 开启了阻止公共访问或存在显式 `Deny` 规则；③ 使用 `--read-base` 时 CDN 回源路径与写入前缀不匹配 |
| `GET 200` 但提示「读回内容与本次写入不符」 | CDN 缓存了旧版 `ci-test.txt` 或匿名读取路径指向了另一个目录 |

## 6. 与其他 Skill 的协作关系

- **`macos-desktop-launch`**：桌面端首次上线第 1 步（权限配置与 `policy` 核对）、第 3 步（OSS Secret）与第 5 步（`probe --write-test`）直接引用本 skill 与 `scripts/oss_verify.py`。
- **`hero-pages`**：统一 Hero 仓库 `imelonkid/melon-pages`（或新建独立 Hero 仓库）首次初始化配置 OSS 权限与实测探活时直接引用本 skill。
- **`project-init`**：涉及对象存储前缀最小权限的通用约定可参照本 skill 执行。
