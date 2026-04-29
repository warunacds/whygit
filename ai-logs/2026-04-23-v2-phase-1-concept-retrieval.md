---
date: 2026-04-23
model: claude-opus-4-7
session_summary: Shipped whygit v2 Phase 1 — concept-triggered retrieval via UserPromptSubmit hook
---

## What we built / changed

Added three new artefacts to whygit, closing the v1 "session-scoped retrieval" gap:

- `.claude/hooks/concept_match.sh` — bash hook registered against `UserPromptSubmit`. Reads the prompt from stdin JSON, scans every `*.md` in `.claude/skills/` top-level, parses each file's `concepts.aliases` from frontmatter via awk, and case-insensitively substring-matches each alias against the normalized prompt. On match, the full skill file is emitted inside a `<whygit-memory>` block on stdout — Claude Code injects that stdout into the turn's context. Output is budget-constrained to 9k chars (leaving 1k headroom under Claude Code's 10k stdout cap), with a truncation notice when more skills match than fit.
- `.claude/commands/migrate-skills.md` — slash command that backfills the `concepts:` frontmatter block on v1 skills in-session (no nested `claude -p`, no drafts directory). Uses the same propose-approve-commit pattern as `/learn`.
- `.claude/settings.json` — registers the hook on `UserPromptSubmit` with matcher `"*"`.

Updated:
- `.claude/commands/learn.md` gained a new Phase 3.5 "Concept extraction" that grows a `concepts:` block on every NEW or PATCH draft.
- `.claude/skills/curl-pipe-bash-self-contained.md` (the repo's own dogfood skill) gained a `concepts:` block with aliases `["piped installer", "install script", "installer", "curl pipe bash"]`.
- `install-whygit.sh` embeds all v2 artefacts as heredocs, creates `.claude/hooks/`, and merges `.claude/settings.json` idempotently (jq preferred; warning fallback if jq is missing).
- `SPEC.md`, `README.md`, `CLAUDE.md` all document the new `/migrate-skills` command and the v2 retrieval model.

Testing: 9 shell integration tests under `tests/phase1/` cover happy path, no-match, case-insensitive match, v1-skill exclusion, WHYGIT_SKIP_HOOKS env bypass, budget truncation, non-failure on bad inputs, 100-skill performance guard, and installer idempotency. All green.

## Key decisions & reasoning

**Phase 1 scope was deliberately narrowed from the full v2 spec** to three components: concept extraction, concept_match.sh, and /migrate-skills. The v2 spec also covers auto-capture, auto-mine, review-skills, and naming-guard — those are deferred to separate future cycles. Reasoning: concept extraction alone is useless without retrieval, and retrieval without migration leaves existing users with silently-degraded behaviour. Those three form the smallest coherent shippable slice. Auto-capture + auto-mine are a separate loop (the *writing* side of v2) and naming-guard is both the trickiest and the one most in need of feedback on the retrieval slice before it's built.

**Hook contract was verified against Anthropic docs before writing any code** via a claude-code-guide subagent. Key findings: UserPromptSubmit input is stdin JSON (not env vars), plain stdout is injected into context (no envelope required), there's a 10k-char output cap, matcher `"*"` matches all, regex and pipe syntaxes are supported. One divergence from the v2 spec: stdin is JSON, not raw text, so the parser uses `jq` when available with a `sed`-based fallback.

**Chose in-session `/migrate-skills` over a shell script with nested `claude -p`.** The v2 spec suggested `scripts/migrate-v1-skills.sh` calling `claude -p` per skill and writing drafts to `.claude/skills/.drafts/`. Rejected in favor of a slash command that proposes migrations inline with `[y / N / select]`. Reasoning: nested-Claude from a shell script has recursion risks and environment-propagation fragility, and the drafts directory would have dragged in half of the deferred `/review-skills` component (Component 2 in the spec). The slash command is simpler, reuses the `/learn` UX pattern, and keeps the whole interaction in a context window where detail is cheap.

**Stayed with 9k char output budget and hard-stop truncation.** Alternatives considered: emit summary-only per skill (halves size, loses grounding), rank by match strength and cap at top-5 (invents a ranking system we don't have evidence we need), ignore the cap entirely (silent correctness bug). 9k budget with a truncation notice preserves the happy path for typical repos while degrading gracefully and visibly at scale.

**Kept case-insensitive substring match simple.** Spec notes word-boundary matching as a future upgrade if noise becomes real — Phase 1 explicitly tolerates false positives because injected skills are context, not commands, and the cost of a spurious inject is far lower than the cost of a missed inject.

## Alternatives considered

- **Phase 1 = concept extraction only** (no hook, no migration). Thinnest possible shipment but the value isn't visible without the hook. Rejected.
- **Phase 1 = the full v2 spec end-to-end.** Too large for a single design-plan-implement cycle. Would have mixed retrieval-side and capture-side work, blurring the failure modes. Rejected in favor of the scoped slice.
- **JSON envelope (`hookSpecificOutput.additionalContext`) vs plain stdout.** Both are supported by Claude Code. Plain stdout wins on simplicity and bash-friendliness; envelope is only needed for features like `permissionDecision` we don't use in Phase 1.
- **Python hook.** Rejected because whygit is committedly zero-runtime-dependency and cross-platform-friendly; bash + awk is universally available on macOS and Linux without installs.

## Prompts that shaped direction

- "Lets go with B" (choosing the retrieval-slice scope over all-of-v2 or extraction-only).
- "C" (running the hook-contract verification as a parallel agent rather than trusting spec assumptions).
- "A" (budget truncation with a notice rather than summary-mode, ranking, or ignoring the cap).
- "B" (in-session /migrate-skills rather than shell script with nested claude -p).

## Follow-up / known limitations

- Performance is ~275–375ms for 100 skills. Target was 200ms. Acceptable for now; the v2 spec mentions a `.claude/.cache/concept_index.txt` as a future optimization.
- `concept_match.sh` scans skill files fresh on every prompt. No cache.
- Alias matching is case-insensitive substring only. No word-boundary or stemming.
- `/migrate-skills` has not been exercised end-to-end against the repo's one pre-v2 skill — the example skill was hand-migrated in Task 12 for dogfooding. Running `/migrate-skills` in a real session on a repo with pre-v2 skills is the next manual verification step.
- Installer warns rather than failing when `jq` is missing, but gracefully produces a manual-config message instead. This is fine for Phase 1; could be hardened later.
- Future Phase 2 components (auto-capture, auto-mine, /review-skills, naming-guard) are not built. They will be separate brainstorming-design-plan-implement cycles.
