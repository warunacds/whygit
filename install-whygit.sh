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
mkdir -p -- "$TARGET/.claude/skills/.conflicts"
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
1. 2026-02-26 · auth-middleware-refactor
   Refactored JWT auth into middleware layer. Moved token validation out of controllers.
   → ai-logs/2026-02-26-auth-middleware-refactor.md

2. 2026-02-24 · payment-webhook-handling
   Added Stripe webhook endpoint with signature verification.
   → ai-logs/2026-02-24-payment-webhook-handling.md
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

# --- FILE: .claude/commands/learn.md ---
cat > "$TARGET/.claude/commands/learn.md" << 'HEREDOC'
# /learn — Mine ai-logs/ for Learnable Failures

Turn accumulated `ai-logs/` entries into concrete, repo-specific guardrails in `.claude/skills/`. This is the *read* half of whygit's reflective loop — `/commit` writes the diary, `/learn` turns the diary into a rulebook.

**Principle:** stop making the same mistake twice in this repo.

## Usage

- `/learn` — mine all unprocessed logs
- `/learn --log <path>` — re-mine one specific log, ignoring the processed ledger

## Step 0: Validate environment

Confirm `.claude/skills/` exists. If it doesn't, tell the user:

> `.claude/skills/` not found. Re-run `install-whygit.sh` in this repo to upgrade whygit with the /learn feature.

And stop.

## Phase 1 — Gather

1. Read `.claude/skills/.processed` if present. Treat missing as empty. Parse as one log filename per line.
2. If `--log <path>` was passed, operate on that single file and ignore the processed ledger.
3. Otherwise, list files in `ai-logs/` (ignore `.gitkeep` and non-`.md` files). Exclude any file whose basename appears in `.processed`. Sort newest-first by filename date prefix.
4. Read each unprocessed log in full using the Read tool.
5. List files in `.claude/skills/`. For each `*.md` file (excluding `README.md`), read only the frontmatter + the `## When to apply` and `## When NOT to apply` sections. Skip bodies for token efficiency.
6. Read every file in `.claude/skills/.conflicts/` (if any) so you know which tensions are already flagged. Do not re-flag the same conflict.

If there are no unprocessed logs and no `--log` flag, tell the user:

> No unprocessed logs in `ai-logs/`. Everything in `.processed` has already been mined. Run `/learn --log <path>` to re-mine a specific log.

And stop.

## Phase 2 — Attribute

For each unprocessed log, decide whether it contains a **learnable failure**. A learnable failure is one of:

- A wrong turn that wasted time ("we initially tried X but it didn't work because…")
- A bug that shipped and had to be fixed
- A decision that was reversed in a later session
- A piece of context that, if known earlier, would have changed the approach
- A repeated annoyance ("this is the third time we've had to remember…")

Logs that record only successful, uneventful work are **not** learnable. Skip them. They still get recorded in `.processed` at the end so you don't re-read them next time.

For each learnable failure, classify it:

- **NEW** — no existing skill's `When to apply` matches this failure's shape. Draft a new skill file.
- **PATCH** — an existing skill covers the category but missed this specific case. Draft a guardrail addition to the existing skill's `## Guardrails` section.
- **CONFLICT** — the failure directly contradicts what an existing skill says. Do **not** attempt to resolve. Draft a conflict record for `.claude/skills/.conflicts/`.

## Phase 3 — Self-audit (the quality gate)

The biggest failure mode of `/learn` is producing abstract, generic skills. The following checks exist to prevent that. Apply them to every NEW or PATCH draft **before** including it in the proposal.

Run each check in order. If a check fails, attempt exactly **one** rewrite. If the rewrite still fails, **drop the draft silently** (it does not appear in the proposal). Keep a count of drops with reasons to report at the end of Phase 3.

### Check 1: Specificity

Does `## When to apply` name at least one concrete artefact — a file path, function name, library name, schema type, data shape, command, or API endpoint?

- **Good:** "Modifying a `@Model` class in `Sources/Models/` that has already shipped to TestFlight."
- **Bad:** "Working with data models." "Anything involving state management."

If no concrete artefact, rewrite once. If still generic, drop.

### Check 2: Citation

Does `## Why this exists` quote or paraphrase the specific failure from the source log, with enough detail that a reader can verify the lesson is real by opening the log?

- **Good:** "Captured from `ai-logs/2026-04-03-auth-refactor.md` — we shipped a non-optional `User.lastLoginAt` and crashed every existing install on launch."
- **Bad:** "Captured from past experience with migration issues."

If the citation is vague or missing, rewrite once. If still vague, drop.

### Check 3: Banned phrases

Reject any guardrail containing these phrases:

- "be careful with"
- "think about"
- "consider"
- "make sure to"
- "in general"
- "as a rule of thumb"
- "best practice"
- "keep in mind"
- "be aware"

These are abstraction tells. A guardrail should be a specific rule tied to a specific trigger. Rewrite the guardrail as a concrete instruction. If you cannot make it concrete, drop the draft.

### Check 4: Deletability

