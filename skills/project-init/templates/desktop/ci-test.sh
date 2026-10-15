#!/usr/bin/env bash
# 项目基线 · 桌面应用的 CI 测试入口（melon-ci pr-check：scripts/ci-test.sh 存在就跑；本机也能跑）。
# 只跑不需要图形界面的测试（node --test）；不碰外网和真实数据。
set -euo pipefail
cd "$(dirname "$0")/.."
echo "▸ 安装依赖（不下载 Electron 二进制：测试用不到）"
corepack enable >/dev/null 2>&1 || true
corepack prepare pnpm@10.32.1 --activate >/dev/null
ELECTRON_SKIP_BINARY_DOWNLOAD=1 pnpm install --frozen-lockfile
echo "▸ 语法检查"
find src -name '*.js' -print0 | xargs -0 -n1 node --check
echo "▸ 测试"
pnpm run --if-present test
