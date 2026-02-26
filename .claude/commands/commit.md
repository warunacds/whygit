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
