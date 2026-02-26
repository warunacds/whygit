#!/bin/bash
# install-whygit.sh
# Run this from the root of any repo to add whygit AI decision logging

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-.}"  # default to current directory

# --- Input validation ---

# Resolve to absolute path and ensure it exists and is a directory
TARGET="$(cd -- "$TARGET" 2>/dev/null && pwd)" || {
  echo "❌ Error: '$1' is not a valid directory." >&2
  exit 1
}

# Ensure target is a git repository (works for regular repos and worktrees)
if ! git -C "$TARGET" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "❌ Error: '$TARGET' is not a git repository. whygit requires a git repo." >&2
  exit 1
fi

# Ensure source files exist before starting
MISSING=0
for src in \
  "$SCRIPT_DIR/.claude/commands/commit.md" \
  "$SCRIPT_DIR/.claude/commands/rewind.md" \
  "$SCRIPT_DIR/.claude/commands/log.md" \
  "$SCRIPT_DIR/ai-logs/.gitkeep" \
  "$SCRIPT_DIR/CLAUDE.md"; do
  if [ ! -f "$src" ]; then
    echo "❌ Missing source file: $src" >&2
    MISSING=1
  fi
done
[ "$MISSING" -eq 1 ] && exit 1

# --- Trap for partial-failure cleanup ---
trap 'echo "" >&2; echo "❌ Install failed. whygit may be partially installed — check $TARGET manually." >&2' ERR

echo "📦 Installing whygit into: $TARGET"

# Create directories
mkdir -p -- "$TARGET/.claude/commands"
mkdir -p -- "$TARGET/ai-logs"

# Copy command files
cp -- "$SCRIPT_DIR/.claude/commands/commit.md" "$TARGET/.claude/commands/commit.md"
cp -- "$SCRIPT_DIR/.claude/commands/rewind.md" "$TARGET/.claude/commands/rewind.md"
cp -- "$SCRIPT_DIR/.claude/commands/log.md"    "$TARGET/.claude/commands/log.md"

# Copy ai-logs placeholder
cp -- "$SCRIPT_DIR/ai-logs/.gitkeep" "$TARGET/ai-logs/.gitkeep"

# Merge or create CLAUDE.md (idempotent: skip if already contains whygit block)
if [ -f "$TARGET/CLAUDE.md" ]; then
  if grep -qF "AI Decision Logging" "$TARGET/CLAUDE.md"; then
    echo "ℹ️  CLAUDE.md already contains whygit config — skipping append"
  else
    {
      echo ""
      echo "---"
      cat -- "$SCRIPT_DIR/CLAUDE.md"
    } >> "$TARGET/CLAUDE.md"
    echo "⚠️  Appended to existing CLAUDE.md — review for duplicates"
  fi
else
  cp -- "$SCRIPT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md"
fi

echo ""
echo "✅ Done! whygit installed:"
echo "   $TARGET/CLAUDE.md"
echo "   $TARGET/.claude/commands/commit.md"
echo "   $TARGET/.claude/commands/rewind.md"
echo "   $TARGET/.claude/commands/log.md"
echo "   $TARGET/ai-logs/.gitkeep"
echo ""
echo "📝 Next: git add . && git commit -m 'chore: add AI decision logging'"
echo ""
echo "🚀 In Claude Code, use:"
echo "   /commit         → log + commit"
echo "   /log            → log only"
echo "   /rewind         → browse history"
echo "   /rewind <topic> → search history"
