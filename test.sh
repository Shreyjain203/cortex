#!/bin/bash
# cortex smoke tests — verifies install.sh and the pre-push hook without calling Claude
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

ok()      { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail()    { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
section() { echo ""; echo "── $1"; }

# Isolate HOME so we don't touch real ~/.git-templates or ~/.claude
TMP=$(mktemp -d)
export HOME="$TMP/home"
mkdir -p "$HOME"
trap 'rm -rf "$TMP"' EXIT

# Create a temp git repo to run tests in
REPO="$TMP/repo"
git init "$REPO" --quiet
cd "$REPO"
git config user.email "test@example.com"
git config user.name "Test"

section "install.sh — basic install"

bash "$SCRIPT_DIR/install.sh" > "$TMP/install.out" 2>&1
INSTALL_EXIT=$?

[ "$INSTALL_EXIT" -eq 0 ]                                         && ok "exits 0"            || fail "exit $INSTALL_EXIT (see $TMP/install.out)"
[ -f "$HOME/.claude/commands/cortex.md" ]                         && ok "skill installed"    || fail "skill not installed"
[ -f "$HOME/.git-templates/hooks/pre-push" ]                      && ok "global hook written" || fail "global hook missing"
[ -x "$HOME/.git-templates/hooks/pre-push" ]                      && ok "global hook executable" || fail "global hook not executable"
[ -f "$REPO/.git/hooks/pre-push" ]                                && ok "repo hook written"  || fail "repo hook missing"
[ -x "$REPO/.git/hooks/pre-push" ]                                && ok "repo hook executable" || fail "repo hook not executable"
grep -q "cortex pre-push hook" "$REPO/.git/hooks/pre-push"        && ok "hook has cortex marker" || fail "hook missing marker"

section "install.sh — backs up non-cortex hook"

FOREIGN_HOOK="$REPO/.git/hooks/pre-push"
echo '#!/bin/bash' > "$FOREIGN_HOOK"; echo 'exit 0' >> "$FOREIGN_HOOK"; chmod +x "$FOREIGN_HOOK"
bash "$SCRIPT_DIR/install.sh" > /dev/null 2>&1
BACKED=$(ls "$REPO/.git/hooks/pre-push.bak."* 2>/dev/null | wc -l | tr -d ' ')
[ "$BACKED" -ge 1 ] && ok "foreign hook backed up" || fail "foreign hook not backed up"

section "install.sh — idempotent (cortex hook not double-backed-up)"

BEFORE=$(ls "$REPO/.git/hooks/pre-push.bak."* 2>/dev/null | wc -l | tr -d ' ')
bash "$SCRIPT_DIR/install.sh" > /dev/null 2>&1
AFTER=$(ls "$REPO/.git/hooks/pre-push.bak."* 2>/dev/null | wc -l | tr -d ' ')
[ "$BEFORE" -eq "$AFTER" ] && ok "re-install doesn't add backup" || fail "re-install added unnecessary backup"

section "hook — no .cortex/ dir exits silently"

HOOK="$REPO/.git/hooks/pre-push"
bash "$HOOK" < /dev/null > /dev/null 2>&1
ok ".cortex/ absent → exits 0"

section "hook — lock contention"

mkdir -p "$REPO/.cortex"
mkdir "$REPO/.cortex/.sync_lock"
OUTPUT=$(bash "$HOOK" 2>&1 || true)
echo "$OUTPUT" | grep -q "sync already in progress" && ok "lock contention surfaced to stderr" || fail "lock message missing"
rmdir "$REPO/.cortex/.sync_lock"

section "hook — missing meta.json"

OUTPUT=$(bash "$HOOK" 2>&1 || true)
echo "$OUTPUT" | grep -q "meta.json missing"      && ok "missing meta.json detected" || fail "missing meta.json not detected"
[ -f "$REPO/.cortex/errors.log" ]                  && ok "errors.log written"         || fail "errors.log not written"
grep -q "meta.json missing" "$REPO/.cortex/errors.log" && ok "error logged to file"  || fail "error not in errors.log"

section "hook — schema migration (v0 → v1)"

git -C "$REPO" commit --allow-empty -m "init" --quiet
HEAD=$(git -C "$REPO" rev-parse HEAD)
# Write a v0 meta.json (no schema_version, no commits_since_full_scan)
cat > "$REPO/.cortex/meta.json" << JSON
{"project_name":"test","created_at":"2026-01-01T00:00:00Z","last_updated":"2026-01-01T00:00:00Z","last_commit":"$HEAD","scan_mode":"fresh","baseline_commit":"$HEAD"}
JSON
rm -f "$REPO/.cortex/errors.log"
bash "$HOOK" 2>/dev/null || true
VER=$(python3 -c "import json; print(json.load(open('$REPO/.cortex/meta.json')).get('schema_version','missing'))")
CFS=$(python3 -c "import json; print(json.load(open('$REPO/.cortex/meta.json')).get('commits_since_full_scan','missing'))")
[ "$VER" = "1" ] && ok "schema_version set to 1" || fail "schema_version wrong (got: $VER)"
[ "$CFS" = "0" ] && ok "commits_since_full_scan defaulted to 0" || fail "commits_since_full_scan wrong (got: $CFS)"

section "hook — no diff when last_commit == HEAD"

rm -f "$REPO/.cortex/errors.log"
bash "$HOOK" 2>/dev/null
[ ! -f "$REPO/.cortex/errors.log" ] && ok "no errors logged when nothing changed" || fail "spurious errors.log on no-op push"

section "hook — last_commit not in history (rebase scenario)"

cat > "$REPO/.cortex/meta.json" << 'JSON'
{"schema_version":1,"project_name":"test","created_at":"2026-01-01T00:00:00Z","last_updated":"2026-01-01T00:00:00Z","last_commit":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","scan_mode":"fresh","baseline_commit":"deadbeef","commits_since_full_scan":0}
JSON
OUTPUT=$(bash "$HOOK" 2>&1 || true)
echo "$OUTPUT" | grep -q "no longer in history" && ok "missing history commit detected" || fail "missing history commit not caught"

echo ""
echo "── results"
echo "  passed: $PASS"
echo "  failed: $FAIL"
echo ""
[ "$FAIL" -eq 0 ] && echo "all tests passed" && exit 0 || exit 1
