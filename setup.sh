#!/bin/bash
# MCL Setup Script
# Installs my-claude-lang globally: skill files + auto-activation hook.
# Run once — works for all projects.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/skills/my-claude-lang.md"
SKILL_RULES_SRC="$SCRIPT_DIR/skills/my-claude-lang"
HOOK_SRC="$SCRIPT_DIR/hooks/mcl-activate.sh"

SKILL_DST="$HOME/.claude/skills/my-claude-lang"
HOOK_DST="$HOME/.claude/hooks/mcl-activate.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "my-claude-lang (MCL) Setup"
echo "=========================="
echo ""

# 0. Version consistency check
#    The VERSION file at the repo root is the single source of truth.
#    Every consumer (README.md, README.tr.md, skill file, hook banner)
#    must carry the same `🌐 MCL X.Y.Z` banner. Historical references
#    like "Since MCL 5.0.0" are NOT caught because the check is anchored
#    on the banner emoji.
VERSION_FILE="$SCRIPT_DIR/VERSION"
if [ ! -f "$VERSION_FILE" ]; then
  echo "[ERROR] VERSION file missing at $VERSION_FILE"
  exit 1
fi
CANONICAL_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if ! printf '%s' "$CANONICAL_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "[ERROR] VERSION file contains malformed semver: '$CANONICAL_VERSION'"
  exit 1
fi
echo "MCL version: $CANONICAL_VERSION"
VERSION_MISMATCH=0
for f in "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/README.tr.md" "$SKILL_SRC" "$HOOK_SRC"; do
  [ -f "$f" ] || continue
  FILE_VERSION="$(grep -oE '🌐 MCL [0-9]+\.[0-9]+\.[0-9]+' "$f" | head -1 | awk '{print $3}')"
  if [ -n "$FILE_VERSION" ] && [ "$FILE_VERSION" != "$CANONICAL_VERSION" ]; then
    echo "[WARN] Version drift: $f has $FILE_VERSION, VERSION says $CANONICAL_VERSION"
    VERSION_MISMATCH=1
  fi
done
if [ "$VERSION_MISMATCH" -eq 0 ]; then
  echo "[OK] Version $CANONICAL_VERSION consistent across README.md, README.tr.md, skill file, hook"
fi
echo ""

# 1. Install skill files
#    Clean the destination first so renamed/removed files do NOT linger
#    from prior MCL versions. Without this, stale files can shadow
#    current behavior (seen during 5.2.0 → 5.3.0 upgrade).
rm -rf "$SKILL_DST"
mkdir -p "$SKILL_DST"
cp "$SKILL_SRC" "$SKILL_DST/SKILL.md"
cp "$SKILL_RULES_SRC"/*.md "$SKILL_DST/"
echo "[OK] Skill files installed to $SKILL_DST (clean copy)"

# 2. Install hook script
mkdir -p "$(dirname "$HOOK_DST")"
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"
echo "[OK] Hook script installed to $HOOK_DST"

# 3. Configure hook in settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
  cat > "$SETTINGS_FILE" << 'SETTINGS'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/mcl-activate.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS
  echo "[OK] Created $SETTINGS_FILE with MCL hook"
else
  if grep -q '"hooks"' "$SETTINGS_FILE" 2>/dev/null && grep -q "mcl-activate" "$SETTINGS_FILE" 2>/dev/null; then
    echo "[OK] Hook already configured in $SETTINGS_FILE"
  else
    echo ""
    echo "[!] settings.json already exists. Add this to your $SETTINGS_FILE:"
    echo ""
    cat << 'MANUAL'
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/mcl-activate.sh"
          }
        ]
      }
    ]
  }
MANUAL
    echo ""
    echo "    Add it inside your existing settings.json."
  fi
fi

echo ""
echo "Done! MCL is now installed globally."
echo "Open a new Claude Code session and start typing in your language."
