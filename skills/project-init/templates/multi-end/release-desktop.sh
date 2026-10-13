#!/usr/bin/env bash
# 发布 Mac 桌面端：按 tag desktop-vX.Y.Z 构建安装包，上传对象存储，更新下载站的版本清单，存档到 GitHub Release。
#
#   scripts/release-desktop.sh patch|minor|major   # 本机一条龙：打下一个 desktop-v tag 并推到 GitHub → 构建 → 发布
#   scripts/release-desktop.sh desktop-v0.2.0      # 重新构建、发布某个已有版本
#   scripts/release-desktop.sh build <tag> <目录>   # 只构建（CI 用）：dmg 与 latest.json 写到 <目录>
#   scripts/release-desktop.sh publish <目录>       # 只发布（CI 用）：上传对象存储 + 版本清单经部署入口 + GitHub Release
#   scripts/release-desktop.sh oss-test             # 检查对象存储配置：上传一个小文件，再从公网读回来
#
# 平时在 GitHub 上点「发布桌面端」（.github/workflows/release-desktop.yml）；本机这条路是应急通道，规则相同。
#
# 产物：__PRODUCT__-<版本>-arm64.dmg（未经 Apple 公证：首次打开要在「系统设置 → 隐私与安全性」里放行）
# 下载：安装包在阿里云 OSS（OSS_BUCKET / OSS_PREFIX），版本清单 latest.json 在服务端 /download/desktop/，
#      清单里的下载链接指向 OSS（DOWNLOAD_BASE）；客户端检查到新版本就提示下载（apps/desktop/updater.js）
#      没配 OSS 时退回旧路径：安装包和清单都经 SSH 放到 __HOST__ 的下载站
#
# 回滚：桌面端装到用户电脑上就收不回来了，客户端只会提示「更新的」版本。
#   新版有问题 → 修复后发 patch；界面问题不用发桌面端（界面由服务端提供，回滚服务端即可）。
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/lib-release.sh

ARCH=arm64
SVC=__NAME__
DEPLOY_SSH="${DEPLOY_SSH:-__HOST__-deploy}"              # 部署入口（deploy 用户 + 强制命令）
LEGACY_HOST="${LEGACY_HOST:-__HOST__}"                    # 没配 OSS 时的旧路径（root SSH）
OSS_ENDPOINT="${OSS_ENDPOINT:-oss-cn-hangzhou.aliyuncs.com}"
OSS_PREFIX="${OSS_PREFIX:-__NAME__/desktop}"
oss_ready() { [[ -n "${OSS_BUCKET:-}" && -n "${OSS_ACCESS_KEY_ID:-}" && -n "${OSS_ACCESS_KEY_SECRET:-}" ]]; }
[[ -z "${DOWNLOAD_BASE:-}" && -n "${OSS_BUCKET:-}" ]] && DOWNLOAD_BASE="https://$OSS_BUCKET.$OSS_ENDPOINT/$OSS_PREFIX"

