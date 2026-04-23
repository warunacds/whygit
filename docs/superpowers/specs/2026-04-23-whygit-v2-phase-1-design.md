# whygit v2 — Phase 1 Design: Concept-Triggered Retrieval

Date: 2026-04-23
Status: Approved for implementation

---

## Context

v1 of whygit captures session reasoning via `/commit` and mines it into skills via `/learn`. Skills load once at session start via a two-pass scan defined in `CLAUDE.md`.

v1 has three gaps that v2 (per the full v2 spec) closes:
1. Capture is manual and discipline-dependent.
2. Retrieval is session-scoped — skills that become relevant mid-session never fire.
3. Triggers are file-and-symbol indexed, so prompts using domain vocabulary miss matching skills.

This document covers **Phase 1** only. Phase 1 targets gap (2) and (3). Gap (1) is addressed in a later cycle (auto-capture and auto-mine).

## Scope

In scope for Phase 1:
- **Component 3 (concept extraction):** `/learn` grows `concepts:` frontmatter on every NEW/PATCH skill it produces.
- **Component 4 (concept_match.sh):** a `UserPromptSubmit` hook injects matching skills into the turn's context just-in-time.
- **Migration (/migrate-skills slash command):** backfills `concepts:` on existing v1 skills in-session with user approval.

Deferred (not in Phase 1):
- Component 1: auto_capture Stop hook
- Component 2: auto_mine + `/review-skills`
- Component 5: naming_guard PreToolUse hook
- Component 6 (drafts directory, `.auto/` logs): only the settings-merge and install updates are in scope

## Claude Code hook contract (verified)

Verified against Claude Code's hooks documentation (code.claude.com/docs/en/hooks.md):

- Event name `UserPromptSubmit` is correct.
- Input arrives on stdin as a JSON object. For `UserPromptSubmit`, the prompt text is at `.prompt`. There is no env-var variant.
- Plain stdout from a `UserPromptSubmit` hook is injected into the context Claude sees for that turn. Alternately, structured output via a JSON envelope with `hookSpecificOutput.additionalContext` works too. Phase 1 uses plain stdout for simplicity.
- The injected context is capped at 10,000 characters total. Excess is truncated to a file with a preview link.
- Matcher syntax: `"*"` matches all, pipe-separated matches multiple values, regex supported. The nested `{"matcher": "...", "hooks": [{"type": "command", "command": "..."}]}` shape in `settings.json` is current.
- `$CLAUDE_PROJECT_DIR` is a real environment variable available to hook scripts.

## Architecture

```
user types prompt
      │
      ▼
┌─────────────────────────────────────────────┐
│  UserPromptSubmit hook                      │
│    .claude/hooks/concept_match.sh           │
│                                              │
│  1. Read JSON from stdin; extract .prompt    │
│  2. Normalize (lowercase, collapse space)    │
│  3. For each .claude/skills/*.md:            │
│       parse concepts.aliases from frontmatter│
│       if any alias is substring → match     │
│  4. Emit <whygit-memory> block on stdout,    │
│     bounded by ~9k-char budget              │
└─────────────────────────────────────────────┘
      │
      ▼ stdout → Claude reads as extra context
      ▼
Claude's response is grounded in matching skills
```

Skill writes continue through `/learn` and now produce frontmatter with a `concepts:` block. Existing skills are upgraded via `/migrate-skills` — a one-shot, user-approved pass.

## File additions and updates

```
whygit/
├── .claude/
│   ├── commands/
│   │   ├── learn.md              # UPDATED: Phase 3.5 concept extraction
│   │   └── migrate-skills.md     # NEW
│   ├── hooks/
│   │   └── concept_match.sh      # NEW, executable
│   ├── skills/
│   │   └── curl-pipe-bash-self-contained.md   # UPDATED: add concepts block
│   └── settings.json             # NEW or MERGED: register UserPromptSubmit hook
├── install-whygit.sh             # UPDATED: embed new files, merge settings.json
├── SPEC.md                       # UPDATED: document v2 Phase 1
└── tests/
    └── phase1/                   # NEW: shell-based integration tests
```

## Component 1 — `concept_match.sh`

### Inputs and outputs

