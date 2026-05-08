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

set -e

HEAD=$(git rev-parse HEAD)
META=".cortex/meta.json"

if [ ! -f "$META" ]; then
  # No .cortex/ yet — run a fresh scan
  if command -v claude &>/dev/null; then
    claude --print "You are setting up a .cortex/ project intelligence workspace for the first time. Run /cortex install to scan this repo and create the workspace files (.cortex/state.md, backlog.md, debt.md, decisions.md, scratch.md, meta.json). Then update .gitignore to include .cortex/." 2>/dev/null || true
  fi
  exit 0
fi

LAST=$(python3 -c "import json,sys; print(json.load(open('$META'))['last_commit'])" 2>/dev/null || echo "")

if [ -z "$LAST" ] || [ "$LAST" = "$HEAD" ]; then
  exit 0
fi

DIFF=$(git diff "$LAST".."$HEAD" --name-only 2>/dev/null || echo "")

if [ -z "$DIFF" ]; then
  exit 0
fi

# Ask Claude to update .cortex/ based on the diff
if command -v claude &>/dev/null; then
  DIFF_CONTENT=$(git diff "$LAST".."$HEAD" 2>/dev/null | head -c 50000)
  echo "$DIFF_CONTENT" | claude --print "You are updating a .cortex/ project intelligence workspace. The diff above contains all changes since the last sync. Update .cortex/state.md, .cortex/backlog.md, .cortex/debt.md, and .cortex/decisions.md to reflect these changes. Do not touch .cortex/scratch.md. Then update .cortex/meta.json setting last_commit to $(git rev-parse HEAD) and last_updated to now. Be concise. Remove stale entries. Add new ones." 2>/dev/null || true
fi

exit 0
HOOK_BODY

chmod +x "$HOOK"

echo "✓ cortex installed."
echo "  Claude Code skill → ~/.claude/commands/cortex.md"
echo "  Global pre-push hook → $HOOK"
echo "  git init.templateDir → $TEMPLATE_DIR"
echo ""
echo "New repos pick up the hook automatically on 'git init'."
echo "Existing repos: run 'git init' once in the repo root to copy the hook."
echo ""
echo "Run /cortex install in any repo to do an initial scan."
