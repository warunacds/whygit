#!/bin/bash
# install-whygit.sh
# Self-contained installer — pipe directly from curl or run locally.
# All file contents are embedded as heredocs; no source-directory dependency.
#
# Usage:
#   bash install-whygit.sh [target-directory]
#   curl -fsSL <url>/install-whygit.sh | bash -s -- [target-directory]

set -e

TARGET="${1:-.}"

# --- Input validation ---

# Resolve to absolute path and ensure it exists and is a directory
TARGET="$(cd -- "$TARGET" 2>/dev/null && pwd)" || {
  echo "❌ Error: '${1:-.}' is not a valid directory." >&2
  exit 1
}

# Ensure target is a git repository (works for regular repos and worktrees)
if ! git -C "$TARGET" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "❌ Error: '$TARGET' is not a git repository. whygit requires a git repo." >&2
  exit 1
fi

echo "📦 Installing whygit into: $TARGET"

# --- Trap for partial-failure cleanup (registered after validation, so it only fires during install) ---
trap 'echo "" >&2; echo "❌ Install failed. whygit may be partially installed — check $TARGET manually." >&2' ERR

# Create directories
mkdir -p -- "$TARGET/.claude/commands"
mkdir -p -- "$TARGET/ai-logs"

# --- FILE: .claude/commands/commit.md ---
cat > "$TARGET/.claude/commands/commit.md" << 'HEREDOC'
# /commit — AI Decision Log + Git Commit

Perform the following steps in order. Do not skip any step.

## Step 1: Gather context

Run these commands to understand what changed:
```
git diff --staged --stat
git diff --staged
git status
```

If nothing is staged, run `git add -A` first, then re-check.

## Step 2: Generate the AI log

Create a log file at `ai-logs/YYYY-MM-DD-<slug>.md` where:
- `YYYY-MM-DD` is today's date
- `<slug>` is a 2-4 word kebab-case summary of the work (e.g. `auth-middleware-refactor`)

Use this exact template:

```markdown
---
date: YYYY-MM-DD
model: claude-sonnet-4-6
session_summary: <one line description>
---

## What we built / changed

<Describe what was actually implemented or modified. Be specific about files and logic.>

## Key decisions & reasoning

<For each significant decision made during this session, explain:
- What the decision was
- Why this approach was chosen
- What tradeoff it involves>

## Alternatives considered

<List approaches that were discussed or considered but not taken, and why they were rejected.>

## Prompts that shaped direction

<Summarize the key prompts or questions from the user that drove the most important decisions. Paraphrase, don't copy verbatim.>

## Follow-up / known limitations

<Note anything left incomplete, known issues, or suggested next steps.>
```

## Step 3: Stage the log

```
git add ai-logs/
```

## Step 4: Commit everything

Write a conventional commit message referencing the log:

```
git commit -m "<type>: <short description>

AI decision log: ai-logs/YYYY-MM-DD-<slug>.md

<2-3 sentence summary of what changed and the key reasoning>"
```

Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`

## Step 5: Confirm

Tell the user:
- The commit hash (from `git log -1 --oneline`)
- The log file path
- A one-line summary of what was committed
HEREDOC

# --- FILE: .claude/commands/log.md ---
cat > "$TARGET/.claude/commands/log.md" << 'HEREDOC'
# /log — Write AI Decision Log (without committing)

Same as /commit but only writes the log file — does not stage or commit anything.

Useful when you want to capture reasoning mid-session or when you'll commit manually.

## Step 1: Generate the log

Look at recent changes for context:
```
git diff HEAD
git status
```

## Step 2: Write the log file

Create `ai-logs/YYYY-MM-DD-<slug>.md` using the same template as /commit:

```markdown
---
date: YYYY-MM-DD
model: claude-sonnet-4-6
session_summary: <one line description>
---

## What we built / changed

## Key decisions & reasoning

## Alternatives considered

## Prompts that shaped direction

