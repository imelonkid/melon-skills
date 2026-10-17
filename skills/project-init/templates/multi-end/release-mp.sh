#!/usr/bin/env bash
# 发布微信小程序（多端项目的小程序端，项目基线「小程序端」）：按 tag mp-vX.Y.Z 构建，经部署入口在固定 IP 的主机上
# 用 miniprogram-ci 上传为体验版，GitHub Release 存档。提审、全量发布在微信后台人工完成（微信没有提审接口）。
#
#   scripts/release-mp.sh build <tag> <目录>   # 只构建（CI 用）：<目录>/mp.tar.gz（构建产物）与 meta.json
#   scripts/release-mp.sh publish <目录>       # 只发布（CI 用）：经部署入口 mp-upload 上传为体验版 + GitHub Release
#
# 发布只在线上：GitHub 上点「发布小程序」（.github/workflows/release-mp.yml → melon-ci mp-release）。
# 上传密钥只在上传主机（运维仓库登记），本脚本与 CI 都拿不到；DEPLOY_SSH 指向那台主机的部署入口。
# 回滚：微信后台「版本回退」到上一个线上版本；不行就修复后发 patch。
# 变量后紧跟中文全角字符一律写 ${…}（macOS 自带 bash 3.2 会把全角字节当成变量名）。
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/lib-release.sh

SVC=__NAME__                      # 部署入口里登记的服务名（如 yuxian-mp）
APP_DIR="${APP_DIR:-apps/miniapp}"
OUT_DIR="${OUT_DIR:-dist/build/mp-weixin}"   # uni-app：npm run build:mp-weixin 的输出
DEPLOY_SSH="${DEPLOY_SSH:-mp-target}"
MAX_KB=20480                      # 微信整包上限 20 MB（含分包）

build() {   # build <tag> <输出目录>
  TAG="$1"; local out="$2"; VER="${TAG#mp-v}"
  [[ "$TAG" =~ ^mp-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "tag 不合法：$TAG"
  PREV="$(git tag -l 'mp-v[0-9]*' --sort=-v:refname | grep -A1 -x "$TAG" | tail -n +2 | head -1 || true)"
  mkdir -p "$out"
  local src; src="$(mktemp -d)"
  checkout_tag "$src"
  echo "▸ 构建小程序 ${VER}"
  ( cd "$src/$APP_DIR" && if [[ -f pnpm-lock.yaml ]]; then pnpm install --frozen-lockfile --silent; else npm ci --no-audit --no-fund --silent; fi ) || die "安装依赖失败"
  ( cd "$src/$APP_DIR" && VITE_APP_VERSION="$VER" npm run build:mp-weixin ) || die "构建失败"
  local dist="$src/$APP_DIR/$OUT_DIR"
  [[ -f "$dist/app.json" ]] || die "构建产物里没有 app.json（${OUT_DIR}）"
  local kb; kb="$(du -sk "$dist" | cut -f1)"
  (( kb <= MAX_KB )) || die "构建产物 ${kb} KB，超过微信整包上限 ${MAX_KB} KB"
  tar -czf "$out/mp.tar.gz" -C "$dist" .
  jq -n --arg v "$VER" --arg t "$TAG" --arg n "$(notes "$APP_DIR")" --arg k "$kb" '{version:$v, tag:$t, notes:$n, size_kb:($k|tonumber)}' > "$out/meta.json"
  rm -rf "$src"
  echo "▸ 产物：mp.tar.gz（构建 ${kb} KB）"
}

publish() {   # publish <目录>
  local out="$1"
  [[ -f "$out/mp.tar.gz" && -f "$out/meta.json" ]] || die "$out 里没有 mp.tar.gz 或 meta.json（先 build）"
  TAG="$(jq -r .tag "$out/meta.json")"
  echo "▸ 经部署入口上传为体验版（${DEPLOY_SSH}）"
  ssh "$DEPLOY_SSH" mp-upload "$SVC" "$TAG" "as=$(whoami | tr -cd 'A-Za-z0-9._@-')" < "$out/mp.tar.gz" || die "上传失败"
  PREV="$(git tag -l 'mp-v[0-9]*' --sort=-v:refname | grep -A1 -x "$TAG" | tail -n +2 | head -1 || true)"
  cp "$out/mp.tar.gz" "$out/$TAG.tar.gz"
  github_release "$out/$TAG.tar.gz"
  echo "✓ 小程序 $TAG 已上传为体验版。接下来在微信后台：设为体验版测试 → 提交审核 → 审核通过后全量发布"
}

case "${1:-}" in
  build)   build "${2:?tag}" "${3:?输出目录}" ;;
  publish) publish "${2:?目录}" ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
