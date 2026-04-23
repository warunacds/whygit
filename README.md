# whygit

> Claude Code remembers the *why* behind your codebase — and surfaces it just-in-time as you work.

Git records what changed. **whygit** records why. It captures the reasoning behind AI-assisted code changes, mines them into durable guardrails, and — as of v2 — injects the right guardrail into Claude's context the moment a prompt needs it. No dashboard. No API. Just markdown files in your repo.

---

## Install

**One-liner (curl):**

```bash
curl -fsSL https://raw.githubusercontent.com/warunacds/whygit/main/install-whygit.sh | bash
```

This installs whygit into the current directory (must be a git repo).

To install into a specific repo:

```bash
curl -fsSL https://raw.githubusercontent.com/warunacds/whygit/main/install-whygit.sh -o install-whygit.sh
chmod +x install-whygit.sh
./install-whygit.sh /path/to/your/repo
```

**Manual:**

```bash
git clone https://github.com/warunacds/whygit.git
cd whygit
./install-whygit.sh /path/to/your/repo
```

Then commit the installed files:

```bash
git add . && git commit -m "chore: add whygit (AI decision logs + skills)"
```

---

## What v2 gives you

Ask Claude to "fix the install script" and — without being prompted — it already knows the three scars your installer has accumulated: `$BASH_SOURCE[0]` is empty under `curl | bash`, the `ERR` trap has to come after input validation, `cp --` guards against dash-prefixed paths. Those facts live in a skill file in your repo. The moment you typed "install script", whygit's hook matched the phrase against the skill's aliases and injected the full guardrail into Claude's context for that turn.

Before v2, skills loaded once at session start. If a skill's trigger didn't match your opening prompt, it never fired — even when you asked about the same thing ten minutes later using different words. v2 closes that gap.

### Concept-triggered retrieval in action

```text
You:    "let me know before I update the installer script"
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ Claude Code fires UserPromptSubmit hook                     │
│                                                             │
│   .claude/hooks/concept_match.sh                            │
│     reads JSON on stdin, extracts the prompt,               │
│     scans each .claude/skills/*.md for matching aliases,    │
│     emits matching skills wrapped in <whygit-memory>        │
└─────────────────────────────────────────────────────────────┘
        │
        ▼ stdout is injected into Claude's turn context
        ▼
<whygit-memory>
Relevant prior decisions from this codebase's memory:

### From curl-pipe-bash-self-contained.md

# Install scripts piped from curl must be self-contained

## Guardrails
1. Never use $BASH_SOURCE[0] in a script intended for piped execution…
2. Embed every file the installer writes as a heredoc…
...
</whygit-memory>

Claude: "Before I touch install-whygit.sh — there are seven guardrails on
        this file captured from two prior incidents. Want me to walk through
        them first, or should I just keep them in mind while I work?"
```

### Skill file shape (v2)

```yaml
---
id: curl-pipe-bash-self-contained
created: 2026-04-09
updated: 2026-04-23
sources:
  - ai-logs/2026-02-26-open-source-release.md
status: active
concepts:
  - name: piped-installer
    aliases: ["piped installer", "install script", "installer", "curl pipe bash"]
    anchors:
      - install-whygit.sh
---

# Install scripts piped from curl must be self-contained

## When to apply
- Writing a shell script users will run via `curl -fsSL ... | bash`
- …

## Guardrails
1. Never use `$BASH_SOURCE[0]` in piped execution — it is empty.
2. …
```

- **Concept:** a domain-level noun phrase a developer on this codebase would use in conversation.
- **Aliases:** 2–4 phrasings a developer or LLM might use. The canonical name is always in the list.
- **Anchors:** 1–3 file paths that implement the concept.

Retrieval is a case-insensitive substring match: any alias contained in your prompt (in any casing) fires the skill.

---

## Upgrade guide (v1 → v2)

If you already installed whygit v1, this is the full upgrade flow:

### 1. Re-run the installer

```bash
curl -fsSL https://raw.githubusercontent.com/warunacds/whygit/main/install-whygit.sh | bash
```

The installer is idempotent. It adds the new v2 artefacts without touching your existing logs, skills, or commands:

