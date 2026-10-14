#!/usr/bin/env bash
# 项目基线 v1 · Python 服务的 CI 测试入口（melon-ci pr-check：scripts/ci-test.sh 存在就跑；本机也能跑）。
# 不碰外网和真实数据：临时数据目录、随机端口；失败时打出服务日志。Python 版本与 deploy/Dockerfile 一致。
set -euo pipefail
cd "$(dirname "$0")/.."
PY="${PYTHON:-python3}"

echo "▸ 语法检查"
"$PY" -m compileall -q app

if [[ -d tests ]]; then
  echo "▸ 单元测试"
  "$PY" -m unittest discover -s tests -q
fi

echo "▸ 冒烟：启动服务，等 /health 返回 200"
DATA="$(mktemp -d)"; LOG="$DATA/server.log"; PORT=$((20000 + RANDOM % 20000))
APP_VERSION=ci "$PY" -u app/main.py --data "$DATA" --port "$PORT" >"$LOG" 2>&1 &
PID=$!; trap 'kill $PID 2>/dev/null || true; rm -rf "$DATA"' EXIT
for _ in $(seq 30); do
  if curl -fsS "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"version": *"ci"'; then echo "  ✓ /health 正常"; exit 0; fi
  kill -0 $PID 2>/dev/null || break
  sleep 1
done
echo "✗ 服务 30 秒内没有健康起来，日志："; cat "$LOG"; exit 1
