#!/usr/bin/env bash
# 项目基线 v1 · 静态站的 CI 测试入口：能构建出产物即通过（melon-ci pr-check 另外会构建镜像）
set -euo pipefail
cd "$(dirname "$0")/.."
corepack enable >/dev/null 2>&1 || true
corepack prepare pnpm@10.32.1 --activate >/dev/null
pnpm install --frozen-lockfile
pnpm run build
[[ -n "$(ls -A dist 2>/dev/null)" ]] || { echo "✗ 构建后 dist/ 是空的"; exit 1; }
echo "  ✓ 构建成功"
