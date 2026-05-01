#!/bin/bash
# Test: Phase 4 RISK_GATE gates fire correctly in default mode (sec/db/ui).
#
# When Phase 3 IMPLEMENTATION ends with code writes and the project
# enters Phase 4 RISK_GATE with phase4_*_scan_done=false, the Stop hook
# runs the security/db/ui scan helpers and emits `decision:block` with
# the Phase 4 START reminder. State flags `phase4_security_scan_done`,
# `phase4_db_scan_done`, `phase4_ui_scan_done` flip to true after each
# scan completes.

echo "--- test-phase4-gates ---"

_pf_proj="$(setup_test_dir)"

_pf_init_phase4() {
  python3 - "$_pf_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 4, "phase_name": "RISK_GATE",
     "is_ui_project": False, "design_approved": True,
     "spec_hash": "deadbeefcafef00d1234567890abcdef",
     "phase4_security_scan_done": False,
     "phase4_db_scan_done": False,
     "phase4_ui_scan_done": False,
     "phase4_ops_scan_done": False,
     "phase4_perf_scan_done": False,
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_pf_init_phase4

# Build a Phase 3 transcript: spec block + Write tool call (signal that
# code was written, triggers Phase 4 RISK_GATE START gate).
_pf_t="$_pf_proj/t.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_pf_t" spec-correct "Admin Panel"
python3 - "$_pf_t" <<'PY'
import json, sys
path = sys.argv[1]
extra = {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
         "message":{"role":"assistant","content":[
             {"type":"tool_use","id":"toolu_w1","name":"Write",
              "input":{"file_path":"src/index.ts","content":"export const x = 1;"}}]}}
with open(path, "a") as f:
    f.write(json.dumps(extra) + "\n")
PY

_pf_out="$(printf '%s' "{\"transcript_path\":\"${_pf_t}\",\"session_id\":\"pf\",\"cwd\":\"${_pf_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_pf_proj" \
    MCL_STATE_DIR="$_pf_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"

# Stop hook should emit a Phase 4 START reminder block (decision:block).
assert_contains "[default] Phase 4 RISK_GATE Stop → decision:block" "$_pf_out" '"decision": "block"'
assert_contains "[default] reminder mentions Phase 4" "$_pf_out" "Phase 4"

# State should show all 5 scans done (clean project → HIGH=0 baseline).
_pf_sec="$(python3 -c "import json; print(json.load(open('$_pf_proj/.mcl/state.json')).get('phase4_security_scan_done', False))")"
_pf_db="$(python3 -c "import json; print(json.load(open('$_pf_proj/.mcl/state.json')).get('phase4_db_scan_done', False))")"
_pf_ui="$(python3 -c "import json; print(json.load(open('$_pf_proj/.mcl/state.json')).get('phase4_ui_scan_done', False))")"
_pf_ops="$(python3 -c "import json; print(json.load(open('$_pf_proj/.mcl/state.json')).get('phase4_ops_scan_done', False))")"
_pf_perf="$(python3 -c "import json; print(json.load(open('$_pf_proj/.mcl/state.json')).get('phase4_perf_scan_done', False))")"
assert_equals "[default] security scan done" "$_pf_sec" "True"
assert_equals "[default] db scan done" "$_pf_db" "True"
assert_equals "[default] ui scan done" "$_pf_ui" "True"
assert_equals "[default] ops scan done" "$_pf_ops" "True"
assert_equals "[default] perf scan done" "$_pf_perf" "True"

cleanup_test_dir "$_pf_proj"
