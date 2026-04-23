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
