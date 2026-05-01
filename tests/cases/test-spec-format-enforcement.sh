#!/bin/bash
# Test: 9.3.0 spec format violations are ADVISORY (audit only).
#
# Spec emission is documentation, not a state gate. Format violations
# (missing 7 H2 sections, no 📋 prefix) → audit warning + continue.
# Write/Edit stays unlocked because Phase 4 is independent of spec
# format (Phase 1 summary-confirm is the gate).

echo "--- test-spec-format-enforcement ---"

if [ "${MCL_MINIMAL_CORE:-0}" = "1" ]; then
  printf '  SKIP: spec-format-enforcement disabled (MCL_MINIMAL_CORE=1)\n'
  return 0 2>/dev/null || true
fi

_sf_proj="$(setup_test_dir)"

_sf_init() {
  python3 - "$_sf_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 2, "current_phase": 4, "phase_name": "EXECUTE",
     "spec_hash": None,
     "ui_flow_active": False,
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_sf_run_partial_check() {
  local transcript="$1"
  set +e
  _SF_LAST_OUT="$(bash "$REPO_ROOT/hooks/lib/mcl-partial-spec.sh" check "$transcript" 2>/dev/null)"
  _SF_LAST_RC=$?
  set -e
}

_sf_run_stop() {
  printf '%s' "{\"transcript_path\":\"$1\",\"session_id\":\"sf\",\"cwd\":\"${_sf_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_sf_proj" \
      MCL_STATE_DIR="$_sf_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

# ---- Case 1: bare "Spec:" → rc=3, advisory only ----
_sf_init
_sf_t1="$_sf_proj/t1.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t1" spec-no-emoji-bare
_sf_run_partial_check "$_sf_t1"
assert_equals "bare 'Spec:' → partial-spec rc=3" "$_SF_LAST_RC" "3"

_sf_out1="$(_sf_run_stop "$_sf_t1")"
# Advisory only — no decision:block in output.
if printf '%s' "$_sf_out1" | grep -q '"decision": "block"'; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] bare Spec: produced decision:block (should be advisory)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [1] bare Spec: → no decision:block (advisory)\n'
fi
if grep -q "spec-format-warn" "$_sf_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] spec-format-warn audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] spec-format-warn audit missing\n'
fi

# ---- Case 2: missing H2 sections → rc=0, advisory only ----
_sf_init
rm -f "$_sf_proj/.mcl/audit.log"
_sf_t2="$_sf_proj/t2.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t2" spec-partial "Edge Cases,Out of Scope"
_sf_run_partial_check "$_sf_t2"
assert_equals "missing sections → partial-spec rc=0" "$_SF_LAST_RC" "0"

_sf_out2="$(_sf_run_stop "$_sf_t2")"
if printf '%s' "$_sf_out2" | grep -q '"decision": "block".*[Ss]pec.*missing\|MCL.*Spec.*eksik'; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [2] missing sections produced spec-format block (should be advisory)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [2] missing sections → no spec-format block (advisory)\n'
fi
if grep -q "spec-format-warn" "$_sf_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [2] spec-format-warn audit captured (missing sections)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [2] spec-format-warn audit missing\n'
fi

# ---- Case 3: canonical spec → rc=1 (clean) ----
_sf_init
rm -f "$_sf_proj/.mcl/audit.log"
_sf_t3="$_sf_proj/t3.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t3" spec-correct "Test"
_sf_run_partial_check "$_sf_t3"
assert_equals "canonical spec → partial-spec rc=1" "$_SF_LAST_RC" "1"

# ---- Case 4: Phase 4 Write attempt with bad spec → STILL ALLOWED ----
_sf_init
rm -f "$_sf_proj/.mcl/audit.log"
_sf_t4="$_sf_proj/t4.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t4" spec-no-emoji-bare
# Pre-tool Write attempt with state at phase=4 (already past summary-confirm).
_sf_payload="$(python3 -c "
import json,sys
print(json.dumps({
  'tool_name':'Write',
  'tool_input':{'file_path':sys.argv[1],'content':'export default 1;'},
  'transcript_path':sys.argv[2],
  'session_id':'sf','cwd':sys.argv[3]
}))" "$_sf_proj/src/x.ts" "$_sf_t4" "$_sf_proj")"

_sf_out4="$(printf '%s' "$_sf_payload" \
  | CLAUDE_PROJECT_DIR="$_sf_proj" \
    MCL_STATE_DIR="$_sf_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null)"

if [ -z "$_sf_out4" ] || ! printf '%s' "$_sf_out4" | grep -q '"permissionDecision": "deny"'; then
  PASS=$((PASS+1))
  printf '  PASS: [4] Phase 4 Write with bad spec → ALLOWED (advisory only)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [4] Phase 4 Write blocked despite advisory spec format\n'
  printf '        output: %s\n' "$(printf '%s' "$_sf_out4" | head -c 200)"
fi

cleanup_test_dir "$_sf_proj"
