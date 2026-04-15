#!/bin/bash
# MCL Hook Setup Script
# Installs the MCL auto-activation hook into Claude Code settings.
# Run this once — it works globally for all projects.

set -e

HOOK_DIR="$HOME/.claude/hooks"
HOOK_FILE="$HOOK_DIR/mcl-activate.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "MCL Hook Setup"
echo "=============="
echo ""

# 1. Copy hook script
mkdir -p "$HOOK_DIR"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/mcl-activate.sh" "$HOOK_FILE"
chmod +x "$HOOK_FILE"
echo "[OK] Hook script installed to $HOOK_FILE"

# 2. Update settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
  # Create settings.json with hook
  cat > "$SETTINGS_FILE" << 'SETTINGS'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "type": "command",
        "command": "~/.claude/hooks/mcl-activate.sh"
      }
    ]
  }
}
SETTINGS
  echo "[OK] Created $SETTINGS_FILE with MCL hook"
else
  # Check if hook already exists
  if grep -q "mcl-activate" "$SETTINGS_FILE" 2>/dev/null; then
    echo "[OK] Hook already configured in $SETTINGS_FILE"
  else
    echo ""
    echo "[!] settings.json already exists. Add this manually:"
    echo ""
    echo '  "hooks": {'
    echo '    "UserPromptSubmit": ['
    echo '      {'
    echo '        "type": "command",'
    echo '        "command": "~/.claude/hooks/mcl-activate.sh"'
    echo '      }'
    echo '    ]'
    echo '  }'
    echo ""
    echo "    Add it inside your existing settings.json."
  fi
fi

echo ""
echo "Done. MCL will now auto-activate when non-English input is detected."
echo "Test it: open Claude Code and type something in your language."
