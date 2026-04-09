---
date: 2026-04-09
model: claude-opus-4-6
session_summary: Designed and shipped /learn and /skills — whygit's continual learning loop
---

## What we built / changed

Added `/learn` and `/skills` slash commands to whygit, closing the
read-write reflective learning loop. whygit already handled the *write* side
(sessions → `/commit` → `ai-logs/`). `/learn` adds the *read* side: mine
accumulated `ai-logs/` for learnable failures, produce concrete guardrails,
store them as markdown in `.claude/skills/`.

**New files:**
- `.claude/commands/learn.md` — 255-line command body with Phase 1–4
  workflow (Gather, Attribute, Self-audit, Propose-and-write), few-shot
  examples, and the CONFLICT/PATCH/NEW classification logic
- `.claude/commands/skills.md` — read-only browser with a conflicts banner
  at the top
- `.claude/skills/curl-pipe-bash-self-contained.md` — real example skill
  mined from the two existing ai-logs (open-source-release +
  install-script-security-fixes). Eats whygit's own dog food.
- `.claude/skills/.processed` — empty ledger file for tracking which logs
  have been mined
- `.claude/skills/.conflicts/.gitkeep` — scaffolding for the unresolved
  contradictions directory

**Files modified:**
- `CLAUDE.md` — appended `## Skills` section with explicit two-pass routing
  instruction (scan frontmatter + triggers → selectively load matching
  bodies)
- `README.md` — added `/learn` and `/skills` to usage, updated file tree,
  added a new "Learning loop" explainer paragraph
- `SPEC.md` — full `/learn` + `/skills` sections, new "Skill File Format"
  section, updated directives / usage / file structure
- `install-whygit.sh` — grew from ~300 to ~650 lines. Four new heredocs
  (`learn.md`, `skills.md`, the example skill), new `mkdir` for
  `.claude/skills/.conflicts`, new `SKILLS_BLOCK` variable with a dual
  idempotency guard (AI Decision Logging + Skills blocks append
  independently), an `ls *.md`-guarded write for the example skill so
  user-authored skills never get clobbered, and updated success message.

**Design and plan docs (gitignored under `docs/plans/`):**
- `docs/plans/2026-04-09-learn-command-design.md` — the validated design
- `docs/plans/2026-04-09-learn-command.md` — the implementation plan with
  17 tasks

## Key decisions & reasoning

**Utility tracking deferred to Phase 2 (Question 1).** The spec originally
proposed Option B — infer utility scores by mining logs for mentions of
skill ids. The problem: skills that work best *prevent* the failures that
would get logged, so log-mining systematically undercounts successes and
utility scores drift toward zero for the best skills. Shipping a fake
signal in v1 would make quality regressions harder to diagnose. Decision:
no counters, no scores, no `/skills prune` in v1 at all. v1 frontmatter
still includes `status: active` so Phase 2 can add `quarantined` without a
migration.

**`.processed` ledger at `.claude/skills/.processed` (Question 2).**
Alternative was modifying `ai-logs/` with a footer or frontmatter marker,
but that violates the immutability rule that's the first bullet in
whygit's existing CLAUDE.md. Plain-text ledger keeps `ai-logs/` immutable,
stays cheap (no bookkeeping daemon), committed to git like everything
else, and makes `/learn` reproducible — delete the ledger to force a full
re-mine after sharpening the prompt.

**Conflicts get their own directory, not chat-only (Question 3).**
`.claude/skills/.conflicts/<slug>.md` — one markdown file per unresolved
contradiction, committed to git, surfaced by `/skills`. Chat-only would
silently drop conflicts if the user doesn't act in the moment, and once
the raising log is in `.processed` the conflict is gone forever.
Quarantining the whole conflicting skill was rejected as too aggressive —
most conflicts are refinements, not contradictions.

**Example skill ships real, not a template (Question 4).** Mined from
whygit's own `ai-logs/2026-02-26-open-source-release.md` and
`ai-logs/2026-02-26-install-script-security-fixes.md`. The skill is about
`curl | bash` installer self-containment — genuinely the lesson whygit
learned the hard way when the original SCRIPT_DIR-based installer broke
under piped execution. Three reasons: (1) it's the best possible
pre-flight test of the `/learn` prompt's quality bar — if you can't
produce a crisp concrete skill from this log, the prompt isn't sharp
enough; (2) it doubles as documentation, showing new users what "good"
looks like in situ; (3) it's meta-honest — whygit's whole pitch is
"capture the why," so shipping a skill learned from its own why is the
purest demonstration of the loop closing.

**`/skills` is read-only in v1 (Question 5).** Dropping utility scores
removed half the command's original purpose, but the conflicts banner at
the top is load-bearing — without it, files in `.claude/skills/.conflicts/`
rot silently because nothing surfaces them. So v1 ships a minimal
read-only lister with id, title, created/updated, source count, plus a
big warning banner when conflicts exist. No `/skills <id>` browser
(`cat .claude/skills/<id>.md` works), no `/skills prune` (Phase 2).

**CLAUDE.md uses explicit two-pass routing (Question 6).** "Read all skill
frontmatter + `When to apply` sections, then read full bodies only for
matches." This tells Claude exactly how to route rather than leaving it
implicit. README.md inside `.claude/skills/` becomes decorative
(auto-regenerated as best-effort by `/learn`) rather than load-bearing;
if regeneration fails, routing still works because Claude reads skill
files directly. Lazy "check when relevant" routing was rejected — fails
silently when Claude doesn't notice, which defeats the entire point.

