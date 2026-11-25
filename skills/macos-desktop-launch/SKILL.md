---
name: macos-desktop-launch
description: 按 melon 门户流程接入、发布或验收使用 Developer ID 签名并通过 OSS 分发 DMG 的 macOS 桌面 App。适用于首次上线、已有项目发版和失败发布续跑。
---

# macOS 桌面 App 上线

按本页顺序推进。**首次接入**走第 0～8 步；**常规发版**从第 7 步进入；**配置变更或发布失败**从受影响的检查恢复。每步记下目标、负责人、验证结果和证据（PR、run、tag、Request ID 或摘要），再进入下一步。一次发布的目标始终取自当前应用。

先从应用工作流、发布脚本、门户登记及项目基线核实变量：应用仓库 `REPO`、OSS 的 `BUCKET`、`ENDPOINT`、对象目录 `PREFIX`、实际下载基础 URL `DOWNLOAD_BASE`、发布工作流文件名 `WORKFLOW`、标签前缀 `TAG_PREFIX`、清单模式 `MODE`（`oss` 或 `deploy`）、清单 URL `MANIFEST`。桶与路径分开填写，前缀不带首尾斜杠。新接入的项目尚无登记时，从拟合并的应用与运维 PR 核对。在执行前展示这一行目标供用户辨认：

> 仓库 / 发布端 / 生产环境 / OSS 写入路径 / 玩家下载位置 / 版本清单 / 标签前缀

以下为 zsh 或 bash 命令。将 `SKILL_DIR` 设为本技能所在目录，从本机私有运维配置取得 `OPS_REPO`，`PROJECT_INIT` 设为当前项目基线技能目录。命令中的其余大写变量由本次目标或用户选择提供。凭据由持有人在自己的隐藏输入框或终端输入。

```bash
check() { python3 "$SKILL_DIR/scripts/verify.py" "$@"; }
```

## 第 0 步（维护者）：接入基线并建立 production 环境

核对当前桌面基线。按本次变更开 PR：应用仓库接入发布工作流、运维仓库登记桌面端；只有通用基线实际缺能力时才开基线 PR。已有接入直接核对。在获得推送与开 PR 的授权后交付变更。

应用 GitHub 桌面规范，建立环境，再写入两个非机密变量。基线脚本末尾可能报告第 3 步尚未填写的 Secret；确认环境和变量已建立，并在第 3 步重跑完整检查。分支保护等设置失败要先处理。

```bash
bash "$PROJECT_INIT/scripts/github-apply.sh" "$REPO" --kind desktop
gh variable set OSS_BUCKET --body "$BUCKET" --env production -R "$REPO"
gh variable set OSS_ENDPOINT --body "$ENDPOINT" --env production -R "$REPO"
check environment --repo "$REPO" --bucket "$BUCKET" --endpoint "$ENDPOINT"
```

有新 PR 时，将实际 PR 链接逐个传给 `check prs opened`。普通 PR 用 Linux 检查；正式签名、公证安排在按标签构建的 macOS 作业。

## 第 1 步（云账号管理员）：为应用下载目录配置读写权限

1. RAM 中选择本次发布身份，核对它对 `$BUCKET/$PREFIX/*` 的 `oss:PutObject` 权限。资源 ARN 使用桶所属主账号 ID。子用户 UID、AccessKey ID 含义不同。
2. OSS 控制台 → 目标 Bucket → 权限控制 → Bucket 授权策略。对匿名账号仅授予该目录对象的 `oss:GetObject`。允许玩家直接下载即可，不需要列桶或删除权限。遇到阻止公共访问时，先核对项目登记的实际公开下载方案。
3. 如有导出的 RAM 和 Bucket 策略，用下式核对明确授权的目标目录。此检查只匹配项目级授权声明；通过 CDN 或共享身份等其他策略实现时按其实际配置核验，不为匹配示例新增权限。最终读写能力在第 5 步实测。

```bash
check policy --ram "$RAM_POLICY_FILE" --policy "$BUCKET_POLICY_FILE" --region "$OSS_REGION" --owner "$BUCKET_OWNER" --bucket "$BUCKET" --prefix "$PREFIX"
```

## 第 2 步（凭据持有人）：备齐签名、公证和上传材料

准备发布身份的一对 AccessKey、包含正式签名私钥的 Developer ID Application .p12 及导出密码、Apple 公证 .p8、Key ID 和 Issuer ID。需要重新导出 .p12 时，使用「钥匙串访问 → 我的证书」。如使用 1Password，可从已有条目取得，或按项目保存。

在持有人本机验证文件可用性：

```bash
bash "$SKILL_DIR/scripts/verify-materials.sh" "$P12_FILE" "$P8_FILE"
```

如使用 1Password CLI，另可执行 `check vault --refs "$REFS_JSON"` 验证材料可读。JSON 的 `ak_id, ak_secret, p12, p12_password, p8, key_id, issuer_id` 七个键只填各自的 `op://` 引用。Apple 对 Key ID 与 Issuer ID 组合的实际认可，以正式公证作业为准。

## 第 3 步（仓库管理员）：写入并核对 production 配置

使用目标仓库和第 2 步的材料。Secret 只能重写，列表只显示名称和更新时间。已有且已经验证的配置可直接复核。

**对象存储**，逐条运行并按提示输入对应值：

