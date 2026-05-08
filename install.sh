#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/cortex.md"

die()  { echo "error: $1" >&2; exit 1; }
step() { echo "  $1"; }

# Dependency checks
command -v git     &>/dev/null || die "git is required but not found in PATH"
command -v python3 &>/dev/null || die "python3 is required but not found in PATH"
[ -f "$SRC" ] || die "cortex.md not found at $SRC — run install.sh from the cortex directory"

echo "installing cortex..."

# 1. Install the cortex skill into Claude Code
DEST="$HOME/.claude/commands/cortex.md"
mkdir -p "$HOME/.claude/commands"
cp "$SRC" "$DEST"
step "skill → $DEST"

# 2. Configure git global template directory
TEMPLATE_DIR="$HOME/.git-templates"
mkdir -p "$TEMPLATE_DIR/hooks"
git config --global init.templateDir "$TEMPLATE_DIR" || die "failed to set git init.templateDir"
step "git init.templateDir → $TEMPLATE_DIR"

# 3. Write the global pre-push hook (back up any non-cortex hook before overwriting)
HOOK="$TEMPLATE_DIR/hooks/pre-push"
if [ -f "$HOOK" ] && ! grep -q "cortex pre-push hook" "$HOOK" 2>/dev/null; then
  BACKUP="$HOOK.bak.$(date +%s)"
  cp "$HOOK" "$BACKUP"
  step "backed up existing global hook → $BACKUP"
fi

cat > "$HOOK" << 'HOOK_BODY'
#!/bin/bash
# cortex pre-push hook — updates .cortex/ workspace on every push
# Installed globally via ~/.git-templates. Safe to delete if you remove cortex.

META=".cortex/meta.json"
ERROR_LOG=".cortex/errors.log"
LOCK_DIR=".cortex/.sync_lock"
BACKUP_DIR=".cortex/.backup"
FULL_SCAN_THRESHOLD=30
SCHEMA_VERSION=1

# Only run if .cortex/ workspace has been initialized
[ -d ".cortex" ] || exit 0

# Acquire lock — prevents race conditions when multiple devs push simultaneously
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "cortex: sync already in progress (another push?), skipping" >&2
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

log_error() {
  mkdir -p .cortex
  printf "[%s] %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$ERROR_LOG"
  echo "cortex: $1" >&2
  echo "  See .cortex/errors.log for details." >&2
}

if [ ! -f "$META" ]; then
  log_error "meta.json missing. Run /cortex install to reinitialize the workspace."
  exit 0
fi

# Schema migration — runs before any early exits so old workspaces get upgraded on next push
STORED_VERSION=$(python3 -c "import json; print(json.load(open('$META')).get('schema_version', 0))" 2>/dev/null || echo "0")
if [ "$STORED_VERSION" -lt "$SCHEMA_VERSION" ]; then
  python3 -c "
import json
with open('$META', 'r') as f:
    d = json.load(f)