**Single idempotent installer, not a second `install-learn.sh`
(Question 7).** The existing `install-whygit.sh` is already idempotent for
the CLAUDE.md merge via a `grep -qF` marker. Extended the pattern with a
second marker (`"This repo uses \`.claude/skills/\`"`) so the Skills block
appends independently of the AI Decision Logging block — existing users
get the new feature on re-run without touching anything else. The example
skill is guarded by `ls *.md > /dev/null 2>&1` so it's only written if
`.claude/skills/` is empty, protecting user-authored or previously-learned
skills.

**Self-audit quality gate inside the `/learn` prompt (Question 8).** The
spec's biggest warned-about failure mode is abstract, generic skills
("be careful with state management" vs "never call setState inside
useEffect without a dependency check"). v1 ships four mechanical checks
enforced inside the `/learn` prompt between drafting and proposal:
(1) specificity — `When to apply` must name concrete artefacts;
(2) citation — `Why this exists` must quote the source log;
(3) banned phrases — reject guardrails containing "be careful with",
"think about", "consider", "make sure to", "in general", "as a rule of
thumb", "best practice", "keep in mind", "be aware"; (4) deletability —
if a new-team dev could write it without reading the log, drop it.
Drafts that fail a check get one rewrite attempt, then are dropped
silently. Few-shot examples (one GOOD, one BAD) are embedded in the
prompt to anchor the bar.

**HEREDOC naming inside the example skill.** The skill's guardrails 2 and
3 reference embedded heredocs (`cat > ... << 'HEREDOC'`). When this skill
was embedded inside the installer's own outer heredoc, a literal bare
`HEREDOC` on its own line would have closed the outer delimiter early.
Fixed by renaming the in-skill references to `HERE_DOC` (with underscore),
applied consistently in both the source file and the installer embed so
they don't drift.

**Distribution of design/plan docs.** Put both the design doc and the
implementation plan under `docs/plans/` — which is gitignored in the
public repo per the earlier decision from the open-source-release
session. These are internal scaffolding, not public documentation.
whygit itself is the public artefact; the planning trail stays local.

## Alternatives considered

- **Option A utility tracking (manual confirmation during `/commit`).**
  Adds friction to the core command for a signal we don't yet know is
  needed. Deferred along with Option B to Phase 2, at which point we can
  pick whichever proves workable.

- **Footer or frontmatter markers in `ai-logs/`** for the processed
  ledger. Would have required relaxing the immutability rule. Rejected.

- **`--since 7d` flag on `/learn`.** Duplicates what `.processed`
  already does for the normal case ("mine what I haven't mined yet").
  Deferred to Phase 3.

- **Shipping an empty `.claude/skills/`** or a template-only file. Less
  pedagogical, doesn't test the `/learn` prompt's quality bar before
  release. Rejected in favor of the real example.

- **Concreteness grades shown to the user next to each proposed skill.**
  Redundant if the self-audit works, and inviting a user override weakens
  the bar. Rejected — self-audit drops failures silently.

- **Separate `install-learn.sh` as a second installer.** Doubles the
  surface area and makes existing whygit users do work to get the new
  feature. Rejected in favor of upgrading the main installer.

- **Worktree-based development** per the executing-plans skill default.
  User explicitly said "dont ask me so many questions" and wanted direct
  implementation; the project is small markdown-only with low blast
  radius. Ran on main with frequent commits instead.

## Prompts that shaped direction

- Initial request was the full SPEC-LEARN.md pasted into the conversation,
  with the ask framed as "turn this spec into a design, then plan, then
  implementation" — i.e., not to invent from scratch but to pressure-test
  the spec's assumptions and ship Phase 1 of it.
- User chose Option B on the utility-tracking question without needing
  convincing, confirming the "defer entirely" bias was right.
- User consistently picked the recommended option (B or C) on questions
  2–7, suggesting the reasoning was well-calibrated rather than
  sandbagging. Question 8 also accepted Option B (self-audit + few-shot).
- Midway through the design presentation walkthrough, user said "write
  the plan and implement please dont ask me so many questions." Took this
  as durable instruction for the remainder of the session: stop asking
  section-by-section approvals, skip the worktree default, write the
  design doc, write the plan, execute inline.
- User approved each design section ("yeah" / "looks good" / "yes") up
  to that point, so the pressure to accelerate wasn't pushback on the
  direction — just a request to stop adding friction once alignment
  existed.

## Follow-up / known limitations

- **`/learn` has not been executed end-to-end yet.** Task 16 was a
  paper-walkthrough of the prompt against the two existing logs, not an
  actual live run. When the next real session closes and someone runs
  `/learn`, we'll see whether the self-audit phase behaves as intended.
  The first live run is the real test — a draft that looks substantively
  equivalent to the shipped example would validate the prompt. A draft
  that's more abstract means sharpening the banned-phrase list or
  tightening the specificity check.
- **Phase 2 work queued:** utility tracking (pick between Option A and
  Option B once there are real skills to measure), `/skills prune`, the
  quarantine workflow.
- **Phase 3 work queued:** `--since <duration>` flag on `/learn`, an
  interactive conflict resolution UI (currently conflicts are just files
  to be edited by hand), optional manual confirmation of skill utility
  during `/commit`.
- **The `/skills` output shows `updated YYYY-MM-DD` even when created
  == updated**, which is cosmetic noise. Minor UX polish, not worth a
  patch until there's a real session where it matters.
- **`.claude/skills/README.md` regeneration is specified as best-effort
  inside the `/learn` prompt, but has no test.** The first live run will
  either produce it or fail silently — if the README becomes useful,
  promote it to required; if nobody notices it's missing, drop the
  regeneration step.
- **11 commits are ahead of origin/main.** Not pushed. User can push when
  ready.
