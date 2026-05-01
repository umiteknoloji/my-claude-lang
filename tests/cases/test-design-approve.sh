#!/bin/bash
# Test: 10.0.0 Phase 2 DESIGN_REVIEW → Phase 3 IMPLEMENTATION on
# design askq approval.
#
# When the model emits an AskUserQuestion with a design-approval body
# in Phase 2 and the user selects "Onayla", the Stop hook must:
#   - flip design_approved=true
#   - advance current_phase to 3 IMPLEMENTATION
#   - write `design-approve-via-askuserquestion` audit

echo "--- test-design-approve ---"

_da_proj="$(setup_test_dir)"

_da_init() {
  python3 - "$_da_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 2, "phase_name": "DESIGN_REVIEW",
     "is_ui_project": True, "design_approved": False,
     "spec_hash": "deadbeefcafef00d",
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_da_state_field() {
  python3 -c "import json; d=json.load(open('$_da_proj/.mcl/state.json')); v=d.get('$1'); print('null' if v is None else (str(v).lower() if isinstance(v,bool) else v))"
}

_da_run_stop() {
  local transcript="$1"
  printf '%s' "{\"transcript_path\":\"${transcript}\",\"session_id\":\"da\",\"cwd\":\"${_da_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_da_proj" \
      MCL_STATE_DIR="$_da_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

# ---- Case 1: design askq + "Onayla" → state=3, design_approved=true ----
_da_init
_da_t1="$_da_proj/t1.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_da_t1" design-askq-onayla "Onayla"
_da_run_stop "$_da_t1" >/dev/null

assert_equals "[1] design askq Onayla → current_phase=3" "$(_da_state_field current_phase)" "3"
assert_equals "[1] phase_name=IMPLEMENTATION" "$(_da_state_field phase_name)" "IMPLEMENTATION"
assert_equals "[1] design_approved=true" "$(_da_state_field design_approved)" "true"

if grep -q "design-approve-via-askuserquestion" "$_da_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] design-approve-via-askuserquestion audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] design-approve-via-askuserquestion audit missing\n'
  grep "design-approve\|phase-transition" "$_da_proj/.mcl/audit.log" 2>/dev/null | tail -3
fi

# ---- Case 2: design askq + "Değiştir" → no transition ----
_da_init
rm -f "$_da_proj/.mcl/audit.log"
_da_t2="$_da_proj/t2.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_da_t2" design-askq-onayla "Değiştir"
_da_run_stop "$_da_t2" >/dev/null

assert_equals "[2] design askq non-approve → current_phase stays 2" "$(_da_state_field current_phase)" "2"
assert_equals "[2] design_approved stays false" "$(_da_state_field design_approved)" "false"

cleanup_test_dir "$_da_proj"
