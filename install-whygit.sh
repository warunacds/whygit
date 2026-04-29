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
mkdir -p -- "$TARGET/.claude/hooks"
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

# --- FILE: .claude/commands/skills.md ---
cat > "$TARGET/.claude/commands/skills.md" << 'HEREDOC'
# /skills — List Active Skills + Unresolved Conflicts

Read-only browser for `.claude/skills/`. Shows every active skill with a one-line summary, plus a warning banner at the top if there are any unresolved conflicts that need human review.

## Usage

`/skills` — list all active skills and surface any unresolved conflicts.

(No other modes in v1. Use `cat .claude/skills/<id>.md` to view a specific skill in full.)

## Step 0: Validate environment

If `.claude/skills/` does not exist, tell the user:

> `.claude/skills/` not found. Re-run `install-whygit.sh` in this repo to upgrade whygit with the skills feature.

And stop.

## Step 1: Count unresolved conflicts

Count files matching `.claude/skills/.conflicts/*.md` (ignore `.gitkeep` and any hidden files).

If the count is non-zero, print this banner **first**, before the skill list:

```
.claude/skills/ — <total> active skills
⚠️  <N> unresolved conflict(s) in .claude/skills/.conflicts/ — review needed
```

If zero, print only the top line:

```
.claude/skills/ — <total> active skills
```

If there are no skill files at all, print:

```
.claude/skills/ — no skills yet
Run /learn to mine ai-logs/ for learnable failures.
```

And stop.

## Step 2: List active skills

List all `*.md` files in `.claude/skills/` except `README.md`. For each file:

1. Read the frontmatter: `id`, `created`, `updated`, `sources` (count the list length).
2. Read the first `#` heading after the frontmatter — that's the display title.
3. Skip the file if the frontmatter is missing or malformed (warn the user with "skipped <filename>: malformed frontmatter" and continue).

Sort by `updated` descending. If `updated` is missing, fall back to `created`.

Print as a numbered list:

```
1. <id>
   <title>
   Created <created> · <source count> source(s)<if updated: · updated <updated>>
   → .claude/skills/<filename>

2. ...
```

## Step 3: If there are unresolved conflicts, show them briefly

After the skill list, if there were any conflicts, print a `## Conflicts` section listing each one with its filename and its top-level `# Conflict: <title>` heading, plus a one-liner reminder:

```
## Conflicts needing review

1. .claude/skills/.conflicts/<file>.md
   Conflict: <title>

Resolve conflicts by editing the affected skill and deleting the conflict file.
```

Nothing mutates in this command. It is read-only.
HEREDOC

# --- FILE: .claude/commands/migrate-skills.md ---
cat > "$TARGET/.claude/commands/migrate-skills.md" << 'HEREDOC'
# /migrate-skills — Backfill concepts block on existing v1 skills

Backfill v2 `concepts:` frontmatter on skill files that were authored before v2. Reads each skill plus its source logs, extracts domain concepts with aliases and anchors, and proposes the additions for batch approval. No nested Claude invocation — everything runs in this session.

## Usage

- `/migrate-skills` — scan all skills, propose migrations for those missing `concepts:`.

## Step 0: Validate environment

If `.claude/skills/` does not exist, tell the user:

> `.claude/skills/` not found. Re-run `install-whygit.sh` to install whygit.

And stop.

## Phase 1 — Discover

1. List every `*.md` in `.claude/skills/` (top level only; skip `.drafts/` and `.conflicts/`).
2. Read the frontmatter of each and exclude any file that already contains a `concepts:` key.
3. Stop with "No skills to migrate — Phase 1 ready" if the candidate list is empty.

## Phase 2 — Extract

For each candidate skill:

1. Read the full skill file.
2. For each log in the skill's `sources:` list, read the log file. If a log is missing, note it.
3. Extract concepts using these rules:

### What counts as a concept

- Domain terminology the team uses in conversation.
- Architectural patterns specific to this codebase.
- Problem categories.
- Feature areas.

### What does NOT count

- File paths.
- Class or method names.
- Generic programming terms (refactor, bug fix, performance).
- Library or framework names without domain binding.

Rule of thumb: a concept survives renaming its implementation.

For each concept, produce:
- `name`: kebab-case identifier
- `aliases`: 2–4 alternate phrasings a developer or LLM might use. Always include the canonical name.
- `anchors`: 1–3 file paths that implement the concept

### Self-audit

For each concept:
- Would two engineers on this codebase agree on the meaning?
- Are aliases genuinely different phrasings, or just grammatical variants? Reject duplicates.
- Is the concept already covered by another skill in this migration batch? If so, note the overlap to the user but still propose — the hook dedupes by skill file, not by concept.