- Creates `.claude/hooks/concept_match.sh`
- Adds `.claude/commands/migrate-skills.md`
- Merges `.claude/settings.json` (preserves your existing hooks and permissions)
- Appends the `/migrate-skills` row to CLAUDE.md's Skills table

### 2. Backfill concepts on your existing skills

```
/migrate-skills
```

This scans `.claude/skills/` for pre-v2 skills (those without a `concepts:` block), reads each skill plus its source logs, proposes a `concepts:` block for each, and asks for batch approval. Nothing is written until you say `y` or `select`.

### 3. Commit

```bash
git add .claude ai-logs CLAUDE.md
git commit -m "chore: upgrade whygit to v2 (concept-triggered retrieval)"
```

### 4. Verify

Start a fresh Claude Code session. Type a prompt that contains one of your migrated skills' aliases. Claude should reference the skill's guardrails without being prompted to — that's the retrieval working.

If you installed whygit for the first time with v2, you have nothing to migrate — `/learn` already emits `concepts:` on every new skill.

---

## Usage

```
/commit              → log session reasoning + stage all + commit
/log                 → write log only, no commit
/rewind              → browse all sessions newest first
/rewind auth         → find sessions related to "auth"
/rewind 2026-02-26   → show all logs from that date
/learn               → mine ai-logs/ for reusable skills
/skills              → list active skills and unresolved conflicts
/migrate-skills      → backfill concepts: on pre-v2 skills (v2 upgrade step)
```

---

## How it works

whygit installs slash commands, a CLAUDE.md directive, a settings.json hook entry, and a single hook script into your repo:

```
your-repo/
├── CLAUDE.md                        # Rules Claude follows in this repo
├── .claude/
│   ├── commands/
│   │   ├── commit.md                # /commit
│   │   ├── log.md                   # /log
│   │   ├── rewind.md                # /rewind
│   │   ├── learn.md                 # /learn
│   │   ├── skills.md                # /skills
│   │   └── migrate-skills.md        # /migrate-skills  (v2)
│   ├── hooks/
│   │   └── concept_match.sh         # UserPromptSubmit hook  (v2)
│   ├── settings.json                # Registers the hook  (v2)
│   └── skills/
│       ├── curl-pipe-bash-self-contained.md
│       └── ...
└── ai-logs/
    ├── 2026-02-26-auth-refactor.md
    ├── 2026-02-24-payment-webhooks.md
    └── ...
```

### Logs capture

- What was built or changed
- Key decisions and reasoning
- Alternatives considered
- Prompts that shaped direction
- Known limitations and follow-up

Logs are plain markdown. They live in your repo. They're committed with your code. Nothing leaves your machine.

### The learning loop

1. **`/commit`** captures the reasoning from a session as a new log.
2. **`/learn`** mines unprocessed logs for wrong turns, reversed decisions, or context that would have changed the approach. It drafts skills (with `concepts:` blocks) and asks for approval.
3. **`concept_match.sh`** runs on every user prompt, injecting any skill whose aliases appear in the prompt.
4. **`/skills`** lists what's in your rulebook today.

Every mutation is human-approved. Nothing is silently written.

---

## Comparison

|  | whygit | entire.io |
|--|--------|-----------|
| Capture method | On-demand via `/commit` | Automatic, continuous |
| Content | Curated summary + extracted guardrails | Full transcript + tool calls |
| Storage | `ai-logs/` and `.claude/skills/` in your repo | Hidden git branch |
| Retrieval | Concept-triggered via hook (v2) | Checkpoint restore |
| Dependencies | None (jq optional) | CLI + account |
| Privacy | Fully local | Cloud dashboard |
| Cost | Free | TBD |

**Philosophy:** entire.io captures everything automatically. whygit captures curated reasoning on demand and surfaces the right guardrail at the right moment. They're complementary — entire.io is the raw tape, whygit is the edited highlights that show up when you need them.

---

## Non-goals

- Not a replacement for good commit messages
- Not a full session transcript tool
- Not a web dashboard
- Not dependent on any external API at commit time or prompt time
- Not automatic (every skill, every log, every migration is human-approved)

---

## License

MIT — see [LICENSE](LICENSE)
