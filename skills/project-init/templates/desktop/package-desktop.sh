#!/usr/bin/env bash
# 项目基线 · 桌面应用的打包钩子（走「技术选型例外」、不用 Electron 的桌面应用才需要；Electron 项目不放这个文件）。
# scripts/release-desktop.sh build 在 tag 的内容里调用它：
#
#   scripts/package-desktop.sh <版本号 X.Y.Z> <tag vX.Y.Z> <输出目录>
#
# 约定：
#   1. 在 <输出目录> 产出 __PRODUCT__.app（名字与 release-desktop.sh 的 PRODUCT 一致），至少 ad-hoc 签名（codesign --sign -）
#   2. 版本号构建时注入，不改源码：Info.plist 的 CFBundleShortVersionString = X.Y.Z、CFBundleVersion = tag；
#      随应用分发的命令行工具同样注入（如 Go：-ldflags "-X main.version=<tag>"）
#   3. 只用 macOS 构建机自带或流水线装好的工具（Xcode / Swift、Node、按需的 Go）；不下载未钉版本的东西
#   4. 失败就非零退出（release-desktop.sh 据此中止，不发布半成品）
# dmg、版本清单、上传、GitHub Release 由 release-desktop.sh 统一做，这里不管。
set -euo pipefail
VER="${1:?版本号}"; TAG="${2:?tag}"; OUT="${3:?输出目录}"
mkdir -p "$OUT"

# ↓ 换成本项目的构建步骤，最后把 .app 放到 "$OUT/__PRODUCT__.app"
#   例（SwiftPM 菜单栏 App）：
#   swift build -c release --arch arm64 --package-path apps/macos
#   …组装 "$OUT/__PRODUCT__.app/Contents/{MacOS,Resources,Info.plist}"，Info.plist 写入 $VER / $TAG
#   codesign --force --sign - "$OUT/__PRODUCT__.app"
echo "✗ scripts/package-desktop.sh 还没写本项目的构建步骤" >&2; exit 1
