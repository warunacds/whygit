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
