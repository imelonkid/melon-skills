#!/usr/bin/env bash
# 公开仓库的敏感信息扫描。pre-commit 钩子只扫暂存区；手动运行扫全部已跟踪文件。
#
#   scripts/scan-secrets.sh            # 扫全部已跟踪文件
#   scripts/scan-secrets.sh --staged   # 只扫暂存的改动（pre-commit 用）
#
# 两类检查：
#   1. 通用模式：公网 IP、私钥、云厂商 AK、GitHub / OpenAI 类 token、手机号、身份证号、webhook key
#   2. 本机环境变量的**实际值**：把 ~/.zsh/conf.d/ops*.zsh 里的 IP、端口、面板入口、服务器路径
#      逐个当作字面量去搜——变量名可以出现，变量值不行
# 确属误报的行，在行尾加注释 `scan:allow`。
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

if [[ "${1:-}" == "--staged" ]]; then
  files=$(git diff --cached --name-only --diff-filter=ACMR)
  content() { git show ":$1" 2>/dev/null; }
else
  files=$(git ls-files)
  content() { cat "$1" 2>/dev/null; }
fi
[[ -z "$files" ]] && exit 0

# 本机坐标：在一个干净的 zsh 里加载 ops 配置，取出敏感变量的值
values=$(zsh -c '
  for f in ~/.zsh/conf.d/ops.secrets.zsh ~/.zsh/conf.d/ops.zsh; do [[ -r $f ]] && source $f >/dev/null 2>&1; done
  for v in ${(k)parameters}; do
    [[ $v == (ALI|TX|JD|OPS|BLOG)_*(IP|PORT|ENTRY|WEBROOT|CONF) ]] || continue
    val=${(P)v}; (( ${#val} >= 4 )) && print -r -- "$v=$val"
  done' 2>/dev/null | sort -u)

PATTERNS=(
  '公网 IP|\b(([1-9][0-9]?|1[0-9]{2}|2[01][0-9]|22[0-3])\.)([0-9]{1,3}\.){2}[0-9]{1,3}\b'
  '私钥|-----BEGIN [A-Z ]*PRIVATE KEY-----'
  '阿里云 AK|\bLTAI[0-9A-Za-z]{12,}'
  '腾讯云 AK|\bAKID[0-9A-Za-z]{13,}'
  'GitHub token|\bgh[pousr]_[0-9A-Za-z]{30,}'
  'API key|\bsk-[0-9A-Za-z_-]{20,}'
  'Slack token|\bxox[abprs]-[0-9A-Za-z-]{10,}'
  'webhook key|key=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
  '手机号|(^|[^0-9])1[3-9][0-9]{9}([^0-9]|$)'
  '身份证号|(^|[^0-9])[1-9][0-9]{5}(19|20)[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])[0-9]{3}[0-9Xx]([^0-9]|$)'
)
ALLOW_IP='^(127\.|0\.0\.0\.0|255\.|1\.1\.1\.1|8\.8\.8\.8)'

hits=0
report() { printf '  ✗ %s  %s:%s  %s\n' "$1" "$2" "$3" "$(cut -c1-120 <<<"$4")"; hits=$((hits+1)); }

while IFS= read -r f; do
  [[ -z "$f" || "$f" == scripts/scan-secrets.sh ]] && continue
  file -b --mime "$f" 2>/dev/null | grep -q 'charset=binary' && continue
  body=$(content "$f") || continue
  for p in "${PATTERNS[@]}"; do
    name="${p%%|*}"; re="${p#*|}"
    while IFS=: read -r ln line; do
      [[ -z "$ln" || "$line" == *scan:allow* ]] && continue
      if [[ "$name" == "公网 IP" ]]; then
        ip=$(grep -oE "$re" <<<"$line" | grep -vE "$ALLOW_IP" | head -1)
        [[ -z "$ip" ]] && continue
      fi
      report "$name" "$f" "$ln" "$line"
    done < <(grep -nE -e "$re" <<<"$body")
  done
  while IFS= read -r kv; do
    [[ -z "$kv" ]] && continue
    v="${kv%%=*}"; val="${kv#*=}"
    while IFS=: read -r ln line; do
      [[ -z "$ln" || "$line" == *scan:allow* ]] && continue
      report "本机 \$$v 的值" "$f" "$ln" "$line"
    done < <(grep -nF -e "$val" <<<"$body")
  done <<<"$values"
done <<<"$files"

if (( hits )); then
  echo "发现 $hits 处疑似敏感信息。改成环境变量引用；确属误报在行尾加 scan:allow。"
  exit 1
fi
echo "✓ 未发现敏感信息（$(wc -l <<<"$files" | tr -d ' ') 个文件$([[ -n "$values" ]] && echo "，比对了 $(wc -l <<<"$values" | tr -d ' ') 个本机坐标值")）"
