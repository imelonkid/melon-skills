#!/usr/bin/env bash
# 项目规范检查（只读）。✗ 必须修；△ 上线前要补。有 ✗ 时退出码 1。
#
#   check.sh [项目目录] [服务名]     # 默认当前目录；服务名默认取目录名（注册表里叫法不同时传第二个参数）
set -uo pipefail

P="$(cd "${1:-.}" && pwd)"
OPS="${OPS_REPO:-$HOME/Workspace/melon-ops}"
NAME="${2:-$(basename "$P")}"
fail=0; warn=0
ok()  { printf '  ✓ %s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*"; fail=$((fail+1)); }
tip() { printf '  △ %s\n' "$*"; warn=$((warn+1)); }

echo "▸ ${NAME}（${P}）"

echo "▸ git"
if ! git -C "$P" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bad "不是 git 仓库"
else
  br="$(git -C "$P" symbolic-ref --short HEAD 2>/dev/null || echo '?')"
  [[ "$br" == main ]] && ok "分支 main" || tip "当前分支 ${br}，默认分支应为 main"
  url="$(git -C "$P" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    bad "没有 origin 远端（必须托管到 GitHub）"
  elif [[ "$url" =~ github\.com[:/]imelonkid/ ]]; then
    ok "远端 $url"
  else
    bad "远端不在 GitHub：${url}（自建托管跑在业务服务器上，不满足规范 §5.1）"
  fi
  git -C "$P" rev-parse HEAD >/dev/null 2>&1 || bad "还没有提交"
  if [[ -n "$url" ]] && git -C "$P" rev-parse '@{u}' >/dev/null 2>&1; then
    ahead="$(git -C "$P" rev-list --count '@{u}..HEAD')"
    (( ahead == 0 )) && ok "已推送" || tip "有 $ahead 个提交未推送"
  elif [[ -n "$url" ]]; then
    tip "当前分支没有上游（git push -u origin main）"
  fi
  [[ -z "$(git -C "$P" status --porcelain)" ]] || tip "工作区有未提交的改动"

  # 已跟踪的敏感文件
  # 数据目录按规范只认仓库根与 deploy/ 下的 data/（源码里叫 data 的包不算）
  leaked="$(git -C "$P" ls-files | grep -Ei '(^|/)\.env(\.[^/]*)?$|\.pem$|\.key$|\.p12$|(^|/)id_(rsa|ed25519)|\.(db|sqlite3?)$|^(deploy/)?data/' | grep -Ev '(^|/)\.env(\.[^/]+)?\.example$' | grep -Ev '^apps/miniapp/\.env\.(development|production|test)$' || true)"
  # 小程序端的构建模式文件（基线「小程序端」）允许进 git，但只能放公开地址与开关：变量名像密钥的一律算泄露
  for mf in $(git -C "$P" ls-files | grep -E '^apps/miniapp/\.env\.(development|production|test)$'); do
    if grep -qiE '^[[:space:]]*[A-Z_]*(SECRET|KEY|TOKEN|PASSWORD|PASSWD|PRIVATE)[A-Z_]*=' "$P/$mf" 2>/dev/null; then bad "$mf 里有像密钥的变量（小程序不放任何密钥）"
    else ok "$mf 只放公开配置（小程序构建模式文件）"; fi
  done
  [[ -z "$leaked" ]] && ok "没有跟踪密钥 / 数据文件" || { bad "以下文件不该进 git（已在历史里的需用户决定是否清理并轮换密钥）："; sed 's/^/      /' <<<"$leaked"; }
  git -C "$P" check-ignore -q --no-index .env || bad ".gitignore 没有忽略 .env"
  # 鸿蒙签名：仓库里的 build-profile.json5 不能带 signingConfigs 内容
  for bp in $(git -C "$P" ls-files | grep -E '(^|/)build-profile\.json5$'); do
    if git -C "$P" show "HEAD:$bp" 2>/dev/null | grep -qE '"(storePassword|keyPassword)"[[:space:]]*:[[:space:]]*"[^"]+"'; then
      bad "$bp 已提交的版本含签名密码（signingConfigs 应为 []，本机签名用 skip-worktree）"
    fi
  done
  if command -v gitleaks >/dev/null; then
    gl="$(mktemp)"; gitleaks git "$P" --redact --no-banner --log-level error --report-format json --report-path "$gl" >/dev/null 2>&1 || true
    n="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$gl" 2>/dev/null || echo '?')"; rm -f "$gl"
    [[ "$n" == 0 ]] && ok "gitleaks：git 历史无命中" || tip "gitleaks：git 历史命中 $n 处，逐个确认是否误报（gitleaks git . --redact）"
  else
    tip "未安装 gitleaks（brew install gitleaks），无法扫 git 历史"
  fi
  git -C "$P" check-ignore -q --no-index x.db || tip ".gitignore 没有忽略 *.db"
