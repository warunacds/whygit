---
id: curl-pipe-bash-self-contained
created: 2026-04-09
updated: 2026-04-09
sources:
  - ai-logs/2026-02-26-open-source-release.md
  - ai-logs/2026-02-26-install-script-security-fixes.md
status: active
---

# Install scripts piped from curl must be self-contained

## When to apply

- Writing a shell script users will run via `curl -fsSL ... | bash`
- Any installer that copies or references files relative to itself
- Changing an existing installer to support piped execution
- Adding new files that need to ship with an existing piped installer

## When NOT to apply

- Scripts only ever run locally after `git clone`
- Scripts the user has already downloaded and invokes by path
- Scripts whose only job is to `curl` a second payload (those can assume network)

## Guardrails

1. Never use `$BASH_SOURCE[0]`, `${0}`, or any "find my own directory" pattern
   in a script intended for piped execution. Under `curl | bash`, `$BASH_SOURCE[0]`
   is empty so the script fails immediately on the first file operation.
2. Embed every file the installer needs to write as a heredoc (`cat > "$TARGET/path" << 'HERE_DOC' ... HERE_DOC`) directly inside the installer. The script must carry its own payload — no reliance on files in a sibling directory.
3. Use quoted `'HERE_DOC'` (with single quotes) for embedded file contents so shell variables and backticks inside the content are not expanded at install time.
4. Before shipping a change to a piped installer, mentally trace execution with
   `$BASH_SOURCE[0]` set to empty string and confirm every path still resolves.
5. Register any `trap '...' ERR` **after** input validation, not before. Otherwise
   users who pass a bad target see both a clear validation error and a spurious
   "partially installed" warning from the trap.
6. Use `cp --` and `mkdir --` (with the `--` flag) so target paths starting with
   `-` are not misinterpreted as flags.
7. Make CLAUDE.md / config appends idempotent by grepping for a known marker
   string before writing. Re-running the installer must not duplicate blocks.

## Why this exists

Captured from `ai-logs/2026-02-26-open-source-release.md` and
`ai-logs/2026-02-26-install-script-security-fixes.md`.

The original whygit install script used `SCRIPT_DIR` via `BASH_SOURCE[0]` to
locate source files to copy. When a user ran the one-liner
`curl -fsSL .../install-whygit.sh | bash`, `$BASH_SOURCE[0]` was empty, so
`SCRIPT_DIR` resolved to nothing, and the very first `cp` call failed. The
distribution story — "one command, zero dependencies" — was broken.

The fix was to embed every file's contents as heredocs directly inside the
installer and drop the `SCRIPT_DIR` pattern entirely. A follow-up security
pass added input validation, the `trap` repositioning, `cp --` flags, and the
idempotent CLAUDE.md merge. This skill exists so the next person adding a
feature to the installer doesn't re-introduce any of those failure modes.
