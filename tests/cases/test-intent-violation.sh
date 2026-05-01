#!/bin/bash
# Test: 10.0.0 intent violation — pre-tool deny on HIGH-severity
# intent contradiction.
#
# When phase1_intent declares "frontend only, no backend" and the
# model attempts to Write to a backend route path (e.g. Next.js
# app/api/* route), pre-tool must DENY with a reason mentioning
# intent-violation. Frontend writes pass through.
# Stack-agnostic — works for any framework conventionally placing
# backend routes under api/ or routes/ paths.

echo "--- test-intent-violation ---"


_iv_proj="$(setup_test_dir)"

_iv_init() {
  python3 - "$_iv_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 4, "phase_name": "RISK_GATE",
     "is_ui_project": True, "design_approved": True,
     "spec_hash": "deadbeefcafef00d",
     "phase1_intent": "frontend only, no backend",
     "phase1_constraints": "React + Tailwind, static site, no API, no DB",
     "scope_paths": ["src/components/**", "src/pages/**"],
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_iv_init

_iv_run_pretool() {
  local file_path="$1"
  printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${file_path}\",\"content\":\"export const x=1;\"},\"session_id\":\"iv\",\"cwd\":\"${_iv_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_iv_proj" \
      MCL_STATE_DIR="$_iv_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null
}

# ---- Case 1: backend route Write → DENY (HIGH intent violation) ----
mkdir -p "$_iv_proj/app/api/users"
_iv_out_be="$(_iv_run_pretool "$_iv_proj/app/api/users/route.ts")"

assert_contains "[1] backend route Write → permissionDecision deny" "$_iv_out_be" '"permissionDecision": "deny"'
if printf '%s' "$_iv_out_be" | grep -qE "intent-violation|intent violation|intent ihlali"; then
  PASS=$((PASS+1))
  printf '  PASS: [1] deny reason references intent-violation\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] deny reason does not mention intent-violation\n'
  printf '        output: %s\n' "$(printf '%s' "$_iv_out_be" | head -c 250)"
fi

# Audit: HIGH severity intent-violation block.
if grep -qE "intent-violation-block.*HIGH|intent-violation.*severity=HIGH" "$_iv_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] intent-violation-block audit with severity=HIGH\n'
else
  # Allow either explicit HIGH marker or the audit event by name.
  if grep -q "intent-violation-block" "$_iv_proj/.mcl/audit.log" 2>/dev/null; then
    PASS=$((PASS+1))
    printf '  PASS: [1] intent-violation-block audit captured\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: [1] intent-violation-block audit missing\n'
  fi
fi

# ---- Case 2: frontend Write → ALLOWED (in-scope) ----
mkdir -p "$_iv_proj/src/components"
_iv_out_fe="$(_iv_run_pretool "$_iv_proj/src/components/Header.tsx")"
if [ -z "$_iv_out_fe" ] || ! printf '%s' "$_iv_out_fe" | grep -q '"permissionDecision": "deny"'; then
  PASS=$((PASS+1))
  printf '  PASS: [2] frontend Write in-scope → allowed\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [2] frontend Write blocked unexpectedly\n'
  printf '        output: %s\n' "$(printf '%s' "$_iv_out_fe" | head -c 200)"
fi

cleanup_test_dir "$_iv_proj"
