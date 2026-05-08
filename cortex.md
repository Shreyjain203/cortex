# cortex

Bootstrap and maintain a private project intelligence workspace in `.cortex/`. Runs a full scan on first install, then diffs on every subsequent push via a git hook. The workspace is local-only and agent-agnostic.

## Usage

```
/cortex install   — first-time setup on a repo
/cortex           — manual sync (hook does this automatically on push)
```

---

## Instructions

When this skill is invoked, follow the steps below exactly.

### Step 1 — Detect mode

Check whether `.cortex/meta.json` exists.

- **Exists** → read it. Note `last_commit`. Mode = **incremental**.
- **Missing** → Mode = **fresh**.

### Step 2 — Find baseline commit

Run `git log --oneline` (limit 1). If git history exists, note the oldest commit SHA as `baseline_commit`. If the repo has no commits yet, set `baseline_commit = "HEAD"`.

For **incremental** mode, `baseline_commit` = the `last_commit` value from `meta.json`.

### Step 3 — Scan the repo

**Fresh mode:** Read all source files. Build a complete picture of:
- What the project does
- What is built and live
- What is planned or in-progress (TODOs, comments, READMEs)
- Obvious technical debt (dead code, duplicated logic, hardcoded values, missing error handling)
- Any architectural decisions that are implicit in the code

**Incremental mode:** Run `git diff <last_commit>..HEAD --name-only` to get changed files. Read only those files plus any files they directly import/reference. Build a delta picture of what changed.

### Step 4 — Write `.cortex/` workspace files

Create the `.cortex/` directory if it doesn't exist. Write or update the following files:

#### `.cortex/state.md`
What is built and live. Format:
```
# State
_Last updated: <date>_

## What exists
- <feature or module>: <one-line description of current state>
- ...

## Architecture (brief)
<2-4 sentences on how the system fits together>

## Stack
<language, frameworks, key dependencies>
```

#### `.cortex/backlog.md`
What is planned or in-progress. Populate from TODOs, FIXMEs, README future-work sections, and any comments signaling intent. Format:
```
# Backlog
_Last updated: <date>_

## High priority
- [ ] <item>

## Medium priority
- [ ] <item>

## Low priority / ideas
- [ ] <item>
```

#### `.cortex/debt.md`
What should be cleaned up, removed, or fixed. Be specific — name the file and line if possible. Format:
```
# Technical Debt
_Last updated: <date>_

- **<file or module>**: <what the problem is and why it matters>
- ...
```

#### `.cortex/decisions.md`
Lightweight ADR log — why things were built the way they were. Infer from code structure, comments, and naming. Format:
```
# Decisions
_Last updated: <date>_

## <short title>
**Date inferred:** <date or "unknown">
**Decision:** <what was decided>
**Rationale:** <why, as best as can be inferred>
**Consequences:** <what this locks in or rules out>

---
```

#### `.cortex/scratch.md`
Free-form space for notes, blog drafts, pitch ideas, or braindumps. On first install, seed it with a one-paragraph project summary in plain English — written as if explaining the project to a new engineer. Leave a clear comment at the top that this file is for human use.

```
# Scratch
<!-- This file is yours. Notes, drafts, pitches, braindumps. cortex won't overwrite content here. -->

## Project summary (auto-generated, feel free to rewrite)
<plain English summary>
```

**Important:** On incremental updates, never overwrite `scratch.md`. It belongs to the human.

#### `.cortex/meta.json`
```json
{
  "project_name": "<inferred from repo folder name or package.json/Cargo.toml/etc>",
  "created_at": "<ISO timestamp of first install>",
  "last_updated": "<ISO timestamp of this run>",
  "last_commit": "<current HEAD SHA>",
  "scan_mode": "fresh | incremental",
  "baseline_commit": "<SHA or HEAD>"
}
```

On incremental runs, preserve `created_at` and `baseline_commit` from the existing `meta.json`. Update only `last_updated`, `last_commit`, and `scan_mode`.

### Step 5 — Verify the pre-push git hook

The pre-push hook is installed globally by `bash install.sh` via `~/.git-templates/hooks/pre-push`. It is copied automatically into every repo on `git init` — no per-repo hook writing is needed.

Check that the hook is present in the current repo:

```bash
ls .git/hooks/pre-push
```

If it is missing (the user hasn't run `git init` since installing cortex), print:

```
Note: global pre-push hook not found in .git/hooks/. Run 'git init' in this repo root to copy it from ~/.git-templates, then push to activate auto-sync.
```

Do not write a new hook file here. The source of truth is `~/.git-templates/hooks/pre-push`.

### Step 6 — Update `.gitignore`

Check if `.gitignore` exists. If yes, append `.cortex/` only if it's not already present. If no `.gitignore` exists, create one with `.cortex/` as the first entry.

### Step 7 — Confirm

Print a brief summary:
```
cortex installed.

.cortex/
  state.md       ✓
  backlog.md     ✓
  debt.md        ✓
  decisions.md   ✓
  scratch.md     ✓
  meta.json      ✓

pre-push hook → ~/.git-templates/hooks/pre-push (global) ✓
.gitignore updated ✓

Workspace is local-only. It will update automatically on every git push.
Run /cortex anytime to sync manually.
```

---

## Manual sync (`/cortex` with no args)

If invoked without `install`, run Steps 1–4 only (incremental mode, skip hook and gitignore steps). Confirm with a one-liner: `cortex synced. <N> files diffed.`
