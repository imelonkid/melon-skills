#!/usr/bin/env bash
# 发布与回滚：一律以 git tag 为单位。线上版本 = 某个 tag，没有 tag 的代码不上线。
#
#   scripts/deploy.sh patch|minor|major   # 发新版：在 HEAD 打下一个 vX.Y.Z，推到 GitHub，构建并上线
#   scripts/deploy.sh v1.4.0              # 上线指定的已有 tag（比线上旧 = 回滚，相同 = 重新部署）
#   scripts/deploy.sh rollback            # 回滚到上一个成功上线的 tag
#   scripts/deploy.sh status              # 线上版本与最近的部署事件
#
#   EMERGENCY=1 scripts/deploy.sh patch   # 紧急变更：允许 08–23 点之外发新版，24 小时内补复盘
#
# 规则（运维规范 §5.1、§9.3）：
#   - 新 tag 只打在已推送到 origin/main 的干净 HEAD 上；tag 先推到 GitHub 再上线
#   - 镜像与 compose 都取自 tag 的内容（git archive / git show），与本地工作区无关
#   - 镜像名 <名>:<tag>，版本号经 build-arg 烘进镜像的 APP_VERSION
#   - 服务器 releases/<tag>.yml 存每个版本的 compose，docker-compose.prod.yml 是当前版本的副本
#   - 服务器保留最近 5 个版本；回滚到其中的版本不用重新构建，秒级完成
#   - 健康检查 60 秒不过，自动切回上线前的版本（镜像和 compose 一起切）
#   - 每次部署往 deploy.log 追加一行事件；当前版本写在 RELEASE
#   - 回滚不受发布窗口限制
#
# 服务器上只需事先准备好 /opt/__NAME__/ 和其中的 .env（来自 1Password ops/__NAME__/prod）。
set -euo pipefail

NAME=__NAME__
HOST="${DEPLOY_HOST:-__HOST__}"          # ~/.ssh/config 里的主机别名
DIR="/opt/$NAME"
HEALTH="http://127.0.0.1:__PORT__/health"
COMPOSE=docker-compose.prod.yml
KEEP=5

cd "$(git rev-parse --show-toplevel)"
die() { echo "✗ $*" >&2; exit 1; }
remote() { ssh "$HOST" "$@"; }

ARG="${1:-}"
[[ -n "$ARG" ]] || { sed -n '3,9p' "$0"; exit 1; }

if [[ "$ARG" == status ]]; then
  remote "cd $DIR && echo \"线上版本：\$(cat RELEASE 2>/dev/null || echo 未知)\" && tail -n 10 deploy.log 2>/dev/null"
  exit 0
fi

remote "test -d $DIR && test -f $DIR/.env" \
  || die "服务器上缺 $DIR 或 $DIR/.env（从 1Password ops/$NAME/prod 创建）"

git fetch -q --tags origin
CURRENT="$(remote "cat $DIR/RELEASE 2>/dev/null" || true)"

case "$ARG" in
  patch|minor|major)
    KIND=release
    h=$((10#$(date +%H)))
    if (( h < 8 || h >= 23 )) && [[ "${EMERGENCY:-}" != 1 ]]; then
      die "现在 $(date +%H:%M) 不在发布窗口（08–23 点）。紧急变更用 EMERGENCY=1，并在 24 小时内补复盘"
    fi
    [[ -z "$(git status --porcelain)" ]] || die "工作区有未提交的改动"
    [[ "$(git symbolic-ref --short HEAD)" == main ]] || die "只从 main 发版"
    git merge-base --is-ancestor HEAD origin/main || die "HEAD 还没推到 origin/main，先 git push"
    last="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -1)"; last="${last:-v0.0.0}"
    IFS=. read -r ma mi pa <<<"${last#v}"
    case "$ARG" in
      major) TAG="v$((ma+1)).0.0" ;;
      minor) TAG="v$ma.$((mi+1)).0" ;;
      patch) TAG="v$ma.$mi.$((pa+1))" ;;
    esac
    git tag -a "$TAG" -m "release $TAG"
    git push -q origin "$TAG"
    echo "▸ 新版本 $TAG（上一版 $last），tag 已推到 GitHub"
    ;;
  rollback)
    KIND=rollback
    TAG="$(remote "awk -F'\t' -v cur='$CURRENT' '\$5==\"ok\" && \$2!=cur {v=\$2} END{print v}' $DIR/deploy.log 2>/dev/null" || true)"
    [[ -n "$TAG" ]] || die "deploy.log 里找不到可回滚的上一版"
    echo "▸ 回滚：${CURRENT:-未知} → $TAG"
    ;;
  v*)
    git rev-parse -q --verify "refs/tags/$ARG" >/dev/null || die "tag $ARG 不存在（git tag -l 查看）"
    TAG="$ARG"
    if [[ "$TAG" == "$CURRENT" ]]; then KIND=redeploy
    elif [[ -n "$CURRENT" && "$(printf '%s\n' "$TAG" "$CURRENT" | sort -V | head -1)" == "$TAG" ]]; then KIND=rollback
    else KIND=release; fi
    ;;
  *) die "不认识的参数：$ARG" ;;
