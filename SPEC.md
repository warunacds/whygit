# whygit — Spec

> Capture the *why* behind AI-assisted code changes, committed alongside the code itself.

---

## Problem

When Claude Code writes or refactors code, the reasoning behind those decisions lives only in the context window. Once the session ends, it's gone. Git records what changed — not why, not what alternatives were considered, not what prompts drove the direction. This creates a "provenance gap": code exists without its rationale.

---

## Solution

A lightweight, zero-dependency system that uses Claude Code's native slash command mechanism to capture curated AI decision logs as markdown files, committed alongside code changes into the repository.

No external services. No accounts. No cloud. Just files in git.

---

## Design Principles

- **Curated over comprehensive** — human-readable summaries, not raw transcripts
- **In-repo** — logs live with the code, not in a dashboard
- **Zero overhead** — one command at end of session, everything else is automatic
- **Portable** — works in any git repo, any team, any CI
- **Private by default** — nothing leaves your machine
- **Customizable** — all behaviour is defined in plain markdown files

---

## File Structure

```
your-repo/
├── CLAUDE.md                          # Persistent Claude Code instructions
├── .claude/
│   ├── commands/
│   │   ├── commit.md                  # /commit slash command
│   │   ├── log.md                     # /log slash command
│   │   ├── rewind.md                  # /rewind slash command
│   │   ├── learn.md                   # /learn slash command
│   │   └── skills.md                  # /skills slash command
│   └── skills/                        # Learned guardrails
│       ├── .processed                 # Mined-log ledger
│       ├── .conflicts/                # Unresolved contradictions
│       └── <skill-id>.md              # One file per active skill
├── ai-logs/
│   ├── .gitkeep                       # Ensures directory is tracked
│   ├── 2026-02-26-auth-refactor.md
│   ├── 2026-02-24-payment-webhooks.md
│   └── ...
└── install-whygit.sh                  # One-time setup script
```

---

## Commands

### `/commit`
**Primary command.** Logs the session reasoning and commits all staged changes.

Execution steps (in order):
1. Run `git diff --staged --stat` and `git status` to understand what changed
2. If nothing staged, run `git add -A` first
3. Generate an AI log file at `ai-logs/YYYY-MM-DD-<slug>.md`
4. Stage the log file with `git add ai-logs/`
5. Commit with a conventional commit message that references the log file path
6. Report the commit hash, log path, and one-line summary to the user

---

### `/log`
**Write log only, no commit.** Useful mid-session or when committing manually.

Execution steps:
1. Run `git diff HEAD` and `git status` for context
2. Generate the AI log file (same format as `/commit`)
3. Report the file path — does not stage or commit anything

---

### `/rewind`
**Browse AI decision history.** Accepts optional keyword or date argument.

Modes:
- `/rewind` — list all sessions newest first, with one-line summaries
- `/rewind <keyword>` — search logs by topic using grep, show matching files
- `/rewind <date>` — show all logs from a specific `YYYY-MM-DD`
- After showing results, offer to display full content of any specific log
- When showing a full log, also surface the associated git commit via `git log --oneline`

---

### `/learn`
**Mine `ai-logs/` for learnable failures.** Turns past wrong turns into concrete skills at `.claude/skills/`.

Modes:
- `/learn` — mine all unprocessed logs
- `/learn --log <path>` — re-mine a specific log, ignoring the processed ledger

Flow:
1. Read `.claude/skills/.processed` to find which logs have already been mined
2. Read unprocessed `ai-logs/*.md` in full
3. Attribute each log to one of: NEW (new skill), PATCH (amend existing skill), CONFLICT (contradicts existing skill)
4. Self-audit each draft for concreteness — drafts that are too generic are dropped
5. Propose all changes in chat and ask the user to approve (`y` / `N` / `select`)
6. On approval, write skill files, record processed logs, and commit

Every mutation to `.claude/skills/` is human-approved. `/learn` never writes silently.

---

### `/skills`
**List active skills and unresolved conflicts.** Read-only.

Prints a numbered list of every `*.md` file in `.claude/skills/` with id, title, created/updated dates, and source count. If `.claude/skills/.conflicts/` contains any files, prints a warning banner at the top.

No arguments in v1. Use `cat .claude/skills/<id>.md` to view a specific skill in full.

