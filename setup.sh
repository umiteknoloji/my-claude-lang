#!/bin/bash
# MCL Setup Script
# Installs my-claude-lang globally: skill files + three auto-activation hooks.
# Run once — works for all projects.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/skills/my-claude-lang.md"
SKILL_RULES_SRC="$SCRIPT_DIR/skills/my-claude-lang"
HOOK_SRC_DIR="$SCRIPT_DIR/hooks"
HOOK_ACTIVATE_SRC="$HOOK_SRC_DIR/mcl-activate.sh"
HOOK_PRETOOL_SRC="$HOOK_SRC_DIR/mcl-pre-tool.sh"
HOOK_STOP_SRC="$HOOK_SRC_DIR/mcl-stop.sh"
HOOK_LIB_SRC="$HOOK_SRC_DIR/lib"

SKILL_DST="$HOME/.claude/skills/my-claude-lang"
HOOK_DST_DIR="$HOME/.claude/hooks"
HOOK_ACTIVATE_DST="$HOOK_DST_DIR/mcl-activate.sh"
HOOK_PRETOOL_DST="$HOOK_DST_DIR/mcl-pre-tool.sh"
HOOK_STOP_DST="$HOOK_DST_DIR/mcl-stop.sh"
HOOK_LIB_DST="$HOOK_DST_DIR/lib"
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
for f in "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/README.tr.md" "$SKILL_SRC" "$HOOK_ACTIVATE_SRC"; do
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

# 2. Install hook scripts (three hooks + lib/)
#    mcl-activate.sh         — UserPromptSubmit: renders MCL banner + activates skill
#    mcl-pre-tool.sh         — PreToolUse: phase-lock gate for mutating tools
#    mcl-stop.sh             — Stop: spec-hash tracking + approval-marker transitions
#    lib/mcl-state.sh        — shared state helpers (sourced by pre-tool + stop)
#    lib/mcl-config.sh       — .mcl/config.json reader (opt-in developer config)
#    lib/mcl-test-runner.sh  — opt-in Phase 5 test-runner orchestration
mkdir -p "$HOOK_DST_DIR"
cp "$HOOK_ACTIVATE_SRC" "$HOOK_ACTIVATE_DST"
cp "$HOOK_PRETOOL_SRC"  "$HOOK_PRETOOL_DST"
cp "$HOOK_STOP_SRC"     "$HOOK_STOP_DST"
chmod +x "$HOOK_ACTIVATE_DST" "$HOOK_PRETOOL_DST" "$HOOK_STOP_DST"

# Clean lib destination so renamed/removed helpers don't linger.
rm -rf "$HOOK_LIB_DST"
mkdir -p "$HOOK_LIB_DST"
cp "$HOOK_LIB_SRC"/*.sh "$HOOK_LIB_DST/"
echo "[OK] Hook scripts + lib installed to $HOOK_DST_DIR"

# 3. Configure hooks in settings.json
#    Fresh install: write all three event registrations.
#    Existing file: detect any missing hook and print the manual block.
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
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/mcl-pre-tool.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/mcl-stop.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS
  echo "[OK] Created $SETTINGS_FILE with MCL hooks (activate + pre-tool + stop)"
else
  # Detect hook REGISTRATION, not just substring. The user's permissions
  # allowlist often contains the hook path too — matching on `mcl-stop`
  # alone yields false positives. Anchor on the `~/.claude/hooks/` prefix
  # that only appears in a hook `command` field.
  MISSING=""
  grep -q '~/.claude/hooks/mcl-activate.sh'  "$SETTINGS_FILE" 2>/dev/null || MISSING="$MISSING mcl-activate"
  grep -q '~/.claude/hooks/mcl-pre-tool.sh'  "$SETTINGS_FILE" 2>/dev/null || MISSING="$MISSING mcl-pre-tool"
  grep -q '~/.claude/hooks/mcl-stop.sh'      "$SETTINGS_FILE" 2>/dev/null || MISSING="$MISSING mcl-stop"
  if [ -z "$MISSING" ]; then
    echo "[OK] All three MCL hooks already configured in $SETTINGS_FILE"
  else
    echo ""
    echo "[!] settings.json exists but is missing:$MISSING"
    echo "    Merge the following into the \"hooks\" object in $SETTINGS_FILE:"
    echo ""
    cat << 'MANUAL'
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/mcl-activate.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/mcl-pre-tool.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/mcl-stop.sh" }
        ]
      }
    ]
  }
MANUAL
    echo ""
  fi
fi

echo ""

# 4. Post-install smoke check
#    "Yazdım ≠ çalışıyor." Verify the files actually landed where they
#    must be before telling the developer setup is done. Failure here
#    indicates a broken install that would otherwise silently no-op.
SMOKE_FAIL=0
check_file() {
  if [ -f "$1" ]; then
    echo "[OK] $1"
  else
    echo "[FAIL] Missing: $1"
    SMOKE_FAIL=1
  fi
}
check_exec() {
  if [ -x "$1" ]; then
    echo "[OK] executable: $1"
  else
    echo "[FAIL] Not executable: $1"
    SMOKE_FAIL=1
  fi
}

echo "Post-install smoke check:"
check_file "$SKILL_DST/SKILL.md"
check_file "$HOOK_ACTIVATE_DST"
check_file "$HOOK_PRETOOL_DST"
check_file "$HOOK_STOP_DST"
check_file "$HOOK_LIB_DST/mcl-state.sh"
check_file "$HOOK_LIB_DST/mcl-config.sh"
check_file "$HOOK_LIB_DST/mcl-test-runner.sh"
check_exec "$HOOK_ACTIVATE_DST"
check_exec "$HOOK_PRETOOL_DST"
check_exec "$HOOK_STOP_DST"

# Verify mcl-activate.sh produces well-formed JSON on empty stdin
# (fast proxy for "hook actually runs and its deps resolve").
if echo '{}' | bash "$HOOK_ACTIVATE_DST" 2>/dev/null | python3 -m json.tool >/dev/null 2>&1; then
  echo "[OK] mcl-activate.sh emits valid JSON"
else
  echo "[FAIL] mcl-activate.sh did not emit valid JSON"
  SMOKE_FAIL=1
fi

echo ""
if [ "$SMOKE_FAIL" = "0" ]; then
  echo "── Opt-in test runner (β) ──"
  echo "If you add a 'test_command' to a project's .mcl/config.json, MCL will"
  echo "execute it during Phase 5 in YOUR shell with NO sandbox. The command"
  echo "inherits your env, filesystem access, and network. MCL does not"
  echo "review the command — audit your own config.json entries before use."
  echo ""
  echo "Done! MCL $CANONICAL_VERSION is now installed globally."
else
  echo "[FAIL] Setup completed but smoke check detected issues above."
  exit 1
fi
