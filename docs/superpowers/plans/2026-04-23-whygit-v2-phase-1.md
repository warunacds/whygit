# whygit v2 — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship concept-triggered retrieval for whygit — a `UserPromptSubmit` hook that injects matching skills into Claude's context mid-session, plus the `/learn` and `/migrate-skills` flows that produce and backfill the `concepts:` frontmatter the hook reads.

**Architecture:** A shell hook (`concept_match.sh`) parses `aliases` from the `concepts:` block of every `.claude/skills/*.md` file, does a case-insensitive substring match against the current prompt (read from stdin as JSON), and emits matching skills wrapped in a `<whygit-memory>` block on stdout — Claude Code injects that stdout into the turn's context. Skill authoring flows through `/learn` (new skills) and `/migrate-skills` (existing v1 skills). Settings.json registration happens via the install script.

**Tech Stack:** Bash (zero runtime deps — `jq` optional, `awk`/`sed` fallback), markdown slash commands, Claude Code's hook system.

**Spec:** `docs/superpowers/specs/2026-04-23-whygit-v2-phase-1-design.md`

---

## File Structure

```
whygit/
├── .claude/
│   ├── commands/
│   │   ├── learn.md                         # MODIFY: add Phase 3.5 concept extraction
│   │   └── migrate-skills.md                # CREATE
│   ├── hooks/
│   │   └── concept_match.sh                 # CREATE, chmod +x
│   ├── skills/
│   │   └── curl-pipe-bash-self-contained.md # MODIFY: add concepts block
│   └── settings.json                        # MERGE: register UserPromptSubmit hook
├── install-whygit.sh                         # MODIFY: embed new files + settings merge
├── SPEC.md                                   # MODIFY: document Phase 1
├── README.md                                 # MODIFY: mention /migrate-skills and retrieval
├── CLAUDE.md                                 # MODIFY: add /migrate-skills to command table
└── tests/
    └── phase1/
        ├── run_all.sh                        # CREATE: test harness
        ├── helpers.sh                        # CREATE: shared fixtures and assertions
        ├── test_happy_path.sh                # CREATE
        ├── test_no_match.sh                  # CREATE
        ├── test_case_insensitive.sh          # CREATE
        ├── test_ignores_v1_skills.sh         # CREATE
        ├── test_skip_env.sh                  # CREATE
        ├── test_budget_truncation.sh         # CREATE
        ├── test_never_fails.sh               # CREATE
        ├── test_performance.sh               # CREATE
        └── test_installer_idempotency.sh     # CREATE
```

Responsibilities:
- `concept_match.sh` — the only runtime hook. Parses prompt, matches aliases, emits context block.
- `migrate-skills.md` — slash command prose read by Claude. All logic runs in-session.
- `learn.md` — slash command prose, v1 behaviour + new Phase 3.5.
- `install-whygit.sh` — distribution. Embeds every runtime artefact. Idempotent.
- `tests/phase1/*` — shell integration tests. No language runtime.

---

## Task 1 — Test harness scaffolding

**Files:**
- Create: `tests/phase1/helpers.sh`
- Create: `tests/phase1/run_all.sh`

### - [ ] Step 1: Write `tests/phase1/helpers.sh`

```bash
#!/usr/bin/env bash
# Shared test helpers for phase1. Source with: . "$(dirname "$0")/helpers.sh"

# Fail-fast behaviour is the caller's choice — helpers only export.

TESTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_ROOT/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/concept_match.sh"

# -----------------------------------------------------------------------------
# mk_fixture <dir>
#
# Creates a throwaway fixture directory layout:
#   <dir>/.claude/skills/
# Caller adds skill files afterwards.
# -----------------------------------------------------------------------------
mk_fixture() {
  local dir="$1"
  rm -rf -- "$dir"
  mkdir -p -- "$dir/.claude/skills"
  echo "$dir"
}

# -----------------------------------------------------------------------------
# write_skill <fixture-dir> <filename> <aliases-json-array>
#
# Writes a v2-shape skill file with a concepts block.
#   write_skill /tmp/fx installer.md '["installer", "install script"]'
# -----------------------------------------------------------------------------
write_skill() {
  local fixture="$1"
  local filename="$2"
  local aliases="$3"
  local title="${4:-Test skill $filename}"
  local body="${5:-Guardrail body for $filename.}"

  cat > "$fixture/.claude/skills/$filename" <<EOF
---
id: ${filename%.md}
created: 2026-04-23
updated: 2026-04-23
sources:
  - ai-logs/test.md
status: active
concepts:
  - name: test-concept
    aliases: $aliases
    anchors:
      - test.txt
---

# $title

## When to apply
- test trigger

## Guardrails
1. $body
EOF
}

# -----------------------------------------------------------------------------
# write_v1_skill <fixture-dir> <filename>
#
# Writes a v1-shape skill file (no concepts block).
# -----------------------------------------------------------------------------
write_v1_skill() {
  local fixture="$1"
  local filename="$2"

  cat > "$fixture/.claude/skills/$filename" <<EOF
---
id: ${filename%.md}
created: 2026-04-23
sources:
  - ai-logs/test.md
status: active
---

# V1 skill

## When to apply
- v1 trigger
EOF
}

# -----------------------------------------------------------------------------
# run_hook <fixture-dir> <prompt-text>
#
# Invokes concept_match.sh with the fixture and JSON stdin carrying the prompt.
# Prints the hook's stdout. Exit code is preserved for inspection via $?.
# -----------------------------------------------------------------------------
run_hook() {
  local fixture="$1"
  local prompt="$2"
  local payload
  # Escape double quotes and backslashes for the JSON string
  payload=$(printf '%s' "$prompt" | python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"UserPromptSubmit","prompt":sys.stdin.read()}))' 2>/dev/null) || {
    # Python fallback — use jq if available
    if command -v jq >/dev/null 2>&1; then
      payload=$(jq -cn --arg p "$prompt" '{hook_event_name:"UserPromptSubmit",prompt:$p}')
    else
      # Last resort: minimally-escaped JSON
      local esc
      esc=$(printf '%s' "$prompt" | sed 's/\\/\\\\/g; s/"/\\"/g')
      payload="{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"$esc\"}"
    fi
  }
  CLAUDE_PROJECT_DIR="$fixture" bash "$HOOK" <<< "$payload"
}

# -----------------------------------------------------------------------------
# assert_eq <actual> <expected> <label>
# assert_contains <haystack> <needle> <label>
# assert_empty <value> <label>
# -----------------------------------------------------------------------------
assert_eq() {
  if [[ "$1" != "$2" ]]; then
    echo "FAIL [$3]: expected '$2' got '$1'" >&2
    exit 1
  fi
}

assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    echo "FAIL [$3]: expected substring '$2' in output" >&2
    echo "----- output -----" >&2
    echo "$1" >&2
    echo "----- /output -----" >&2
    exit 1
  fi
}

assert_not_contains() {
  if [[ "$1" == *"$2"* ]]; then
    echo "FAIL [$3]: did not expect substring '$2' in output" >&2
    exit 1
  fi
}

assert_empty() {
  if [[ -n "$1" ]]; then
    echo "FAIL [$2]: expected empty output, got:" >&2
    echo "$1" >&2
    exit 1
  fi
}

pass() {
  echo "PASS: $1"
}
```

