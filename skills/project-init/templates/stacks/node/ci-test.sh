#!/usr/bin/env bash
# 项目基线 v2 · Node 服务的 CI 测试入口（melon-ci pr-check：scripts/ci-test.sh 存在就跑；本机也能跑）。
# 不碰外网和真实数据：临时数据目录、随机端口；失败时打出服务日志。Node / pnpm 版本与 deploy/Dockerfile 一致。
# 私有包 @imelonkid/*：CI 里 melon-ci 提供 NODE_AUTH_TOKEN；本机先 export 一个有 read:packages 的令牌（.npmrc 引用它）
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ 安装依赖"
corepack enable >/dev/null 2>&1 || true
corepack prepare pnpm@10.32.1 --activate >/dev/null
pnpm install --frozen-lockfile

echo "▸ 测试"
pnpm run --if-present test

echo "▸ 冒烟：启动服务，等 /health 返回 200"
DATA="$(mktemp -d)"; LOG="$DATA/server.log"; PORT=$((20000 + RANDOM % 20000))
APP_VERSION=ci PORT="$PORT" DATA_DIR="$DATA" node src/server.js >"$LOG" 2>&1 &
PID=$!; trap 'kill $PID 2>/dev/null || true; rm -rf "$DATA"' EXIT
for _ in $(seq 30); do
  if curl -fsS "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"version":"ci"'; then echo "  ✓ /health 正常"; exit 0; fi
  kill -0 $PID 2>/dev/null || break
  sleep 1
done
echo "✗ 服务 30 秒内没有健康起来，日志："; cat "$LOG"; exit 1