Ask yourself: could a reasonable developer on a new team have written this skill **without ever reading the source log**? If yes, it's too generic — drop it. The whole point of a skill is that it encodes a specific repo's specific scar tissue.

### Few-shot examples (internalize before drafting)

**GOOD draft:**

```markdown
# Install scripts piped from curl must be self-contained

## When to apply
- Writing a shell script users will run via `curl -fsSL ... | bash`
- Any installer that copies or references files relative to itself

## When NOT to apply
- Scripts only ever run locally after `git clone`

## Guardrails
1. Never use `$BASH_SOURCE[0]`, `${0}`, or "find my own directory" patterns
   in a script intended for piped execution — they are empty under `curl | bash`.
2. Embed every file the installer writes as a heredoc inside the script itself.

## Why this exists
Captured from `ai-logs/2026-02-26-open-source-release.md`. The original whygit
install script used `SCRIPT_DIR` via `BASH_SOURCE[0]` to locate source files
to copy. When piped from `curl | bash`, `BASH_SOURCE[0]` is empty so the script
failed immediately on the first copy.
```

**BAD draft (would be dropped):**

```markdown
# Shell script best practices

## When to apply
- Writing any shell script

## Guardrails
1. Be careful with path handling
2. Consider how users will invoke the script
3. Make sure to test edge cases

## Why this exists
Learned from past shell scripting mistakes.
```

This draft fails Check 1 (no concrete artefact), Check 2 (vague citation), Check 3 (three banned phrases), and Check 4 (any team could write this without reading the log). Dropped.

## Phase 4 — Propose and write

Show the user a structured proposal in chat. Format:

```
/learn proposal — <N> changes from <M> logs, <K> drafts dropped (<reasons>)

NEW  .claude/skills/<id>.md
     Source: ai-logs/<date>-<slug>.md
     Trigger: <one-line summary from When to apply>

PATCH .claude/skills/<existing-id>.md
     Source: ai-logs/<date>-<slug>.md
     Adds guardrail: <one-line summary>

CONFLICT .claude/skills/.conflicts/<date>-<slug>.md
     Existing skill: <id> says "<quote>"
     Log <date> says "<quote>"
     Needs human review

Logs with no learnable failures (will be marked processed):
- ai-logs/<date>-<slug>.md — <one-line why: routine work, no wrong turns>
```

Then show **the full text of each NEW skill and each PATCH diff** so the user can read before approving. For CONFLICT files, show the full body too.

Then ask:

> Apply these changes? **[y/N/select]**

- `y` — apply everything below, commit, done.
- `N` — discard. Do not modify `.processed`. Do not commit. Tell the user "discarded, nothing written."
- `select` — ask the user which items (by number) to apply. Apply only those. Mark only their source logs as processed.

### Writing the changes (on `y` or `select`)

For each applied NEW skill:
1. Write `.claude/skills/<id>.md` using the Write tool.

For each applied PATCH:
1. Read the existing skill file.
2. Append the new guardrail as an additional numbered item in the `## Guardrails` section.
3. Append the source log to the frontmatter `sources:` list.
4. Update the frontmatter `updated:` field to today's date.
5. Write the modified file back.

For each CONFLICT:
1. Write `.claude/skills/.conflicts/<date>-<conflict-slug>.md` using the Write tool. Use this template:

```markdown
---
id: <date>-<conflict-slug>
created: <today's date YYYY-MM-DD>
source_log: ai-logs/<source log filename>
existing_skill: <id of the conflicting skill>
status: unresolved
---

# Conflict: <short title>

## Existing skill says
> <quoted guardrail from the existing skill>

(from `.claude/skills/<existing-id>.md`, `Guardrails` section)

## Log <date> says
> <quoted failure description from the source log>

## Suggested resolutions
1. <option 1>
2. <option 2>
3. <option 3>

Resolve this by editing `.claude/skills/<existing-id>.md` and deleting this file.
```

### Updating `.processed`

After writing the applied changes, append to `.claude/skills/.processed`:
- Every log whose proposals were applied
- Every log that raised a conflict that was recorded
- Every log that contained no learnable failures (so it is not re-read next run)

Do **not** append logs whose proposals the user rejected during `select`. Those should remain unprocessed so they can be re-mined after the prompt is sharpened.

### Regenerate `.claude/skills/README.md` (best effort)

Write a simple index listing all `*.md` files in `.claude/skills/` (excluding `README.md` itself). For each, show the id, first `#` heading as title, created date, and source count. Sort by `updated` descending, falling back to `created`. If this step fails for any reason, continue — the README is decorative and skills still route correctly without it.

### Commit the learning

Stage all changes in `.claude/skills/`:

```
git add .claude/skills/
```

Commit with a message like:

```
learn: <one-line summary of what changed>

Sources:
- ai-logs/<file1>
- ai-logs/<file2>

<N conflicts flagged for review: .claude/skills/.conflicts/<files>>
```

Report to the user:
- The commit hash
- A list of the written files
- The drop count from Phase 3 (e.g. "2 drafts dropped: 1 too abstract, 1 banned phrases after rewrite")
- Any unresolved conflicts that need human review
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
