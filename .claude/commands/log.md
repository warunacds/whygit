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
