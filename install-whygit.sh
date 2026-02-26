#!/bin/bash
# install-whygit.sh
# Run this from the root of any repo to add whygit AI decision logging

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-.}"  # default to current directory

echo "📦 Installing whygit into: $TARGET"

# Create directories
mkdir -p "$TARGET/.claude/commands"
mkdir -p "$TARGET/ai-logs"

# Copy command files
cp "$SCRIPT_DIR/.claude/commands/commit.md" "$TARGET/.claude/commands/commit.md"
cp "$SCRIPT_DIR/.claude/commands/rewind.md" "$TARGET/.claude/commands/rewind.md"
cp "$SCRIPT_DIR/.claude/commands/log.md"    "$TARGET/.claude/commands/log.md"

# Copy ai-logs placeholder
cp "$SCRIPT_DIR/ai-logs/.gitkeep" "$TARGET/ai-logs/.gitkeep"

# Merge or create CLAUDE.md
if [ -f "$TARGET/CLAUDE.md" ]; then
  echo "" >> "$TARGET/CLAUDE.md"
  echo "---" >> "$TARGET/CLAUDE.md"
  cat "$SCRIPT_DIR/CLAUDE.md" >> "$TARGET/CLAUDE.md"
  echo "⚠️  Appended to existing CLAUDE.md — review for duplicates"
else
  cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md"
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
