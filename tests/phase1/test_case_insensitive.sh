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
