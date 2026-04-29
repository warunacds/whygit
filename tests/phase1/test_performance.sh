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
