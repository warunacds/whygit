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

## Phase 3.5 — Concept extraction

For every NEW or PATCH draft that survived Phase 3, extract a `concepts:` block that will be added to the skill's frontmatter. Concepts drive v2's just-in-time retrieval: when a future user prompt contains any alias, this skill is injected into the turn's context.

### Definitions

- **Concept:** a domain-level noun phrase a developer on this codebase would use in conversation.
- **Alias:** an alternate phrasing of the concept. 2–4 per concept. The canonical name is always in the alias list.
- **Anchor:** a file path that implements or embodies the concept. 1–3 per concept.

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

Rule of thumb: a concept survives renaming its implementation. An implementation class name is not a concept — the domain phrase the team uses for that class's responsibility is.

### Self-audit (before including)

For each concept:
- Would two engineers on this codebase agree on the meaning? If no, drop.
- Is this concept already in an existing skill? If so, the draft should have been a PATCH — revisit the attribution.
- Are aliases genuinely different phrasings, or just grammatical variants (plural vs singular, -ing vs -ed)? Reject near-duplicates.

Add the extracted concepts to the draft's frontmatter under a `concepts:` key before including it in the Phase 4 proposal. The user sees and approves concepts as part of the skill — no separate gate.

### Skill frontmatter shape

```yaml
---
id: <id>
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources:
  - ai-logs/<source log filename>
status: active
concepts:
  - name: <concept-name>
    aliases: ["<canonical name>", "<alternate phrasing>"]
    anchors:
      - <file path>
---
```

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
