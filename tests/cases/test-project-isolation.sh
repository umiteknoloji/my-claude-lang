#!/bin/bash
# Test: project isolation enforcement (since 9.1.3).
#
# Real-session bug: model ran `cd /Users/umit && npx create-next-app
# ...` from inside the active project, then Read sibling-project
# files. Vaad #1 (project isolation) was violated. mcl-pre-tool.sh
# now denies any tool call whose target resolves outside
# CLAUDE_PROJECT_DIR + system whitelist (/tmp, package caches, MCL
# skill files, stack-detect, /usr).
#
# Coverage: cross-boundary attempts must deny, in-scope and
# whitelist must pass. Across all phases (the isolation gate is
# phase-agnostic).

echo "--- test-project-isolation ---"

_iso_proj="$(setup_test_dir)"
_iso_state="$_iso_proj/.mcl/state.json"
mkdir -p "$_iso_proj/.mcl"
python3 - <<PY
import json, time
o = {
    "schema_version": 3,
    "current_phase": 3,
    "phase_name": "IMPLEMENTATION",
    "is_ui_project": False,
    "design_approved": True,
    "last_update": int(time.time()),
}
open("$_iso_state", "w").write(json.dumps(o))
PY

_iso_run() {
  local tool="$1" input_json="$2"
  printf '%s' "{\"tool_name\":\"${tool}\",\"tool_input\":${input_json},\"session_id\":\"iso\",\"cwd\":\"${_iso_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_iso_proj" \
      MCL_STATE_DIR="$_iso_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null
}

_iso_assert_deny() {
  local label="$1" tool="$2" input="$3"
  local out
  out="$(_iso_run "$tool" "$input")"
  if printf '%s' "$out" | grep -q '"permissionDecision": "deny"'; then
    PASS=$((PASS+1))
    printf '  PASS: %s → deny\n' "$label"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: %s — expected deny, got: %s\n' "$label" "$(printf '%s' "$out" | head -c 120)"
  fi
}

_iso_assert_allow() {
  local label="$1" tool="$2" input="$3"
  local out
  out="$(_iso_run "$tool" "$input")"
  if [ -z "$out" ]; then
    PASS=$((PASS+1))
    printf '  PASS: %s → allow\n' "$label"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: %s — expected allow, got: %s\n' "$label" "$(printf '%s' "$out" | head -c 120)"
  fi
}

# ---- Bash: lexical escape patterns deny ----
_iso_assert_deny  "Bash cd .."          "Bash" '{"command":"cd .. && ls"}'
_iso_assert_deny  "Bash cd ../sibling"  "Bash" '{"command":"cd ../sibling && pwd"}'
_iso_assert_deny  "Bash cd ~"           "Bash" '{"command":"cd ~ && pwd"}'
_iso_assert_deny  "Bash cd ~/x"         "Bash" '{"command":"cd ~/x && ls"}'
_iso_assert_deny  "Bash cd \$HOME"      "Bash" '{"command":"cd $HOME && pwd"}'
_iso_assert_deny  "Bash pushd .."       "Bash" '{"command":"pushd .. > /dev/null"}'

# ---- Bash: absolute path outside project ----
_iso_assert_deny  "Bash cd /Users/other"     "Bash" '{"command":"cd /Users/other/proj && pwd"}'
_iso_assert_deny  "Bash cat sibling abs"     "Bash" '{"command":"cat /Users/x/other/file.ts"}'
_iso_assert_deny  "Bash cat ../escape"       "Bash" '{"command":"cat ../sibling/file.ts"}'
_iso_assert_deny  "Bash cat /etc/passwd"     "Bash" '{"command":"cat /etc/passwd"}'

# ---- Bash: in-project + whitelist allows ----
_iso_assert_allow "Bash cd /tmp/build"       "Bash" '{"command":"cd /tmp/build && npm install"}'
_iso_assert_allow "Bash cd subdir"           "Bash" '{"command":"cd src && ls"}'
_iso_assert_allow "Bash npm install"         "Bash" '{"command":"npm install --production"}'
_iso_assert_allow "Bash git status"          "Bash" '{"command":"git status"}'
_iso_assert_allow "Bash node ./bin"          "Bash" '{"command":"node ./bin/cli.js"}'

# ---- Read/Write/Edit: cross-boundary deny ----
_iso_assert_deny  "Read sibling abs"         "Read"  '{"file_path":"/Users/x/other/file.ts"}'
_iso_assert_deny  "Read /etc/passwd"         "Read"  '{"file_path":"/etc/passwd"}'
_iso_assert_deny  "Write sibling abs"        "Write" '{"file_path":"/Users/x/other/x.ts","content":"x"}'
_iso_assert_deny  "Edit cross-boundary"      "Edit"  '{"file_path":"/Users/x/other/x.ts","old_string":"a","new_string":"b"}'

# ---- Read whitelist allows ----
_iso_assert_allow "Read skill .md"           "Read"  '{"file_path":"~/.claude/skills/my-claude-lang.md"}'
_iso_assert_allow "Read skill subdir"        "Read"  '{"file_path":"~/.claude/skills/my-claude-lang/phase1-rules.md"}'

# ---- Glob/Grep: pattern handling ----
_iso_assert_allow "Glob src/**/*.ts"         "Glob"  '{"pattern":"src/**/*.ts"}'
_iso_assert_deny  "Glob ../*"                "Glob"  '{"pattern":"../*"}'
_iso_assert_deny  "Glob /Users/other/**"     "Glob"  '{"pattern":"/Users/other/**"}'
_iso_assert_allow "Grep in-scope pattern"    "Grep"  '{"pattern":"useState","path":"src/"}'
_iso_assert_deny  "Grep cross-boundary path" "Grep"  '{"pattern":"x","path":"/Users/other/proj"}'

# ---- Phase-agnostic: same gate fires in Phase 1 (not just Phase 4) ----
python3 - <<PY
import json, time
o = {
    "schema_version": 3,
    "current_phase": 1,
    "phase_name": "INTENT",
    "is_ui_project": False,
    "design_approved": False,
    "last_update": int(time.time()),
}
open("$_iso_state", "w").write(json.dumps(o))
PY
_iso_assert_deny  "Phase 1 cd .. (gate phase-agnostic)"  "Bash" '{"command":"cd .. && ls"}'

# ---- Audit log captures isolation block ----
if grep -q "block-isolation" "$_iso_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: audit log captures block-isolation events\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: no block-isolation audit lines found\n'
fi

cleanup_test_dir "$_iso_proj"
