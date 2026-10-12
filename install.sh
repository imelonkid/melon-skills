#!/usr/bin/env bash
# 把 skills/* 软链到 ~/.claude/skills/。幂等；已有同名目录先备份。
set -euo pipefail
R="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.claude/skills"
BK="$HOME/.claude/skills-backup/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$D"
for s in "$R"/skills/*/; do
  s="${s%/}"; n="$(basename "$s")"; dst="$D/$n"
  [[ -f "$s/SKILL.md" ]] || { echo "  ? 跳过 $n（没有 SKILL.md）"; continue; }
  if [[ -L "$dst" && "$(readlink "$dst")" == "$s" ]]; then echo "  = $n"; continue; fi
  if [[ -e "$dst" || -L "$dst" ]]; then mkdir -p "$BK"; mv "$dst" "$BK/"; echo "  ↪ 备份 $dst → $BK/"; fi
  ln -s "$s" "$dst"; echo "  + $n → $s"
done

# 提交前敏感信息扫描（仓库是公开的）
git -C "$R" config core.hooksPath .githooks && echo "  ✓ pre-commit 敏感信息扫描已启用"
