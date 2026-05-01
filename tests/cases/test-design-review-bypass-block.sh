#!/bin/bash
# Test: 10.0.0 Phase 2 → Phase 3 bypass block.
#
# In Phase 2 DESIGN_REVIEW (is_ui_project=true, design_approved=false),
# pre-tool Write attempts to BACKEND paths (e.g. backend route or
# API/server file outside frontend) must be denied with a reason
# referencing the Phase 2 design askq requirement.
#
# Frontend writes are still allowed in Phase 2 (design build path).

echo "--- test-design-review-bypass-block ---"

_dbb_proj="$(setup_test_dir)"

_dbb_init() {
  python3 - "$_dbb_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 2, "phase_name": "DESIGN_REVIEW",
     "is_ui_project": True, "design_approved": False,
     "spec_hash": "deadbeefcafef00d",
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_dbb_init

_dbb_run_pretool() {
  local file_path="$1"
  printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${file_path}\",\"content\":\"// hi\"},\"session_id\":\"dbb\",\"cwd\":\"${_dbb_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_dbb_proj" \
      MCL_STATE_DIR="$_dbb_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null
}

# ---- Case 1: backend Write in Phase 2 → DENY ----
mkdir -p "$_dbb_proj/src/api" "$_dbb_proj/server"
_dbb_out_be1="$(_dbb_run_pretool "$_dbb_proj/src/api/users.ts")"

assert_contains "[1] backend src/api/* in Phase 2 → permissionDecision deny" "$_dbb_out_be1" '"permissionDecision": "deny"'
if printf '%s' "$_dbb_out_be1" | grep -qE "DESIGN_REVIEW|Phase 2|design askq|Tasarım"; then
  PASS=$((PASS+1))
  printf '  PASS: [1] deny reason references Phase 2 / DESIGN_REVIEW\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] deny reason does not reference Phase 2 design askq\n'
  printf '        output: %s\n' "$(printf '%s' "$_dbb_out_be1" | head -c 250)"
fi

# ---- Case 2: backend Write at server/* in Phase 2 → DENY ----
_dbb_out_be2="$(_dbb_run_pretool "$_dbb_proj/server/routes.ts")"
assert_contains "[2] backend server/* in Phase 2 → permissionDecision deny" "$_dbb_out_be2" '"permissionDecision": "deny"'

# ---- Case 3: frontend Write in Phase 2 → ALLOWED ----
mkdir -p "$_dbb_proj/src/components"
_dbb_out_fe="$(_dbb_run_pretool "$_dbb_proj/src/components/Login.tsx")"
if [ -z "$_dbb_out_fe" ] || ! printf '%s' "$_dbb_out_fe" | grep -q '"permissionDecision": "deny"'; then
  PASS=$((PASS+1))
  printf '  PASS: [3] frontend Write in Phase 2 → allowed\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [3] frontend Write in Phase 2 blocked unexpectedly\n'
  printf '        output: %s\n' "$(printf '%s' "$_dbb_out_fe" | head -c 200)"
fi

cleanup_test_dir "$_dbb_proj"
