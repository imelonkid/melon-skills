#!/usr/bin/env bash
# 发布：本机构建 linux/amd64 → 传镜像 → 同步 compose → 重建 → 健康检查，不过自动回滚。
#
#   scripts/deploy.sh            # 部署当前 HEAD（工作区必须干净）
#
# 服务器上只需要事先准备好 /opt/__NAME__/ 和其中的 .env（来自 1Password）。
set -euo pipefail

NAME=__NAME__
HOST="${DEPLOY_HOST:-__HOST__}"          # ~/.ssh/config 里的主机别名
DIR="/opt/$NAME"
HEALTH="http://127.0.0.1:__PORT__/health"
COMPOSE=docker-compose.prod.yml

cd "$(git rev-parse --show-toplevel)"
[[ -z "$(git status --porcelain)" ]] || { echo "✗ 工作区有未提交的改动，先提交"; exit 1; }
VER="$(git describe --tags --always)"
echo "▸ 版本 $VER → $HOST:$DIR"

ssh "$HOST" "test -d $DIR && test -f $DIR/.env" \
  || { echo "✗ 服务器上缺 $DIR 或 $DIR/.env（从 1Password ops/$NAME/prod 创建）"; exit 1; }

echo "▸ 构建"
docker buildx build --platform linux/amd64 -f deploy/Dockerfile -t "$NAME:$VER" --load .

echo "▸ 传输镜像"
docker save "$NAME:$VER" | gzip | ssh "$HOST" 'gunzip | docker load'
scp -q "deploy/$COMPOSE" "$HOST:$DIR/$COMPOSE"

echo "▸ 重建并检查健康"
ssh "$HOST" NAME="$NAME" VER="$VER" DIR="$DIR" HEALTH="$HEALTH" COMPOSE="$COMPOSE" bash -s <<'REMOTE'
set -euo pipefail
cd "$DIR"
[[ -x ./pre-deploy.sh ]] && ./pre-deploy.sh          # T0 服务：在这里先做一次备份
had_prev=0
docker image inspect "$NAME:prod" >/dev/null 2>&1 && { docker tag "$NAME:prod" "$NAME:rollback"; had_prev=1; }
docker tag "$NAME:$VER" "$NAME:prod"
docker compose -f "$COMPOSE" up -d
for _ in $(seq 30); do
  if curl -fsS -o /dev/null "$HEALTH"; then echo "✓ $VER 健康"; exit 0; fi
  sleep 2
done
echo "✗ 60 秒内健康检查未通过"
docker compose -f "$COMPOSE" logs --tail 50
if (( had_prev )); then
  echo "▸ 回滚到上一版"
  docker tag "$NAME:rollback" "$NAME:prod"
  docker compose -f "$COMPOSE" up -d
fi
exit 1
REMOTE
