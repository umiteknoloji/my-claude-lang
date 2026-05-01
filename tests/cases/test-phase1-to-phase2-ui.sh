#!/bin/bash
# Test: 10.0.0 Phase 1 INTENT → Phase 2 DESIGN_REVIEW transition
# (UI projects).
#
# When summary-confirm askq is approved AND is_ui_project=true, state
# transitions to current_phase=2 (DESIGN_REVIEW). design_approved stays
# false — Phase 2 itself emits the design askq later, and approval there
# is what flips design_approved=true and advances to Phase 3.
# Audit event: `phase-transition-to-design-review` with
# `1->2 source=summary-confirm`.

echo "--- test-phase1-to-phase2-ui ---"

_p2_proj="$(setup_test_dir)"

_p2_init_phase1_ui() {
  python3 - "$_p2_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 1, "phase_name": "INTENT",
     "is_ui_project": True, "design_approved": False,
     "spec_hash": None, "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_p2_run_stop() {
  local transcript="$1"
  printf '%s' "{\"transcript_path\":\"${transcript}\",\"session_id\":\"p2\",\"cwd\":\"${_p2_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_p2_proj" \
      MCL_STATE_DIR="$_p2_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

_p2_state_field() {
  python3 -c "import json; d=json.load(open('$_p2_proj/.mcl/state.json')); v=d.get('$1'); print('null' if v is None else (str(v).lower() if isinstance(v,bool) else v))"
}

# ---- Case 1: summary-confirm approve (UI) → state=2 ----
_p2_init_phase1_ui
_p2_t1="$_p2_proj/t1.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_p2_t1" summary-confirm-askq-onayla "Onayla"
_p2_run_stop "$_p2_t1" >/dev/null

assert_equals "[1] UI approve → current_phase=2" "$(_p2_state_field current_phase)" "2"
assert_equals "[1] phase_name=DESIGN_REVIEW" "$(_p2_state_field phase_name)" "DESIGN_REVIEW"
assert_equals "[1] design_approved=false (Phase 2 askq is yet to fire)" "$(_p2_state_field design_approved)" "false"

if grep -qE "phase-transition-to-design-review.*1->2.*source=summary-confirm" "$_p2_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] phase-transition-to-design-review 1->2 source=summary-confirm audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] phase-transition-to-design-review 1->2 audit missing\n'
  grep "phase-transition\|summary-confirm" "$_p2_proj/.mcl/audit.log" 2>/dev/null | tail -3
fi

# ---- Case 2: summary-confirm non-approve → state stays at 1 ----
_p2_init_phase1_ui
rm -f "$_p2_proj/.mcl/audit.log"
_p2_t2="$_p2_proj/t2.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_p2_t2" summary-confirm-askq-onayla "Düzenle"
_p2_run_stop "$_p2_t2" >/dev/null

assert_equals "[2] UI non-approve → current_phase stays 1" "$(_p2_state_field current_phase)" "1"

cleanup_test_dir "$_p2_proj"