# —— 构建：tag 的内容 → dmg + latest.json ——
build() {   # build <tag> <输出目录>
  TAG="$1"; local out="$2"; VER="${TAG#desktop-v}"
  [[ "$TAG" =~ ^desktop-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "tag 不合法：$TAG"
  PREV="$(git tag -l 'desktop-v[0-9]*' --sort=-v:refname | grep -A1 -x "$TAG" | tail -n +2 | head -1 || true)"
  mkdir -p "$out"
  local src; src="$(mktemp -d)"
  checkout_tag "$src"
  echo "▸ 构建 __PRODUCT__ ${VER}（${ARCH}）"
  ( cd "$src" && node scripts/vendor.js )
  for f in react.production.min.js react-dom.production.min.js babel.min.js; do
    [[ -s "$src/apps/web/vendor/$f" ]] || die "网页界面缺 vendor/${f}（scripts/vendor.js 没拉到），安装包里的兜底界面会白屏"
  done
  ( cd "$src/apps/desktop" && pnpm install --frozen-lockfile --silent \
    && CSC_IDENTITY_AUTO_DISCOVERY=false npx electron-builder --mac dmg --$ARCH -c.extraMetadata.version="$VER" --publish never )
  local dmg="__PRODUCT__-$VER-$ARCH.dmg"
  [[ -f "$src/apps/desktop/dist/$dmg" ]] || die "没有生成 $dmg"
  mv "$src/apps/desktop/dist/$dmg" "$out/"
  local link="$dmg"; [[ -n "${DOWNLOAD_BASE:-}" ]] && link="${DOWNLOAD_BASE%/}/$dmg"
  jq -n --arg v "$VER" --arg t "$TAG" --arg d "$(date '+%F %T')" --arg n "$(notes apps/desktop apps/web)" \
        --arg a "$ARCH" --arg f "$link" '{version:$v, tag:$t, date:$d, notes:$n, files:{($a):$f}}' > "$out/latest.json"
  rm -rf "$src"
  echo "▸ 产物：$out/${dmg}（$(du -h "$out/$dmg" | cut -f1)）"
}

# 上传到 OSS（V1 签名，只用 curl + openssl，CI 和本机都不用装阿里云的工具）
oss_put() {   # oss_put <文件> <对象名> <content-type>
  local file="$1" key="$2" ct="$3" date sig
  date="$(LC_ALL=C TZ=GMT date '+%a, %d %b %Y %H:%M:%S GMT')"
  sig="$(printf 'PUT\n\n%s\n%s\n/%s/%s' "$ct" "$date" "$OSS_BUCKET" "$key" | openssl dgst -sha1 -hmac "$OSS_ACCESS_KEY_SECRET" -binary | base64)"
  local resp
  resp="$(curl -sS --fail-with-body -X PUT -T "$file" -H "Date: $date" -H "Content-Type: $ct" -H "Authorization: OSS $OSS_ACCESS_KEY_ID:$sig" \
    "https://$OSS_BUCKET.$OSS_ENDPOINT/$key" 2>&1)" || { grep -oE '<(Code|Message)>[^<]*' <<<"$resp" | sed 's/^</  OSS /' >&2; return 1; }
}

# —— 发布：上传安装包 → 更新版本清单（最后做，客户端看到清单时安装包一定已就位）→ GitHub Release ——
publish() {   # publish <目录>
  local out="$1" dmg; dmg="$(cd "$out" && ls __PRODUCT__-*-$ARCH.dmg | head -1)"
  [[ -n "$dmg" && -f "$out/latest.json" ]] || die "$out 里没有安装包或 latest.json（先 build）"
  TAG="$(jq -r .tag "$out/latest.json")"
  if oss_ready; then
    echo "▸ 上传 OSS：$OSS_BUCKET/$OSS_PREFIX/$dmg"
    local s; s=$(date +%s)
    oss_put "$out/$dmg" "$OSS_PREFIX/$dmg" application/x-apple-diskimage
    echo "  用时 $(( $(date +%s) - s ))s"
    curl -fsSI "${DOWNLOAD_BASE%/}/$dmg" >/dev/null || die "上传后从公网取不到 ${DOWNLOAD_BASE%/}/${dmg}（桶是公共读吗？）"
    # 构建时可能不知道 OSS 地址（CI 的构建机拿不到配置）：发布时把下载链接统一改成 OSS 地址
    jq --arg a "$ARCH" --arg u "${DOWNLOAD_BASE%/}/$dmg" '.files[$a] = $u' "$out/latest.json" > "$out/latest.json.tmp" && mv "$out/latest.json.tmp" "$out/latest.json"
    echo "▸ 更新版本清单（经部署入口 ${DEPLOY_SSH}）"
    ssh "$DEPLOY_SSH" manifest "$SVC" desktop "as=$(whoami | tr -cd 'A-Za-z0-9._@-')" < "$out/latest.json"
  else
    echo "▸ 没配 OSS，退回旧路径：经 SSH 放到 $LEGACY_HOST 的下载站"
    local dir=/opt/__NAME__/downloads/desktop
    ssh "$LEGACY_HOST" "mkdir -p $dir"
    scp -q "$out/$dmg" "$LEGACY_HOST:$dir/$dmg"
    scp -q "$out/latest.json" "$LEGACY_HOST:$dir/latest.json.tmp"
    ssh "$LEGACY_HOST" "cd $dir && mv latest.json.tmp latest.json && ls -t __PRODUCT__-*.dmg | tail -n +6 | xargs -r rm -f"
  fi
  PREV="$(git tag -l 'desktop-v[0-9]*' --sort=-v:refname | grep -A1 -x "$TAG" | tail -n +2 | head -1 || true)"
  github_release "$out/$dmg"
  echo "✓ 桌面端 $TAG 已发布：$(jq -r ".files.$ARCH" "$out/latest.json")"
}

case "${1:-}" in
  oss-test)
    oss_ready || die "要先设置 OSS_BUCKET、OSS_ACCESS_KEY_ID、OSS_ACCESS_KEY_SECRET（以及 OSS_ENDPOINT）"
    f="$(mktemp)"; echo "ok $(date '+%F %T')" > "$f"; key="$OSS_PREFIX/ci-test.txt"
    if oss_put "$f" "$key" text/plain; then echo "✓ 上传成功：$OSS_BUCKET/$key"; else echo "✗ 上传失败（上面是 OSS 返回的原因）"; exit 1; fi
    if got="$(curl -fsS "${DOWNLOAD_BASE%/}/ci-test.txt")"; then echo "✓ 公网读取成功：$got"; else echo "✗ 公网读取失败：检查「阻止公共访问」已关闭、匿名只读策略覆盖 $OSS_PREFIX/*"; exit 1; fi
    rm -f "$f" ;;
  build)   build "${2:?tag}" "${3:?输出目录}" ;;
  publish) publish "${2:?目录}" ;;
  *)
    resolve_tag desktop-v "${1:-}"
    push_tag
    OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
    build "$TAG" "$OUT"
    publish "$OUT" ;;
esac
