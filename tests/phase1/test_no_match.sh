#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_nomatch_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null
write_skill "$FX" "installer.md" '["installer"]'

set +e
out="$(run_hook "$FX" "what is the weather today")"
rc=$?
set -e

assert_eq "$rc" "0" "exit code"
assert_empty "$out" "no-match output"

pass "no match: empty stdout"
