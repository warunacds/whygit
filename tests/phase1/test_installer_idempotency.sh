#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_installer_$$"
trap "rm -rf -- $FX" EXIT

rm -rf -- "$FX"
mkdir -p -- "$FX"
git -C "$FX" init -q

bash "$REPO_ROOT/install-whygit.sh" "$FX" >/dev/null

snap_dir=$(mktemp -d)
cp -R -- "$FX" "$snap_dir/after_first"

bash "$REPO_ROOT/install-whygit.sh" "$FX" >/dev/null

diff -r --exclude=".git" -- "$snap_dir/after_first" "$FX" > "$snap_dir/diff.txt" || true

if [[ -s "$snap_dir/diff.txt" ]]; then
  echo "FAIL: installer is not idempotent. Diff:" >&2
  cat "$snap_dir/diff.txt" >&2
  rm -rf -- "$snap_dir"
  exit 1
fi

rm -rf -- "$snap_dir"
pass "installer is idempotent across two runs"
