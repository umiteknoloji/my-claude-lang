#!/bin/bash
# Test: 9.2.3 UI_REVIEW gate enforcement.
#
# Real-session bug (vaad #2): model wrote UI files in Phase 4a, ran
# dev server, then said "uygulamayı kullanabilirsin" and finished —
# bypassing Phase 4b review gate entirely.
#
# 9.2.3 fix: hook auto-advances ui_sub_phase BUILD_UI → UI_REVIEW when
# frontend files are detected, then blocks Stop until model calls
# AskUserQuestion with a UI-review prompt.
#
# Skipped under MCL_MINIMAL_CORE=1 (UI gate is non-essential there).

echo "--- test-ui-review-gate ---"

if [ "${MCL_MINIMAL_CORE:-0}" = "1" ]; then
  printf '  SKIP: ui-review-gate disabled (MCL_MINIMAL_CORE=1)\n'
  return 0 2>/dev/null || true
fi

_ur_proj="$(setup_test_dir)"

_ur_init_4a() {
  python3 - "$_ur_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 2, "current_phase": 4, "phase_name": "EXECUTE",
     "spec_approved": True, "spec_hash": "deadbeefcafef00d",
     "ui_flow_active": True, "ui_sub_phase": "BUILD_UI",
     "ui_reviewed": False,
     "phase4_5_security_scan_done": True, "phase4_5_db_scan_done": True,
     "phase4_5_ui_scan_done": True, "phase4_5_ops_scan_done": True,
     "phase4_5_perf_scan_done": True,
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

# ---- Case 1: BUILD_UI + frontend files written + no askq → BLOCK ----
_ur_init_4a
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
              "input":{"file_path":"package.json","content":"{}"}},
             {"type":"text","text":"UI hazır ve tarayıcıda açıldı: http://localhost:5173/users — incele, sonra geri dön ve ne düşündüğünü yaz."}
         ]}}
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(extra) + "\n")
PY

_ur_out1="$(_ur_run_stop "$_ur_t1")"

assert_contains "[1] BUILD_UI + UI files + no askq → decision:block" "$_ur_out1" '"decision": "block"'
assert_contains "[1] reason mandates askq" "$_ur_out1" "AskUserQuestion"
assert_contains "[1] reason references phase4b" "$_ur_out1" "phase4b-ui-review.md"

_ur_sub1="$(_ur_state_field ui_sub_phase)"
assert_equals "[1] auto-advance BUILD_UI → UI_REVIEW" "$_ur_sub1" "UI_REVIEW"

if grep -q "ui-sub-phase-auto-advance" "$_ur_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] ui-sub-phase-auto-advance audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] ui-sub-phase-auto-advance audit missing\n'
fi

if grep -q "ui-review-gate-block" "$_ur_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] ui-review-gate-block audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] ui-review-gate-block audit missing\n'
fi

# ---- Case 2: UI_REVIEW + askq present → no block (gate satisfied) ----
_ur_init_4a
# Pre-set ui_sub_phase=UI_REVIEW (we're testing the askq satisfaction path)
python3 -c "
import json
p='$_ur_proj/.mcl/state.json'
d=json.load(open(p)); d['ui_sub_phase']='UI_REVIEW'
open(p,'w').write(json.dumps(d))
"
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
              "input":{"questions":[{"question":"MCL 9.2.3 | Tasarımı onaylıyor musun?",
                "options":[{"label":"Onayla","description":""},{"label":"Değiştir","description":""},{"label":"İptal","description":""}]}]}}
         ]}}
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(extra) + "\n")
PY

_ur_out2="$(_ur_run_stop "$_ur_t2")"

if printf '%s' "$_ur_out2" | grep -q "ui-review-gate-block\|UI hazır. Phase 4b zorunlu"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [2] gate fired despite askq present\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [2] askq present → gate satisfied (no block)\n'
fi

# ---- Case 3: ui_flow_active=false → gate skipped (non-UI project) ----
_ur_init_4a
python3 -c "
import json
p='$_ur_proj/.mcl/state.json'
d=json.load(open(p)); d['ui_flow_active']=False
open(p,'w').write(json.dumps(d))
"
rm -f "$_ur_proj/.mcl/audit.log"

_ur_t3="$_ur_proj/t3.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_ur_t3" spec-correct "API"
python3 - "$_ur_t3" <<'PY'
import json, sys
extra = {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
         "message":{"role":"assistant","content":[
             {"type":"tool_use","id":"tu_w1","name":"Write",
              "input":{"file_path":"src/components/UserList.tsx","content":"x"}}
         ]}}
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(extra) + "\n")
PY

_ur_out3="$(_ur_run_stop "$_ur_t3")"

if printf '%s' "$_ur_out3" | grep -q "UI hazır"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [3] gate fired on non-UI project (ui_flow_active=false)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [3] non-UI project → gate skipped\n'
fi

# ---- Case 4: ui_reviewed=true → gate skipped (already approved) ----
_ur_init_4a
python3 -c "
import json
p='$_ur_proj/.mcl/state.json'
d=json.load(open(p)); d['ui_sub_phase']='BACKEND'; d['ui_reviewed']=True
open(p,'w').write(json.dumps(d))
"
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

if printf '%s' "$_ur_out4" | grep -q "UI hazır"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [4] gate fired despite ui_reviewed=true\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [4] ui_reviewed=true → gate skipped (Phase 4c open)\n'
fi

cleanup_test_dir "$_ur_proj"