esac

# —— 镜像：服务器上已有就不重建；否则从 tag 的内容构建 ——
if remote "docker image inspect $NAME:$TAG >/dev/null 2>&1"; then
  echo "▸ 服务器已有镜像 $NAME:$TAG，跳过构建"
else
  echo "▸ 从 tag $TAG 构建 linux/amd64"
  SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT
  git archive "$TAG" | tar -x -C "$SRC"
  docker buildx build --platform linux/amd64 -f "$SRC/deploy/Dockerfile" \
    --build-arg APP_VERSION="$TAG" -t "$NAME:$TAG" --load "$SRC"
  echo "▸ 传输镜像"
  docker save "$NAME:$TAG" | gzip | remote 'gunzip | docker load' >/dev/null
fi
remote "mkdir -p $DIR/releases"
git show "$TAG:deploy/$COMPOSE" | remote "cat > $DIR/releases/$TAG.yml"

echo "▸ 上线 $TAG（$KIND）"
remote NAME="$NAME" TAG="$TAG" DIR="$DIR" HEALTH="$HEALTH" COMPOSE="$COMPOSE" KIND="$KIND" WHO="$(whoami)" KEEP="$KEEP" bash -s <<'REMOTE'
set -euo pipefail
cd "$DIR"
event()   { printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$1" "$KIND" "$WHO" "$2" >> deploy.log; }
switch()  { cp "releases/$1.yml" "$COMPOSE" && docker tag "$NAME:$1" "$NAME:prod" && docker compose -f "$COMPOSE" up -d --remove-orphans; }
healthy() { for _ in $(seq 30); do curl -fsS -o /dev/null "$HEALTH" && return 0; sleep 2; done; return 1; }

prev="$(cat RELEASE 2>/dev/null || true)"
if [[ "$KIND" == release && -x ./pre-deploy.sh ]]; then ./pre-deploy.sh; fi   # T0：发新版前先备份
switch "$TAG"
if healthy; then
  echo "$TAG" > RELEASE; event "$TAG" ok; echo "✓ $TAG 已上线且健康"
  # 只保留最近 KEEP 个版本（当前版本永远保留）
  for old in $(docker images "$NAME" --format '{{.Tag}}' | grep -E '^v[0-9]' | sort -rV | tail -n +$((KEEP+1))); do
    [[ "$old" == "$TAG" ]] && continue
    docker rmi "$NAME:$old" >/dev/null 2>&1 || true; rm -f "releases/$old.yml"
  done
  exit 0
fi
echo "✗ $TAG 60 秒内健康检查未通过"; docker compose -f "$COMPOSE" logs --tail 50 || true
event "$TAG" failed
if [[ -n "$prev" && -f "releases/$prev.yml" ]] && docker image inspect "$NAME:$prev" >/dev/null 2>&1; then
  echo "▸ 自动切回 $prev"
  KIND=auto-rollback; switch "$prev"
  if healthy; then event "$prev" ok; echo "✓ 已回到 $prev"; else event "$prev" failed; fi
fi
exit 1
REMOTE
