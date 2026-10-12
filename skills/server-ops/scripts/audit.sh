#!/usr/bin/env zsh
# 安全基线核查：确认加固过的配置没有被改回去。只读。
#   audit.sh [--sudo]     --sudo：需要提权的检查用 ssh -t 交互输密码
emulate -L zsh
source "${0:A:h}/lib.sh"

USE_SUDO=0
[[ "$1" == "--sudo" ]] && USE_SUDO=1
AGENT_PORT="${OPS_BESZEL_AGENT_PORT:-45876}"   # Beszel agent 的官方默认端口
issues=0

probe() {  # probe <ip> <port> <名称>：从本机能连上就是暴露了
  if nc -z -G 5 -w 5 "$1" "$2" 2>/dev/null; then
    bad "$3（$1:$2）从公网可达 —— 检查安全组！"; ((issues++))
  else
    ok "$3 对公网不可达"
  fi
}

print
hr "公网暴露面"
for p in ${=OPS_SITES}; do
  h=$(site $p SSH); ip=$(site $p IP); pp=$(site $p PANEL_PORT)
  [[ -n "$pp" ]] && probe "$ip" "$pp" "$h 1Panel"
  probe "$ip" "$AGENT_PORT" "$h Beszel agent"   # 只对监控中心的 /32 放行，本机连不上才对
done
if [[ -n "$OPS_IP" ]]; then
  [[ -n "$OPS_BESZEL_PORT" ]] && probe "$OPS_IP" "$OPS_BESZEL_PORT" "Beszel Hub"
  [[ -n "$OPS_GATUS_PORT"  ]] && probe "$OPS_IP" "$OPS_GATUS_PORT"  "Gatus"
fi

print
hr "SSH 配置"
for p in ${=OPS_SITES}; do
  h=$(site $p SSH)
  cfg=$(rsh "$h" 'sshd -T 2>/dev/null || sudo -n sshd -T 2>/dev/null')
  if [[ -z "$cfg" && $USE_SUDO -eq 1 ]]; then
    cfg=$(ssh -t -o ConnectTimeout=10 "$h" 'sudo sshd -T' 2>/dev/null | tr -d '\r')
  fi
  [[ -z "$cfg" ]] && { warn "$h 读不到 sshd 配置 —— 加 --sudo 重跑可交互提权"; continue; }
  g() { grep -i "^$1 " <<< "$cfg" | awk '{print $2}'; }
  [[ "$(g passwordauthentication)" == "no" ]] \
    && ok "$h 密码认证已关闭" \
    || { bad "$h 密码认证是开的！"; ((issues++)); }
  case "$(g permitrootlogin)" in
    no|prohibit-password|without-password) ok "$h PermitRootLogin = $(g permitrootlogin)（仅密钥）" ;;
    *) warn "$h PermitRootLogin = $(g permitrootlogin)（建议 prohibit-password）" ;;
  esac
  au=$(g allowusers); [[ -n "$au" ]] && ok "$h AllowUsers = $au" || warn "$h 未设 AllowUsers"
  mt=$(g maxauthtries); [[ "$mt" -le 3 ]] && ok "$h MaxAuthTries = $mt" || warn "$h MaxAuthTries = $mt（建议 3）"
done

print
hr "待打补丁"
for p in ${=OPS_SITES}; do
  h=$(site $p SSH)
  r=$(rsh "$h" '
    if command -v apt-get >/dev/null; then
      n=$(apt-get -s dist-upgrade 2>/dev/null | grep "^Inst" | grep -ci security)
      echo "apt $n $([ -f /var/run/reboot-required ] && echo 1 || echo 0)"
    elif [ "$(id -u)" != 0 ] && ! sudo -n true 2>/dev/null; then
      echo "needsudo"
    else
      s=$( (sudo -n true 2>/dev/null && sudo dnf updateinfo summary --security || dnf updateinfo summary --security) 2>/dev/null | grep -iE "Security notice" | head -4)
      echo "dnf"; echo "$s"
    fi')
  case "${r%%$'\n'*}" in
    "") warn "$h 查询失败" ;;
    needsudo) dim "$h 查询需提权（sudo 要密码），跳过" ;;
    apt*)
      read -r _ n rb <<< "$r"
      (( n > 0 )) && { warn "$h 有 $n 个安全更新待装（unattended-upgrades 没跑？）"; ((issues++)); } || ok "$h 无待装安全更新"
      (( rb == 1 )) && warn "$h 已装的更新需要重启生效" ;;
    dnf)
      s="${r#*$'\n'}"; s="${s#dnf}"
      if [[ -z "${s//[[:space:]]/}" ]]; then ok "$h 无待打安全补丁"
      else
        grep -qi critical <<< "$s" && { bad "$h 有 Critical 补丁待打"; ((issues++)); } || warn "$h 有安全补丁待打"
        print "$s" | sed 's/^/       /'
      fi ;;
  esac
done

print
hr "容器自启策略"
restart_bad=0
for p in ${=OPS_SITES}; do
  h=$(site $p SSH)
  out=$(rsh "$h" 'for c in $(docker ps -q); do docker inspect -f "{{.Name}} {{.HostConfig.RestartPolicy.Name}}" $c; done')
  while read -r n pol; do
    [[ -z "$n" ]] && continue
    [[ "$pol" == "always" || "$pol" == "unless-stopped" ]] \
      || { warn "$h ${n#/} 的 restart=$pol（重启后不会自动拉起）"; ((restart_bad++)); ((issues++)); }
  done <<< "$out"
done
(( restart_bad == 0 )) && ok "所有运行中的容器都会自动重启"

print
hr "磁盘"
for p in ${=OPS_SITES}; do
  h=$(site $p SSH)
  u=$(rsh "$h" "df / | awk 'NR==2{print \$5}' | tr -d %")
  [[ -z "$u" ]] && continue
  (( u >= 85 )) && { bad "$h 磁盘 ${u}%%"; ((issues++)); } || ok "$h 磁盘 ${u}%%"
done

print
hr "运维基线（\$OPS_REPO/registry/baseline.toml）"
BL="$OPS_REPO/baseline/check.py"
if [[ -x "$BL" ]]; then
  out=$("$BL" --quiet 2>&1) || ((issues++))
  print "$out" | grep -E "■|❌|全部|共" | sed 's/^/  /'
else
  warn "找不到 $BL"
fi

print
if (( issues == 0 )); then
  print -P "  %F{green}%B基线核查通过，没有发现回退%b%f"
else
  print -P "  %F{red}%B发现 $issues 处需要处理%b%f"
fi
print
