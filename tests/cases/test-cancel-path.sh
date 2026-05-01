#!/bin/bash
# Test: 10.0.4 cancel-path branch — Phase 2/3 → Phase 1 rollback.
#
# Covers Patch C from 10.0.4: when current_phase > 1 and the last user
# message is a clean cancel token (≤30 chars, exact match after lowercase
# + lead/trail strip against CANCEL_WORDS), reset to Phase 1 and clear
# all Phase 2+ flags. Approval-style tightening prevents false-positives
# like "geri al feature X" from matching as cancel intent.
#
# Acceptance:
#   1. Phase 2 + "iptal"   → phase=1, design_approved=false,
#                            phase-rollback-via-cancel audit captured.
#   2. Phase 3 + "cancel"  → phase=1, all Phase 2+ flags cleared.
#   3. Phase 2 + "geri al feature X" → NO rollback (multi-word guard).
#   4. Phase 1 + "iptal"   → noop (no rollback audit).
#   5. Phase 2 + 50-char message containing "iptal" → no rollback.

echo "--- test-cancel-path ---"

_cp_make_transcript() {
  local path="$1"
  local last_user="$2"
  python3 - "$path" "$last_user" <<'PY'
import json, sys
path, last_user = sys.argv[1], sys.argv[2]
turns = [
    {"type":"user","timestamp":"2026-05-01T00:00:00Z",
     "message":{"role":"user","content":"backoffice yap"}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:30Z",
     "message":{"role":"assistant","content":[{"type":"text","text":"Özet:\n- intent: x\nOnaylıyor musun?"}]}},
    {"type":"user","timestamp":"2026-05-01T00:00:45Z",
     "message":{"role":"user","content":"evet"}},
    {"type":"user","timestamp":"2026-05-01T00:01:00Z",
     "message":{"role":"user","content": last_user}},
]
with open(path, "w") as fh:
    for t in turns:
        fh.write(json.dumps(t) + "\n")
PY
}

