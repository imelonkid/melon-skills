#!/usr/bin/env bash
# 项目基线 v3 · NestJS 服务的 CI 测试入口（melon-ci pr-check：scripts/ci-test.sh 存在就跑；本机也能跑）。
# 检查 → 单测 → 编译 → 起临时 MySQL（Docker，随机端口、内存盘，跑完删掉）→ 迁移 → 端到端 → 冒烟（/health 版本 = ci）。
# 不碰外网服务和真实数据。Node 22 / pnpm 与 Dockerfile 一致（ci.yml 传 node-version: "22"）。
# 私有包 @imelonkid/*：CI 里 melon-ci 提供 NODE_AUTH_TOKEN；本机先 export 一个有 read:packages 的令牌
set -euo pipefail
cd "$(dirname "$0")/.."            # 多端项目放在 apps/server/scripts/ 时，这里就是 apps/server
MYSQL_IMAGE="${MYSQL_IMAGE:-mysql:8.4}"

echo "▸ 安装依赖"
corepack enable >/dev/null 2>&1 || true
corepack prepare pnpm@10.32.1 --activate >/dev/null
pnpm install --frozen-lockfile

echo "▸ 生成数据库客户端（src/generated，不进 git）"
pnpm run prisma:generate

echo "▸ 检查与单测"
pnpm run lint
pnpm run typecheck
pnpm run test

echo "▸ 编译"
pnpm run build

echo "▸ 临时 MySQL（${MYSQL_IMAGE}）"
DB="ci-mysql-$$-$RANDOM"; PW="ci-$RANDOM-$RANDOM"
docker run -d --rm --name "$DB" -e MYSQL_ROOT_PASSWORD="$PW" -e MYSQL_DATABASE=app -p 127.0.0.1::3306 --tmpfs /var/lib/mysql "$MYSQL_IMAGE" >/dev/null
DATA="$(mktemp -d)"; PID=""
cleanup() { [[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true; docker rm -f "$DB" >/dev/null 2>&1 || true; rm -rf "$DATA"; }
trap cleanup EXIT
PORT_DB="$(docker port "$DB" 3306/tcp | head -1 | sed 's/.*://')"
for _ in $(seq 60); do docker exec "$DB" mysqladmin ping -uroot -p"$PW" --silent >/dev/null 2>&1 && break; sleep 2; done
for _ in $(seq 30); do docker exec "$DB" mysql -uroot -p"$PW" -e 'SELECT 1' app >/dev/null 2>&1 && break; sleep 2; done
export DATABASE_URL="mysql://root:${PW}@127.0.0.1:${PORT_DB}/app"
pnpm exec prisma migrate deploy

echo "▸ 端到端"
pnpm run --if-present test:e2e

echo "▸ 冒烟：启动服务，等 /health 返回 200 且版本 = ci"
LOG="$DATA/server.log"; PORT=$((20000 + RANDOM % 20000))
APP_VERSION=ci PORT="$PORT" HOST=127.0.0.1 node dist/main.js >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 30); do
  if curl -fsS "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"version":"ci"'; then echo "  ✓ /health 正常"; exit 0; fi
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
echo "✗ 服务 30 秒内没有健康起来，日志："; cat "$LOG"; exit 1
