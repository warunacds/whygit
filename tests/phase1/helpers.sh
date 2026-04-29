#!/usr/bin/env bash
# Shared test helpers for phase1. Source with: . "$(dirname "$0")/helpers.sh"

TESTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_ROOT/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/concept_match.sh"

mk_fixture() {
  local dir="$1"
  rm -rf -- "$dir"
  mkdir -p -- "$dir/.claude/skills"
  echo "$dir"
}

write_skill() {
  local fixture="$1"
  local filename="$2"
  local aliases="$3"
  local title="${4:-Test skill $filename}"
  local body="${5:-Guardrail body for $filename.}"

  cat > "$fixture/.claude/skills/$filename" <<EOF
---
id: ${filename%.md}
created: 2026-04-23
updated: 2026-04-23
sources:
  - ai-logs/test.md
status: active
concepts:
  - name: test-concept
    aliases: $aliases
    anchors:
      - test.txt
---

# $title

## When to apply
- test trigger

## Guardrails
1. $body
EOF
}

write_v1_skill() {
  local fixture="$1"
  local filename="$2"

  cat > "$fixture/.claude/skills/$filename" <<EOF
---
id: ${filename%.md}
created: 2026-04-23
sources:
  - ai-logs/test.md
status: active
---

# V1 skill

## When to apply
- v1 trigger
EOF
}

run_hook() {
  local fixture="$1"
  local prompt="$2"
  local payload
  payload=$(printf '%s' "$prompt" | python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"UserPromptSubmit","prompt":sys.stdin.read()}))' 2>/dev/null) || {
    if command -v jq >/dev/null 2>&1; then
      payload=$(jq -cn --arg p "$prompt" '{hook_event_name:"UserPromptSubmit",prompt:$p}')
    else
      local esc
      esc=$(printf '%s' "$prompt" | sed 's/\\/\\\\/g; s/"/\\"/g')
      payload="{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"$esc\"}"
    fi
  }
  CLAUDE_PROJECT_DIR="$fixture" bash "$HOOK" <<< "$payload"
}

assert_eq() {
  if [[ "$1" != "$2" ]]; then
    echo "FAIL [$3]: expected '$2' got '$1'" >&2
    exit 1
  fi
}

assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    echo "FAIL [$3]: expected substring '$2' in output" >&2
    echo "----- output -----" >&2
    echo "$1" >&2
    echo "----- /output -----" >&2
    exit 1
  fi
}

assert_not_contains() {
  if [[ "$1" == *"$2"* ]]; then
    echo "FAIL [$3]: did not expect substring '$2' in output" >&2
    exit 1
  fi
}

assert_empty() {
  if [[ -n "$1" ]]; then
    echo "FAIL [$2]: expected empty output, got:" >&2
    echo "$1" >&2
    exit 1
  fi
}

pass() {
  echo "PASS: $1"
}
