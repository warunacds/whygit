# whygit

> Capture the *why* behind AI-assisted code changes, committed alongside the code itself.

Git records what changed. **whygit** records why — the reasoning, the alternatives considered, the prompts that shaped the direction. One command at the end of a Claude Code session. Everything committed as markdown, living alongside your code.

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
git add . && git commit -m "chore: add AI decision logging"
```

---

## Usage

In any Claude Code session:

```
/commit              → log session reasoning + stage all + commit
/log                 → write log only, no commit
/rewind              → browse all sessions newest first
/rewind auth         → find sessions related to "auth"
/rewind 2026-02-26   → show all logs from that date
```

That's it.

---

## How it works

whygit installs three Claude Code slash commands and a `CLAUDE.md` directive into your repo:

```
your-repo/
├── CLAUDE.md                        # Tells Claude to log reasoning
├── .claude/
│   └── commands/
│       ├── commit.md                # /commit slash command
│       ├── log.md                   # /log slash command
│       └── rewind.md                # /rewind slash command
└── ai-logs/
    ├── 2026-02-26-auth-refactor.md
    ├── 2026-02-24-payment-webhooks.md
    └── ...
```

Each log captures:
- What was built or changed
- Key decisions and reasoning
- Alternatives considered
- Prompts that shaped direction
- Known limitations and follow-up

Logs are plain markdown. They live in your repo. They're committed with your code. Nothing leaves your machine.

---

## Comparison

|  | whygit | entire.io |
|--|--------|-----------|
| Capture method | On-demand via `/commit` | Automatic, continuous |
| Content | Curated summary | Full transcript + tool calls |
| Storage | `ai-logs/` in your repo | Hidden git branch |
| Dependencies | None | CLI + account |
| Privacy | Fully local | Cloud dashboard |
| Cost | Free | TBD |

**Philosophy:** entire.io captures everything automatically. whygit captures curated reasoning on demand. They're complementary — entire.io is the raw tape, whygit is the edited highlights.

---

## Non-goals

- Not a replacement for good commit messages
- Not a full session transcript tool
- Not a web dashboard
- Not dependent on any external API at commit time

---

## License

MIT — see [LICENSE](LICENSE)