## Follow-up / known limitations
```

## Step 3: Confirm

Tell the user the file path. Remind them to include it in their next commit or run `/commit` when ready.
HEREDOC

# --- FILE: .claude/commands/rewind.md ---
cat > "$TARGET/.claude/commands/rewind.md" << 'HEREDOC'
# /rewind — Browse AI Decision History

Browse past AI decision logs to understand why code was written the way it was.

## Usage

- `/rewind` — show all sessions, newest first
- `/rewind <keyword>` — find sessions related to a topic
- `/rewind <date>` — show sessions from a specific date (YYYY-MM-DD)

## Step 1: List available logs

```
ls -t ai-logs/*.md 2>/dev/null || echo "No AI logs found."
```

If no logs exist, tell the user: "No AI decision logs found. Use /commit at the end of a session to start building your history."

## Step 2: Handle the query

### No argument → show index

For each file in `ai-logs/` (newest first), extract and display:
- Date
- `session_summary` from frontmatter
- `## What we built / changed` (first 2 sentences only)
- Filename as reference

Format as a clean numbered list. Example:
```
1. 2025-02-26 · auth-middleware-refactor
   Refactored JWT auth into middleware layer. Moved token validation out of controllers.
   → ai-logs/2025-02-26-auth-middleware-refactor.md

2. 2025-02-24 · payment-webhook-handling
   Added Stripe webhook endpoint with signature verification.
   → ai-logs/2025-02-24-payment-webhook-handling.md
```

### Keyword argument → search and show

Search log files for the keyword:
```
grep -ril "<keyword>" ai-logs/
```

Show full content of matching files, or the top 2 if many match.

### Date argument → show that day's sessions

```
ls ai-logs/<date>-*.md
```

Show full content of each file from that date.

## Step 3: Offer to dig deeper

After showing the index or search results, ask:
"Want me to show the full reasoning for any of these? Just say the number or slug."

When showing a full log, also run:
```
git log --oneline --all | grep <slug>
```
to surface the exact commit(s) associated with that session.
HEREDOC

# --- FILE: ai-logs/.gitkeep ---
touch "$TARGET/ai-logs/.gitkeep"

# --- FILE: CLAUDE.md (idempotent: append only if block not already present) ---
CLAUDE_BLOCK='# Claude Code Instructions

## AI Decision Logging

This repo uses AI decision logging to track reasoning alongside code changes.

### Rules
- **Never delete or modify files** in `ai-logs/`
- At the end of any significant work session, proactively offer: *"Want me to log this session and commit? Just say /commit."*
- If the user asks "why did we do X" or "how did we decide Y", check `ai-logs/` first before answering from context

### Commands
| Command | What it does |
|---------|-------------|
| `/commit` | Logs session reasoning → stages all changes → commits |
| `/log` | Writes a log file only, no commit |
| `/rewind` | Browse all past AI decision logs |
| `/rewind <keyword>` | Search logs by topic |
| `/rewind <date>` | Show logs from a specific date |

### Log format
Logs live in `ai-logs/YYYY-MM-DD-<slug>.md` and capture:
- What was built/changed
- Key decisions and reasoning
- Alternatives considered
- Prompts that shaped direction
- Follow-up / known limitations

### When to log
- After implementing a non-trivial feature
- After a significant refactor
- After debugging a hard problem
- After making an architectural decision
- Any session where "why did we do it this way" might be asked later'

if [ -f "$TARGET/CLAUDE.md" ]; then
  if grep -qF "AI Decision Logging" "$TARGET/CLAUDE.md"; then
    echo "ℹ️  CLAUDE.md already contains whygit config — skipping append"
  else
    printf '\n---\n%s\n' "$CLAUDE_BLOCK" >> "$TARGET/CLAUDE.md"
    echo "⚠️  Appended to existing CLAUDE.md — review for duplicates"
  fi
else
  printf '%s\n' "$CLAUDE_BLOCK" > "$TARGET/CLAUDE.md"
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
