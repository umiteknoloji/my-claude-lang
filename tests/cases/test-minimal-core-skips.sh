#!/bin/bash
# Test: MCL_MINIMAL_CORE=1 actually skips the listed non-essential systems.
#
# 9.2.0 introduced MCL_MINIMAL_CORE=1 to disable Phase 4 ops/perf/test
# coverage gates, Phase 6, hook-debug blocks, partial-spec recovery,
# and per-write severity enforcement. Code stays in place; runtime
# guards short-circuit.
#
# This test confirms each guard fires in the right direction:
#   default mode: feature engaged
#   MCL_MINIMAL_CORE=1: feature skipped, audit/state evidence-of-skip

echo "--- test-minimal-core-skips ---"

_mc_proj="$(setup_test_dir)"

_mc_init_phase4_state() {
  python3 - "$_mc_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 4, "phase_name": "RISK_GATE",
     "is_ui_project": False, "design_approved": True,
     "spec_hash": "deadbeefcafef00d1234567890abcdef",
     "phase4_ops_scan_done": False,
     "phase4_perf_scan_done": False,
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

# ---- Case 1: ops/perf scans marked done in MINIMAL mode ----
_mc_init_phase4_state
rm -f "$_mc_proj/.mcl/audit.log"
_mc_t1="$_mc_proj/t1.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_mc_t1" spec-correct "Admin Panel"

# A code-write turn (simulates Phase 4 work-in-progress).
python3 - "$_mc_t1" <<'PY'
import json, sys
path = sys.argv[1]
extra = {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
         "message":{"role":"assistant","content":[
             {"type":"tool_use","id":"toolu_w1","name":"Write",
              "input":{"file_path":"/tmp/foo.ts","content":"hi"}}]}}
with open(path, "a") as f:
    f.write(json.dumps(extra) + "\n")
PY

MCL_MINIMAL_CORE=1 \
  CLAUDE_PROJECT_DIR="$_mc_proj" \
  MCL_STATE_DIR="$_mc_proj/.mcl" \
  MCL_REPO_PATH="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1 \
  <<< "{\"transcript_path\":\"${_mc_t1}\",\"session_id\":\"mc1\",\"cwd\":\"${_mc_proj}\"}"

_ops_done="$(python3 -c "import json; print(json.load(open('$_mc_proj/.mcl/state.json')).get('phase4_ops_scan_done', False))")"
_perf_done="$(python3 -c "import json; print(json.load(open('$_mc_proj/.mcl/state.json')).get('phase4_perf_scan_done', False))")"
assert_equals "[MINIMAL] ops scan marked done (skip-mode)" "$_ops_done" "True"
assert_equals "[MINIMAL] perf scan marked done (skip-mode)" "$_perf_done" "True"

if grep -q "ops-scan-block\|ops-medium-prose" "$_mc_proj/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [MINIMAL] ops scan fired audit (should have been skipped)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [MINIMAL] ops scan produced no audit (skipped)\n'
fi

# ---- Case 2: hook-debug Read on MCL paths in MINIMAL mode → ALLOWED ----
# Create a fresh project with phase=2 (hook-debug only fires in Phase 1-3).
_mc_init_phase2() {
  python3 - "$_mc_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 2, "phase_name": "DESIGN_REVIEW",
     "is_ui_project": True, "design_approved": False,
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}
_mc_init_phase2
rm -f "$_mc_proj/.mcl/audit.log"

_pre_input='{"tool_name":"Read","tool_input":{"file_path":"/Users/x/.mcl/lib/hooks/lib/mcl-state.sh"},"transcript_path":"'"$_mc_t1"'","session_id":"mc2","cwd":"'"$_mc_proj"'"}'

# Default mode → DENY
_default_out="$(printf '%s' "$_pre_input" | \
  CLAUDE_PROJECT_DIR="$_mc_proj" MCL_STATE_DIR="$_mc_proj/.mcl" \
  MCL_REPO_PATH="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null)"
assert_contains "[default] Read on hook path → deny" "$_default_out" '"permissionDecision": "deny"'

# MINIMAL mode → no hook-debug deny (project-isolation may still fire on /Users/x/)
_mc_init_phase2
rm -f "$_mc_proj/.mcl/audit.log"
_minimal_out="$(printf '%s' "$_pre_input" | \
  MCL_MINIMAL_CORE=1 \
  CLAUDE_PROJECT_DIR="$_mc_proj" MCL_STATE_DIR="$_mc_proj/.mcl" \
  MCL_REPO_PATH="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null)"

# In MINIMAL mode, hook-debug branch is skipped. The project-isolation
# branch still fires for cross-project paths. So we should NOT see a
# block-hook-debug audit (but may see block-isolation).
if grep -q "block-hook-debug" "$_mc_proj/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [MINIMAL] block-hook-debug fired (should be skipped)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [MINIMAL] block-hook-debug skipped\n'
fi

# ---- Case 3: partial-spec recovery skipped in MINIMAL mode ----
_mc_init_phase2
rm -f "$_mc_proj/.mcl/audit.log"
_mc_t3="$_mc_proj/t3.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_mc_t3" spec-partial "Edge Cases,Out of Scope"

MCL_MINIMAL_CORE=1 \
  CLAUDE_PROJECT_DIR="$_mc_proj" \
  MCL_STATE_DIR="$_mc_proj/.mcl" \
  MCL_REPO_PATH="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1 \
  <<< "{\"transcript_path\":\"${_mc_t3}\",\"session_id\":\"mc3\",\"cwd\":\"${_mc_proj}\"}"

if grep -q "partial-spec " "$_mc_proj/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [MINIMAL] partial-spec audit fired (should be skipped)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [MINIMAL] partial-spec recovery skipped\n'
fi

cleanup_test_dir "$_mc_proj"
