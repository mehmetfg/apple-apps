#!/bin/bash
# Oturum başında: son değişiklikleri çek, devir-teslim notunu göster.
cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0
git fetch origin --quiet 2>/dev/null
echo "== Son 8 commit (tüm dallar) =="
git log --all --oneline -8 --decorate 2>/dev/null
echo
echo "== Çekilmemiş değişiklik =="
git status -sb 2>/dev/null | head -1
echo
echo "== HANDOFF.md =="
cat HANDOFF.md 2>/dev/null || echo "(HANDOFF.md yok)"
