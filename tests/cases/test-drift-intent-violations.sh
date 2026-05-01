#!/bin/bash
# Test: 10.0.0 Phase 4 RISK_GATE architectural drift + intent violation advisories.
#
# mcl-drift-scan.py compares Phase 3/4 writes against:
#   (a) state.scope_paths — Technical Approach declared paths
#   (b) state.phase1_intent + state.phase1_constraints
# Findings are ADVISORY (audit only) — no decision:block.

echo "--- test-drift-intent-violations ---"


_dr_proj="$(setup_test_dir)"

_dr_init() {
  python3 - "$_dr_proj/.mcl/state.json" "$1" "$2" <<'PY'
import json, sys, time
state_path, intent, constraints = sys.argv[1:4]
o = {"schema_version": 3, "current_phase": 4, "phase_name": "RISK_GATE",
     "is_ui_project": False, "design_approved": True,
     "spec_hash": "deadbeef",
     "phase1_intent": intent,
     "phase1_constraints": constraints,
     "scope_paths": ["src/components/", "src/pages/", "package.json"],
     "phase4_security_scan_done": False,
     "phase4_db_scan_done": False,
     "phase4_ui_scan_done": False,
     "phase4_ops_scan_done": False,
     "phase4_perf_scan_done": False,
     "last_update": int(time.time())}
open(state_path, "w").write(json.dumps(o))
PY
}

_dr_build_transcript() {
  # Args: out_path, file_path, content
  python3 - "$@" <<'PY'
import json, sys
out, fp, content = sys.argv[1:4]
spec = """📋 Spec:

## [Frontend Only]

## Objective
Build static admin panel.

## MUST
- React frontend

## SHOULD
- Tailwind

## Acceptance Criteria
- [ ] renders

## Edge Cases
- empty list

## Technical Approach
- src/components/, src/pages/

## Out of Scope
- backend, db, auth
"""
turns = [
    {"type":"user","timestamp":"2026-05-01T00:00:00.000Z",
     "message":{"role":"user","content":"build it"}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:30.000Z",
     "message":{"role":"assistant","content":[{"type":"text","text":spec}]}},
    {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
     "message":{"role":"assistant","content":[
         {"type":"tool_use","id":"toolu_w","name":"Write",
          "input":{"file_path":fp,"content":content}}]}},
]
with open(out,"w") as f:
    for t in turns: f.write(json.dumps(t)+"\n")
PY
}

_dr_run_drift_direct() {
  python3 "$REPO_ROOT/hooks/lib/mcl-drift-scan.py" \
    --state-dir "$_dr_proj/.mcl" \
    --project-dir "$_dr_proj" \
    --transcript "$1" 2>/dev/null
}

_dr_run_stop() {
  printf '%s' "{\"transcript_path\":\"$1\",\"session_id\":\"dr\",\"cwd\":\"${_dr_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_dr_proj" \
      MCL_STATE_DIR="$_dr_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1
}

# ---- Case 1: drift — write outside scope_paths ----
_dr_init "build static admin panel" "react + tailwind, no backend"
_dr_t1="$_dr_proj/t1.jsonl"
mkdir -p "$_dr_proj/src/api"
_dr_build_transcript "$_dr_t1" "src/api/users.ts" "export const list = () => [];"

_dr_out1="$(_dr_run_drift_direct "$_dr_t1")"
_dr_drift_count="$(printf '%s' "$_dr_out1" | python3 -c \
  'import json,sys; r=json.loads(sys.stdin.read() or "{}"); print(len(r.get("drift_findings",[])))' 2>/dev/null)"

if [ "$_dr_drift_count" -ge 1 ] 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] drift detected (%s finding(s))\n' "$_dr_drift_count"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] drift not detected. output: %s\n' "$(printf '%s' "$_dr_out1" | head -c 200)"
fi

# Hook integration: stop hook should emit phase4-drift audit.
_dr_run_stop "$_dr_t1"
if grep -q "phase4-drift" "$_dr_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] phase4-drift audit captured by stop hook\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] phase4-drift audit missing from stop hook run\n'
fi

# Critical: drift is ADVISORY — Write should still be allowed.
# (Just verify the hook didn't emit decision:block)
_dr_stop_out="$(printf '%s' "{\"transcript_path\":\"$_dr_t1\",\"session_id\":\"dr2\",\"cwd\":\"${_dr_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_dr_proj" MCL_STATE_DIR="$_dr_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"
# decision:block may still come from Phase 4 START reminder (legitimate).
# But the drift itself should NOT cause a block message about drift.
if printf '%s' "$_dr_stop_out" | grep -q "drift.*BLOCKED\|drift.*deny"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] drift produced a hard block (should be advisory)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [1] drift is advisory (no hard block)\n'
fi

# ---- Case 2: intent violation — phase1_intent says "no auth" but writes auth code ----
_dr_init "static frontend, no auth" "React + Tailwind, no backend, no auth"
_dr_t2="$_dr_proj/t2.jsonl"
mkdir -p "$_dr_proj/src/components"
_dr_build_transcript "$_dr_t2" "src/components/Login.tsx" \
  "import NextAuth from 'next-auth';\nexport const auth = NextAuth({});"

_dr_out2="$(_dr_run_drift_direct "$_dr_t2")"
_dr_iv_count="$(printf '%s' "$_dr_out2" | python3 -c \
  'import json,sys; r=json.loads(sys.stdin.read() or "{}"); print(len(r.get("intent_violations",[])))' 2>/dev/null)"

if [ "$_dr_iv_count" -ge 1 ] 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [2] intent violation detected (%s finding(s))\n' "$_dr_iv_count"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [2] intent violation not detected. output: %s\n' "$(printf '%s' "$_dr_out2" | head -c 250)"
fi

rm -f "$_dr_proj/.mcl/audit.log"
_dr_run_stop "$_dr_t2"
if grep -q "phase4-intent-violation" "$_dr_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [2] phase4-intent-violation audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [2] phase4-intent-violation audit missing\n'
fi

# ---- Case 3: clean write within scope, no intent violation → no findings ----
_dr_init "build admin panel" "React + Tailwind"
_dr_t3="$_dr_proj/t3.jsonl"
mkdir -p "$_dr_proj/src/components"
_dr_build_transcript "$_dr_t3" "src/components/UserList.tsx" \
  "export default function UserList() { return null; }"

_dr_out3="$(_dr_run_drift_direct "$_dr_t3")"
_dr_total="$(printf '%s' "$_dr_out3" | python3 -c \
  'import json,sys; r=json.loads(sys.stdin.read() or "{}"); print(len(r.get("drift_findings",[]))+len(r.get("intent_violations",[])))' 2>/dev/null)"

assert_equals "[3] clean write → 0 findings" "$_dr_total" "0"

cleanup_test_dir "$_dr_proj"