```bash
gh secret set OSS_ACCESS_KEY_ID --env production -R "$REPO"
gh secret set OSS_ACCESS_KEY_SECRET --env production -R "$REPO"
```

**签名证书**，使用实际 .p12 路径，再输入导出密码：

```bash
set -o pipefail
base64 -i "$P12_FILE" | gh secret set MACOS_CERT_P12_BASE64 --env production -R "$REPO"
gh secret set MACOS_CERT_P12_PASSWORD --env production -R "$REPO"
```

**公证 API 密钥**，使用实际 .p8 路径，再输入 Key ID 和 Issuer ID：

```bash
base64 -i "$P8_FILE" | gh secret set NOTARY_KEY_P8_BASE64 --env production -R "$REPO"
gh secret set NOTARY_KEY_ID --env production -R "$REPO"
gh secret set NOTARY_ISSUER_ID --env production -R "$REPO"
```

**验证**。独立桌面 App 可把版本清单发往 OSS；清单由自有服务端分发时，`deploy` 模式还会检查部署入口。涉及特殊 entitlement 时，按该项目工作流检查描述文件。

```bash
bash "$PROJECT_INIT/scripts/github-apply.sh" "$REPO" --check --kind desktop
check secrets --repo "$REPO" --mode "$MODE" --bucket "$BUCKET" --endpoint "$ENDPOINT"
```

## 第 4 步（门户管理员）：确认门户有权访问目标仓库

GitHub → Settings → Developer settings → Fine-grained tokens → 门户使用的令牌 → Repository access。首次接入时按需加入目标仓库，并核对该令牌具备触发目标 Actions 工作流的权限。已接入项目复用现有授权。用门户实际身份验证，普通开发者自己的 gh 登录只能证明个人权限。

```bash
check portal-token --repo "$REPO"
```

验证器通过隐藏输入读取令牌，只访问目标仓库的工作流列表。在门户运行环境已有凭据时，可用其原有只读探测代替交付令牌。真正的写入调度在第 7 步验证。

## 第 5 步（凭据持有人）：小文件上传和匿名回读

对照第 0 步的目标，使用本次发布凭据写入或更新其下的 `ci-test.txt`。脚本显示完整目的地址，在本机终端隐藏输入 AccessKey，用一次性随机内容上传，然后匿名 GET 并逐字节比对。成功后保留测试文件。

```bash
check oss --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "$PREFIX" --write-test
```

只有本次 PUT 和匿名回读均成功才能记为通过。404、读到旧内容、另一个项目的测试结果都不能代替。失败时保留操作名、HTTP 状态、Request ID；写入失败检查发布身份与目标前缀，匿名读取失败检查玩家下载路径。直连 OSS 公共读使用上述检查；如果项目登记的是 CDN 下载地址，使用 `--read-base "$DOWNLOAD_BASE"` 从实际下载入口回读。换过 Key 后还须确认工作流使用的 production Secret 已更新。

## 第 6 步（维护者合并，运维人员同步）：让门户显示桌面发布端

按依赖顺序，检验所需 PR 的必需检查，通过后由维护者点 Squash and merge，再验证合并状态。已存在的配置无需制造空 PR。

```bash
check prs ready "${PR_URLS[@]}"
# 维护者完成合并后
check prs merged "${PR_URLS[@]}"
check registration --config "$OPS_REPO/portal/config.json" --repo "$REPO" --tag-prefix "$TAG_PREFIX" --workflow "$WORKFLOW" --manifest "$MANIFEST"
```

在已纳入合并提交的运维检出目录执行。门户配置有变化时，经本次同步授权后运行 `bash "$OPS_REPO/portal/push.sh"`。随后从**已上线的门户**选中目标项目，确认出现「桌面端」、工作流和目标版本；本地 JSON 检查只证明登记内容正确。

## 第 7 步（发布人发起，流水线构建）：通过门户发布目标版本

选择项目 → 桌面端 → patch / minor / major，核对预期版本再触发。按当前发布窗口和紧急变更规则执行。门户从 main 发起调度；Linux 门禁检查 main 的 CI 后打标签，macOS 从该标签构建、正式签名、公证并装订票据。发布任务处理安装包、清单和 GitHub Release。

用门户本次记录的 run ID 和目标 tag 验证，区分同仓库其他发布端：

```bash
gh run watch "$RUN_ID" --repo "$REPO" --exit-status
check release-run --repo "$REPO" --workflow "$WORKFLOW" --run-id "$RUN_ID" --tag "$TAG"
```

若只有分发失败且同一 run 的构建产物仍可用，修复具体原因，经发布人授权用 `gh run rerun "$RUN_ID" --failed -R "$REPO"`，继续检查同一 tag。发布人决定是否上线；创建或调用本 Skill 本身不触发发版。

## 第 8 步（维护者验收）：从用户入口验证最终制品

在 macOS 上，从门户登记的线上清单和实际下载地址验收。校验 Release、清单版本、每个架构条目的安装包及最终 SHA-256；对重复指向同一 Universal DMG 的条目只下载一次。只读挂载最终 DMG，检查 Gatekeeper、签名、公证票据和 App 版本。最后由用户或已获授权的测试人员打开 App 验证首次启动，记录线上 tag、run 和下载结果。

```bash
check delivery --repo "$REPO" --tag-prefix "$TAG_PREFIX" --tag "$TAG" --version "$VERSION" --manifest "$MANIFEST" --download-base "$DOWNLOAD_BASE"
```
