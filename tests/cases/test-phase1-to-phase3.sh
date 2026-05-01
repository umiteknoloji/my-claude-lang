#!/bin/bash
# Test: 10.0.0 Phase 1 INTENT → Phase 3 IMPLEMENTATION transition
# (non-UI projects).
#
# Phase 1 summary-confirm askq is the gate. When approved AND
# is_ui_project=false, state transitions directly to current_phase=3
# (IMPLEMENTATION), skipping Phase 2 DESIGN_REVIEW. Audit event:
# `phase-transition-to-implementation` with `1->3 source=summary-confirm`.
# design_approved is NOT changed by this transition (stays at default).

echo "--- test-phase1-to-phase3 ---"

_p3_proj="$(setup_test_dir)"

_p3_init_phase1_nonui() {
  python3 - "$_p3_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 1, "phase_name": "INTENT",
     "is_ui_project": False, "design_approved": False,
     "spec_hash": None, "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_p3_run_stop() {
  local transcript="$1"
  printf '%s' "{\"transcript_path\":\"${transcript}\",\"session_id\":\"p3\",\"cwd\":\"${_p3_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_p3_proj" \
      MCL_STATE_DIR="$_p3_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

_p3_state_field() {
  python3 -c "import json; d=json.load(open('$_p3_proj/.mcl/state.json')); v=d.get('$1'); print('null' if v is None else (str(v).lower() if isinstance(v,bool) else v))"
}

# ---- Case 1: summary-confirm approve (non-UI) → state=3 ----
_p3_init_phase1_nonui
_p3_t1="$_p3_proj/t1.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_p3_t1" summary-confirm-askq-onayla "Onayla"
_p3_run_stop "$_p3_t1" >/dev/null

assert_equals "[1] non-UI approve → current_phase=3" "$(_p3_state_field current_phase)" "3"
assert_equals "[1] phase_name=IMPLEMENTATION" "$(_p3_state_field phase_name)" "IMPLEMENTATION"

# design_approved should NOT be touched on non-UI path (stays false).
assert_equals "[1] design_approved unchanged on non-UI path" "$(_p3_state_field design_approved)" "false"

if grep -qE "phase-transition-to-implementation.*1->3.*source=summary-confirm" "$_p3_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] phase-transition-to-implementation 1->3 source=summary-confirm audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] phase-transition-to-implementation 1->3 audit missing\n'
  grep "phase-transition\|summary-confirm" "$_p3_proj/.mcl/audit.log" 2>/dev/null | tail -3
fi

# ---- Case 2: summary-confirm non-approve → state stays at 1 ----
_p3_init_phase1_nonui
rm -f "$_p3_proj/.mcl/audit.log"
_p3_t2="$_p3_proj/t2.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_p3_t2" summary-confirm-askq-onayla "Düzenle"
_p3_run_stop "$_p3_t2" >/dev/null

assert_equals "[2] non-approve → current_phase stays 1" "$(_p3_state_field current_phase)" "1"

# ---- Case 3: state idempotency — already at phase=3, summary-confirm no-op ----
python3 - "$_p3_proj/.mcl/state.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d['current_phase'] = 3; d['phase_name'] = 'IMPLEMENTATION'
json.dump(d, open(p, 'w'))
PY
rm -f "$_p3_proj/.mcl/audit.log"
_p3_run_stop "$_p3_t1" >/dev/null

assert_equals "[3] already phase=3 → no second transition" "$(_p3_state_field current_phase)" "3"
if ! grep -q "phase-transition-to-implementation.*1->3" "$_p3_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [3] no spurious 1->3 audit when already at 3\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [3] re-transition fired on already-phase-3 state\n'
fi

cleanup_test_dir "$_p3_proj"
