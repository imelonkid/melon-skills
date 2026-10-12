# melon-skills 维护规范

给在本仓库工作的 AI 助手（Claude Code、Codex 等）和人看。`CLAUDE.md` 引用本文件。

## 这是什么

melonkid 的 Claude Code skills。**公开仓库**。每个 skill 一个目录，`install.sh` 把它们软链到 `~/.claude/skills/`。

```
skills/<名>/SKILL.md        必需：frontmatter（name、description）+ 正文
skills/<名>/scripts/        可选：可执行脚本，默认只读
skills/<名>/templates/      可选：模板，占位符写成 __大写__
index.html                  项目说明首页（给人看）
site/<名>.html              每个 skill 的介绍页
site/site.js                skill 清单（首页卡片和顶部菜单都从这里生成）
site/style.css              页面样式（明暗两套色板）
scripts/scan-secrets.sh     敏感信息扫描；.githooks/pre-commit 调用它
install.sh                  软链 skills + 启用 pre-commit
```

## 一、敏感信息：零容忍

本仓库任何文件、任何提交都**不得**出现：

- IP 地址（`127.0.0.1` 等本地地址除外）、端口号与主机的对应关系、面板入口路径、服务器上的具体部署路径
- 密码、私钥、AK/SK、token、webhook key
- 手机号、身份证号、证件信息、真实账号
- 私有仓库里的主机档案内容（容器清单、安全组规则、内网地址）

**依赖的数据一律走环境变量**：

1. 在 skill 里只写变量名（`$OPS_REPO`、`$ALI_IP`），并说明它定义在哪（`~/.zsh/conf.d/ops.zsh`，私有仓库 `melon-ops`）。
2. 脚本开头检查需要的变量，缺了就报出变量名并退出，**不写兜底的真实值**。
3. 新增变量时，同时改私有仓库 `melon-ops/workstation/zsh/ops.zsh`，并在 `index.html` 的「环境变量」表登记**名字和含义**（不写值）。
4. 示例值用占位符：`__NAME__`、`__PORT__`、`example.com`。

提交前 pre-commit 会跑 `scripts/scan-secrets.sh --staged`：查通用模式，并把本机 `ops.zsh` 里的 IP、端口、面板入口的**实际值**当字面量去搜。**不要用 `--no-verify` 绕过。** 误报在行尾加 `scan:allow`，并在提交信息里说明。

一旦泄露：先轮换密钥 / 改端口，再处理历史；告诉用户，不要自己 `push --force`。

## 二、每次更新都要同步文档

改 skill 的行为、流程、依赖变量、脚本参数时，**在同一个提交里**同步更新：

| 改了什么 | 要同步的地方 |
|---|---|
| 任何 skill 的行为或流程 | 该 skill 的 `SKILL.md` + `site/<名>.html` |
| 新增 / 改名 / 删除 skill | `README.md` 表格、`site/site.js` 的 `SKILLS`、新建或删除 `site/<名>.html`、`index.html` 的 `<noscript>` 链接 |
| 依赖的环境变量 | `SKILL.md`、`site/<名>.html`、`index.html`「环境变量」表、私有仓库 `ops.zsh` |
| 安装方式 / 仓库结构 | `README.md`、`index.html`「安装」、本文件 |
| 敏感信息规则 | 本文件、`scripts/scan-secrets.sh`、`index.html`「敏感信息防线」 |

提交前自查：`git diff --stat` 里如果只有代码没有文档，多半漏了。

## 三、写 skill 的约定

- `description` 写清**什么时候触发**（用户会怎么说），这是 Claude 选 skill 的唯一依据。
- 正文写流程、检查项、红线；**事实**（主机、路径、清单）运行时去读私有仓库或环境变量。
- 脚本默认只读；会改东西的脚本要在文件头写明，并且需要显式参数才执行。
- 需要用户密码、验证码、证件的步骤，交给用户本人执行。
- 中文写作；代码、命令、文件名保持原样。

## 四、提交

- 分支 `main`；提交信息 `<类型>(<范围>): <中文描述>`，类型用 feat / fix / docs / chore / refactor，范围用 skill 名。
- 推送前跑一次全量扫描：`scripts/scan-secrets.sh`。
- 页面改动后在浏览器打开 `index.html` 看一眼：菜单能跳转、明暗模式正常、手机宽度不横向滚动。
