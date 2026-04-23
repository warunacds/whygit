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
