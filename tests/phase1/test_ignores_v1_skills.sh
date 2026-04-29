#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_v1_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null
write_v1_skill "$FX" "v1-only.md"

set +e
out="$(run_hook "$FX" "anything v1 trigger at all")"
set -e

assert_empty "$out" "v1 skills do not match"

pass "v1 skills: no concepts block means no match"
