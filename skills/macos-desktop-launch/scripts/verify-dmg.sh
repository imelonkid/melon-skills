#!/usr/bin/env bash
# 在 macOS 上只读挂载流水线产物，验签并读取 App 版本。
set -euo pipefail
dmg="${1:?DMG 文件路径}"
expected="${2:?预期的 CFBundleShortVersionString}"
codesign --verify --strict "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"
mount_dir=$(mktemp -d)
trap 'rmdir "$mount_dir"' EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg" >/dev/null
trap 'hdiutil detach "$mount_dir" >/dev/null && rmdir "$mount_dir"' EXIT
shopt -s nullglob
apps=("$mount_dir"/*.app)
[[ ${#apps[@]} == 1 ]] || { echo "安装包顶层应含一个 .app" >&2; exit 1; }
app="${apps[0]}"
codesign --verify --deep --strict "$app"
spctl --assess --type execute "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$version" == "$expected" ]] || { echo "App 版本 $version，与预期 $expected 不符" >&2; exit 1; }
echo "Gatekeeper、签名、公证票据和 App 版本 $version 均通过"