fi

# 项目基线：项目按哪一版接入（templates/BASELINE.md）
BASE_CUR="$(cat "$(dirname "$0")/../templates/melon-baseline" 2>/dev/null || echo v1)"
echo "▸ 项目基线（当前 ${BASE_CUR}）"
if [[ -f "$P/.melon-baseline" ]]; then
  BASE_PRJ="$(tr -d '[:space:]' < "$P/.melon-baseline")"
  [[ "$BASE_PRJ" == "$BASE_CUR" ]] && ok "按基线 $BASE_PRJ 接入" || tip "按基线 $BASE_PRJ 接入，当前是 ${BASE_CUR}：按 templates/BASELINE.md「变更」跟进后改 .melon-baseline"
else
  tip "没有 .melon-baseline：还没对照项目基线（templates/BASELINE.md）接入"
fi

echo "▸ 文件"
[[ -f "$P/README.md" ]] && ok README.md || tip "缺 README.md"
# 脚本里变量后紧跟中文全角字符（"$APP（"）：macOS 自带 bash 3.2 在 UTF-8 环境下会把全角字节当成变量名，
# CI 的 macOS 构建机上直接报 unbound variable（本机用 Homebrew bash 5 发现不了），一律写 ${…}
sh_bad="$(cd "$P" && git ls-files -z '*.sh' 2>/dev/null | xargs -0 perl -ne 'print "$ARGV:$.\n" if /\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/; close ARGV if eof' 2>/dev/null | head -5)"
[[ -z "$sh_bad" ]] && ok "脚本变量写法（兼容 bash 3.2）" || bad "脚本里变量后紧跟全角字符，改成 \${…}：$(echo $sh_bad)"
# CLAUDE.md 是 Claude 在本项目开发的强制约束：必须存在，且有「## 边界」一节（负责 / 不负责 / 与其他项目的关系）。
# 允许 CLAUDE.md 是指向 AGENTS.md 的链接，或用 @AGENTS.md 引用它
if [[ -f "$P/CLAUDE.md" ]]; then
  ok CLAUDE.md
  claude_txt="$(cat "$P/CLAUDE.md")"
  grep -q '^@AGENTS.md' "$P/CLAUDE.md" && [[ -f "$P/AGENTS.md" ]] && claude_txt+=$'\n'"$(cat "$P/AGENTS.md")"
  if grep -q '^## 边界' <<<"$claude_txt"; then ok "CLAUDE.md 有「边界」"
  else bad "CLAUDE.md 没有「## 边界（强制）」一节：写明本项目负责什么、不负责什么（归谁）、与其他项目的关系"; fi
else
  bad "缺 CLAUDE.md（Claude 在本项目开发的强制约束，模板 templates/CLAUDE.md）"
fi

C=""
for c in deploy/docker-compose.prod.yml docker-compose.prod.yml; do [[ -f "$P/$c" ]] && { C="$P/$c"; break; }; done
if [[ -z "$C" && -f "$OPS/registry/services/$NAME.yaml" ]] && grep -qE '^\s+compose:' "$OPS/registry/services/$NAME.yaml"; then
  echo "▸ 部署"
  bad "注册表登记为服务，但仓库没有 deploy/docker-compose.prod.yml"
