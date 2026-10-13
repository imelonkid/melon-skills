#!/usr/bin/env bash
# 发布鸿蒙 App：按 tag harmony-vX.Y.Z 构建 release 包，存档到 GitHub Release，再由你上传到华为 AGC。
#
#   scripts/release-harmony.sh patch|minor|major   # 发新版：打下一个 harmony-v 的 tag 并推到 GitHub，构建
#   scripts/release-harmony.sh harmony-v0.2.0      # 重新构建某个已有版本
#   DRY_RUN=1 scripts/release-harmony.sh patch     # 演练：从当前 HEAD 构建，不打 tag、不建 Release
#
# 版本号：versionName = X.Y.Z；versionCode = (X+1)·1000000 + Y·1000 + Z（只增不减，AGC 要求），构建时注入，不改源码。
# 签名：仓库里 signingConfigs 是 []，构建时注入本机的签名配置：
#   HARMONY_SIGNING=<文件>  指定一份带 signingConfigs 的 build-profile.json5（上架用 AGC 发布证书那份，放在仓库外）
#   不指定 → 用本机 apps/harmony/build-profile.json5（DevEco 自动签名 = 调试证书：只能装到已登记的设备，不能上架）
# 产物：build/outputs/default/*.app（上传 AGC）与 entry 的 .hap（hdc install 装真机）。
#
# 回滚：应用市场发出去收不回来，也不能降版本号。有问题只能修复后发更高版本；
# 所以服务端必须兼容老版本客户端（apps/server/src/compat.js 的 MIN_CLIENT 只在新版已上架后才提高）。
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/lib-release.sh

D=/Applications/DevEco-Studio.app/Contents
[[ -d "$D" ]] || die "没找到 DevEco Studio（$D）"
SIGNING="${HARMONY_SIGNING:-apps/harmony/build-profile.json5}"

if [[ "${DRY_RUN:-}" == 1 ]]; then
  last="$(git tag -l 'harmony-v[0-9]*' --sort=-v:refname | head -1)"; VER="${last#harmony-v}"; VER="${VER:-0.0.0}"
  IFS=. read -r ma mi pa <<<"$VER"; VER="$ma.$mi.$((pa+1))"; TAG="harmony-v$VER-dry"; NEW=0
  SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT
  git ls-files -co --exclude-standard -z | xargs -0 tar -cf - | tar -xf - -C "$SRC"
  echo "▸ 演练：从当前工作区构建 $VER（不打 tag、不建 Release）"
else
  resolve_tag harmony-v "${1:-}"
  push_tag
  SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT
  checkout_tag "$SRC"
fi
IFS=. read -r ma mi pa <<<"$VER"; CODE=$(( (ma+1)*1000000 + mi*1000 + pa ))
H="$SRC/apps/harmony"

# 版本号与签名注入（只改解包出来的副本）
python3 - "$H" "$SIGNING" "$VER" "$CODE" <<'PY'
import re, sys
h, signing, ver, code = sys.argv[1:]
def arr(s, key):
    m = re.search(r'"%s"\s*:\s*\[' % key, s)
    if not m: return None
    i = m.end() - 1; d = 0; j = i; q = None
    while j < len(s):
        c = s[j]
        if q:
            if c == '\\': j += 1
            elif c == q: q = None
        elif c in '"\'': q = c
        elif c == '[': d += 1
        elif c == ']':
            d -= 1
            if d == 0: return (i, j + 1)
        j += 1
p = f'{h}/AppScope/app.json5'; s = open(p, encoding='utf-8').read()
s = re.sub(r'("versionCode"\s*:\s*)\d+', r'\g<1>' + code, s)
s = re.sub(r'("versionName"\s*:\s*")[^"]*(")', r'\g<1>' + ver + r'\2', s)
open(p, 'w', encoding='utf-8').write(s)
src = open(signing, encoding='utf-8').read(); a = arr(src, 'signingConfigs')
cfg = src[a[0]:a[1]] if a else '[]'
p = f'{h}/build-profile.json5'; s = open(p, encoding='utf-8').read(); b = arr(s, 'signingConfigs')
s = s[:b[0]] + cfg + s[b[1]:]
open(p, 'w', encoding='utf-8').write(s)
kind = 'none' if cfg.strip() == '[]' else ('debug' if ('debugKey' in cfg or 'default_harmony_' in cfg) else 'release')
open(f'{h}/.signing-kind', 'w').write(kind)
PY
KIND="$(cat "$H/.signing-kind")"; rm -f "$H/.signing-kind"
case "$KIND" in
  none) die "没有签名配置：DevEco 里配好签名，或用 HARMONY_SIGNING 指定" ;;
  debug) echo "⚠️  用的是 DevEco 自动签名（调试证书）：产物只能装到已登记的设备，不能上传 AGC 上架" ;;
  release) echo "▸ 发布证书签名" ;;
esac

echo "▸ 构建 __PRODUCT__ 鸿蒙 $VER（versionCode $CODE）"
export DEVECO_SDK_HOME=$D/sdk NODE_HOME=$D/tools/node PATH="$D/tools/node/bin:$D/tools/ohpm/bin:$PATH"
( cd "$H" && ohpm install --all >/dev/null \
  && node $D/tools/hvigor/bin/hvigorw.js assembleApp --mode project -p product=default -p buildMode=release --no-daemon 2>&1 \
     | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E "ERROR|BUILD SUCCESSFUL|BUILD FAILED|Error Message|At File" | head -40 )
APPF="$(ls "$H"/build/outputs/default/*-signed.app 2>/dev/null | head -1)"
HAPF="$(ls "$H"/entry/build/default/outputs/default/entry-default-signed.hap 2>/dev/null | head -1)"
[[ -n "$APPF" ]] || die "没有生成签名的 .app"
OUT="${TMPDIR:-/tmp}/__NAME__-harmony-release/$TAG"; mkdir -p "$OUT"
cp "$APPF" "$OUT/__PRODUCT__-harmony-$VER.app"; [[ -n "$HAPF" ]] && cp "$HAPF" "$OUT/__PRODUCT__-harmony-$VER.hap"
echo "▸ 产物：$OUT"; ls -lh "$OUT" | tail -n +2

if [[ "${DRY_RUN:-}" != 1 ]]; then
  github_release "$OUT"/*
  [[ "$KIND" == release ]] && echo "下一步（你本人）：AGC 控制台 → 我的应用 → __PRODUCT__ → 版本信息，上传 $OUT/__PRODUCT__-harmony-$VER.app 并提交审核"
fi
echo "✓ 鸿蒙 $TAG 构建完成"
