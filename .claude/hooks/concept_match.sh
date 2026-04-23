#!/usr/bin/env bash
# whygit v2 concept-match hook for UserPromptSubmit.
# Reads JSON on stdin, emits matching skills wrapped in <whygit-memory> on stdout.
# Must never exit non-zero; hook failures must never block the user.

set -u

if [[ "${WHYGIT_SKIP_HOOKS:-0}" == "1" ]]; then
  exit 0
fi

SKILLS_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills"
[[ -d "$SKILLS_DIR" ]] || exit 0

MAX_BYTES=9000

STDIN="$(cat 2>/dev/null || true)"
[[ -z "$STDIN" ]] && exit 0

if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$STDIN" | jq -r '.prompt // empty' 2>/dev/null || true)"
else
  PROMPT="$(printf '%s' "$STDIN" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | head -1)"
fi
[[ -z "$PROMPT" ]] && exit 0

PROMPT_NORM="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')"

buffer=""
emitted=0
omitted=0

shopt -s nullglob
for skill in "$SKILLS_DIR"/*.md; do
  [[ -f "$skill" ]] || continue

  aliases="$(awk '
    BEGIN { fm = 0; in_concepts = 0 }
    /^---[[:space:]]*$/ { fm = !fm; next }
    !fm { next }
    /^concepts:/ { in_concepts = 1; next }
    in_concepts && /^[[:space:]]+aliases:/ {
      line = $0
      while (match(line, /"[^"]+"/)) {
        print tolower(substr(line, RSTART+1, RLENGTH-2))
        line = substr(line, RSTART+RLENGTH)
      }
      next
    }
    in_concepts && /^[a-zA-Z_]+:/ { in_concepts = 0 }
  ' "$skill" 2>/dev/null)" || aliases=""

  [[ -z "$aliases" ]] && continue

  matched=0
  while IFS= read -r alias; do
    [[ -z "$alias" ]] && continue
    if [[ "$PROMPT_NORM" == *"$alias"* ]]; then
      matched=1
      break
    fi
  done <<< "$aliases"
  (( matched == 0 )) && continue

  content="$(cat "$skill" 2>/dev/null || true)"
  section="### From $(basename "$skill")"$'\n\n'"$content"$'\n\n---\n\n'

  wrapper_size=120
  candidate_size=$(( ${#buffer} + ${#section} + wrapper_size ))
  if (( candidate_size > MAX_BYTES )); then
    omitted=$((omitted + 1))
    continue
  fi
  buffer="${buffer}${section}"
  emitted=$((emitted + 1))
done

if (( emitted > 0 )); then
  printf '<whygit-memory>\n'
  printf "Relevant prior decisions from this codebase's memory:\n\n"
  printf '%s' "$buffer"
  if (( omitted > 0 )); then
    printf '(%d additional matching skills omitted — run /skills to browse)\n' "$omitted"
  fi
  printf '</whygit-memory>\n'
fi

exit 0
