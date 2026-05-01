#!/bin/bash
# Test: 10.0.0 Phase 2 DESIGN_REVIEW gate enforcement.
#
# In 10.0.0 the UI design askq lives at Phase 2 DESIGN_REVIEW. After
# Phase 1 → Phase 2 transition (is_ui_project=true), the model writes
# frontend skeleton files in Phase 2, then must call AskUserQuestion
# with a design-approval prompt. design_approved=true is the gate to
# leave Phase 2 → Phase 3 IMPLEMENTATION.
#
# Failure mode: model writes frontend skeleton + calls localhost dev
# server but does NOT call AskUserQuestion → Stop hook injects
# guidance demanding the design askq.
#
# 

echo "--- test-ui-review-gate ---"


_ur_proj="$(setup_test_dir)"

_ur_init_phase2() {
  python3 - "$_ur_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 2, "phase_name": "DESIGN_REVIEW",
     "is_ui_project": True, "design_approved": False,
     "spec_hash": "deadbeefcafef00d",
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_ur_run_stop() {
  local transcript="$1"
  printf '%s' "{\"transcript_path\":\"${transcript}\",\"session_id\":\"ur\",\"cwd\":\"${_ur_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_ur_proj" \
      MCL_STATE_DIR="$_ur_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

_ur_state_field() {
  python3 -c "import json; d=json.load(open('$_ur_proj/.mcl/state.json')); v=d.get('$1'); print('null' if v is None else (str(v).lower() if isinstance(v,bool) else v))"
}

# ---- Case 1: Phase 2 + frontend files written + no askq → BLOCK ----
_ur_init_phase2
_ur_t1="$_ur_proj/t1.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_ur_t1" spec-correct "Backoffice"
# Append assistant turn with frontend Write tool calls
python3 - "$_ur_t1" <<'PY'
import json, sys
extra = {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
         "message":{"role":"assistant","content":[
             {"type":"tool_use","id":"tu_w1","name":"Write",
              "input":{"file_path":"src/components/UserList.tsx","content":"export default ()=>null;"}},
             {"type":"tool_use","id":"tu_w2","name":"Write",
              "input":{"file_path":"src/pages/Index.tsx","content":"export default ()=>null;"}},
             {"type":"tool_use","id":"tu_w3","name":"Write",
              "input":{"file_path":"package.json","content":"{}"}},
             {"type":"text","text":"UI hazır ve tarayıcıda açıldı: http://localhost:5173/users — incele, sonra geri dön ve ne düşündüğünü yaz."}
         ]}}
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(extra) + "\n")
PY

_ur_out1="$(_ur_run_stop "$_ur_t1")"

assert_contains "[1] Phase 2 + UI files + no askq → decision:block" "$_ur_out1" '"decision": "block"'
assert_contains "[1] reason mandates askq" "$_ur_out1" "AskUserQuestion"

if grep -qE "design-review-gate-block|ui-review-gate-block" "$_ur_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] design-review-gate-block audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] design-review-gate-block audit missing\n'
fi

# ---- Case 2: Phase 2 + askq present → no block (gate satisfied) ----
_ur_init_phase2
rm -f "$_ur_proj/.mcl/audit.log"

_ur_t2="$_ur_proj/t2.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_ur_t2" spec-correct "Backoffice"
python3 - "$_ur_t2" <<'PY'
import json, sys
extra = {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
         "message":{"role":"assistant","content":[
             {"type":"tool_use","id":"tu_w1","name":"Write",
              "input":{"file_path":"src/components/UserList.tsx","content":"x"}},
             {"type":"text","text":"UI hazır: http://localhost:5173"},
             {"type":"tool_use","id":"tu_q","name":"AskUserQuestion",
              "input":{"questions":[{"question":"MCL 10.0.0 | Tasarımı onaylıyor musun?",
                "options":[{"label":"Onayla","description":""},{"label":"Değiştir","description":""},{"label":"İptal","description":""}]}]}}
         ]}}
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(extra) + "\n")
PY

_ur_out2="$(_ur_run_stop "$_ur_t2")"

if printf '%s' "$_ur_out2" | grep -qE "design-review-gate-block|ui-review-gate-block"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [2] gate fired despite askq present\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [2] askq present → gate satisfied (no block)\n'
fi

# ---- Case 3: is_ui_project=false → gate skipped (non-UI project) ----
python3 - "$_ur_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 3, "phase_name": "IMPLEMENTATION",
     "is_ui_project": False, "design_approved": True,
     "spec_hash": "deadbeefcafef00d",
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
rm -f "$_ur_proj/.mcl/audit.log"

_ur_t3="$_ur_proj/t3.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_ur_t3" spec-correct "API"
python3 - "$_ur_t3" <<'PY'
import json, sys
extra = {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
         "message":{"role":"assistant","content":[
             {"type":"tool_use","id":"tu_w1","name":"Write",
              "input":{"file_path":"src/api/users.ts","content":"x"}}
         ]}}
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(extra) + "\n")
PY

_ur_out3="$(_ur_run_stop "$_ur_t3")"

if printf '%s' "$_ur_out3" | grep -qE "design-review-gate-block|UI hazır"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [3] gate fired on non-UI project (is_ui_project=false)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [3] non-UI project → gate skipped\n'
fi

# ---- Case 4: design_approved=true (Phase 3) → gate skipped (already approved) ----
python3 - "$_ur_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 3, "phase_name": "IMPLEMENTATION",
     "is_ui_project": True, "design_approved": True,
     "spec_hash": "deadbeefcafef00d",
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
rm -f "$_ur_proj/.mcl/audit.log"

_ur_t4="$_ur_proj/t4.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_ur_t4" spec-correct "Backoffice"
python3 - "$_ur_t4" <<'PY'
import json, sys
extra = {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
         "message":{"role":"assistant","content":[
             {"type":"tool_use","id":"tu_w1","name":"Write",
              "input":{"file_path":"src/api/users.ts","content":"x"}}
         ]}}
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(extra) + "\n")
PY

_ur_out4="$(_ur_run_stop "$_ur_t4")"

if printf '%s' "$_ur_out4" | grep -qE "design-review-gate-block|UI hazır"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [4] gate fired despite design_approved=true\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [4] design_approved=true → gate skipped (Phase 3 backend open)\n'
fi

cleanup_test_dir "$_ur_proj"
