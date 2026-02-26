---
date: 2026-02-26
model: claude-sonnet-4-6
session_summary: Security and robustness audit of install-whygit.sh, followed by fixes
---

## What we built / changed

Audited `install-whygit.sh` and applied fixes for all identified security and robustness issues.

## Key decisions & reasoning

Six issues were fixed in `install-whygit.sh`:

1. **`$TARGET` path validation** — Resolved target to an absolute path using `cd -- "$TARGET" && pwd`, failing fast with a clear error if the path is invalid or not a directory. Prevents path traversal or unexpected write destinations.

2. **Git repo check** — Added `[ ! -d "$TARGET/.git" ]` guard before any writes. whygit commands depend on git; silently installing into a non-git dir would leave the user with broken commands.

3. **Source file existence pre-check** — All 5 source files are verified upfront before the install begins. If any are missing, the script lists what's missing and exits cleanly rather than failing mid-install.

4. **`trap` for partial-failure cleanup** — Added `trap '...' ERR` so if `set -e` fires mid-install, the user gets an actionable message instead of a silent exit.

5. **`cp --` and `mkdir --` flags** — All copy and mkdir calls now use `--` to prevent paths starting with `-` from being misinterpreted as flags.

6. **Idempotent CLAUDE.md merge** — Added `grep -qF "AI Decision Logging"` guard before appending. Re-running the installer no longer duplicates the whygit block in existing CLAUDE.md files.

## Alternatives considered

- For #6, could have used a checksum or marker comment instead of grepping for a known string. Chose the string grep as it's more readable and robust to minor formatting changes in the block.
- For #3, could have checked files lazily (at copy time). Upfront validation gives a better UX — the user sees all missing files at once rather than one at a time.

## Prompts that shaped direction

- "audit @install-whygit.sh" — triggered full security and robustness review
- "can you fix the security issues" — directed fixes to issues #1–#5 (security-classified)
- Implied #6 (idempotency) was also wanted; confirmed after the fact

## Follow-up / known limitations

- Remaining low-priority issues from the audit not yet addressed: `--help` flag (#9), dynamic file list in success output (#8).

---

## Addendum: git worktree fix

Replaced `[ ! -d "$TARGET/.git" ]` with `git -C "$TARGET" rev-parse --is-inside-work-tree > /dev/null 2>&1`.

In a worktree, `.git` is a file (not a directory) pointing back to the main repo's `.git/worktrees/` entry, so the directory check always failed. `git rev-parse --is-inside-work-tree` handles both regular repos and worktrees correctly via git's own resolution logic.
