#!/bin/bash
# Test: 9.3.0 Phase 1 summary-confirm askq → Phase 4 transition.
#
# Phase model simplified in 9.3.0: Phase 2 (SPEC_REVIEW) and Phase 3
# (USER_VERIFY) removed. Phase 1 summary-confirm askq IS the gate.
# Approval directly transitions state to current_phase=4 (EXECUTE).

echo "--- test-phase1-to-phase4 ---"

_p4_proj="$(setup_test_dir)"

_p4_init_phase1() {
  python3 - "$_p4_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 2, "current_phase": 1, "phase_name": "COLLECT",
     "ui_flow_active": False,
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_p4_build_summary_askq() {
  local out="$1" selected="${2:-Onayla}"
  python3 - "$out" "$selected" <<'PY'
import json, sys
out, selected = sys.argv[1], sys.argv[2]
question = "MCL 9.3.0 | Bu özet doğru mu?"
turns = [
    {"type":"user","timestamp":"2026-05-01T00:00:00.000Z",
     "message":{"role":"user","content":"build admin panel"}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:30.000Z",
     "message":{"role":"assistant","content":[
         {"type":"text","text":"━━━━━\nÖzet:\n- intent: admin panel\n- stack: React + FastAPI\n━━━━━"}]}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:40.000Z",
     "message":{"role":"assistant","content":[
         {"type":"tool_use","id":"toolu_p4","name":"AskUserQuestion",
          "input":{"questions":[{"question":question,
            "options":[{"label":selected,"description":""},{"label":"Düzenle","description":""},{"label":"İptal","description":""}]}]}}]}},
    {"type":"user","timestamp":"2026-05-01T00:00:50.000Z",
     "message":{"role":"user","content":[
         {"type":"tool_result","tool_use_id":"toolu_p4",
          "content":f"User has answered your questions: \"{question}\"=\"{selected}\"."}]}},
]
with open(out,"w") as f:
    for t in turns: f.write(json.dumps(t)+"\n")
PY
}

_p4_run_stop() {
  local transcript="$1"
  printf '%s' "{\"transcript_path\":\"${transcript}\",\"session_id\":\"p4\",\"cwd\":\"${_p4_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_p4_proj" \
      MCL_STATE_DIR="$_p4_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

_p4_state_field() {
  python3 -c "import json; d=json.load(open('$_p4_proj/.mcl/state.json')); v=d.get('$1'); print('null' if v is None else (str(v).lower() if isinstance(v,bool) else v))"
}

# ---- Case 1: summary-confirm approve → state=4 ----
_p4_init_phase1
_p4_t1="$_p4_proj/t1.jsonl"
_p4_build_summary_askq "$_p4_t1" "Onayla"
_p4_run_stop "$_p4_t1" >/dev/null

assert_equals "[1] approve → current_phase=4" "$(_p4_state_field current_phase)" "4"
assert_equals "[1] phase_name=EXECUTE" "$(_p4_state_field phase_name)" "EXECUTE"

if grep -q "phase-transition-to-execute" "$_p4_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] phase-transition-to-execute audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] phase-transition-to-execute audit missing\n'
fi

# ---- Case 2: summary-confirm non-approve → state stays at 1 ----
_p4_init_phase1
rm -f "$_p4_proj/.mcl/audit.log"
_p4_t2="$_p4_proj/t2.jsonl"
_p4_build_summary_askq "$_p4_t2" "Düzenle"
_p4_run_stop "$_p4_t2" >/dev/null

assert_equals "[2] non-approve → current_phase stays 1" "$(_p4_state_field current_phase)" "1"

# ---- Case 3: state idempotency — already at phase=4, summary-confirm no-op ----
python3 - "$_p4_proj/.mcl/state.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d['current_phase'] = 4; d['phase_name'] = 'EXECUTE'
json.dump(d, open(p, 'w'))
PY
rm -f "$_p4_proj/.mcl/audit.log"
_p4_run_stop "$_p4_t1" >/dev/null

assert_equals "[3] already phase=4 → no second transition" "$(_p4_state_field current_phase)" "4"
if ! grep -q "phase-transition-to-execute.*1->4" "$_p4_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [3] no spurious 1->4 audit when already at 4\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [3] re-transition fired on already-phase-4 state\n'
fi

cleanup_test_dir "$_p4_proj"