- Input: JSON on stdin. The prompt text is at `.prompt`.
- Output: on match, a `<whygit-memory>` block on stdout; on no match or any error, empty stdout. Always exit 0.

### Output format

```
<whygit-memory>
Relevant prior decisions from this codebase's memory:

### From <skill-filename>

<full skill content>

---

### From <other-skill>

...

---
</whygit-memory>
```

If the cumulative byte count would exceed the budget, the block ends with a truncation notice on its own line above the closing tag:

```
(N additional matching skills omitted — run /skills to browse)
</whygit-memory>
```

### Budget

9,000 characters hard limit, leaving 1,000 chars of headroom under Claude Code's 10k stdout cap. Budget is measured on the final emitted bytes (including the wrapper and headers). Once appending the next skill would breach the budget, emit the truncation notice and stop.

### Parsing strategy

- JSON: use `jq` if present. If `jq` is missing, attempt a fallback: extract the `"prompt"` value with `grep`/`sed` on the raw stdin. If the fallback fails, exit 0 with empty stdout.
- Frontmatter: use `awk` to find the block between the first two `---` delimiters and the `concepts:` block within it, then extract alias strings.
- Normalization: lowercase both sides, collapse whitespace runs to single spaces. Substring match.
- Iteration: glob `"$CLAUDE_PROJECT_DIR/.claude/skills/"*.md` — top-level only, not `.drafts/` or `.conflicts/` subdirs (the glob won't descend).

### Performance

Target: complete in under 200ms for repos with up to 200 skills. Substring matching is O(skills × aliases × prompt length) — all small constants. No caching in Phase 1; the cache file in the v2 spec is a future optimization.

### Safety

- Exit 0 on every internal error. Hook failures must never block the user.
- Respect `WHYGIT_SKIP_HOOKS=1` at the top of the script: exit 0 immediately with no output.
- Never write to stderr unless a log is explicitly configured (Phase 1: no logging).

### Reference implementation (informative)

```bash
#!/usr/bin/env bash
set -euo pipefail

[[ "${WHYGIT_SKIP_HOOKS:-0}" == "1" ]] && exit 0

SKILLS_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills"
[[ -d "$SKILLS_DIR" ]] || exit 0

STDIN="$(cat)"

# Extract prompt (jq preferred)
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$STDIN" | jq -r '.prompt // empty' 2>/dev/null)" || PROMPT=""
else
  PROMPT="$(printf '%s' "$STDIN" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi
[[ -z "$PROMPT" ]] && exit 0

PROMPT_NORM="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')"
MAX_BYTES=9000
buffer=""
emitted=0
omitted=0

for skill in "$SKILLS_DIR"/*.md; do
  [[ -f "$skill" ]] || continue

  aliases="$(awk '
    /^---$/ { fm = !fm; next }
    fm && /^concepts:/ { in_concepts = 1; next }
    fm && in_concepts && /aliases:/ {
      line = $0
      while (match(line, /"[^"]+"/)) {
        print tolower(substr(line, RSTART+1, RLENGTH-2))
        line = substr(line, RSTART+RLENGTH)
      }
    }
    fm && /^[a-z]+:/ && !/aliases:/ { in_concepts = 0 }
  ' "$skill" 2>/dev/null)" || aliases=""

  matched=0
  while IFS= read -r alias; do
    [[ -z "$alias" ]] && continue
    if [[ "$PROMPT_NORM" == *"$alias"* ]]; then
      matched=1
      break
    fi
  done <<< "$aliases"
  [[ "$matched" == "0" ]] && continue

  section="### From $(basename "$skill")"$'\n\n'"$(cat "$skill")"$'\n\n---\n\n'
  candidate="${buffer}${section}"
  header_size=120  # wrapper overhead
  if (( ${#candidate} + header_size > MAX_BYTES )); then
    omitted=$((omitted + 1))
    continue
  fi
  buffer="$candidate"
  emitted=$((emitted + 1))
done

if (( emitted > 0 )); then
  printf '<whygit-memory>\n'
  printf "Relevant prior decisions from this codebase's memory:\n\n"
  printf '%s' "$buffer"
  if (( omitted > 0 )); then
    printf '(%d additional matching skills omitted — run /skills to browse)\n' "$omitted"
  fi
  printf '</whygit-memory>\n'
fi
```

Implementation will adjust specifics (byte accounting, quoting) as the tests demand.

## Component 2 — `/learn` concept extraction

Updates to `.claude/commands/learn.md`. A new **Phase 3.5: Concept extraction** sits between the self-audit (Phase 3) and the proposal (Phase 4). For each NEW or PATCH draft that passes self-audit, Claude extracts:

- `name`: kebab-case domain noun phrase
- `aliases`: 2–4 alternate phrasings; canonical name always included
- `anchors`: 1–3 file paths that implement the concept

### What counts as a concept

- Domain terminology the team uses in conversation.
- Architectural patterns specific to this codebase.
- Problem categories.
- Feature areas.

### What does NOT count

- File paths.
- Class or method names.
- Generic programming terms (refactor, bug fix, performance).
- Library/framework names without domain binding.

Rule of thumb: a concept survives renaming its implementation. A class name is not a concept; the domain phrase the team uses for that class's responsibility is.

### Self-audit

Before including a concept in a draft:
- Would two engineers on this codebase agree on its meaning?
- Is it already in an existing skill? If so, PATCH.
- Are aliases different phrasings or just grammatical variants? Reject near-duplicates.

### Concepts appear in the skill draft

The user sees and approves concepts as part of the `/learn` proposal. No separate approval step. The updated skill frontmatter becomes:

```yaml
---
id: <id>
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources:
  - ai-logs/<source-log-filename>
status: active
concepts:
  - name: <concept-name>
    aliases: ["<canonical name>", "<alternate phrasing 1>", "<alternate phrasing 2>"]
    anchors:
      - <file path 1>
      - <file path 2>
---
```

### Backwards compatibility

v1 skills without `concepts:` continue to load through the existing two-pass CLAUDE.md flow. They do not fire via `concept_match` until they are migrated. The `/migrate-skills` command closes this gap.

## Component 3 — `/migrate-skills` slash command

`.claude/commands/migrate-skills.md`. In-session flow that mirrors `/learn`'s proposal-approve pattern. No nested `claude -p` call, no drafts directory.

### Flow

1. **Discover.** List every `*.md` in `.claude/skills/` whose frontmatter lacks a `concepts:` block.
2. **Extract.** For each, read the full skill and its source logs. Apply the same extraction rules as `/learn` Phase 3.5.
3. **Propose.** Present all extractions as a batch. For each skill, show:
   - The skill's id and title
   - The proposed `concepts:` block
   - A one-line rationale grounded in the source log
4. **Approve.** Ask `[y / N / select]`.
5. **Write.** On `y`, for each approved skill Claude performs a targeted frontmatter edit (via the `Edit` tool, not a full-file rewrite) that:
   - Inserts the `concepts:` block into existing frontmatter while preserving the order of other fields
   - Updates `updated:` to today's date
6. **Commit.** Stage `.claude/skills/`, commit with `learn: backfill concepts for existing v1 skills` and a body listing the migrated files.
7. **Report.** Print the commit hash and list of migrated skills.

### Edge cases

- Skill already has a `concepts:` block: skip silently.
- Skill has no `sources:` or the listed logs are missing: ask the user whether to migrate anyway using only the skill's own content, or to skip.
- Empty `.claude/skills/`: print "No skills to migrate — Phase 1 ready" and exit.

## Settings.json

Registered hook:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/concept_match.sh" }
        ]
      }
    ]
  }
}
```

The installer merges rather than overwrites. Detection: check whether any entry under `.hooks.UserPromptSubmit[*].hooks[*].command` contains the string `concept_match.sh`. If yes, leave the file alone. If the file doesn't exist, write the minimal shape above.

If a file exists but lacks our entry, parse with `jq`, inject our block, and write back atomically. If `jq` is missing during installation, print a warning and instruct the user to add the entry manually.

## Install script updates

Additions to `install-whygit.sh`:

1. Create `.claude/hooks/` directory.
2. Embed `concept_match.sh` via heredoc and `chmod +x` after write.
3. Embed `migrate-skills.md` via heredoc into `.claude/commands/`.
4. Merge `settings.json` idempotently using the detection rule above.
5. Update the embedded `curl-pipe-bash-self-contained.md` heredoc to include a `concepts:` block so the example skill dogfoods the new format.
6. Append `/migrate-skills` to the Skills command table in the CLAUDE.md block (idempotent via marker grep).

Install script safety properties already in place continue to hold: idempotency, input validation, no `$BASH_SOURCE[0]` reliance, `cp --`/`mkdir --` flags, quoted heredoc delimiters. See the existing `.claude/skills/curl-pipe-bash-self-contained.md` for the full set.

## Testing strategy

Shell-based integration tests under `tests/phase1/`. Each test is a self-contained script that sets up a fixture, runs `concept_match.sh`, and asserts on stdout and exit code.

Tests in scope:
1. **Happy path.** Fixture with `aliases: ["installer"]`. Stdin prompt "Fix the installer script". Expect `<whygit-memory>` with the skill, exit 0.
2. **No match.** Same fixture, prompt "what's the weather". Expect empty stdout, exit 0.
3. **Case-insensitive.** Alias `"Installer"`, prompt `"update the INSTALLER"`. Expect match.
4. **Ignores skills without concepts.** v1-shape fixture. Expect no match on any prompt.
5. **Respects WHYGIT_SKIP_HOOKS.** Env set, matching prompt. Expect empty stdout.
6. **Budget truncation.** 20-skill fixture each >1k chars, all match. Expect stdout ≤ 10k, truncation notice present.
7. **Never exits non-zero.** Malformed JSON, missing skills dir, unreadable file — each exits 0.
8. **Performance guard.** 100-skill fixture, `time` wrapper, assert wall clock < 500ms (loose — 200ms is the target, 500 is the guard against regression).
9. **Installer idempotency.** Run `install-whygit.sh` twice into a fresh git repo, expect no diff on second run.

Manual end-to-end verification: inside a real Claude Code session in this very repo, add a test alias to the `curl-pipe-bash-self-contained.md` skill, type a prompt containing that alias, and confirm Claude's response references the skill's guardrails without prompting.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| `jq` not installed on user's system | Fallback `sed`-based prompt extraction; exit silently on any failure |
| Malformed frontmatter breaks parser | `awk` tolerates missing keys and malformed sections; never errors out |
| User's existing `settings.json` has conflicting UserPromptSubmit hooks | Installer detects existing `concept_match.sh` by string match and leaves conflicting entries alone; warns user if `jq` missing during merge |
| Alias substring match produces false positives | Acceptable in Phase 1 — injected skills are context, not commands. If noise becomes real, Phase 2 adds word-boundary matching |
| Skills in `.drafts/` or `.conflicts/` accidentally scanned | `concept_match` globs only top-level `*.md` — subdirs not scanned |
| Recursion when Claude invokes `claude -p` from a hook | `WHYGIT_SKIP_HOOKS=1` check at the top of `concept_match.sh` breaks the cycle |
| 10k output cap silently truncates | Explicit 9k budget + truncation notice visible to Claude and to the user |

## Non-goals

- Embeddings or semantic retrieval.
- Ranking by match strength. First-match-per-skill wins.
- Auto-capture or auto-mine.
- Naming guardrail on `PreToolUse`.
- Drafts directory, `.auto/` logs, `/review-skills`.
- Word-boundary or stemmed matching.
- Team-shared skill libraries.

## Success criteria

Phase 1 is successful when:

1. A fresh session in a whygit-installed repo: user types a prompt containing an alias from an existing skill, and Claude's response visibly references the skill's guardrails without being prompted to.
2. `concept_match.sh` passes all nine tests above.
3. `/migrate-skills` backfills every pre-v2 skill in this repo without corrupting frontmatter.
4. Running `install-whygit.sh` twice on a fresh git repo produces identical output on the second run.

## Rollout within Phase 1

Implementation order:
1. Write `concept_match.sh` and its tests. Ship.
2. Update `/learn` to emit `concepts:` on new skills.
3. Write `/migrate-skills`, run it against this repo's own skill.
4. Update `install-whygit.sh` to embed the new files and merge settings.
5. Update `SPEC.md` and `README.md` to document v2 Phase 1.
6. Each step commits separately with a corresponding AI decision log.
