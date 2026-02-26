---
date: 2026-02-26
model: claude-sonnet-4-6
session_summary: Designed and shipped whygit as a public open source project on GitHub
---

## What we built / changed

Released whygit as a public open source repository at https://github.com/warunacds/whygit.

Files added:
- `LICENSE` — MIT license, 2026, author Waruna
- `README.md` — full public-facing docs: tagline, install instructions (curl + manual), usage, how it works, comparison table, non-goals
- `.gitignore` — excludes `.DS_Store`, `.claude/settings.local.json`, `docs/plans/`
- `docs/plans/2026-02-26-open-source-release-design.md` — design doc (gitignored from public)
- `docs/plans/2026-02-26-open-source-release.md` — implementation plan (gitignored from public)

Files rewritten:
- `install-whygit.sh` — made fully self-contained by embedding all file contents as heredocs; removed `SCRIPT_DIR`/`BASH_SOURCE` dependency so `curl | bash` works correctly

Files fixed:
- `install-whygit.sh` — moved ERR trap after input validation block to avoid misleading "partially installed" error on validation failures
- `README.md`, `SPEC.md`, `.claude/commands/rewind.md` — updated stale 2025 example dates to 2026
- GitHub repo created and all commits pushed via `gh repo create`

## Key decisions & reasoning

**Self-contained install script (Option C)**
The original script used `SCRIPT_DIR` (via `BASH_SOURCE[0]`) to find source files to copy. When piped from `curl | bash`, `BASH_SOURCE[0]` is empty so the script immediately fails. The fix was to embed all file contents as heredocs directly in the script — no external files needed. This makes `curl -fsSL .../install-whygit.sh | bash` genuinely work with no prerequisites.

**MIT license**
Maximum permissiveness, widest adoption, no friction. Right call for a zero-dependency developer tool targeting solo Claude Code users.

**GitHub-only distribution (no Homebrew, npm, or hosted domain)**
Kept scope minimal for the initial release. curl installer points to raw GitHub URL — no hosting cost, no infrastructure, works immediately on repo creation.

**docs/plans/ gitignored**
The planning documents contained `YOUR_USERNAME` placeholder text (from the brainstorming/planning session). Rather than clean up internal scaffolding for public consumption, the cleaner decision was to gitignore the entire `docs/plans/` directory — these are implementation artifacts, not public documentation.

**ERR trap placement**
The trap was originally registered before input validation, causing users who passed a non-git directory to see both a clear error message AND a spurious "partially installed" warning. Moving the trap to after the validation block means it only fires during actual installation.

## Alternatives considered

**Option A (git clone only)** — Remove curl paths, document only git clone. Honest and works today, but worse UX. Rejected in favour of making the script truly self-contained.

**Option B (curl that clones then runs)** — Keep curl but have it clone the repo first. Adds complexity, still requires git. Rejected.

**Homebrew / npm / npx distribution** — Broader reach but more maintenance overhead. Out of scope for MVP release.

**Staged/private beta release** — Share with trusted devs before going public. Rejected as over-cautious given the project is clean and well-specced.

## Prompts that shaped direction

- User wanted to release whygit as open source, with community adoption as primary goal and credibility as secondary
- Solo Claude Code users as the target audience (not teams)
- MIT license explicitly chosen
- GitHub-only + curl installer as the distribution approach
- When the curl installer was found to be broken (self-contained issue), user chose Option C: make the script embed all files inline
- User asked to use `gh` to create and push the repo directly rather than doing it manually through the GitHub web UI

## Follow-up / known limitations

- Curl installer verified locally but not yet tested from the live public URL (repo was just made public)
- No CONTRIBUTING.md or issue templates yet — fine for initial release, worth adding if community traction develops
- No GitHub Actions to validate installs on PRs
- `docs/plans/` is gitignored so planning docs are local-only — if future contributors join, a different approach to sharing plans may be needed
- The `/rewind` example output in the rewind command shows fictional log filenames — could be replaced with a real example once the project has more actual usage history
