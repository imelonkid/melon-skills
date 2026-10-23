#!/usr/bin/env bash
# 按项目基线把 GitHub 仓库设置应用到一个仓库（templates/github/settings.json）：合并方式、main 分支保护、production 环境。
#
#   scripts/github-apply.sh imelonkid/<名> [--kind service|desktop]           应用（幂等）
#   scripts/github-apply.sh imelonkid/<名> --check [--kind service|desktop]   只检查与基线是否一致，不改
#   --kind：production 环境要的变量与密钥按项目类型（默认 service：部署入口与镜像仓库；desktop：对象存储）
#
# 不写 secrets 与环境变量的值（DEPLOY_SSH_KEY、ACR_PASSWORD …）：那些按 SKILL.md「4b」由各自的流程写入；--check 只核对名字齐不齐。
set -euo pipefail
R="${1:?用法：github-apply.sh <owner/repo> [--check] [--kind service|desktop]}"; shift
MODE=apply; KIND=service
while [[ $# -gt 0 ]]; do
  case "$1" in --check) MODE=--check ;; --kind) KIND="${2:?--kind 要跟 service 或 desktop}"; shift ;; *) echo "不认识的参数：$1" >&2; exit 2 ;; esac
  shift
done
[[ "$KIND" == service || "$KIND" == desktop ]] || { echo "--kind 只能是 service 或 desktop" >&2; exit 2; }
S="$(cd "$(dirname "$0")/../templates/github" && pwd)/settings.json"
J() { python3 -c "import json,sys; d=json.load(open('$S')); print(json.dumps(eval(sys.argv[1])))" "$1"; }
fail=0; ok() { printf '  ✓ %s\n' "$*"; }; bad() { printf '  ✗ %s\n' "$*"; fail=1; }

if [[ "$MODE" != --check ]]; then
  echo "▸ 应用基线到 $R"
  gh api -X PATCH "repos/$R" --input <(J "d['repo']") --silent && ok "合并方式"
  B="$(J "d['branch_protection']['branch']" | tr -d '"')"
  gh api -X PUT "repos/$R/branches/$B/protection" --input <(J "{k:v for k,v in d['branch_protection'].items() if k!='branch'}") --silent && ok "$B 分支保护"
  for env in $(J "' '.join(d['environments'])" | tr -d '"'); do
    gh api -X PUT "repos/$R/environments/$env" -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true' --silent
    have="$(gh api "repos/$R/environments/$env/deployment-branch-policies" --jq '[.branch_policies[].name]|join(" ")')"
    for b in $(J "' '.join(d['environments']['$env']['branches'])" | tr -d '"'); do
      [[ " $have " == *" $b "* ]] || gh api -X POST "repos/$R/environments/$env/deployment-branch-policies" -f name="$b" -f type=branch --silent
    done
    ok "$env 环境（只允许 $(J "' '.join(d['environments']['$env']['branches'])" | tr -d '"')）"
  done
fi

echo "▸ 检查 $R 与基线是否一致"
python3 - "$R" "$S" "$KIND" <<'PY' || fail=1
import json, subprocess, sys
r, s, kind = sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3]
gh = lambda p: json.loads(subprocess.run(["gh", "api", p], capture_output=True, text=True).stdout or "null")
bad = 0
def chk(ok, msg):
    global bad
    print(("  ✓ " if ok else "  ✗ ") + msg); bad |= not ok
repo = gh(f"repos/{r}")
for k, v in s["repo"].items():
    chk(repo.get(k) == v, f"{k} = {v}（实际 {repo.get(k)}）")
bp = s["branch_protection"]; p = gh(f"repos/{r}/branches/{bp['branch']}/protection") or {}
want = set(bp["required_status_checks"]["contexts"]); have = set((p.get("required_status_checks") or {}).get("contexts", []))
chk(want <= have, f"{bp['branch']} 必须通过的检查：{', '.join(sorted(want))}" + ("" if want <= have else f"（缺 {', '.join(sorted(want - have))}）"))
chk((p.get("enforce_admins") or {}).get("enabled") is True, "管理员也受约束")
chk(p.get("required_pull_request_reviews") is not None, "必须走 PR")
chk((p.get("required_linear_history") or {}).get("enabled") is True, "线性历史")
for env, spec in s["environments"].items():
    pol = gh(f"repos/{r}/environments/{env}/deployment-branch-policies") or {}
    names = {x["name"] for x in pol.get("branch_policies", [])}
    chk(set(spec["branches"]) == names, f"{env} 环境只允许 {', '.join(spec['branches'])}（实际 {', '.join(sorted(names)) or '未设置'}）")
    need = (spec.get("kinds") or {}).get(kind, spec)
    for what in ("variables", "secrets"):
        want = set(need.get(what, []))
        have = {x["name"] for x in (gh(f"repos/{r}/environments/{env}/{what}?per_page=100") or {}).get(what, [])}
        miss = sorted(want - have)
        chk(not miss, f"{env} 环境的{'变量' if what == 'variables' else '密钥'}（{kind}）：{', '.join(sorted(want))}" + (f"（缺 {', '.join(miss)}）" if miss else ""))
sys.exit(bad)
PY
exit $fail