d.setdefault('commits_since_full_scan', 0)
d['schema_version'] = 1
with open('$META', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null && echo "cortex: migrated workspace schema to v${SCHEMA_VERSION}" >&2
fi

HEAD=$(git rev-parse HEAD 2>/dev/null) || { log_error "git rev-parse HEAD failed"; exit 0; }

LAST=$(python3 -c "import json; print(json.load(open('$META')).get('last_commit',''))" 2>/dev/null || echo "")
COMMITS_SINCE=$(python3 -c "import json; print(json.load(open('$META')).get('commits_since_full_scan', 0))" 2>/dev/null || echo "0")

[ -z "$LAST" ] || [ "$LAST" = "$HEAD" ] && exit 0

# Validate last_commit still in history — catches rebases and force-pushes
if ! git cat-file -e "${LAST}^{commit}" 2>/dev/null; then
  log_error "last_commit $LAST is no longer in history (rebase/force-push?). Run /cortex install to resync."
  exit 0
fi

DIFF=$(git diff "$LAST".."$HEAD" --name-only 2>/dev/null || echo "")
[ -z "$DIFF" ] && exit 0

if ! command -v claude &>/dev/null; then
  log_error "claude CLI not found — auto-sync skipped. Install from https://claude.ai/code"
  exit 0
fi

# Snapshot workspace before sync — restored automatically on Claude failure
mkdir -p "$BACKUP_DIR"
for f in state.md backlog.md debt.md decisions.md meta.json; do
  [ -f ".cortex/$f" ] && cp ".cortex/$f" "$BACKUP_DIR/$f.bak"
done

NEW_COMMITS=$((COMMITS_SINCE + 1))
SYNC_EXIT=0

if [ "$COMMITS_SINCE" -ge "$FULL_SCAN_THRESHOLD" ]; then
  echo "cortex: $COMMITS_SINCE commits since last full scan — running full re-scan to evict stale entries..." >&2
  claude --print "You are refreshing a .cortex/ project intelligence workspace. This workspace has received ${COMMITS_SINCE} incremental updates without a full scan, so stale entries have likely accumulated. Do a complete fresh scan of the entire repository. Rebuild .cortex/state.md, .cortex/backlog.md, .cortex/debt.md, and .cortex/decisions.md from scratch — remove any entries that reference files, features, or modules no longer present in the repo. Do not touch .cortex/scratch.md. Update .cortex/meta.json: set last_commit to $(git rev-parse HEAD), last_updated to now (ISO 8601), scan_mode to 'fresh', schema_version to 1, commits_since_full_scan to 0." 2>/dev/null || SYNC_EXIT=$?
  NEW_COMMITS=0
else
  DIFF_CONTENT=$(git diff "$LAST".."$HEAD" 2>/dev/null | head -c 50000)
  echo "$DIFF_CONTENT" | claude --print "You are updating a .cortex/ project intelligence workspace. The diff above contains all changes since the last sync. Update .cortex/state.md, .cortex/backlog.md, .cortex/debt.md, and .cortex/decisions.md to reflect these changes. Remove any entries that reference files or features deleted in this diff. Do not touch .cortex/scratch.md. Update .cortex/meta.json: set last_commit to $(git rev-parse HEAD), last_updated to now (ISO 8601), scan_mode to 'incremental', schema_version to 1, commits_since_full_scan to ${NEW_COMMITS}." 2>/dev/null || SYNC_EXIT=$?
fi

if [ "$SYNC_EXIT" -ne 0 ]; then
  # Restore snapshot so the workspace stays in a consistent state
  for f in state.md backlog.md debt.md decisions.md meta.json; do
    [ -f "$BACKUP_DIR/$f.bak" ] && cp "$BACKUP_DIR/$f.bak" ".cortex/$f"
  done
  log_error "claude sync failed (exit $SYNC_EXIT) — workspace restored from pre-sync snapshot"
  exit 0
fi

# Verify meta.json was actually updated — if Claude skipped it, patch it ourselves
UPDATED_LAST=$(python3 -c "import json; print(json.load(open('$META')).get('last_commit',''))" 2>/dev/null || echo "")
if [ "$UPDATED_LAST" != "$HEAD" ]; then
  python3 -c "
import json, datetime
with open('$META', 'r') as f:
    d = json.load(f)
d['last_commit'] = '$HEAD'
d['last_updated'] = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
d['commits_since_full_scan'] = $NEW_COMMITS
d['schema_version'] = 1
with open('$META', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null || log_error "failed to update meta.json — next push may re-sync unnecessarily"
fi

exit 0
HOOK_BODY

chmod +x "$HOOK"
step "global hook → $HOOK"

# 4. Install hook directly into the current repo if we're inside one
if git rev-parse --git-dir &>/dev/null 2>&1; then
  GIT_HOOKS_DIR="$(git rev-parse --git-dir)/hooks"
  mkdir -p "$GIT_HOOKS_DIR"
  REPO_HOOK="$GIT_HOOKS_DIR/pre-push"
  if [ -f "$REPO_HOOK" ] && ! grep -q "cortex pre-push hook" "$REPO_HOOK" 2>/dev/null; then
    BACKUP="$REPO_HOOK.bak.$(date +%s)"
    cp "$REPO_HOOK" "$BACKUP"
    step "backed up existing repo hook → $BACKUP"
  fi
  cp "$HOOK" "$REPO_HOOK"
  chmod +x "$REPO_HOOK"
  step "repo hook  → $REPO_HOOK"
fi

echo ""

# 5. Initial workspace scan — run automatically if we're in a git repo without .cortex/ yet
if git rev-parse --git-dir &>/dev/null 2>&1 && [ ! -d ".cortex" ] && git rev-parse HEAD &>/dev/null 2>&1; then
  if command -v claude &>/dev/null; then
    REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
    HEAD_SHA=$(git rev-parse HEAD)
    echo "scanning repo for initial workspace... (this takes ~30-60s)"
    claude --print "You are setting up a .cortex/ project intelligence workspace for the first time in a repo called '${REPO_NAME}'. Read all source files and build a complete picture of the project. Then write the following files:

.cortex/state.md — what is built and live (features, brief architecture, stack)
.cortex/backlog.md — planned/in-progress items grouped by priority, sourced from TODOs/FIXMEs/READMEs
.cortex/debt.md — technical debt with specific file references where possible
.cortex/decisions.md — lightweight ADR log inferred from code structure and comments
.cortex/scratch.md — seed with a one-paragraph plain-English project summary; add a comment that this file belongs to the human and won't be overwritten
.cortex/meta.json — {\"schema_version\":1,\"project_name\":\"${REPO_NAME}\",\"created_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"last_updated\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"last_commit\":\"${HEAD_SHA}\",\"scan_mode\":\"fresh\",\"baseline_commit\":\"${HEAD_SHA}\",\"commits_since_full_scan\":0}

Also append .cortex/ to .gitignore if not already present (create .gitignore if missing)." 2>/dev/null \
      && echo "✓ done. Workspace written to .cortex/" \
      || echo "! scan failed — run /cortex install manually to create the workspace"
  else
    echo "✓ done. claude CLI not found — run /cortex install in any repo to create the workspace."
  fi
else
  echo "✓ done. Run /cortex install in any repo to do the initial scan."
fi
