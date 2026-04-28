#!/bin/bash
# MCL Uninstall Script
# Removes my-claude-lang: skill files, hooks, and settings.json entries.
# Does NOT delete the MCL repo itself — only the installed artifacts.

set -e

HOOK_DST_DIR="$HOME/.claude/hooks"
SKILL_DST="$HOME/.claude/skills/my-claude-lang"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "my-claude-lang (MCL) Uninstall"
echo "================================"
echo ""

# 1. Remove hook entries from settings.json
if [ -f "$SETTINGS_FILE" ]; then
  python3 - "$SETTINGS_FILE" << 'PYREMOVE'
import json, sys, os, tempfile

MCL_COMMANDS = {
    "~/.claude/hooks/mcl-activate.sh",
    "~/.claude/hooks/mcl-pre-tool.sh",
    "~/.claude/hooks/mcl-stop.sh",
    "~/.claude/hooks/mcl-post-tool.sh",
}

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception as e:
    print(f"[WARN] Cannot parse {path}: {e}. Skipping settings cleanup.")
    sys.exit(0)

hooks_obj = data.get("hooks", {})
if not isinstance(hooks_obj, dict):
    print("[OK] No hooks object found in settings.json — nothing to remove.")
    sys.exit(0)

removed = []
for event in list(hooks_obj.keys()):
    entries = hooks_obj[event]
    if not isinstance(entries, list):
        continue
    new_entries = []
    for entry in entries:
        if not isinstance(entry, dict):
            new_entries.append(entry)
            continue
        hook_list = entry.get("hooks", [])
        new_hooks = [h for h in hook_list
                     if not (isinstance(h, dict) and h.get("command") in MCL_COMMANDS)]
        if len(new_hooks) < len(hook_list):
            removed.extend(h.get("command") for h in hook_list
                           if isinstance(h, dict) and h.get("command") in MCL_COMMANDS)
            if new_hooks:
                entry = dict(entry)
                entry["hooks"] = new_hooks
                new_entries.append(entry)
        else:
            new_entries.append(entry)
    if new_entries:
        hooks_obj[event] = new_entries
    elif event in hooks_obj:
        del hooks_obj[event]

if not removed:
    print("[OK] No MCL hook entries found in settings.json.")
    sys.exit(0)

dirpath = os.path.dirname(os.path.abspath(path))
try:
    fd, tmp = tempfile.mkstemp(dir=dirpath, suffix=".json.tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
    print(f"[OK] Removed {len(set(removed))} MCL hook(s) from {path}")
except Exception as e:
    try: os.unlink(tmp)
    except Exception: pass
    print(f"[FAIL] Could not write {path}: {e}")
    sys.exit(1)
PYREMOVE
else
  echo "[OK] settings.json not found — nothing to remove."
fi

# 2. Remove skill files
if [ -d "$SKILL_DST" ]; then
  rm -rf "$SKILL_DST"
  echo "[OK] Removed skill directory: $SKILL_DST"
else
  echo "[OK] Skill directory not found — already clean."
fi

# 3. Remove hook scripts
REMOVED_HOOKS=0
for f in \
  "$HOOK_DST_DIR/mcl-activate.sh" \
  "$HOOK_DST_DIR/mcl-pre-tool.sh" \
  "$HOOK_DST_DIR/mcl-stop.sh" \
  "$HOOK_DST_DIR/mcl-post-tool.sh"; do
  if [ -f "$f" ]; then
    rm -f "$f"
    echo "[OK] Removed $f"
    REMOVED_HOOKS=1
  fi
done
[ "$REMOVED_HOOKS" -eq 0 ] && echo "[OK] Hook scripts not found — already clean."

# 4. Remove lib files (only MCL-owned ones)
LIB_DIR="$HOOK_DST_DIR/lib"
if [ -d "$LIB_DIR" ]; then
  REMOVED_LIB=0
  for f in "$LIB_DIR"/mcl-*.sh "$LIB_DIR"/mcl-*.py; do
    [ -f "$f" ] || continue
    rm -f "$f"
    echo "[OK] Removed $f"
    REMOVED_LIB=1
  done
  [ "$REMOVED_LIB" -eq 0 ] && echo "[OK] No MCL lib files found — already clean."
  if [ -z "$(ls -A "$LIB_DIR" 2>/dev/null)" ]; then
    rmdir "$LIB_DIR"
    echo "[OK] Removed empty lib directory: $LIB_DIR"
  fi
fi

# 5. Per-project .mcl/ cleanup hint
echo ""
echo "Per-project .mcl/ directories (state, specs, logs) are NOT removed"
echo "automatically. To clean a specific project:"
echo "  rm -rf /path/to/project/.mcl"
echo ""
echo "MCL uninstalled. Start a new Claude Code session for the change to take effect."
