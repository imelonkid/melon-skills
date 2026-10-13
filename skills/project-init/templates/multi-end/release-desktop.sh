#!/usr/bin/env bash
# 发布 Mac 桌面端：按 tag desktop-vX.Y.Z 构建安装包，上传到下载站，客户端检查到新版本后提示下载。
#
#   scripts/release-desktop.sh patch|minor|major   # 发新版：打下一个 desktop-v 的 tag 并推到 GitHub，构建、上传
#   scripts/release-desktop.sh desktop-v0.2.0      # 重新构建、上传某个已有版本
#
# 产物：__PRODUCT__-<版本>-arm64.dmg（未经 Apple 公证：首次打开要在「系统设置 → 隐私与安全性」里放行）
# 下载站：服务端 /download/desktop/（宿主机 /opt/__NAME__/downloads/desktop），latest.json 最后上传，客户端看到时安装包一定已就位
# 存档：GitHub Release（私有仓库）
#
# 回滚：桌面端装到用户电脑上就收不回来了，客户端只会提示「更新的」版本。
#   新版有问题 → 修复后发 patch（推荐）；或者重新发布旧版本的 latest.json，让还没升级的人别升（已升级的不受影响）。
#   界面问题不用发桌面端：界面由服务端提供，回滚服务端即可（scripts/deploy.sh rollback）。
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/lib-release.sh

HOST="${DEPLOY_HOST:-__HOST__}"
REMOTE_DIR=/opt/__NAME__/downloads/desktop
KEEP=5
ARCH=arm64

resolve_tag desktop-v "${1:-}"
push_tag

SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT
checkout_tag "$SRC"
echo "▸ 构建 __PRODUCT__ $VER（$ARCH）"
( cd "$SRC" && node scripts/vendor.js )
for f in react.production.min.js react-dom.production.min.js babel.min.js; do
  [[ -s "$SRC/apps/web/vendor/$f" ]] || die "网页界面缺 vendor/$f（scripts/vendor.js 没拉到），安装包里的兜底界面会白屏"
done
( cd "$SRC/apps/desktop" && pnpm install --frozen-lockfile --silent \
  && npx electron-builder --mac dmg --$ARCH -c.extraMetadata.version="$VER" --publish never )
DMG="__PRODUCT__-$VER-$ARCH.dmg"
[[ -f "$SRC/apps/desktop/dist/$DMG" ]] || die "没有生成 $DMG"

cat > "$SRC/latest.json" <<JSON
{
  "version": "$VER",
  "tag": "$TAG",
  "date": "$(date '+%F %T')",
  "notes": $(notes apps/desktop apps/web | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))'),
  "files": { "$ARCH": "$DMG" }
}
JSON

echo "▸ 上传到下载站（$HOST:$REMOTE_DIR）"
ssh "$HOST" "mkdir -p $REMOTE_DIR"
scp -q "$SRC/apps/desktop/dist/$DMG" "$HOST:$REMOTE_DIR/$DMG"
scp -q "$SRC/latest.json" "$HOST:$REMOTE_DIR/latest.json.tmp"
ssh "$HOST" "cd $REMOTE_DIR && mv latest.json.tmp latest.json && ls -t __PRODUCT__-*.dmg | tail -n +$((KEEP+1)) | xargs -r rm -f && printf '%s\t%s\t%s\n' \"\$(date '+%F %T')\" '$TAG' '$(whoami)' >> release.log"

github_release "$SRC/apps/desktop/dist/$DMG"
echo "✓ 桌面端 $TAG 已发布：https://__DOMAIN__/download/desktop/$DMG"
