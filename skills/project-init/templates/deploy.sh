#!/usr/bin/env bash
# 发布与回滚：一律以 git tag 为单位。线上版本 = 某个 tag，没有 tag 的代码不上线。
#
#   scripts/deploy.sh patch|minor|major   # 发新版：在 HEAD 打下一个 <前缀>X.Y.Z，推到 GitHub，构建并上线
#   scripts/deploy.sh v1.4.0              # 上线指定的已有 tag（比线上旧 = 回滚，相同 = 重新部署）
#   scripts/deploy.sh rollback            # 回滚到上一个成功上线的 tag（不受发布窗口限制）
#   scripts/deploy.sh status              # 线上版本、服务器上保留的版本、最近的部署事件
#   pbpaste | scripts/deploy.sh config    # 下发配置（.env 全文，来自 1Password），重建并检查健康，不过就还原
#
#   EMERGENCY=1 scripts/deploy.sh patch   # 紧急变更：允许 08–23 点之外发新版，24 小时内补复盘
#
# 服务器上的事全部由部署入口 deploy-agent 完成（私有运维仓库 melon-ops 的 agent/）：
#   - 本脚本只通过 <主机>-deploy（deploy 用户 + 强制命令）调用它，打不开 shell；CI 用的也是同一个入口
#   - compose 由入口自己从 GitHub 取该 tag 的内容（只读部署密钥），本脚本不传 compose
#   - 切换、健康检查（60 秒）、不过自动切回、保留最近 5 版、写 RELEASE 与 deploy.log 都在入口里
# 新服务上线前：在 melon-ops 的 agent/services/<主机>/<名>.conf 登记，跑 agent/install.sh <主机>
#
# 规则（运维规范 §5.1、§9.3）：
#   - 新 tag 只打在已推送到 origin/main 的干净 HEAD 上；tag 先推到 GitHub 再上线
#   - 镜像取自 tag 的内容（git archive）构建，与本地工作区无关；镜像名 <名>:<tag>，版本号经 build-arg 烘进 APP_VERSION
#   - 一个仓库多个端时各端独立 tag：服务端 TAG_PREFIX=server-v，客户端有自己的发布脚本
#   - 构建上下文需要额外内容（比如兄弟仓库按固定版本放进来）时，写 deploy/prepare-context.sh：
#     它在 tag 的内容解包后被 source，可读 ${SRC}、${TAG}，可改 ${CTX}（构建上下文）和 $DOCKERFILE
set -euo pipefail

NAME=__NAME__                            # 与部署入口里登记的服务名、镜像名一致
TAG_PREFIX=v                             # 单端项目 v；多端单仓库用 <端>-v，如 server-v
HOST="${DEPLOY_HOST:-__HOST__-deploy}"   # ~/.ssh/config 里的部署入口别名（deploy 用户）

cd "$(git rev-parse --show-toplevel)"
die() { echo "✗ $*" >&2; exit 1; }
agent() { ssh "$HOST" "$@"; }
WHO="as=$(whoami | tr -cd 'A-Za-z0-9._@-')"

ARG="${1:-}"
[[ -n "$ARG" ]] || { sed -n '3,10p' "$0"; exit 1; }
# 先确认连得上部署入口：连不上时别把「查不到」当成「没有」去白白构建
agent version >/dev/null 2>&1 || die "连不上部署入口 ${HOST}（1Password 解锁并授权了吗？可先执行 ssh $HOST version）"

case "$ARG" in
  status)   agent status "$NAME"; exit ;;
  rollback) agent rollback "$NAME" "$WHO"; exit ;;
  config)   [[ -t 0 ]] && die "用法：pbpaste | scripts/deploy.sh config（从 1Password 复制 .env 全文）"
            agent config "$NAME" "$WHO"; exit ;;
esac

git fetch -q --tags origin
case "$ARG" in
  patch|minor|major)
    h=$((10#$(date +%H)))
    if (( h < 8 || h >= 23 )) && [[ "${EMERGENCY:-}" != 1 ]]; then
      die "现在 $(date +%H:%M) 不在发布窗口（08–23 点）。紧急变更用 EMERGENCY=1，并在 24 小时内补复盘"
    fi
    [[ -z "$(git status --porcelain)" ]] || die "工作区有未提交的改动"
    [[ "$(git symbolic-ref --short HEAD)" == main ]] || die "只从 main 发版"
    git merge-base --is-ancestor HEAD origin/main || die "HEAD 还没推到 origin/main，先 git push"
    last="$(git tag -l "${TAG_PREFIX}[0-9]*.[0-9]*.[0-9]*" --sort=-v:refname | head -1)"; last="${last:-${TAG_PREFIX}0.0.0}"
    IFS=. read -r ma mi pa <<<"${last#"$TAG_PREFIX"}"
    case "$ARG" in
      major) TAG="${TAG_PREFIX}$((ma+1)).0.0" ;;
      minor) TAG="${TAG_PREFIX}$ma.$((mi+1)).0" ;;
      patch) TAG="${TAG_PREFIX}$ma.$mi.$((pa+1))" ;;
    esac
    git tag -a "$TAG" -m "release $TAG"
    git push -q origin "$TAG"
    echo "▸ 新版本 ${TAG}（上一版 ${last}），tag 已推到 GitHub"
    ;;
  "$TAG_PREFIX"[0-9]*)
    git rev-parse -q --verify "refs/tags/$ARG" >/dev/null || die "tag $ARG 不存在（git tag -l 查看）"
    TAG="$ARG"
    ;;
  *) die "不认识的参数：$ARG" ;;
esac

# —— 镜像：服务器上已有就不重建（回滚、重新部署秒级）；否则从 tag 的内容构建并上传 ——
if agent has "$NAME" "$TAG"; then
  echo "▸ 服务器已有镜像 $NAME:${TAG}，跳过构建"
else
  echo "▸ 从 tag $TAG 构建 linux/amd64"
  SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT
  git archive "$TAG" | tar -x -C "$SRC"
  CTX="$SRC"; DOCKERFILE="$SRC/deploy/Dockerfile"
  if [[ -f "$SRC/deploy/prepare-context.sh" ]]; then source "$SRC/deploy/prepare-context.sh"; fi
  docker buildx build --platform linux/amd64 -f "$DOCKERFILE" \
    --build-arg APP_VERSION="$TAG" -t "$NAME:$TAG" --load "$CTX"
  echo "▸ 上传镜像"
  docker save "$NAME:$TAG" | gzip | agent load "$NAME" "$TAG"
fi

agent deploy "$NAME" "$TAG" "$WHO"
