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
