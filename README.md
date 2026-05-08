# cortex

A Claude Code skill that gives your codebase a private PM brain — and keeps it updated automatically on every git push.

Run `/cortex install` once in any repo. cortex scans the project, writes a structured `.cortex/` workspace (state, backlog, debt, decisions, scratch), and installs a local `pre-push` hook that diffs your changes and updates the workspace on every push. The files are local-only, gitignored, and readable by any coding agent.

---

## Install

**Option 1 — curl**
```bash
curl -fsSL https://raw.githubusercontent.com/shreyjain203/cortex/main/install.sh | bash
```

**Option 2 — clone**
```bash
git clone https://github.com/shreyjain203/cortex.git
cd cortex && bash install.sh
```

Then in any repo:
```
/cortex install
```

---

## What it creates

```
.cortex/
  state.md        — what's built and live (compact, LLM-readable)
  backlog.md      — what's planned, prioritised
  debt.md         — what to remove, clean, fix
  decisions.md    — why things were built the way they were (lightweight ADRs)
  scratch.md      — free-form: blog drafts, pitch notes, braindumps
  meta.json       — last_commit, project_name, created_at, scan_mode
```

All files are in `.gitignore`. They never leave your machine.

---

## How it works

1. `/cortex install` does a full repo scan and writes `.cortex/` from scratch.
2. A `pre-push` hook is written to `.git/hooks/pre-push`.
3. On every `git push`, the hook diffs the changed files since the last sync and calls Claude to update `.cortex/` — state, backlog, debt, decisions. `scratch.md` is never touched.
4. `meta.json` tracks `last_commit` so each update is a minimal diff, not a full rescan.

First install: ~50–100k tokens. Every subsequent push: ~5–20k tokens (diff only).

---

## Agent-agnostic

The `.cortex/` workspace is plain markdown and JSON. Any coding agent that reads files — Cursor, Copilot, Aider, your own scripts — benefits from it automatically. The skill file (`cortex.md`) is Claude Code-specific, but the workspace it creates is not.