## Phase 3 — Propose

Print a batch proposal in chat. For each candidate:

```
MIGRATE .claude/skills/<id>.md
  Sources: ai-logs/<file1>[, ai-logs/<file2>]
  Proposed concepts:
    - name: <name>
      aliases: ["<alias1>", "<alias2>"]
      anchors:
        - <anchor>
  Rationale: <one-line grounding in the source log>
```

If any candidate has missing source logs, surface them explicitly:

```
  ⚠️  Missing logs: ai-logs/<missing.md>. Extraction used skill content only.
```

Then ask:

> Apply these migrations? **[y / N / select]**

- `y` — apply everything below.
- `N` — abort. Tell the user "discarded, nothing written."
- `select` — ask which items (by number) to apply. Apply only those.

## Phase 4 — Apply

For each approved migration, edit the skill file with the `Edit` tool:

1. Locate the frontmatter closing delimiter (the second `---`).
2. Insert the `concepts:` block immediately before it.
3. Update the `updated:` line to today's date.
4. Preserve the order and content of all other frontmatter keys.

Do **not** rewrite the whole file — targeted edits only. This avoids accidental body corruption.

## Phase 5 — Commit

Stage `.claude/skills/` and commit:

```
learn: backfill concepts on <N> existing skills

Migrated:
- .claude/skills/<id1>.md
- .claude/skills/<id2>.md
```

Report to the user:
- Commit hash
- List of migrated files
- Any candidates that were skipped and why (missing sources, user declined)

## Failure modes

- If the `Edit` fails because the expected frontmatter closing delimiter isn't unique in the file, fall back to reading + rewriting that one skill, with a warning printed to the user.
- If all migrations fail, roll back via `git restore .claude/skills/` and tell the user.
HEREDOC

# --- FILE: .claude/hooks/concept_match.sh ---
cat > "$TARGET/.claude/hooks/concept_match.sh" << 'HEREDOC'
#!/usr/bin/env bash
# whygit v2 concept-match hook for UserPromptSubmit.
# Reads JSON on stdin, emits matching skills wrapped in <whygit-memory> on stdout.
# Must never exit non-zero; hook failures must never block the user.

set -u

if [[ "${WHYGIT_SKIP_HOOKS:-0}" == "1" ]]; then
  exit 0
fi

SKILLS_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills"
[[ -d "$SKILLS_DIR" ]] || exit 0

MAX_BYTES=9000

STDIN="$(cat 2>/dev/null || true)"
[[ -z "$STDIN" ]] && exit 0

if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$STDIN" | jq -r '.prompt // empty' 2>/dev/null || true)"
else
  PROMPT="$(printf '%s' "$STDIN" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | head -1)"
fi
[[ -z "$PROMPT" ]] && exit 0

PROMPT_NORM="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')"

buffer=""
emitted=0
omitted=0

