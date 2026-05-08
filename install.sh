#!/bin/bash
set -e

DEST="$HOME/.claude/commands/cortex.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/cortex.md"

mkdir -p "$HOME/.claude/commands"
cp "$SRC" "$DEST"

echo "✓ cortex installed. Run /cortex install in any repo."