_cp_init_state() {
  local state_file="$1"
  local phase="$2"
  local design_approved="$3"
  python3 - "$state_file" "$phase" "$design_approved" <<'PY'
import json, sys, time
o = {
    "schema_version": 3,
    "current_phase": int(sys.argv[2]),
    "phase_name": "DESIGN_REVIEW" if sys.argv[2]=="2" else ("IMPLEMENTATION" if sys.argv[2]=="3" else "INTENT"),
    "is_ui_project": True,
    "design_approved": sys.argv[3] == "true",
    "ui_flow_active": True,
    "ui_sub_phase": "BACKEND",
    "ui_reviewed": True,
    "risk_accepted": True,
    "spec_gate_passed": True,
    "phase4_security_scan_done": True,
    "phase4_db_scan_done": True,
    "phase4_ui_scan_done": True,
    "phase4_ops_scan_done": True,
    "phase6_double_check_done": True,
    "pattern_scan_due": True,
    "phase1_turn_count": 5,
    "spec_hash": None,
    "last_update": int(time.time()),
}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_cp_run_stop() {
  local proj="$1"
  local transcript="$2"
  printf '%s' "{\"transcript_path\":\"${transcript}\",\"session_id\":\"cp\",\"cwd\":\"${proj}\"}" \
    | CLAUDE_PROJECT_DIR="$proj" \
      MCL_STATE_DIR="$proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

# ============================================================
# Case 1: Phase 2 + clean "iptal" → rollback to Phase 1
# ============================================================
_cp_proj1="$(setup_test_dir)"
_cp_init_state "$_cp_proj1/.mcl/state.json" 2 true
_cp_t1="$_cp_proj1/t1.jsonl"
_cp_make_transcript "$_cp_t1" "iptal"
_cp_run_stop "$_cp_proj1" "$_cp_t1" >/dev/null

_cp_phase1="$(python3 -c "import json; print(json.load(open('$_cp_proj1/.mcl/state.json')).get('current_phase'))")"
_cp_pname1="$(python3 -c "import json; print(json.load(open('$_cp_proj1/.mcl/state.json')).get('phase_name'))")"
_cp_da1="$(python3 -c "import json; print(json.load(open('$_cp_proj1/.mcl/state.json')).get('design_approved'))")"

assert_equals "[1] Phase 2 + 'iptal' → current_phase=1" "$_cp_phase1" "1"
assert_equals "[1] phase_name=INTENT after rollback" "$_cp_pname1" "INTENT"
assert_equals "[1] design_approved reset to false" "$_cp_da1" "False"

if grep -q "phase-rollback-via-cancel" "$_cp_proj1/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] phase-rollback-via-cancel audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] phase-rollback-via-cancel audit missing\n'
fi

if grep -qE 'from=2[^0-9]' "$_cp_proj1/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] audit detail records from=2\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] audit detail missing from=2\n'
fi

cleanup_test_dir "$_cp_proj1"

# ============================================================
# Case 2: Phase 3 + "cancel" → rollback + Phase 2+ flags cleared
# ============================================================
_cp_proj2="$(setup_test_dir)"
_cp_init_state "$_cp_proj2/.mcl/state.json" 3 true
_cp_t2="$_cp_proj2/t2.jsonl"
_cp_make_transcript "$_cp_t2" "cancel"
_cp_run_stop "$_cp_proj2" "$_cp_t2" >/dev/null

_cp_phase2="$(python3 -c "import json; print(json.load(open('$_cp_proj2/.mcl/state.json')).get('current_phase'))")"
_cp_uifa="$(python3 -c "import json; print(json.load(open('$_cp_proj2/.mcl/state.json')).get('ui_flow_active'))")"
_cp_specg="$(python3 -c "import json; print(json.load(open('$_cp_proj2/.mcl/state.json')).get('spec_gate_passed'))")"
_cp_p4sec="$(python3 -c "import json; print(json.load(open('$_cp_proj2/.mcl/state.json')).get('phase4_security_scan_done'))")"
_cp_turn="$(python3 -c "import json; print(json.load(open('$_cp_proj2/.mcl/state.json')).get('phase1_turn_count'))")"

assert_equals "[2] Phase 3 + 'cancel' → current_phase=1" "$_cp_phase2" "1"
assert_equals "[2] ui_flow_active reset to false" "$_cp_uifa" "False"
assert_equals "[2] spec_gate_passed reset to false" "$_cp_specg" "False"
assert_equals "[2] phase4_security_scan_done reset to false" "$_cp_p4sec" "False"
assert_equals "[2] phase1_turn_count reset to 0" "$_cp_turn" "0"

cleanup_test_dir "$_cp_proj2"

# ============================================================
# Case 3: Phase 2 + "geri al feature X" → NO rollback (multi-word)
# ============================================================
_cp_proj3="$(setup_test_dir)"
_cp_init_state "$_cp_proj3/.mcl/state.json" 2 true
_cp_t3="$_cp_proj3/t3.jsonl"
_cp_make_transcript "$_cp_t3" "geri al feature X"
_cp_run_stop "$_cp_proj3" "$_cp_t3" >/dev/null

_cp_phase3="$(python3 -c "import json; print(json.load(open('$_cp_proj3/.mcl/state.json')).get('current_phase'))")"
_cp_da3="$(python3 -c "import json; print(json.load(open('$_cp_proj3/.mcl/state.json')).get('design_approved'))")"

assert_equals "[3] 'geri al feature X' → no rollback (phase stays 2)" "$_cp_phase3" "2"
assert_equals "[3] design_approved untouched" "$_cp_da3" "True"

if grep -q "phase-rollback-via-cancel" "$_cp_proj3/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [3] false-positive — multi-word "geri al X" triggered cancel\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [3] no phase-rollback audit for multi-word "geri al X"\n'
fi

cleanup_test_dir "$_cp_proj3"

# ============================================================
# Case 4: Phase 1 + "iptal" → noop (no rollback fired)
# ============================================================
_cp_proj4="$(setup_test_dir)"
_cp_init_state "$_cp_proj4/.mcl/state.json" 1 false
_cp_t4="$_cp_proj4/t4.jsonl"
_cp_make_transcript "$_cp_t4" "iptal"
_cp_run_stop "$_cp_proj4" "$_cp_t4" >/dev/null

if grep -q "phase-rollback-via-cancel" "$_cp_proj4/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [4] cancel-path fired at phase=1 (should be noop)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [4] phase=1 + iptal → no rollback audit\n'
fi

cleanup_test_dir "$_cp_proj4"

# ============================================================
# Case 5: Phase 2 + long text containing "iptal" → no rollback
# ============================================================
_cp_proj5="$(setup_test_dir)"
_cp_init_state "$_cp_proj5/.mcl/state.json" 2 true
_cp_t5="$_cp_proj5/t5.jsonl"
_cp_make_transcript "$_cp_t5" "bence iptal etmek yerine devam etsek daha iyi olur"
_cp_run_stop "$_cp_proj5" "$_cp_t5" >/dev/null

_cp_phase5="$(python3 -c "import json; print(json.load(open('$_cp_proj5/.mcl/state.json')).get('current_phase'))")"
assert_equals "[5] long text with 'iptal' inside → phase stays 2" "$_cp_phase5" "2"

if grep -q "phase-rollback-via-cancel" "$_cp_proj5/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [5] long text triggered cancel (>30 char guard broken)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [5] long text with embedded "iptal" → no rollback\n'
fi

cleanup_test_dir "$_cp_proj5"
