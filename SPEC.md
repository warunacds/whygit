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
│   └── commands/
│       ├── commit.md                  # /commit slash command
│       ├── log.md                     # /log slash command
│       └── rewind.md                  # /rewind slash command
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

## Future Ideas

- `/rewind --diff <slug>` — show the git diff alongside the AI log
- `/compare <slug1> <slug2>` — compare reasoning across two sessions  
- GitHub Action to validate that every non-trivial commit has an associated AI log
- VS Code / Claude Code extension to auto-suggest `/commit` on session end detection
- Export to HTML for sharing outside the repo
