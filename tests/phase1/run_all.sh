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
