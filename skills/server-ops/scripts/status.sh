#!/usr/bin/env zsh
# 全景状态：主机资源 + 容器 + 业务探活 + 容器漂移。只读。
# 容器基线来自环境变量 <站点>_CONTAINERS（空格分隔的容器名）。
emulate -L zsh
source "${0:A:h}/lib.sh"

print
hr "主机"
for p in ${=OPS_SITES}; do
  h=$(site $p SSH); ip=$(site $p IP)
  info=$(rsh "$h" 'printf "%s|%s|%s|%s|%s" \
    "$(nproc)C/$(free -g | awk "/^Mem:/{print \$2}")G" \
    "$(df -h / | awk "NR==2{print \$5\" 已用, \"\$4\" 可用\"}")" \
    "$(uname -r)" \
    "$(uptime -p 2>/dev/null | sed "s/up //")" \
    "$(awk "{print \$1}" /proc/loadavg)"')
  if [[ -z "$info" ]]; then bad "$h ($ip) 连不上"; continue; fi
  IFS='|' read -r spec disk kern up load <<< "$info"
  print -P "  %B$h%b  $ip"
  print "     $spec  磁盘 $disk  load $load"
  print "     内核 $kern  已运行 $up"
done

print
hr "容器"
for p in ${=OPS_SITES}; do
  h=$(site $p SSH); baseline=$(site $p CONTAINERS)
  print -P "  %B$h%b"
  live=$(rsh "$h" 'docker ps --format "{{.Names}}|{{.State}}|{{.Status}}"')
  if [[ -z "$live" ]]; then bad "  拿不到容器列表"; continue; fi
  names=()
  while IFS='|' read -r n st stat; do
    [[ -z "$n" ]] && continue
    names+=("$n")
    case "$stat" in
      *unhealthy*) bad  "  $n  $stat" ;;
      *healthy*)   ok   "  $n  $stat" ;;
      Up*)         print "    ·  $n  $stat" ;;
      *)           warn "  $n  $stat" ;;
    esac
  done <<< "$live"
  if [[ -z "$baseline" ]]; then dim "  未设 ${p}_CONTAINERS，跳过漂移检测"; continue; fi
  for b in ${=baseline}; do
    [[ " ${names[*]} " == *" $b "* ]] || bad "  基线里的 $b 没在运行"
  done
  for n in $names; do
    [[ " $baseline " == *" $n "* ]] || warn "  $n 不在基线清单里（新装的？记得更新 ops.zsh 的 ${p}_CONTAINERS）"
  done
done

print
hr "业务探活 (Gatus)"
if [[ -n "$OPS_SSH" && -n "$OPS_GATUS_PORT" ]]; then
  rsh "$OPS_SSH" "curl -s --max-time 8 http://127.0.0.1:$OPS_GATUS_PORT/api/v1/endpoints/statuses" \
    | python3 "$HOME/.zsh/bin/gatus-summary.py" 2>/dev/null \
    || bad "拿不到 Gatus 数据（容器没跑？）"
else
  dim "未设 OPS_SSH / OPS_GATUS_PORT，跳过"
fi
print