shopt -s nullglob
for skill in "$SKILLS_DIR"/*.md; do
  [[ -f "$skill" ]] || continue

  aliases="$(awk '
    BEGIN { fm = 0; in_concepts = 0 }
    /^---[[:space:]]*$/ { fm = !fm; next }
    !fm { next }
    /^concepts:/ { in_concepts = 1; next }
    in_concepts && /^[[:space:]]+aliases:/ {
      line = $0
      while (match(line, /"[^"]+"/)) {
        print tolower(substr(line, RSTART+1, RLENGTH-2))
        line = substr(line, RSTART+RLENGTH)
      }
      next
    }
    in_concepts && /^[a-zA-Z_]+:/ { in_concepts = 0 }
  ' "$skill" 2>/dev/null)" || aliases=""

  [[ -z "$aliases" ]] && continue

  matched=0
  while IFS= read -r alias; do
    [[ -z "$alias" ]] && continue
    if [[ "$PROMPT_NORM" == *"$alias"* ]]; then
      matched=1
      break
    fi
  done <<< "$aliases"
  (( matched == 0 )) && continue

  content="$(cat "$skill" 2>/dev/null || true)"
  section="### From $(basename "$skill")"$'\n\n'"$content"$'\n\n---\n\n'

  wrapper_size=120
  candidate_size=$(( ${#buffer} + ${#section} + wrapper_size ))
  if (( candidate_size > MAX_BYTES )); then
    omitted=$((omitted + 1))
    continue
  fi
  buffer="${buffer}${section}"
  emitted=$((emitted + 1))
done

if (( emitted > 0 )); then
  printf '<whygit-memory>\n'
  printf "Relevant prior decisions from this codebase's memory:\n\n"
  printf '%s' "$buffer"
  if (( omitted > 0 )); then
    printf '(%d additional matching skills omitted — run /skills to browse)\n' "$omitted"
  fi
  printf '</whygit-memory>\n'
fi

exit 0
HEREDOC
chmod +x "$TARGET/.claude/hooks/concept_match.sh"

# --- FILE: .claude/skills/.processed (empty ledger) ---
touch "$TARGET/.claude/skills/.processed"

# --- FILE: .claude/skills/.conflicts/.gitkeep ---
touch "$TARGET/.claude/skills/.conflicts/.gitkeep"

# --- FILE: .claude/skills/curl-pipe-bash-self-contained.md ---
# Only write the example skill if .claude/skills/ has no existing *.md files,
# so we never clobber user-authored or previously-learned skills.
if ! ls "$TARGET/.claude/skills/"*.md > /dev/null 2>&1; then
cat > "$TARGET/.claude/skills/curl-pipe-bash-self-contained.md" << 'HEREDOC'
---
id: curl-pipe-bash-self-contained
created: 2026-04-09
updated: 2026-04-23
sources:
  - ai-logs/2026-02-26-open-source-release.md
  - ai-logs/2026-02-26-install-script-security-fixes.md
status: active
concepts:
  - name: piped-installer
    aliases: ["piped installer", "install script", "installer", "curl pipe bash"]
    anchors:
      - install-whygit.sh
---

# Install scripts piped from curl must be self-contained

## When to apply

- Writing a shell script users will run via `curl -fsSL ... | bash`
- Any installer that copies or references files relative to itself
- Changing an existing installer to support piped execution
- Adding new files that need to ship with an existing piped installer

## When NOT to apply

- Scripts only ever run locally after `git clone`
- Scripts the user has already downloaded and invokes by path
- Scripts whose only job is to `curl` a second payload (those can assume network)

## Guardrails

1. Never use `$BASH_SOURCE[0]`, `${0}`, or any "find my own directory" pattern
   in a script intended for piped execution. Under `curl | bash`, `$BASH_SOURCE[0]`
   is empty so the script fails immediately on the first file operation.
2. Embed every file the installer needs to write as a heredoc (`cat > "$TARGET/path" << 'HERE_DOC' ... HERE_DOC`) directly inside the installer. The script must carry its own payload — no reliance on files in a sibling directory.
3. Use quoted `'HERE_DOC'` (with single quotes) for embedded file contents so shell variables and backticks inside the content are not expanded at install time.
4. Before shipping a change to a piped installer, mentally trace execution with
   `$BASH_SOURCE[0]` set to empty string and confirm every path still resolves.
5. Register any `trap '...' ERR` **after** input validation, not before. Otherwise
   users who pass a bad target see both a clear validation error and a spurious
   "partially installed" warning from the trap.
6. Use `cp --` and `mkdir --` (with the `--` flag) so target paths starting with
   `-` are not misinterpreted as flags.
7. Make CLAUDE.md / config appends idempotent by grepping for a known marker
   string before writing. Re-running the installer must not duplicate blocks.

## Why this exists

Captured from `ai-logs/2026-02-26-open-source-release.md` and
`ai-logs/2026-02-26-install-script-security-fixes.md`.

The original whygit install script used `SCRIPT_DIR` via `BASH_SOURCE[0]` to
locate source files to copy. When a user ran the one-liner
`curl -fsSL .../install-whygit.sh | bash`, `$BASH_SOURCE[0]` was empty, so
`SCRIPT_DIR` resolved to nothing, and the very first `cp` call failed. The
distribution story — "one command, zero dependencies" — was broken.

The fix was to embed every file's contents as heredocs directly inside the
installer and drop the `SCRIPT_DIR` pattern entirely. A follow-up security
pass added input validation, the `trap` repositioning, `cp --` flags, and the
idempotent CLAUDE.md merge. This skill exists so the next person adding a
feature to the installer doesn't re-introduce any of those failure modes.
HEREDOC
  echo "✨ Installed example skill: .claude/skills/curl-pipe-bash-self-contained.md"
else
  echo "ℹ️  .claude/skills/ already has skills — skipping example skill"
fi

# --- FILE: ai-logs/.gitkeep ---
touch "$TARGET/ai-logs/.gitkeep"

# --- FILE: .claude/settings.json (merge idempotently) ---
HOOK_CMD='bash .claude/hooks/concept_match.sh'
SETTINGS="$TARGET/.claude/settings.json"

if [ -f "$SETTINGS" ]; then
  if grep -qF "$HOOK_CMD" "$SETTINGS"; then
    echo "ℹ️  .claude/settings.json already registers concept_match.sh — skipping"
  else
    if command -v jq >/dev/null 2>&1; then
      tmp="$(mktemp)"
      jq --arg cmd "$HOOK_CMD" '
        .hooks //= {} |
        .hooks.UserPromptSubmit //= [] |
        .hooks.UserPromptSubmit += [
          { "matcher": "*", "hooks": [ { "type": "command", "command": $cmd } ] }
        ]
      ' "$SETTINGS" > "$tmp" && mv -- "$tmp" "$SETTINGS"
      echo "✨ Merged UserPromptSubmit hook into .claude/settings.json"
    else
      echo "⚠️  jq not installed — add this to .claude/settings.json manually:"
      echo '    "hooks": { "UserPromptSubmit": [ { "matcher": "*", "hooks": [ { "type": "command", "command": "bash .claude/hooks/concept_match.sh" } ] } ] }'
    fi
  fi
else
  cat > "$SETTINGS" << 'SETTINGS_EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/concept_match.sh" }
        ]
      }
    ]
  }
}
SETTINGS_EOF
  echo "✨ Created .claude/settings.json with concept_match hook"
fi

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

SKILLS_BLOCK='## Skills

This repo uses `.claude/skills/` to store concrete, repo-specific guardrails
learned from past sessions. Before starting work, use a two-pass load:

1. **Scan:** read each `.claude/skills/*.md` file'"'"'s frontmatter and the
   `When to apply` / `When NOT to apply` sections only. Skip bodies.
2. **Match:** for each skill whose `When to apply` matches the current task
   (and none of the `When NOT to apply` cases apply), read the full file
   and apply the guardrails.

If a skill'"'"'s guidance conflicts with an explicit user instruction, follow
the user but mention the conflict so it can be resolved with `/learn`.

If you encounter a situation where a skill *should* exist but doesn'"'"'t — a
mistake that future sessions could avoid — note it clearly in the session
log so `/learn` can capture it later.

### Skill Commands
| Command | What it does |
|---------|-------------|
| `/learn` | Mine unprocessed `ai-logs/` for learnable failures, propose skill changes |
| `/learn --log <path>` | Re-mine one specific log, ignoring the processed ledger |
| `/skills` | List current skills and any unresolved conflicts |
| `/migrate-skills` | Backfill v2 `concepts:` block on pre-v2 skills (one-shot) |'

if [ -f "$TARGET/CLAUDE.md" ]; then
  if grep -qF "AI Decision Logging" "$TARGET/CLAUDE.md"; then
    echo "ℹ️  CLAUDE.md already contains whygit AI Decision Logging block — skipping"
  else
    printf '\n---\n%s\n' "$CLAUDE_BLOCK" >> "$TARGET/CLAUDE.md"
    echo "⚠️  Appended AI Decision Logging block to existing CLAUDE.md — review for duplicates"
  fi

  if grep -qF "This repo uses \`.claude/skills/\`" "$TARGET/CLAUDE.md"; then
    echo "ℹ️  CLAUDE.md already contains whygit Skills block — skipping"
  else
    printf '\n---\n%s\n' "$SKILLS_BLOCK" >> "$TARGET/CLAUDE.md"
    echo "⚠️  Appended Skills block to existing CLAUDE.md — review for duplicates"
  fi
else
  printf '%s\n\n---\n%s\n' "$CLAUDE_BLOCK" "$SKILLS_BLOCK" > "$TARGET/CLAUDE.md"
fi

echo ""
echo "✅ Done! whygit installed:"
echo "   $TARGET/CLAUDE.md"
echo "   $TARGET/.claude/commands/commit.md"
echo "   $TARGET/.claude/commands/log.md"
echo "   $TARGET/.claude/commands/rewind.md"
echo "   $TARGET/.claude/commands/learn.md"
echo "   $TARGET/.claude/commands/skills.md"
echo "   $TARGET/.claude/commands/migrate-skills.md"
echo "   $TARGET/.claude/hooks/concept_match.sh"
echo "   $TARGET/.claude/settings.json"
echo "   $TARGET/.claude/skills/"
echo "   $TARGET/ai-logs/.gitkeep"
echo ""
echo "📝 Next: git add . && git commit -m 'chore: add whygit (AI decision logs + skills)'"
echo ""
echo "🚀 In Claude Code, use:"
echo "   /commit         → log + commit"
echo "   /log            → log only"
echo "   /rewind         → browse history"
echo "   /rewind <topic> → search history"
echo "   /learn          → mine logs for reusable skills"
echo "   /skills         → list current skills and conflicts"
echo "   /migrate-skills → backfill concepts on pre-v2 skills"
