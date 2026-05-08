# cortex

A Claude Code skill that gives your codebase a private PM brain — and keeps it updated automatically on every git push.

Run `bash install.sh` once on your machine. cortex installs globally: it configures a git template directory so every new `git init` automatically gets the pre-push hook. Existing repos need one `git init` to pick it up. Then run `/cortex install` in a repo to do the initial scan and write the `.cortex/` workspace.

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

That's it. The pre-push hook is now global — no per-repo setup required for future repos.

**Existing repos:** run `git init` once in the repo root to copy the hook from the template:
```bash
cd your-existing-repo
git init
```

Then run `/cortex install` in that repo to do the initial scan.

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

1. `bash install.sh` sets `git config --global init.templateDir ~/.git-templates` and writes a `pre-push` hook to `~/.git-templates/hooks/pre-push`.
2. Every new `git init` (or an explicit `git init` in an existing repo) copies the hook from the template into `.git/hooks/pre-push`.
3. Run `/cortex install` once per repo to do a full scan and write `.cortex/`.
4. On every `git push`, the hook diffs the changed files since the last sync and calls Claude to update `.cortex/` — state, backlog, debt, decisions. `scratch.md` is never touched.
5. `meta.json` tracks `last_commit` so each update is a minimal diff, not a full rescan.

First install: ~50–100k tokens. Every subsequent push: ~5–20k tokens (diff only).

---

## Agent-agnostic

The `.cortex/` workspace is plain markdown and JSON. Any coding agent that reads files — Cursor, Copilot, Aider, your own scripts — benefits from it automatically. The skill file (`cortex.md`) is Claude Code-specific, but the workspace it creates is not.