elif [[ -z "$C" ]] && { [[ -f "$P/.github/workflows/release-desktop.yml" || -f "$P/scripts/package-desktop.sh" ]] || { [[ -f "$P/package.json" ]] && grep -q '"electron-builder"' "$P/package.json"; }; }; then
  # 基线 · 桌面应用（独立客户端）：发布走 melon-ci desktop-release（manifest: oss），版本号构建时注入。
  # Electron 默认；走技术选型例外的（如原生 App）用打包钩子 scripts/package-desktop.sh
  echo "▸ 桌面应用"
  f="$P/.github/workflows/release-desktop.yml"
  if [[ -f "$f" ]]; then
    grep -q 'imelonkid/melon-ci/.github/workflows/desktop-release.yml@v2' "$f" && ok "发布表单（melon-ci desktop-release @v2）" || bad "release-desktop.yml 没有调用 melon-ci desktop-release @v2"
    grep -qE 'manifest:[[:space:]]*oss' "$f" && ok "版本清单放对象存储（manifest: oss）" || tip "独立桌面应用应使用 manifest: oss（没有服务端下载站）"
  else bad "缺 .github/workflows/release-desktop.yml（模板 templates/desktop/）"; fi
  [[ -f "$P/scripts/release-desktop.sh" ]] && ok "scripts/release-desktop.sh" || bad "缺 scripts/release-desktop.sh（模板 templates/desktop/）"
  [[ -f "$P/scripts/lib-release.sh" ]] && ok "scripts/lib-release.sh" || bad "缺 scripts/lib-release.sh（模板 templates/multi-end/）"
  grep -q 'package-desktop.sh' "$P/scripts/release-desktop.sh" 2>/dev/null && ok "发布脚本支持打包钩子（基线 v3 模板）" || tip "scripts/release-desktop.sh 是旧模板：换成 templates/desktop/release-desktop.sh（支持 scripts/package-desktop.sh）"
  if [[ -f "$P/scripts/package-desktop.sh" ]]; then
    ok "打包钩子 scripts/package-desktop.sh（技术选型例外）"
    grep -q '技术选型例外' "$P/README.md" 2>/dev/null && ok "README 写了技术选型例外" || tip "不用 Electron 要在 README「技术选型例外」写明"
    grep -qE 'CFBundleShortVersionString' "$P/scripts/package-desktop.sh" && ok "打包时注入版本号（Info.plist）" || tip "scripts/package-desktop.sh 要把版本号注入 Info.plist（CFBundleShortVersionString / CFBundleVersion）"
  else
    grep -q 'extraMetadata.version' "$P/scripts/release-desktop.sh" 2>/dev/null && ok "版本号构建时注入" || tip "发布脚本没有 -c.extraMetadata.version（版本号要在构建时注入）"
    grep -qE '"version":[[:space:]]*"0\.0\.0"' "$P/package.json" 2>/dev/null && ok "package.json version 固定 0.0.0" || tip "package.json 的 version 应固定 0.0.0（真实版本 = tag，构建时注入）"
  fi
  [[ -f "$P/.github/workflows/ci.yml" ]] && ok "ci.yml" || bad "缺 .github/workflows/ci.yml（melon-ci pr-check：发布门禁要求 main 的 CI 全绿）"
  [[ -f "$P/scripts/ci-test.sh" ]] && ok "scripts/ci-test.sh" || tip "缺 scripts/ci-test.sh（模板 templates/desktop/ci-test.sh）"
elif [[ -z "$C" ]]; then
  echo "▸ 没有 docker-compose.prod.yml，按非服务项目处理"
