#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helpers.sh"

FX="/tmp/whygit_phase1_budget_$$"
trap "rm -rf -- $FX" EXIT

mk_fixture "$FX" >/dev/null

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