### - [ ] Step 2: Write `tests/phase1/run_all.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

fail=0
for t in test_*.sh; do
  echo "===> $t"
  if bash "$t"; then
    :
  else
    fail=$((fail + 1))
  fi
done

if (( fail > 0 )); then
  echo ""
  echo "❌ $fail test file(s) failed"
  exit 1
fi

echo ""
echo "✅ All phase1 tests passed"
```

### - [ ] Step 3: Make them executable

Run:
```bash
chmod +x tests/phase1/run_all.sh tests/phase1/helpers.sh
```

### - [ ] Step 4: Commit

```bash
git add tests/phase1/helpers.sh tests/phase1/run_all.sh
git commit -m "test(phase1): add shell test harness scaffolding"
```

---

## Task 2 — Write the first failing test (happy path)

**Files:**
- Create: `tests/phase1/test_happy_path.sh`

### - [ ] Step 1: Write the test

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_happy_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null
write_skill "$FX" "installer.md" '["installer", "install script"]' "Installer rules"

out="$(run_hook "$FX" "Fix the installer script please")"

assert_contains "$out" "<whygit-memory>" "opening tag"
assert_contains "$out" "installer.md"    "skill filename"
assert_contains "$out" "Installer rules" "skill title"
assert_contains "$out" "</whygit-memory>" "closing tag"

pass "happy path: alias match injects skill"
```

### - [ ] Step 2: Make it executable and run it

```bash
chmod +x tests/phase1/test_happy_path.sh
bash tests/phase1/test_happy_path.sh
```

Expected: failure because `.claude/hooks/concept_match.sh` does not yet exist. The failure message will look like `bash: .claude/hooks/concept_match.sh: No such file or directory` and then an `assert_contains` FAIL.

### - [ ] Step 3: Commit the failing test

```bash
git add tests/phase1/test_happy_path.sh
git commit -m "test(phase1): failing happy-path test for concept_match"
```

---

## Task 3 — Minimal `concept_match.sh` to pass the happy path

**Files:**
- Create: `.claude/hooks/concept_match.sh`

### - [ ] Step 1: Create the hook directory

```bash
mkdir -p .claude/hooks
```

### - [ ] Step 2: Write `concept_match.sh`

```bash
#!/usr/bin/env bash
# whygit v2 concept-match hook for UserPromptSubmit.
# Reads JSON on stdin, emits matching skills wrapped in <whygit-memory> on stdout.
# Must never exit non-zero; hook failures must never block the user.

set -u

# Recursion safeguard
if [[ "${WHYGIT_SKIP_HOOKS:-0}" == "1" ]]; then
  exit 0
fi

# Skills directory — fall back to $PWD if $CLAUDE_PROJECT_DIR is unset
SKILLS_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills"
[[ -d "$SKILLS_DIR" ]] || exit 0

MAX_BYTES=9000

# Read stdin
STDIN="$(cat 2>/dev/null || true)"
[[ -z "$STDIN" ]] && exit 0

# Extract prompt
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$STDIN" | jq -r '.prompt // empty' 2>/dev/null || true)"
else
  PROMPT="$(printf '%s' "$STDIN" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | head -1)"
  # Unescape minimal JSON
  PROMPT="$(printf '%b' "${PROMPT//\\n/\\n}" 2>/dev/null || printf '%s' "$PROMPT")"
fi
[[ -z "$PROMPT" ]] && exit 0

PROMPT_NORM="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')"

buffer=""
emitted=0
omitted=0

shopt -s nullglob
for skill in "$SKILLS_DIR"/*.md; do
  [[ -f "$skill" ]] || continue

  aliases="$(awk '
    BEGIN { fm = 0; in_concepts = 0 }
    /^---[[:space:]]*$/ { fm = !fm; next }
    !fm { next }
    /^concepts:/ { in_concepts = 1; next }
    in_concepts && /^[[:space:]]+aliases:/ {
      line = $0
      while (match(line, /"[^"]+"/)) {
        print tolower(substr(line, RSTART+1, RLENGTH-2))
        line = substr(line, RSTART+RLENGTH)
      }
      next
    }
    in_concepts && /^[a-zA-Z_]+:/ { in_concepts = 0 }
  ' "$skill" 2>/dev/null)" || aliases=""

  [[ -z "$aliases" ]] && continue

  matched=0
  while IFS= read -r alias; do
    [[ -z "$alias" ]] && continue
    if [[ "$PROMPT_NORM" == *"$alias"* ]]; then
      matched=1
      break
    fi
  done <<< "$aliases"
  (( matched == 0 )) && continue

  content="$(cat "$skill" 2>/dev/null || true)"
  section="### From $(basename "$skill")"$'\n\n'"$content"$'\n\n---\n\n'

  wrapper_size=120  # <whygit-memory> + intro + </whygit-memory>
  candidate_size=$(( ${#buffer} + ${#section} + wrapper_size ))
  if (( candidate_size > MAX_BYTES )); then
    omitted=$((omitted + 1))
    continue
  fi
  buffer="${buffer}${section}"
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

exit 0
```

