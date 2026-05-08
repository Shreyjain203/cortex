#!/bin/bash
set -e

DEST="$HOME/.claude/commands/cortex.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/cortex.md"

# 1. Install the cortex skill into Claude Code
mkdir -p "$HOME/.claude/commands"
cp "$SRC" "$DEST"

# 2. Configure git global template directory
TEMPLATE_DIR="$HOME/.git-templates"
mkdir -p "$TEMPLATE_DIR/hooks"
git config --global init.templateDir "$TEMPLATE_DIR"

# 3. Write the global pre-push hook
HOOK="$TEMPLATE_DIR/hooks/pre-push"

cat > "$HOOK" << 'HOOK_BODY'
#!/bin/bash
# cortex pre-push hook — updates .cortex/ workspace on every push
# Installed globally via ~/.git-templates. Safe to delete if you remove cortex.

META=".cortex/meta.json"
ERROR_LOG=".cortex/errors.log"
LOCK_DIR=".cortex/.sync_lock"
FULL_SCAN_THRESHOLD=30

# Only run if .cortex/ workspace has been initialized
[ -d ".cortex" ] || exit 0

# Acquire lock — prevents race conditions when multiple devs push simultaneously
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "cortex: sync already in progress (another push?), skipping" >&2
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

log_error() {
  printf "[%s] %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$ERROR_LOG"
  echo "cortex: $1" >&2
  echo "  See .cortex/errors.log for details." >&2
}

if [ ! -f "$META" ]; then
  log_error "meta.json missing. Run /cortex install to reinitialize the workspace."
  exit 0
fi

HEAD=$(git rev-parse HEAD 2>/dev/null) || { log_error "git rev-parse HEAD failed"; exit 0; }

LAST=$(python3 -c "import json; print(json.load(open('$META')).get('last_commit',''))" 2>/dev/null || echo "")
COMMITS_SINCE=$(python3 -c "import json; print(json.load(open('$META')).get('commits_since_full_scan', 0))" 2>/dev/null || echo "0")

[ -z "$LAST" ] || [ "$LAST" = "$HEAD" ] && exit 0

# Validate last_commit still in history — handles rebases and force-pushes
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

NEW_COMMITS=$((COMMITS_SINCE + 1))
SYNC_EXIT=0

if [ "$COMMITS_SINCE" -ge "$FULL_SCAN_THRESHOLD" ]; then
  # Drift threshold reached — full re-scan evicts stale entries accumulated over time
  echo "cortex: $COMMITS_SINCE commits since last full scan — running full re-scan to evict stale entries..." >&2
  claude --print "You are refreshing a .cortex/ project intelligence workspace. This workspace has received ${COMMITS_SINCE} incremental updates without a full scan, so stale entries have likely accumulated. Do a complete fresh scan of the entire repository. Rebuild .cortex/state.md, .cortex/backlog.md, .cortex/debt.md, and .cortex/decisions.md from scratch — remove any entries that reference files, features, or modules no longer present in the repo. Do not touch .cortex/scratch.md. Update .cortex/meta.json: set last_commit to $(git rev-parse HEAD), last_updated to now (ISO 8601), scan_mode to 'fresh', commits_since_full_scan to 0." 2>/dev/null || SYNC_EXIT=$?
  NEW_COMMITS=0
else
  DIFF_CONTENT=$(git diff "$LAST".."$HEAD" 2>/dev/null | head -c 50000)
  echo "$DIFF_CONTENT" | claude --print "You are updating a .cortex/ project intelligence workspace. The diff above contains all changes since the last sync. Update .cortex/state.md, .cortex/backlog.md, .cortex/debt.md, and .cortex/decisions.md to reflect these changes. Remove any entries that reference files or features deleted in this diff. Do not touch .cortex/scratch.md. Update .cortex/meta.json: set last_commit to $(git rev-parse HEAD), last_updated to now (ISO 8601), scan_mode to 'incremental', commits_since_full_scan to ${NEW_COMMITS}." 2>/dev/null || SYNC_EXIT=$?
fi

if [ "$SYNC_EXIT" -ne 0 ]; then
  log_error "claude sync failed (exit $SYNC_EXIT) — workspace may be stale"
  exit 0
fi

# Verify meta.json was actually updated — if Claude skipped it, update ourselves
UPDATED_LAST=$(python3 -c "import json; print(json.load(open('$META')).get('last_commit',''))" 2>/dev/null || echo "")
if [ "$UPDATED_LAST" != "$HEAD" ]; then
  python3 -c "
import json, datetime
with open('$META', 'r') as f:
    d = json.load(f)
d['last_commit'] = '$HEAD'
d['last_updated'] = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
d['commits_since_full_scan'] = $NEW_COMMITS
with open('$META', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null || log_error "failed to update meta.json — next push may re-sync unnecessarily"
fi

exit 0
HOOK_BODY

chmod +x "$HOOK"

# 4. Also install hook directly into the current repo if we're in one
#    This removes the "run git init" friction for existing repos.
if git rev-parse --git-dir &>/dev/null 2>&1; then
  GIT_HOOKS_DIR="$(git rev-parse --git-dir)/hooks"
  mkdir -p "$GIT_HOOKS_DIR"
  cp "$HOOK" "$GIT_HOOKS_DIR/pre-push"
  chmod +x "$GIT_HOOKS_DIR/pre-push"
  CURRENT_REPO_MSG="  Current repo hook    → $GIT_HOOKS_DIR/pre-push ✓"
else
  CURRENT_REPO_MSG="  (Not in a git repo — hook will auto-install on next 'git init')"
fi

echo "✓ cortex installed."
echo "  Claude Code skill    → ~/.claude/commands/cortex.md"
echo "  Global hook template → $HOOK"
echo "  git init.templateDir → $TEMPLATE_DIR"
echo "$CURRENT_REPO_MSG"
echo ""
echo "Future repos pick up the hook automatically on 'git init'."
echo "Run /cortex install in any repo to do an initial scan."
