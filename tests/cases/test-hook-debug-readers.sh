#!/bin/bash
# Test: hook-debug block extends to Read / Grep / Glob in Phase 1-3 (9.0.0).
#
# Bash-tool hook-debug block already lives in tests via real-session
# behavior. This case pins down the 9.0.0 extension: when the model
# tries the dedicated Read/Grep/Glob tools in Phase 1-3, they are
# denied with permissionDecision:deny and the block-hook-debug audit
# captures the tool name.

echo "--- test-hook-debug-readers ---"

if [ "${MCL_MINIMAL_CORE:-0}" = "1" ]; then
  printf '  SKIP: test-hook-debug-readers — hook-debug disabled (MCL_MINIMAL_CORE=1)\n'
  return 0 2>/dev/null || true
fi

_hd_proj="$(setup_test_dir)"

# Plant a Phase 2 state — Phase 1-3 is the deny window.
_hd_state="$_hd_proj/.mcl/state.json"
mkdir -p "$_hd_proj/.mcl"
python3 -c "
import json, time
o = {'schema_version':2, 'current_phase':2, 'phase_name':'SPEC_REVIEW',
     'spec_approved':False, 'last_update':int(time.time())}
open('$_hd_state','w').write(json.dumps(o))
"

# Helper: drive mcl-pre-tool.sh with a tool_name + tool_input pair and
# echo the JSON output. We need `set -e` off here because the hook
# returns exit 0 regardless; we just want stdout.
_hd_run() {
  local tool="$1" json_input="$2"
  printf '%s' "{\"tool_name\":\"${tool}\",\"tool_input\":${json_input},\"session_id\":\"hd\",\"cwd\":\"${_hd_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_hd_proj" \
      MCL_STATE_DIR="$_hd_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null
}

# ---- Test 1: Read on hook-state path → deny ----
_hd_out1="$(_hd_run "Read" '{"file_path":"~/.mcl/lib/hooks/lib/mcl-state.sh"}')"
assert_json_valid "Read hook path → valid JSON" "$_hd_out1"
assert_contains "Read → permissionDecision=deny" "$_hd_out1" '"permissionDecision": "deny"'
assert_contains "Read → reason mentions Phase 1-3" "$_hd_out1" "Phase 1-3"

# ---- Test 2: Grep on hooks dir → deny ----
_hd_out2="$(_hd_run "Grep" '{"pattern":"mcl_state_set","path":"~/.claude/hooks"}')"
assert_contains "Grep hook path → permissionDecision=deny" "$_hd_out2" '"permissionDecision": "deny"'

# ---- Test 3: Glob with hook-name pattern → deny ----
_hd_out3="$(_hd_run "Glob" '{"pattern":"**/mcl-state.sh"}')"
assert_contains "Glob mcl-state.sh → permissionDecision=deny" "$_hd_out3" '"permissionDecision": "deny"'

# ---- Test 4: Read on a project-local file → pass through (empty) ----
_hd_out4="$(_hd_run "Read" '{"file_path":"./README.md"}')"
assert_equals "Read project file → no block (empty stdout)" "$_hd_out4" ""

# ---- Test 5: Phase 4 → block does NOT fire ----
python3 -c "
import json, time
o = {'schema_version':2, 'current_phase':4, 'phase_name':'EXECUTE',
     'spec_approved':True, 'last_update':int(time.time())}
open('$_hd_state','w').write(json.dumps(o))
"
_hd_out5="$(_hd_run "Read" '{"file_path":"~/.mcl/lib/skills/my-claude-lang.md"}')"
assert_equals "Phase 4 → Read hook path passes through" "$_hd_out5" ""

# ---- Test 6: audit log records block-hook-debug with tool name ----
if [ -f "$_hd_proj/.mcl/audit.log" ]; then
  if grep -q "block-hook-debug.*tool=Read" "$_hd_proj/.mcl/audit.log" 2>/dev/null; then
    PASS=$((PASS+1))
    printf '  PASS: audit captures tool=Read in block-hook-debug\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: audit log missing block-hook-debug with tool=Read\n'
    grep "block-hook-debug" "$_hd_proj/.mcl/audit.log" 2>/dev/null | head -3 || true
  fi
else
  FAIL=$((FAIL+1))
  printf '  FAIL: audit.log not created\n'
fi

cleanup_test_dir "$_hd_proj"