else
  echo "▸ 部署（${C#$P/}）"
  [[ -f "$P/.env.example" ]] && ok .env.example || bad "缺 .env.example"
  # 基线 v2：发布只在线上——要有发布 / 回滚表单（melon-ci @v2），不能有本机部署脚本
  for w in release rollback; do
    f="$P/.github/workflows/$w.yml"
    if [[ -f "$f" ]]; then grep -q 'imelonkid/melon-ci/.*@v2' "$f" && ok "$w 表单（melon-ci @v2）" || bad "$w 表单没有调用 melon-ci @v2（镜像必须进镜像仓库）"
    else bad "缺 .github/workflows/$w.yml（模板 templates/workflows/）"; fi
  done
  [[ -f "$P/scripts/deploy.sh" ]] && bad "有 scripts/deploy.sh：基线 v2 起项目不放部署脚本（发布走线上，应急用 melon rollback / status / config）" || ok "没有本机部署脚本"
  if [[ -f "$P/deploy/Dockerfile" ]]; then
    grep -qE '^ARG APP_VERSION' "$P/deploy/Dockerfile" && ok "Dockerfile 烘入 APP_VERSION" || tip "Dockerfile 没有 ARG APP_VERSION（版本号要烘进镜像）"
  else
    bad "缺 deploy/Dockerfile"
  fi

  # 粗略按 services: 下两格缩进的键计数；复杂 compose 以人工复核为准
  n="$(awk '/^services:/{s=1;next} /^[^ #]/{s=0} s&&/^  [A-Za-z0-9_.-]+:/{c++} END{print c+0}' "$C")"
  for k in mem_limit healthcheck; do
    m="$(grep -cE "^\s+$k:" "$C")"
    (( m >= n )) && ok "${k}（$m/${n}）" || bad "$k 只有 $m/$n 个服务配置"
  done
  m="$(grep -cE '^\s+restart:\s*unless-stopped' "$C")"
  (( m >= n )) && ok "restart: unless-stopped（$m/${n}）" || bad "restart: unless-stopped 只有 $m/$n"
  open="$(grep -nE '^\s+-\s*"?([0-9]+:)?[0-9]+:[0-9]+' "$C" | grep -vE '127\.0\.0\.1|\[::1\]' || true)"
  [[ -z "$open" ]] && ok "端口只绑 127.0.0.1" || { bad "端口对外暴露："; sed 's/^/      /' <<<"$open"; }
  grep -qE '^\s+env_file:' "$C" && ok "用 env_file 加载配置" || tip "没有 env_file；若依赖 --env-file 插值，必须写进注册表 deploy.up"
  grep -qE '^\s+-\s*\./data[:/]' "$C" && ok "数据挂载 ./data" || tip "没有挂载 ./data（无状态服务可忽略）"
  grep -rqsE '^\s*(import oss2|from oss2)|require\(.ali-oss.\)|from .ali-oss.' "$P" --include='*.py' --include='*.js' --include='*.ts' --exclude-dir=node_modules \
    && tip "用了厂商专有对象存储 SDK，应改 S3 兼容接口或写进 known_gaps（§5.8）" || true
  grep -qE '^\s+logging:' "$C" && tip "compose 里写了 logging:，日志轮转应交给节点基线" || true
  # 镜像：应用自己的镜像是部署入口打的本地标签 <名>:prod；其余（数据库、缓存等第三方）必须来自镜像仓库并钉版本 + 摘要：
  #   <镜像仓库>/<命名空间>/<名>:<版本>@sha256:…（运维仓库 registry/mirror-images.txt 同步）。
  #   不许直接用 Docker Hub：国内节点拉不动，旧摘要还会被回收，灾备重建会失败
  imgs="$(grep -E '^\s+image:' "$C" | sed -E 's/^[[:space:]]+image:[[:space:]]*//; s/["'"'"']//g; s/[[:space:]]*#.*//; s/[[:space:]]+$//')"
  third="$(grep -vE '^[a-z0-9][a-z0-9._-]*:prod$' <<<"$imgs" | grep . || true)"
  offreg="$( { grep -vE '^[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?/[a-z0-9._/-]+:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}$' <<<"$third"
              grep -E '^(docker\.io|index\.docker\.io|registry-1\.docker\.io)/' <<<"$third"; } | grep . | sort -u || true)"
  if [[ -z "$third" ]]; then ok "没有第三方镜像"
  elif [[ -z "$offreg" ]]; then ok "第三方镜像都来自镜像仓库，钉了版本与摘要"
  else bad "第三方镜像要来自镜像仓库并钉版本 + 摘要（<仓库>/<命名空间>/<名>:<版本>@sha256:…，先登记到运维仓库 registry/mirror-images.txt）："; sed 's/^/      /' <<<"$offreg"; fi
  [[ -f "$P/.env.example" ]] && { grep -q OTEL_ "$P/.env.example" && ok ".env.example 含 OTel 配置" || tip ".env.example 没有 OTEL_*（§8 埋点）"; }
  grep -rqsE '["'"'"'/]health["'"'"' ]' "$P" --include='*.py' --include='*.js' --include='*.ts' --include='*.go' --include='*.rs' --include='*.java' --exclude-dir=node_modules --exclude-dir=deploy \
    && ok "代码里有 /health" || tip "代码里没找到 /health 接口"

  # 多端项目（apps/ 下有客户端）：各端独立 tag、客户端有发布脚本、服务端声明最低客户端版本
  ends=(); for e in desktop harmony ios android; do [[ -d "$P/apps/$e" ]] && ends+=("$e"); done
  if (( ${#ends[@]} )); then
    echo "▸ 多端（${ends[*]}）"
    grep -qE 'tag-prefix:\s*server-v' "$P/.github/workflows/release.yml" 2>/dev/null && ok "服务端 tag 前缀 server-v" || tip "多端项目的服务端发布表单应使用 tag-prefix: server-v（各端独立 tag）"
    for e in "${ends[@]}"; do
      [[ -x "$P/scripts/release-$e.sh" ]] && ok "scripts/release-$e.sh" || tip "缺 scripts/release-$e.sh（模板 templates/multi-end/）"
    done
    grep -rqs 'minClient' "$P/apps/server" --include='*.js' --include='*.ts' --include='*.py' --include='*.go' --exclude-dir=node_modules \
      && ok "服务端返回 minClient（客户端最低版本）" || tip "服务端 /api/health 没有 minClient（客户端兼容契约）"
  fi

  # 小程序端（基线「小程序端」）：发布走 melon-ci mp-release（门户流水线 mp-release）
  if [[ -d "$P/apps/miniapp" ]]; then
    echo "▸ 小程序端"
    grep -qs 'imelonkid/melon-ci/.github/workflows/mp-release.yml@v2' "$P/.github/workflows/release-mp.yml" \
      && ok "发布表单 release-mp.yml（melon-ci mp-release @v2）" || tip "缺 .github/workflows/release-mp.yml 或没调用 melon-ci mp-release @v2（模板 templates/multi-end/）"
  fi

  # 日志公共包（基线 v2 增补 2026-10-21；规范在运维仓库 docs/11-logging.md）：
  #   Node 的服务端 / 网页 / 小程序端用 @imelonkid/common（GitHub Packages 私有包）。
  #   只给 △，不给 ✗：已有项目择期跟进，不让它们突然不过。
  #   范围：仓库根与 apps/* 下的 package.json；桌面（Electron）、鸿蒙端和只做 workspace 根的 package.json 不查
  echo "▸ 日志公共包（Node）"
  uses_common=0; seen_node=0
  for pj in "$P/package.json" "$P"/apps/*/package.json; do
    [[ -f "$pj" ]] || continue
    d="$(dirname "$pj")"; rel="${d#"$P"}"; rel="${rel#/}"; rel="${rel:-.}"
    case "$rel" in apps/desktop|apps/harmony) continue ;; esac
    grep -qE '"electron-builder"|"workspaces"' "$pj" && continue
    seen_node=1
    ver="$(grep -oE '"@imelonkid/common"[[:space:]]*:[[:space:]]*"[^"]*"' "$pj" | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')"
    if [[ -z "$ver" ]]; then
      tip "${rel} 没有依赖 @imelonkid/common（日志与错误上报公共包，不在项目里各写一遍）"; continue
    fi
    uses_common=1
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && ok "${rel} 依赖 @imelonkid/common ${ver}" || tip "${rel} 的 @imelonkid/common 要钉确切版本（现在是 ${ver}）"
    grep -qs 'npm.pkg.github.com' "$d/.npmrc" "$P/.npmrc" && ok "${rel} 有 .npmrc（@imelonkid → GitHub Packages）" \
      || tip "${rel} 缺 .npmrc（模板 templates/stacks/nestjs/npmrc：@imelonkid 指向 npm.pkg.github.com，令牌走 NODE_AUTH_TOKEN）"
  done
  if (( uses_common )); then
    grep -qs 'id=npm_token' "$P/deploy/Dockerfile" && ok "Dockerfile 用 BuildKit secret npm_token 装私有包" \
      || tip "deploy/Dockerfile 装依赖没挂 BuildKit secret npm_token（RUN --mount=type=secret,id=npm_token …，见 templates/stacks/nestjs/Dockerfile）"
    for w in release release-mp; do
      f="$P/.github/workflows/$w.yml"; [[ -f "$f" ]] || continue
      grep -qE 'packages:[[:space:]]*read' "$f" && ok "$w 表单授予 packages: read" || tip "$w 表单的 permissions 要加 packages: read（读私有包 @imelonkid/*）"
    done
  elif (( ! seen_node )); then
    ok "不是 Node 项目，不适用"
  fi

  # 技术架构与选型（基线 v3 2026-10-21）：能机械判断的给 △；README 写了「技术选型例外」的不报
  echo "▸ 技术选型（基线 v3）"
  exc=0; grep -qs '技术选型例外' "$P/README.md" && { exc=1; ok "README 有「技术选型例外」（按例外记录核对）"; }
  for pj in "$P"/apps/admin*/package.json; do
    [[ -f "$pj" ]] || continue
    rel="${pj#"$P/"}"; rel="${rel%/package.json}"
    grep -qE '"vue"[[:space:]]*:' "$pj" && ok "${rel} 前端 Vue" || (( exc )) || tip "${rel} 前端不是 Vue 3（运营后台默认 Vue 3 + Vite + Element Plus）"
  done
  for pj in "$P/apps/server/package.json" "$P/server/package.json"; do
    [[ -f "$pj" ]] || continue
    rel="${pj#"$P/"}"; rel="${rel%/package.json}"
    grep -qE '"@nestjs/core"[[:space:]]*:' "$pj" && ok "${rel} 用 NestJS" || (( exc )) || tip "${rel} 服务端不是 NestJS（服务端默认 TypeScript + NestJS + Prisma + MySQL 8）"
    if grep -qE '"@nestjs/core"' "$pj"; then
      grep -qE '"@prisma/client"[[:space:]]*:' "$pj" && ok "${rel} 用 Prisma" || (( exc )) || tip "${rel} 没用 Prisma（ORM 与迁移默认 Prisma）"
    fi
  done
  if [[ -f "$P/deploy/Dockerfile" ]] && grep -qE '^FROM[[:space:]]+[^ ]*node:' "$P/deploy/Dockerfile"; then
    grep -qE '^FROM[[:space:]]+[^ ]*node:22' "$P/deploy/Dockerfile" && ok "服务端镜像 Node 22" || tip "deploy/Dockerfile 的 Node 不是 22 LTS"
  fi
  if [[ -f "$P/requirements.txt" || -f "$P/pyproject.toml" || -f "$P/server/requirements.txt" ]] && (( ! exc )); then
    tip "Python 服务：基线默认 TypeScript + NestJS；AI / 数据类可用 FastAPI，在 README「技术选型例外」写明"
  fi

  echo "▸ 注册"
  if [[ ! -d "$OPS/registry/services" ]]; then
    tip "找不到 ops 仓库（${OPS}），无法核对注册"
  elif [[ -f "$OPS/registry/services/$NAME.yaml" ]]; then
    R="$OPS/registry/services/$NAME.yaml"
    val() { awk -v k="$1" '$1==k":"{sub(/^[^:]*:[ ]*/,"");sub(/[ ]*#.*/,"");print;exit}' "$R"; }
    ok "已登记 registry/services/$NAME.yaml（$(val status)）"
    for k in status tier dr_level site; do [[ -n "$(val $k)" ]] || bad "注册表缺 $k"; done
    for k in "repo" "up" "secrets" "mem_limit" "url"; do grep -qE "^\s+$k:\s*\S" "$R" || bad "注册表缺 $k"; done
    grep -qE '^assets:' "$R" || bad "注册表缺 assets"
    grep -qE '^\s+repo:\s*git@github\.com:|^\s+repo:\s*https://github\.com/' "$R" || bad "注册表 code.repo 不是 GitHub 地址"
    grep -qE 'TODO|__[A-Z]+__' "$R" && tip "注册表里还有 TODO / 占位符"
    site="$(val site)"; fo="$(val failover_site)"; wi="$(val witness_site)"
    if [[ "$(val dr_level)" == L2 ]]; then
      [[ -n "$fo" && -n "$wi" ]] || bad "L2 必须有 failover_site 与 witness_site"
      [[ "$wi" != "$site" && "$wi" != "$fo" ]] || bad "裁判站点必须是主、备之外的第三站点（§4.3）"
      pair="$(grep -E "primary:\s*$site\b" "$OPS/registry/sites.yaml" | head -1)"
      if [[ -n "$pair" ]]; then
        [[ "$pair" =~ standby:\ *$fo[\ ,}] && "$pair" =~ witness:\ *$wi[\ ,}] ]] && ok "主·备·裁判与 standby_pairs 一致（${site}→${fo}，裁判 ${wi}）" \
          || bad "主·备·裁判与 sites.yaml standby_pairs 不一致：$pair"
      else
        bad "sites.yaml 的 standby_pairs 里没有 primary: $site"
      fi
    fi
  else
    bad "未在 ops 仓库登记 registry/services/$NAME.yaml"
  fi
fi

echo
echo "结果：✗ $fail · △ $warn"
(( fail == 0 ))
