#!/usr/bin/env bash
# macOS 的建项基线跟踪公共 main；其他 Claude skills 继续链接开发工作区。
set -euo pipefail
R="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.claude/skills"
BK="$HOME/.claude/skills-backup/$(date +%Y%m%d-%H%M%S)"
if [[ "$OSTYPE" == darwin* ]]; then
  /usr/bin/python3 "$R/scripts/install_project_init.py"
fi
mkdir -p "$D"
for s in "$R"/skills/*/; do
  s="${s%/}"; n="$(basename "$s")"; dst="$D/$n"
  if [[ "$n" == project-init && "$OSTYPE" == darwin* ]]; then continue; fi
  [[ -f "$s/SKILL.md" ]] || { echo "  ? 跳过 ${n}（没有 SKILL.md）"; continue; }
  if [[ -L "$dst" && "$(readlink "$dst")" == "$s" ]]; then echo "  = $n"; continue; fi
  if [[ -e "$dst" || -L "$dst" ]]; then mkdir -p "$BK"; mv "$dst" "$BK/"; echo "  ↪ 备份 $dst → $BK/"; fi
  ln -s "$s" "$dst"; echo "  + $n → $s"
done

# 提交前敏感信息扫描（仓库是公开的）
git -C "$R" config core.hooksPath .githooks && echo "  ✓ pre-commit 敏感信息扫描已启用"
