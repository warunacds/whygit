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