---

## Log File Format

Filename: `ai-logs/YYYY-MM-DD-<slug>.md`
- Date is session date
- Slug is 2–4 word kebab-case description of the work

```markdown
---
date: YYYY-MM-DD
model: claude-sonnet-4-6
session_summary: One line description of what this session accomplished
---

## What we built / changed
Specific description of what was implemented or modified, including file names
and key logic changes.

## Key decisions & reasoning
For each significant decision: what it was, why this approach, what tradeoff it involves.

## Alternatives considered
Approaches discussed or evaluated but not taken, and why they were rejected.

## Prompts that shaped direction
Paraphrased summary of the key user prompts that drove the most important decisions.

## Follow-up / known limitations
Anything left incomplete, known issues, or suggested next steps.
```

---

## Skill File Format

Filename: `.claude/skills/<id>.md`
- `id` is kebab-case, specific to the lesson (e.g. `curl-pipe-bash-self-contained`)

```markdown
---
id: <id>
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources:
  - ai-logs/<source log filename>
status: active
---

# <Skill title>

## When to apply
- Concrete triggers (file paths, function names, libraries, schema types)

## When NOT to apply
- Cases where the guardrail does not apply

## Guardrails
1. Specific rules tied to specific triggers

## Why this exists
Citation of the source log and a paraphrase of the original failure.
```

`.claude/skills/.processed` — plain text, one log filename per line, tracks which logs `/learn` has already mined.

`.claude/skills/.conflicts/<slug>.md` — markdown files recording cases where a new log contradicts an existing skill. Must be resolved by hand.

---

## Commit Message Format

```
<type>: <short description>

AI decision log: ai-logs/YYYY-MM-DD-<slug>.md

<2–3 sentence summary of what changed and the key reasoning>
```

Types follow conventional commits: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`

---

## CLAUDE.md Directives

The `CLAUDE.md` file instructs Claude Code to:
- Never delete or modify files in `ai-logs/`
- Proactively offer `/commit` at the end of significant work sessions
- Check `ai-logs/` first when asked "why did we do X" or "how did we decide Y"
- Read `.claude/skills/` using a two-pass load at the start of every session (scan triggers, then load matching bodies)

---

## Installation

```bash
# Clone or download the setup files, then run:
./install-whygit.sh /path/to/your/repo

# Or if installing into current directory:
./install-whygit.sh
```

The script:
- Creates `.claude/commands/` and `ai-logs/` directories
- Copies all three command files
- Merges or creates `CLAUDE.md` (safe to run on repos with existing `CLAUDE.md`)
- Prints next steps

After install:
```bash
git add . && git commit -m "chore: add AI decision logging"
```

---

## Usage in Claude Code

```
/commit              → log session reasoning + stage all + commit
/log                 → write log only, no commit
/rewind              → browse all sessions newest first
/rewind auth         → find sessions related to "auth"
/rewind 2026-02-26   → show all logs from that date
/learn               → mine ai-logs/ for reusable skills
/skills              → list active skills and conflicts
```

---

## Comparison to entire.io

| | This system | entire.io |
|---|---|---|
| Capture method | On-demand via `/commit` | Automatic, continuous |
| Content | Curated summary | Full transcript + tool calls |
| Storage | `ai-logs/` in main branch | Hidden `entire/checkpoints/v1` branch |
| Rewind | Browse markdown files | Non-destructive checkpoint restore |
| Dependencies | None | CLI install + account |
| Privacy | Fully local | Cloud dashboard |
| Team features | Shared via git | Web dashboard, PR integration |
| Customization | Edit markdown files | Config options |
| Cost | Free | TBD (seed-stage startup) |

**Philosophy:** entire.io captures everything automatically (observability). This system captures curated reasoning on demand (documentation). They are complementary — entire.io gives you the raw tape, this gives you the edited highlights.

---

## Non-Goals

- Not a replacement for good commit messages
- Not a full session transcript tool (see entire.io for that)
- Not a web dashboard or collaboration platform
- Not an AI commit message generator (the human/Claude writes the message)
- Not dependent on any external AI API call at commit time

---

## v2 Phase 1 — Concept-Triggered Retrieval

v2 adds a `UserPromptSubmit` hook (`.claude/hooks/concept_match.sh`) that injects matching skills into Claude's context mid-session, and grows a `concepts:` block in skill frontmatter to drive retrieval by domain vocabulary rather than only file/symbol names.

### New files

- `.claude/hooks/concept_match.sh` — reads JSON from stdin, matches prompt against every skill's aliases, emits matches wrapped in a `<whygit-memory>` block on stdout (up to 9k chars, with a truncation notice if more match).
- `.claude/commands/migrate-skills.md` — slash command that backfills `concepts:` on existing v1 skills with user approval.
- `.claude/settings.json` — registers the hook.

### Updated skill frontmatter

```yaml
concepts:
  - name: <kebab-case-name>
    aliases: ["<canonical>", "<alternate phrasing>"]
    anchors:
      - <file path>
