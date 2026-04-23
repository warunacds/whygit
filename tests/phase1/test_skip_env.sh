#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_skip_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null
write_skill "$FX" "installer.md" '["installer"]'

payload='{"hook_event_name":"UserPromptSubmit","prompt":"installer"}'
out=$(WHYGIT_SKIP_HOOKS=1 CLAUDE_PROJECT_DIR="$FX" bash "$HOOK" <<< "$payload")

assert_empty "$out" "skip env bypasses hook"

pass "WHYGIT_SKIP_HOOKS=1 bypasses all matching"
