#!/usr/bin/env zsh
# 共享：加载服务器坐标。
# 本 skill 在公开仓库里，不内置任何主机事实。坐标全部来自环境变量，定义在
# ~/.zsh/conf.d/ops.zsh（私有仓库 melon-ops/workstation/zsh/ops.zsh 的软链）
# 与本机的 ops.secrets.zsh。缺了就报错退出，不猜默认值。

for f in "$HOME/.zsh/conf.d/ops.secrets.zsh" "$HOME/.zsh/conf.d/ops.zsh"; do
  [[ -r "$f" ]] && source "$f" >/dev/null 2>&1
done

# need VAR…：缺任何一个就退出
need() {
  local v miss=()
  for v; do [[ -n "${(P)v}" ]] || miss+=("$v"); done
  (( ${#miss} == 0 )) && return 0
  print -u2 "缺少环境变量：${miss[*]}"
  print -u2 "定义在 ~/.zsh/conf.d/ops.zsh（私有仓库 melon-ops/workstation/zsh/ops.zsh）；刚加过就新开终端。"
  exit 2
}

# OPS_SITES：站点前缀列表，如 "ALI TX JD"；每个前缀 P 需要 P_SSH、P_IP，可选 P_CONTAINERS、P_PANEL_PORT
need OPS_SITES OPS_REPO
site() { local p=$1 k=$2; local n="${p}_${k}"; print -r -- "${(P)n}"; }   # site ALI SSH → $ALI_SSH
for _p in ${=OPS_SITES}; do need "${_p}_SSH" "${_p}_IP"; done; unset _p

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)

hr()  { print -P "%F{cyan}──── $1 ────────────────────────────%f"; }
ok()  { print -P "  %F{green}✅%f $1"; }
warn(){ print -P "  %F{yellow}⚠️ %f $1"; }
bad() { print -P "  %F{red}❌%f $1"; }
dim() { print -P "  %F{blue}$1%f"; }

# 在远端跑命令；失败返回非零
rsh() { ssh $SSH_OPTS "$1" "$2" 2>/dev/null; }