```

Skills without `concepts:` continue to load via the existing two-pass CLAUDE.md scan. They simply don't fire via concept-triggered retrieval until migrated.

### Commands

| Command | What it does |
|---|---|
| `/migrate-skills` | Scans `.claude/skills/`, proposes `concepts:` blocks for pre-v2 skills, applies on approval. Idempotent. |

### Hook contract

`concept_match.sh` is registered against Claude Code's `UserPromptSubmit` event. The contract it implements:

**Input:** JSON on stdin, shaped:

```json
{
  "hook_event_name": "UserPromptSubmit",
  "prompt": "the user's prompt text"
}
```

The hook uses `jq` to extract `.prompt` when available, falling back to a `sed`-based extraction when `jq` is not installed.

**Output on match:** a single `<whygit-memory>` block on stdout:

```
<whygit-memory>
Relevant prior decisions from this codebase's memory:

### From <skill-filename>

<full skill file contents>

---

### From <next-matching-skill>

...

---
(N additional matching skills omitted — run /skills to browse)
</whygit-memory>
```

Claude Code injects this stdout into the turn's context. The truncation line only appears when the 9,000-character budget is reached; otherwise it is omitted.

**Output on no match or any error:** empty stdout.

**Exit code:** always 0. The hook never blocks the user. Missing skills directory, malformed JSON, unreadable skill files, and empty stdin all exit cleanly with empty output.

**Environment variables:**

| Variable | Purpose |
|---|---|
| `CLAUDE_PROJECT_DIR` | Root of the Claude Code project. Default `$PWD`. |
| `WHYGIT_SKIP_HOOKS` | Set to `1` to bypass matching (recursion safeguard for nested Claude invocations). |

**Output budget:** 9,000 characters of cumulative skill content, leaving 1,000 characters of headroom under Claude Code's 10,000-character stdout cap. When appending the next matching skill would exceed the budget, the hook stops, records the count of omitted skills, and appends a single-line notice (`(N additional matching skills omitted — run /skills to browse)`) before the closing tag.

**Matching algorithm:** case-insensitive substring match. The prompt is lowercased and whitespace-collapsed; each skill's aliases are likewise lowercased at parse time. If any alias is a substring of the normalized prompt, that skill matches. Matching is first-match-per-skill — aliases beyond the first hit are not evaluated. Skills without a `concepts:` block never match.

**Dependencies:** `bash`, `awk`, `sed`, `tr` (all POSIX-standard). `jq` improves JSON parsing reliability but is not required; installer warns when `jq` is missing but does not fail.

### Settings.json

The installer merges this entry into `.claude/settings.json` (creating the file if missing, preserving any existing hooks/permissions if present):

```json
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
```

Idempotency is verified by string-matching `bash .claude/hooks/concept_match.sh` in the existing file — if present, the merge is skipped. If absent and `jq` is available, the installer appends the new `UserPromptSubmit` entry via `jq`. If `jq` is missing, the installer prints the JSON fragment the user should paste manually.

### Deferred to later v2 cycles

- Automatic capture via Stop hook (`auto_capture.sh`)
- Automatic mining into drafts + `/review-skills` command
- Naming guardrail via PreToolUse hook

---

## Future Ideas

- `/rewind --diff <slug>` — show the git diff alongside the AI log
- `/compare <slug1> <slug2>` — compare reasoning across two sessions  
- GitHub Action to validate that every non-trivial commit has an associated AI log
- VS Code / Claude Code extension to auto-suggest `/commit` on session end detection
- Export to HTML for sharing outside the repo