### - [ ] Step 3: Make the hook executable

```bash
chmod +x .claude/hooks/concept_match.sh
```

### - [ ] Step 4: Run the happy-path test

```bash
bash tests/phase1/test_happy_path.sh
```

Expected:
```
PASS: happy path: alias match injects skill
```

### - [ ] Step 5: Commit

```bash
git add .claude/hooks/concept_match.sh
git commit -m "feat(hooks): add concept_match.sh for UserPromptSubmit retrieval"
```

---

## Task 4 — No-match test

**Files:**
- Create: `tests/phase1/test_no_match.sh`

### - [ ] Step 1: Write the test

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_nomatch_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null
write_skill "$FX" "installer.md" '["installer"]'

out="$(run_hook "$FX" "what is the weather today")"
rc=$?

assert_eq "$rc" "0" "exit code"
assert_empty "$out" "no-match output"

pass "no match: empty stdout"
```

### - [ ] Step 2: Run it

```bash
chmod +x tests/phase1/test_no_match.sh
bash tests/phase1/test_no_match.sh
```

Expected: `PASS: no match: empty stdout`

### - [ ] Step 3: Commit

```bash
git add tests/phase1/test_no_match.sh
git commit -m "test(phase1): no-match case"
```

---

## Task 5 — Case-insensitive match

**Files:**
- Create: `tests/phase1/test_case_insensitive.sh`

### - [ ] Step 1: Write the test

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_case_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null
write_skill "$FX" "installer.md" '["Installer"]'

out="$(run_hook "$FX" "update the INSTALLER please")"

assert_contains "$out" "installer.md" "match despite case"

pass "case-insensitive: uppercase prompt matches lowercase alias"
```

### - [ ] Step 2: Run it

```bash
chmod +x tests/phase1/test_case_insensitive.sh
bash tests/phase1/test_case_insensitive.sh
```

Expected: PASS.

### - [ ] Step 3: Commit

```bash
git add tests/phase1/test_case_insensitive.sh
git commit -m "test(phase1): case-insensitive alias match"
```

---

## Task 6 — Ignores v1 skills without concepts block

**Files:**
- Create: `tests/phase1/test_ignores_v1_skills.sh`

### - [ ] Step 1: Write the test

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_v1_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null
write_v1_skill "$FX" "v1-only.md"

out="$(run_hook "$FX" "anything v1 trigger at all")"

assert_empty "$out" "v1 skills do not match"

pass "v1 skills: no concepts block means no match"
```

### - [ ] Step 2: Run it

```bash
chmod +x tests/phase1/test_ignores_v1_skills.sh
bash tests/phase1/test_ignores_v1_skills.sh
```

Expected: PASS.

### - [ ] Step 3: Commit

```bash
git add tests/phase1/test_ignores_v1_skills.sh
git commit -m "test(phase1): v1 skills without concepts block are ignored"
```

---

## Task 7 — Respects WHYGIT_SKIP_HOOKS

**Files:**
- Create: `tests/phase1/test_skip_env.sh`

### - [ ] Step 1: Write the test

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_skip_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null
write_skill "$FX" "installer.md" '["installer"]'

# Using bash -c so we can set the env var on the exec'd process
payload='{"hook_event_name":"UserPromptSubmit","prompt":"installer"}'
out=$(WHYGIT_SKIP_HOOKS=1 CLAUDE_PROJECT_DIR="$FX" bash "$HOOK" <<< "$payload")

assert_empty "$out" "skip env bypasses hook"

pass "WHYGIT_SKIP_HOOKS=1 bypasses all matching"
```

### - [ ] Step 2: Run it

```bash
chmod +x tests/phase1/test_skip_env.sh
bash tests/phase1/test_skip_env.sh
```

Expected: PASS.

### - [ ] Step 3: Commit

```bash
git add tests/phase1/test_skip_env.sh
git commit -m "test(phase1): WHYGIT_SKIP_HOOKS env bypasses matching"
```

---

## Task 8 — Budget truncation

**Files:**
- Create: `tests/phase1/test_budget_truncation.sh`

### - [ ] Step 1: Write the test

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_budget_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null

# Generate 20 skills each ~700 chars of body -> total > 10k after wrapping
big_body="$(printf 'x%.0s' $(seq 1 700))"
for i in $(seq 1 20); do
  name="skill_$i.md"
  cat > "$FX/.claude/skills/$name" <<EOF
---
id: skill_$i
created: 2026-04-23
updated: 2026-04-23
sources:
  - ai-logs/test.md
status: active
concepts:
  - name: budget-concept
    aliases: ["installer"]
    anchors:
      - test.txt
---

# Skill $i

## Guardrails
1. $big_body
EOF
done

out=$(run_hook "$FX" "installer")

