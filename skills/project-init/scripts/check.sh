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

echo "▸ $NAME（$P）"

echo "▸ git"
if ! git -C "$P" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bad "不是 git 仓库"
else
  br="$(git -C "$P" symbolic-ref --short HEAD 2>/dev/null || echo '?')"
  [[ "$br" == main ]] && ok "分支 main" || tip "当前分支 $br，默认分支应为 main"
  url="$(git -C "$P" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    bad "没有 origin 远端（必须托管到 GitHub）"
  elif [[ "$url" =~ github\.com[:/]imelonkid/ ]]; then
    ok "远端 $url"
  else
    bad "远端不在 GitHub：$url（自建托管跑在业务服务器上，不满足规范 §5.1）"
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
  leaked="$(git -C "$P" ls-files | grep -Ei '(^|/)\.env(\.[^/]*)?$|\.pem$|\.key$|\.p12$|(^|/)id_(rsa|ed25519)|\.(db|sqlite3?)$|^(deploy/)?data/' | grep -Ev '(^|/)\.env(\.[^/]+)?\.example$' || true)"
  [[ -z "$leaked" ]] && ok "没有跟踪密钥 / 数据文件" || { bad "以下文件不该进 git（已在历史里的需用户决定是否清理并轮换密钥）："; sed 's/^/      /' <<<"$leaked"; }
  git -C "$P" check-ignore -q --no-index .env || bad ".gitignore 没有忽略 .env"
  git -C "$P" check-ignore -q --no-index x.db || tip ".gitignore 没有忽略 *.db"
fi

echo "▸ 文件"
[[ -f "$P/README.md" ]] && ok README.md || tip "缺 README.md"
[[ -f "$P/CLAUDE.md" ]] && ok CLAUDE.md || tip "缺 CLAUDE.md"

C=""
for c in deploy/docker-compose.prod.yml docker-compose.prod.yml; do [[ -f "$P/$c" ]] && { C="$P/$c"; break; }; done
if [[ -z "$C" && -f "$OPS/registry/services/$NAME.yaml" ]] && grep -qE '^\s+compose:' "$OPS/registry/services/$NAME.yaml"; then
  echo "▸ 部署"
  bad "注册表登记为服务，但仓库没有 deploy/docker-compose.prod.yml"
elif [[ -z "$C" ]]; then
  echo "▸ 没有 docker-compose.prod.yml，按非服务项目处理"
else
  echo "▸ 部署（${C#$P/}）"
  [[ -f "$P/.env.example" ]] && ok .env.example || bad "缺 .env.example"
  [[ -f "$P/scripts/deploy.sh" ]] && ok scripts/deploy.sh || bad "缺 scripts/deploy.sh（发布与回滚必须走 tag）"
  if [[ -f "$P/deploy/Dockerfile" ]]; then
    grep -qE '^ARG APP_VERSION' "$P/deploy/Dockerfile" && ok "Dockerfile 烘入 APP_VERSION" || tip "Dockerfile 没有 ARG APP_VERSION（版本号要烘进镜像）"
  else
    bad "缺 deploy/Dockerfile"
  fi

  # 粗略按 services: 下两格缩进的键计数；复杂 compose 以人工复核为准
  n="$(awk '/^services:/{s=1;next} /^[^ #]/{s=0} s&&/^  [A-Za-z0-9_.-]+:/{c++} END{print c+0}' "$C")"
  for k in mem_limit healthcheck; do
    m="$(grep -cE "^\s+$k:" "$C")"
    (( m >= n )) && ok "$k（$m/$n）" || bad "$k 只有 $m/$n 个服务配置"
  done
  m="$(grep -cE '^\s+restart:\s*unless-stopped' "$C")"
  (( m >= n )) && ok "restart: unless-stopped（$m/$n）" || bad "restart: unless-stopped 只有 $m/$n"
  open="$(grep -nE '^\s+-\s*"?([0-9]+:)?[0-9]+:[0-9]+' "$C" | grep -vE '127\.0\.0\.1|\[::1\]' || true)"
  [[ -z "$open" ]] && ok "端口只绑 127.0.0.1" || { bad "端口对外暴露："; sed 's/^/      /' <<<"$open"; }
  grep -qE '^\s+env_file:' "$C" && ok "用 env_file 加载配置" || tip "没有 env_file；若依赖 --env-file 插值，必须写进注册表 deploy.up"
  grep -qE '^\s+-\s*\./data[:/]' "$C" && ok "数据挂载 ./data" || tip "没有挂载 ./data（无状态服务可忽略）"
  grep -rqsE '^\s*(import oss2|from oss2)|require\(.ali-oss.\)|from .ali-oss.' "$P" --include='*.py' --include='*.js' --include='*.ts' --exclude-dir=node_modules \
    && tip "用了厂商专有对象存储 SDK，应改 S3 兼容接口或写进 known_gaps（§5.8）" || true
  grep -qE '^\s+logging:' "$C" && tip "compose 里写了 logging:，日志轮转应交给主机基线" || true
  unpinned="$(grep -E '^\s+image:' "$C" | sed -E 's/^\s+image:\s*//; s/["'"'"']//g; s/\s*#.*//' | grep -vE "^$NAME:" | grep -vE ':[^/]+$|@sha256:' ; grep -E '^\s+image:.*:latest' "$C" | sed -E 's/^\s+image:\s*//')"
  [[ -z "$unpinned" ]] && ok "第三方镜像都钉了版本" || { bad "镜像没钉版本："; sed 's/^/      /' <<<"$unpinned"; }
  [[ -f "$P/.env.example" ]] && { grep -q OTEL_ "$P/.env.example" && ok ".env.example 含 OTel 配置" || tip ".env.example 没有 OTEL_*（§8 埋点）"; }
  grep -rqsE '["'"'"'/]health["'"'"' ]' "$P" --include='*.py' --include='*.js' --include='*.ts' --include='*.go' --include='*.rs' --include='*.java' --exclude-dir=node_modules --exclude-dir=deploy \
    && ok "代码里有 /health" || tip "代码里没找到 /health 接口"
  if [[ -f "$P/scripts/deploy.sh" ]]; then
    D="$P/scripts/deploy.sh"
    grep -qE 'git archive' "$D" && grep -qE 'refs/tags|git tag' "$D" && ok "deploy.sh 按 tag 发布（从 tag 内容构建）" || bad "deploy.sh 不是按 tag 发布：每次发版必须打新 tag，从 tag 构建（模板 templates/deploy.sh）"
    grep -qE '^\s*rollback\)' "$D" && ok "deploy.sh 支持按 tag 回滚" || bad "deploy.sh 没有 rollback（回滚到上一个 tag）"
    grep -q EMERGENCY "$D" && ok "deploy.sh 有发布窗口" || tip "deploy.sh 没有 08–23 点发布窗口（§9.3）"
    grep -qE 'auto-rollback' "$D" && ok "deploy.sh 健康检查失败自动回滚" || tip "deploy.sh 没有健康检查失败自动回滚（§9.3）"
  fi

  echo "▸ 注册"
  if [[ ! -d "$OPS/registry/services" ]]; then
    tip "找不到 ops 仓库（$OPS），无法核对注册"
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
        [[ "$pair" =~ standby:\ *$fo[\ ,}] && "$pair" =~ witness:\ *$wi[\ ,}] ]] && ok "主·备·裁判与 standby_pairs 一致（$site→$fo，裁判 $wi）" \
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
