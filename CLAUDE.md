# Claude Code Instructions

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
- Any session where "why did we do it this way" might be asked later

---

## Skills

This repo uses `.claude/skills/` to store concrete, repo-specific guardrails
learned from past sessions. Before starting work, use a two-pass load:

1. **Scan:** read each `.claude/skills/*.md` file's frontmatter and the
   `When to apply` / `When NOT to apply` sections only. Skip bodies.
2. **Match:** for each skill whose `When to apply` matches the current task
   (and none of the `When NOT to apply` cases apply), read the full file
   and apply the guardrails.

If a skill's guidance conflicts with an explicit user instruction, follow
the user but mention the conflict so it can be resolved with `/learn`.

If you encounter a situation where a skill *should* exist but doesn't — a
mistake that future sessions could avoid — note it clearly in the session
log so `/learn` can capture it later.

### Skill Commands
| Command | What it does |
|---------|-------------|
| `/learn` | Mine unprocessed `ai-logs/` for learnable failures, propose skill changes |
| `/learn --log <path>` | Re-mine one specific log, ignoring the processed ledger |
| `/skills` | List current skills and any unresolved conflicts |
