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