size=${#out}
if (( size > 10000 )); then
  echo "FAIL: output size $size exceeded 10000" >&2
  exit 1
fi

assert_contains "$out" "additional matching skills omitted" "truncation notice present"
assert_contains "$out" "</whygit-memory>" "closing tag emitted despite truncation"

pass "budget truncation: stdout <=10k and notice emitted (size=$size)"
```

### - [ ] Step 2: Run it

```bash
chmod +x tests/phase1/test_budget_truncation.sh
bash tests/phase1/test_budget_truncation.sh
```

Expected: PASS with a printed size under 10,000.

### - [ ] Step 3: Commit

```bash
git add tests/phase1/test_budget_truncation.sh
git commit -m "test(phase1): budget truncation emits notice and stays under 10k"
```

---

## Task 9 — Never exits non-zero

**Files:**
- Create: `tests/phase1/test_never_fails.sh`

### - [ ] Step 1: Write the test

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_fail_$$"
trap "rm -rf -- $FX" EXIT

# Case A: malformed JSON
mk_fixture "$FX" >/dev/null
write_skill "$FX" "x.md" '["installer"]'

CLAUDE_PROJECT_DIR="$FX" bash "$HOOK" <<< 'this is not json at all' >/tmp/whygit_fail_a.out
rc=$?
assert_eq "$rc" "0" "malformed JSON exit code"

# Case B: missing skills dir
rm -rf -- "$FX/.claude"
CLAUDE_PROJECT_DIR="$FX" bash "$HOOK" <<< '{"hook_event_name":"UserPromptSubmit","prompt":"hi"}' >/tmp/whygit_fail_b.out
rc=$?
assert_eq "$rc" "0" "missing skills dir exit code"

# Case C: unreadable skill file
mk_fixture "$FX" >/dev/null
write_skill "$FX" "x.md" '["installer"]'
chmod 000 "$FX/.claude/skills/x.md"
CLAUDE_PROJECT_DIR="$FX" bash "$HOOK" <<< '{"hook_event_name":"UserPromptSubmit","prompt":"installer"}' >/tmp/whygit_fail_c.out
rc=$?
chmod 644 "$FX/.claude/skills/x.md"
assert_eq "$rc" "0" "unreadable file exit code"

# Case D: empty stdin
CLAUDE_PROJECT_DIR="$FX" bash "$HOOK" < /dev/null >/tmp/whygit_fail_d.out
rc=$?
assert_eq "$rc" "0" "empty stdin exit code"

pass "never exits non-zero across malformed/missing/unreadable/empty inputs"
```

### - [ ] Step 2: Run it

```bash
chmod +x tests/phase1/test_never_fails.sh
bash tests/phase1/test_never_fails.sh
```

Expected: PASS.

### - [ ] Step 3: Commit

```bash
git add tests/phase1/test_never_fails.sh
git commit -m "test(phase1): hook never exits non-zero on bad input"
```

---

## Task 10 — Performance guard

**Files:**
- Create: `tests/phase1/test_performance.sh`

### - [ ] Step 1: Write the test

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_perf_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null
for i in $(seq 1 100); do
  cat > "$FX/.claude/skills/skill_$i.md" <<EOF
---
id: skill_$i
created: 2026-04-23
updated: 2026-04-23
sources: []
status: active
concepts:
  - name: c$i
    aliases: ["alias-$i", "something-$i"]
    anchors: []
---

# Skill $i

## Guardrails
1. body $i.
EOF
done

payload='{"hook_event_name":"UserPromptSubmit","prompt":"this is a random prompt with nothing useful"}'

start_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
CLAUDE_PROJECT_DIR="$FX" bash "$HOOK" <<< "$payload" >/dev/null
end_ms=$(python3 -c 'import time; print(int(time.time()*1000))')

elapsed=$(( end_ms - start_ms ))
echo "Elapsed: ${elapsed}ms"

if (( elapsed > 500 )); then
  echo "FAIL: performance regression — ${elapsed}ms > 500ms" >&2
  exit 1
fi

pass "performance guard: 100 skills processed in ${elapsed}ms (< 500ms)"
```

### - [ ] Step 2: Run it

```bash
chmod +x tests/phase1/test_performance.sh
bash tests/phase1/test_performance.sh
```

Expected: PASS with a reported elapsed < 500ms.

### - [ ] Step 3: Commit

```bash
git add tests/phase1/test_performance.sh
git commit -m "test(phase1): 100-skill performance guard (<500ms)"
```

---

## Task 11 — Run the whole harness

### - [ ] Step 1: Execute run_all.sh

```bash
bash tests/phase1/run_all.sh
```

Expected:
```
===> test_budget_truncation.sh
PASS: budget truncation: ...
===> test_case_insensitive.sh
PASS: case-insensitive: ...
===> test_happy_path.sh
PASS: happy path: ...
===> test_ignores_v1_skills.sh
PASS: v1 skills: ...
===> test_never_fails.sh
PASS: never exits non-zero ...
===> test_no_match.sh
PASS: no match: ...
===> test_performance.sh
PASS: performance guard: ...
===> test_skip_env.sh
PASS: WHYGIT_SKIP_HOOKS=1 ...

✅ All phase1 tests passed
```

If any fails, stop and fix `concept_match.sh` before proceeding.

### - [ ] Step 2: Commit progress point (if harness changes required)

Only if this step revealed bugs requiring script changes:
```bash
git add .claude/hooks/concept_match.sh
git commit -m "fix(hooks): <describe fix>"
```

---

## Task 12 — Update existing skill with a concepts block

**Files:**
- Modify: `.claude/skills/curl-pipe-bash-self-contained.md` (repo root skill file)

### - [ ] Step 1: Read the current file

```bash
cat .claude/skills/curl-pipe-bash-self-contained.md | head -15
```

You will see frontmatter ending after the `status: active` line.

### - [ ] Step 2: Insert the `concepts:` block

Use the Edit tool to replace the block below. The old_string is the closing `---` of the frontmatter; the new_string adds `concepts:` before it.

Old:
```
sources:
  - ai-logs/2026-02-26-open-source-release.md
  - ai-logs/2026-02-26-install-script-security-fixes.md
status: active
---
```

New:
```
sources:
  - ai-logs/2026-02-26-open-source-release.md
  - ai-logs/2026-02-26-install-script-security-fixes.md
status: active
concepts:
  - name: piped-installer
    aliases: ["piped installer", "install script", "installer", "curl pipe bash"]
    anchors:
      - install-whygit.sh
---
```

Also update the `updated:` line to today's date (`2026-04-23`).

### - [ ] Step 3: Verify the file still parses

```bash
awk '
  BEGIN { fm = 0; in_concepts = 0 }
  /^---[[:space:]]*$/ { fm = !fm; next }
  !fm { next }
  /^concepts:/ { in_concepts = 1; next }
  in_concepts && /^[[:space:]]+aliases:/ {
    while (match($0, /"[^"]+"/)) {
      print tolower(substr($0, RSTART+1, RLENGTH-2))
      $0 = substr($0, RSTART+RLENGTH)
    }
  }
' .claude/skills/curl-pipe-bash-self-contained.md
```

Expected output (order may vary):
```
piped installer
install script
installer
curl pipe bash
```

### - [ ] Step 4: Smoke-test the hook against the real skill

```bash
payload='{"hook_event_name":"UserPromptSubmit","prompt":"working on the install script"}'
CLAUDE_PROJECT_DIR="$PWD" bash .claude/hooks/concept_match.sh <<< "$payload" | head -5
```

Expected first lines:
```
<whygit-memory>
Relevant prior decisions from this codebase's memory:

### From curl-pipe-bash-self-contained.md
```

### - [ ] Step 5: Commit

```bash
git add .claude/skills/curl-pipe-bash-self-contained.md
git commit -m "chore(skills): add concepts block to example skill (dogfooding)"
```

---

## Task 13 — Write `/migrate-skills` slash command

**Files:**
- Create: `.claude/commands/migrate-skills.md`

### - [ ] Step 1: Write the command

```markdown
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
```

### - [ ] Step 2: Verify file looks right

```bash
head -10 .claude/commands/migrate-skills.md
```

### - [ ] Step 3: Commit

```bash
git add .claude/commands/migrate-skills.md
git commit -m "feat(commands): add /migrate-skills for v1→v2 concepts backfill"
```

---

## Task 14 — Update `/learn` to emit concepts on new skills

**Files:**
- Modify: `.claude/commands/learn.md`

### - [ ] Step 1: Read the current file location of Phase 3 → Phase 4 boundary

```bash
grep -n '^## Phase' .claude/commands/learn.md
```

You will see Phases 1 through 4. We insert Phase 3.5 between the existing Phase 3 self-audit and Phase 4 propose-and-write.

### - [ ] Step 2: Edit — insert Phase 3.5

Use the Edit tool to insert the new phase. Locate the text `## Phase 4 — Propose and write` and replace the line preceding it (the end of Phase 3) plus the `## Phase 4` header with Phase 3.5 content plus Phase 4 header.

Old (the closing of Phase 3 immediately before Phase 4 — locate by finding the last content of the Phase 3 banned-phrases dropped example, and the line `## Phase 4 — Propose and write`):

```
This draft fails Check 1 (no concrete artefact), Check 2 (vague citation), Check 3 (three banned phrases), and Check 4 (any team could write this without reading the log). Dropped.

## Phase 4 — Propose and write
```

New:

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
```

### - [ ] Step 3: Verify the structure

```bash
grep -n '^## Phase' .claude/commands/learn.md
```

Expected output includes `## Phase 3.5 — Concept extraction`.

### - [ ] Step 4: Commit

```bash
git add .claude/commands/learn.md
git commit -m "feat(commands): /learn now extracts concepts block for v2 retrieval"
```

---

## Task 15 — Settings.json registration

**Files:**
- Create: `.claude/settings.json`

### - [ ] Step 1: Check if the file already exists

```bash
ls .claude/settings.json 2>/dev/null && echo "exists" || echo "missing"
```

### - [ ] Step 2A: If missing, create it

```bash
cat > .claude/settings.json <<'EOF'
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
EOF
```

### - [ ] Step 2B: If it exists, inspect first, then merge manually using `jq`

```bash
cat .claude/settings.json
```

If the file already contains a UserPromptSubmit hook for `concept_match.sh`, leave it alone.

Otherwise, merge with jq:

```bash
jq '
  .hooks //= {} |
  .hooks.UserPromptSubmit //= [] |
  .hooks.UserPromptSubmit += [
    {
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "bash .claude/hooks/concept_match.sh" }]
    }
  ]
' .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
```

### - [ ] Step 3: Validate JSON

```bash
jq . .claude/settings.json
```

Expected: the full file pretty-printed with no errors.

### - [ ] Step 4: Smoke test by running the hook exactly as settings.json invokes it

```bash
echo '{"hook_event_name":"UserPromptSubmit","prompt":"installer"}' | bash .claude/hooks/concept_match.sh | head -3
```

Expected output begins `<whygit-memory>`.

### - [ ] Step 5: Check whether settings.json should be committed

Look at `.gitignore`:

```bash
cat .gitignore
```

If `settings.json` is gitignored, add `settings.json` to the commit anyway but document in the commit that users installing from fresh will regenerate it. If `settings.local.json` exists separately and settings.json is safe to commit, proceed.

### - [ ] Step 6: Commit

```bash
git add .claude/settings.json
git commit -m "feat(hooks): register UserPromptSubmit hook for concept_match"
```

---

## Task 16 — Installer idempotency test

**Files:**
- Create: `tests/phase1/test_installer_idempotency.sh`

### - [ ] Step 1: Write the test

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

# Create a fresh temp git repo and run the installer twice
FX="/tmp/whygit_phase1_installer_$$"
trap "rm -rf -- $FX" EXIT

rm -rf -- "$FX"
mkdir -p -- "$FX"
git -C "$FX" init -q

# First install
bash "$REPO_ROOT/install-whygit.sh" "$FX" >/dev/null

# Snapshot
snap_dir=$(mktemp -d)
cp -R -- "$FX" "$snap_dir/after_first"

# Second install
bash "$REPO_ROOT/install-whygit.sh" "$FX" >/dev/null

# Diff — except logs, which are noisy
diff -r --exclude=".git" -- "$snap_dir/after_first" "$FX" > "$snap_dir/diff.txt" || true

if [[ -s "$snap_dir/diff.txt" ]]; then
  echo "FAIL: installer is not idempotent. Diff:" >&2
  cat "$snap_dir/diff.txt" >&2
  rm -rf -- "$snap_dir"
  exit 1
fi

rm -rf -- "$snap_dir"
pass "installer is idempotent across two runs"
```

### - [ ] Step 2: Run it (expect FAIL until the installer supports v2)

```bash
chmod +x tests/phase1/test_installer_idempotency.sh
bash tests/phase1/test_installer_idempotency.sh || true
```

It will either fail (if we added new files the installer doesn't know about) or pass (current installer is already idempotent for v1). Either way we fix in Task 17.

### - [ ] Step 3: Commit the test

```bash
git add tests/phase1/test_installer_idempotency.sh
git commit -m "test(phase1): installer idempotency guard"
```

---

## Task 17 — Update `install-whygit.sh` to embed v2 artefacts

**Files:**
- Modify: `install-whygit.sh`

### - [ ] Step 1: Add a new `mkdir -p` for `.claude/hooks/`

Use Edit. Find the line `mkdir -p -- "$TARGET/ai-logs"`.

Old:
```
mkdir -p -- "$TARGET/.claude/commands"
mkdir -p -- "$TARGET/.claude/skills/.conflicts"
mkdir -p -- "$TARGET/ai-logs"
```

New:
```
mkdir -p -- "$TARGET/.claude/commands"
mkdir -p -- "$TARGET/.claude/skills/.conflicts"
mkdir -p -- "$TARGET/.claude/hooks"
mkdir -p -- "$TARGET/ai-logs"
```

### - [ ] Step 2: Insert the `concept_match.sh` heredoc after the `/skills` command heredoc

Find the line `# --- FILE: .claude/skills/.processed (empty ledger) ---` which marks the end of the command-block heredocs.

Insert this block immediately before it:

```
# --- FILE: .claude/hooks/concept_match.sh ---
cat > "$TARGET/.claude/hooks/concept_match.sh" << 'HEREDOC'
#!/usr/bin/env bash
# whygit v2 concept-match hook for UserPromptSubmit.
# Reads JSON on stdin, emits matching skills wrapped in <whygit-memory> on stdout.
# Must never exit non-zero; hook failures must never block the user.

set -u

if [[ "${WHYGIT_SKIP_HOOKS:-0}" == "1" ]]; then
  exit 0
fi

SKILLS_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills"
[[ -d "$SKILLS_DIR" ]] || exit 0

MAX_BYTES=9000

STDIN="$(cat 2>/dev/null || true)"
[[ -z "$STDIN" ]] && exit 0

if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$STDIN" | jq -r '.prompt // empty' 2>/dev/null || true)"
else
  PROMPT="$(printf '%s' "$STDIN" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | head -1)"
fi
[[ -z "$PROMPT" ]] && exit 0

PROMPT_NORM="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')"

buffer=""
emitted=0
omitted=0

shopt -s nullglob
for skill in "$SKILLS_DIR"/*.md; do
  [[ -f "$skill" ]] || continue

  aliases="$(awk '
    BEGIN { fm = 0; in_concepts = 0 }
    /^---[[:space:]]*$/ { fm = !fm; next }
    !fm { next }
    /^concepts:/ { in_concepts = 1; next }
    in_concepts && /^[[:space:]]+aliases:/ {
      line = $0
      while (match(line, /"[^"]+"/)) {
        print tolower(substr(line, RSTART+1, RLENGTH-2))
        line = substr(line, RSTART+RLENGTH)
      }
      next
    }
    in_concepts && /^[a-zA-Z_]+:/ { in_concepts = 0 }
  ' "$skill" 2>/dev/null)" || aliases=""

  [[ -z "$aliases" ]] && continue

  matched=0
  while IFS= read -r alias; do
    [[ -z "$alias" ]] && continue
    if [[ "$PROMPT_NORM" == *"$alias"* ]]; then
      matched=1
      break
    fi
  done <<< "$aliases"
  (( matched == 0 )) && continue

  content="$(cat "$skill" 2>/dev/null || true)"
  section="### From $(basename "$skill")"$'\n\n'"$content"$'\n\n---\n\n'

  wrapper_size=120
  candidate_size=$(( ${#buffer} + ${#section} + wrapper_size ))
  if (( candidate_size > MAX_BYTES )); then
    omitted=$((omitted + 1))
    continue
  fi
  buffer="${buffer}${section}"
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

exit 0
HEREDOC
chmod +x "$TARGET/.claude/hooks/concept_match.sh"
```

### - [ ] Step 3: Insert the `/migrate-skills` command heredoc

Immediately before the `.claude/hooks/concept_match.sh` heredoc you just added, add a heredoc that writes the migrate-skills command. The contents are the full body you saved to `.claude/commands/migrate-skills.md` in Task 13. Do not retype — embed it verbatim via heredoc.

Use Edit. old_string anchor: the `# --- FILE: .claude/hooks/concept_match.sh ---` line you added in Step 2. new_string: the migrate-skills heredoc block shown below, followed by the concept_match line you already have.

Verify drift protection: after writing, run `diff <(sed -n '/cat > "$TARGET\/.claude\/commands\/migrate-skills.md"/,/^HEREDOC$/p' install-whygit.sh | sed -e '1d' -e '$d') .claude/commands/migrate-skills.md` — it should print nothing. If drift exists, installer gets out of sync with the source and users get stale behaviour.

Heredoc block to insert:

~~~bash
# --- FILE: .claude/commands/migrate-skills.md ---
cat > "$TARGET/.claude/commands/migrate-skills.md" << 'HEREDOC'
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
HEREDOC
~~~

### - [ ] Step 4: Update the embedded `curl-pipe-bash-self-contained.md` heredoc

In the installer, find the existing heredoc for the example skill (contains `# Install scripts piped from curl must be self-contained`). Insert a `concepts:` block into its frontmatter (mirroring Task 12). The installer's copy must match the repo's copy.

Old (within the heredoc — between `status: active` and the closing `---`):
```
sources:
  - ai-logs/2026-02-26-open-source-release.md
  - ai-logs/2026-02-26-install-script-security-fixes.md
status: active
---
```

New:
```
sources:
  - ai-logs/2026-02-26-open-source-release.md
  - ai-logs/2026-02-26-install-script-security-fixes.md
status: active
concepts:
  - name: piped-installer
    aliases: ["piped installer", "install script", "installer", "curl pipe bash"]
    anchors:
      - install-whygit.sh
---
```

### - [ ] Step 5: Add an idempotent `settings.json` merge

Find the block starting `if [ -f "$TARGET/CLAUDE.md" ]; then` (CLAUDE.md merge).

Immediately **before** the CLAUDE.md block, insert:

```bash
# --- FILE: .claude/settings.json (merge idempotently) ---
HOOK_CMD='bash .claude/hooks/concept_match.sh'
SETTINGS="$TARGET/.claude/settings.json"

if [ -f "$SETTINGS" ]; then
  if grep -qF "$HOOK_CMD" "$SETTINGS"; then
    echo "ℹ️  .claude/settings.json already registers concept_match.sh — skipping"
  else
    if command -v jq >/dev/null 2>&1; then
      tmp="$(mktemp)"
      jq --arg cmd "$HOOK_CMD" '
        .hooks //= {} |
        .hooks.UserPromptSubmit //= [] |
        .hooks.UserPromptSubmit += [
          { "matcher": "*", "hooks": [ { "type": "command", "command": $cmd } ] }
        ]
      ' "$SETTINGS" > "$tmp" && mv -- "$tmp" "$SETTINGS"
      echo "✨ Merged UserPromptSubmit hook into .claude/settings.json"
    else
      echo "⚠️  jq not installed — add this to .claude/settings.json manually:"
      echo '    "hooks": { "UserPromptSubmit": [ { "matcher": "*", "hooks": [ { "type": "command", "command": "bash .claude/hooks/concept_match.sh" } ] } ] }'
    fi
  fi
else
  cat > "$SETTINGS" << 'SETTINGS_EOF'
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
SETTINGS_EOF
  echo "✨ Created .claude/settings.json with concept_match hook"
fi
```

### - [ ] Step 6: Update the CLAUDE.md Skills command table

Find the `SKILLS_BLOCK=` assignment in the installer. Locate the markdown table within it:

Old:
```
| `/learn` | Mine unprocessed `ai-logs/` for learnable failures, propose skill changes |
| `/learn --log <path>` | Re-mine one specific log, ignoring the processed ledger |
| `/skills` | List current skills and any unresolved conflicts |
```

New:
```
| `/learn` | Mine unprocessed `ai-logs/` for learnable failures, propose skill changes |
| `/learn --log <path>` | Re-mine one specific log, ignoring the processed ledger |
| `/skills` | List current skills and any unresolved conflicts |
| `/migrate-skills` | Backfill v2 `concepts:` block on pre-v2 skills (one-shot) |
```

### - [ ] Step 7: Update the installation summary echoes

At the very end of the installer, find the `echo "✅ Done!` block. Add two new lines for the new artefacts:

Old:
```
echo "   $TARGET/.claude/commands/commit.md"
echo "   $TARGET/.claude/commands/log.md"
echo "   $TARGET/.claude/commands/rewind.md"
echo "   $TARGET/.claude/commands/learn.md"
echo "   $TARGET/.claude/commands/skills.md"
echo "   $TARGET/.claude/skills/"
echo "   $TARGET/ai-logs/.gitkeep"
```

New:
```
echo "   $TARGET/.claude/commands/commit.md"
echo "   $TARGET/.claude/commands/log.md"
echo "   $TARGET/.claude/commands/rewind.md"
echo "   $TARGET/.claude/commands/learn.md"
echo "   $TARGET/.claude/commands/skills.md"
echo "   $TARGET/.claude/commands/migrate-skills.md"
echo "   $TARGET/.claude/hooks/concept_match.sh"
echo "   $TARGET/.claude/settings.json"
echo "   $TARGET/.claude/skills/"
echo "   $TARGET/ai-logs/.gitkeep"
```

And add `/migrate-skills` to the usage echo block at the bottom:

Old:
```
echo "   /skills         → list current skills and conflicts"
```

New:
```
echo "   /skills         → list current skills and conflicts"
echo "   /migrate-skills → backfill concepts on pre-v2 skills"
```

### - [ ] Step 8: Run the idempotency test

```bash
bash tests/phase1/test_installer_idempotency.sh
```

Expected: PASS.

If it fails, the diff output will show what's still non-idempotent. Common cause: duplicated append in an existing file. Fix the issue before commit.

### - [ ] Step 9: Commit

```bash
git add install-whygit.sh
git commit -m "feat(install): embed v2 Phase 1 artefacts + settings merge"
```

---

## Task 18 — Update SPEC.md and README.md

**Files:**
- Modify: `SPEC.md`
- Modify: `README.md`

### - [ ] Step 1: Add a v2 Phase 1 section to SPEC.md

Use Edit. Find the `## Future Ideas` heading at the end. Immediately before it, insert:

```markdown
---

## v2 Phase 1 — Concept-Triggered Retrieval

v2 adds a `UserPromptSubmit` hook (`.claude/hooks/concept_match.sh`) that injects matching skills into Claude's context mid-session, and grows a `concepts:` block in skill frontmatter to drive retrieval by domain vocabulary rather than only file/symbol names.

### New files

- `.claude/hooks/concept_match.sh` — reads JSON from stdin, matches prompt against every skill's aliases, emits matches wrapped in a `<whygit-memory>` block on stdout (up to 9k chars, with a truncation notice if more match).
- `.claude/commands/migrate-skills.md` — slash command that backfills `concepts:` on existing v1 skills with user approval.
- `.claude/settings.json` — registers the hook.

### Updated skill frontmatter

```yaml
concepts:
  - name: <kebab-case-name>
    aliases: ["<canonical>", "<alternate phrasing>"]
    anchors:
      - <file path>
```

Skills without `concepts:` continue to load via the existing two-pass CLAUDE.md scan. They simply don't fire via concept-triggered retrieval until migrated.

### Commands

| Command | What it does |
|---|---|
| `/migrate-skills` | Scans `.claude/skills/`, proposes `concepts:` blocks for pre-v2 skills, applies on approval. Idempotent. |

### Deferred to later v2 cycles

- Automatic capture via Stop hook (`auto_capture.sh`)
- Automatic mining into drafts + `/review-skills` command
- Naming guardrail via PreToolUse hook

---
```

### - [ ] Step 2: Update README.md usage table

Find the ``` ``` usage block near the top. Old:

```
/commit              → log session reasoning + stage all + commit
/log                 → write log only, no commit
/rewind              → browse all sessions newest first
/rewind auth         → find sessions related to "auth"
/rewind 2026-02-26   → show all logs from that date
/learn               → mine ai-logs/ for reusable skills
/skills              → list active skills and unresolved conflicts
```

New:

```
/commit              → log session reasoning + stage all + commit
/log                 → write log only, no commit
/rewind              → browse all sessions newest first
/rewind auth         → find sessions related to "auth"
/rewind 2026-02-26   → show all logs from that date
/learn               → mine ai-logs/ for reusable skills
/skills              → list active skills and unresolved conflicts
/migrate-skills      → backfill concepts: on pre-v2 skills (v2 upgrade step)
```

### - [ ] Step 3: Add a v2 section to README.md

Find the `## Non-goals` heading. Immediately before it, insert:

```markdown
---

## v2: concept-triggered retrieval

whygit v2 adds a `UserPromptSubmit` hook that injects matching skills into Claude's context mid-session. Skills grow a `concepts:` block that maps domain phrases (e.g. `"installer"`, `"piped installer"`) to the skill file.

When you type a prompt containing any alias from any skill's `concepts:` block, Claude receives the full skill as context for that turn — without you having to remember it's relevant.

Existing v1 skills are unchanged; run `/migrate-skills` once to add `concepts:` to them.
```

### - [ ] Step 4: Commit

```bash
git add SPEC.md README.md
git commit -m "docs: document v2 Phase 1 concept-triggered retrieval"
```

---

## Task 19 — Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

### - [ ] Step 1: Add `/migrate-skills` to the Skill Commands table

Use Edit. Find:

```
| `/skills` | List current skills and any unresolved conflicts |
```

Replace with:

```
| `/skills` | List current skills and any unresolved conflicts |
| `/migrate-skills` | Backfill v2 `concepts:` block on pre-v2 skills (one-shot) |
```

### - [ ] Step 2: Commit

```bash
git add CLAUDE.md
git commit -m "docs(claude): add /migrate-skills to Skills command table"
```

---

## Task 20 — End-to-end sanity run

### - [ ] Step 1: Run the complete test suite

```bash
bash tests/phase1/run_all.sh
```

Expected: all 9 tests pass.

### - [ ] Step 2: Smoke test `concept_match.sh` against this repo's own skill

```bash
echo '{"hook_event_name":"UserPromptSubmit","prompt":"I want to modify the install script"}' \
  | bash .claude/hooks/concept_match.sh \
  | head -20
```

Expected: the `curl-pipe-bash-self-contained.md` skill is surfaced inside a `<whygit-memory>` block.

### - [ ] Step 3: Dry-run the installer into a fresh tmp repo

```bash
TMPREPO="$(mktemp -d)/new-repo"
mkdir -p "$TMPREPO"
git -C "$TMPREPO" init -q
bash install-whygit.sh "$TMPREPO"
ls -la "$TMPREPO/.claude/"
ls -la "$TMPREPO/.claude/hooks/"
ls -la "$TMPREPO/.claude/commands/"
cat "$TMPREPO/.claude/settings.json"
rm -rf -- "$TMPREPO"
```

Expected:
- `.claude/hooks/concept_match.sh` exists and is executable.
- `.claude/commands/migrate-skills.md` exists.
- `.claude/settings.json` has the UserPromptSubmit hook.
- Example skill is present with a `concepts:` block.

### - [ ] Step 4: Run the installer a second time against the same (cleaned) fresh repo

Run the idempotency test one more time:

```bash
bash tests/phase1/test_installer_idempotency.sh
```

Expected: PASS.

### - [ ] Step 5: Write an AI decision log

Invoke `/log` in the Claude Code session to produce a log of this Phase 1 implementation, or write by hand if the slash command isn't available from this worktree. Use the existing `ai-logs/YYYY-MM-DD-<slug>.md` template.

### - [ ] Step 6: Final commit

```bash
git add ai-logs/
git commit -m "chore(ai-logs): record v2 Phase 1 implementation session"
```

### - [ ] Step 7: Summarise status

Tell the user:
- Which tasks completed
- The final commit hash
- Any manual verification they should run inside a real Claude Code session (trigger a concept alias, confirm the skill appears in context)
