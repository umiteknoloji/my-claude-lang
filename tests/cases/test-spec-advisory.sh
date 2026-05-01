#!/bin/bash
# Test: 10.0.0 spec format violations are ADVISORY (audit only).
#
# In 10.0.0 the 📋 Spec: format check no longer blocks Write/Edit.
# When the model emits a malformed spec (no 📋 emoji, missing H2
# sections, etc.), the Stop hook writes a `spec-format-warn` audit
# event but does NOT emit `decision:block`. Phase 3 Write/Edit stays
# unlocked because Phase 1 summary-confirm IS the gate.

echo "--- test-spec-advisory ---"

if [ "${MCL_MINIMAL_CORE:-0}" = "1" ]; then
  printf '  SKIP: spec-advisory disabled (MCL_MINIMAL_CORE=1)\n'
  return 0 2>/dev/null || true
fi

_sa_proj="$(setup_test_dir)"

_sa_init() {
  python3 - "$_sa_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 3, "phase_name": "IMPLEMENTATION",
     "is_ui_project": False, "design_approved": True,
     "spec_hash": None,
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_sa_run_stop() {
  printf '%s' "{\"transcript_path\":\"$1\",\"session_id\":\"sa\",\"cwd\":\"${_sa_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_sa_proj" \
      MCL_STATE_DIR="$_sa_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

# ---- Case 1: bare "Spec:" without 📋 → spec-format-warn audit, no block ----
_sa_init
_sa_t1="$_sa_proj/t1.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sa_t1" spec-no-emoji-bare
_sa_out1="$(_sa_run_stop "$_sa_t1")"

if printf '%s' "$_sa_out1" | grep -qE '"decision": "block".*[Ss]pec format|MCL SPEC FORMAT|MCL SPEC RECOVERY'; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] bare Spec: produced spec-format hard block (should be advisory)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [1] bare Spec: → no spec-format hard block (advisory)\n'
fi
if grep -q "spec-format-warn" "$_sa_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] spec-format-warn audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] spec-format-warn audit missing\n'
fi

# ---- Case 2: missing H2 sections → spec-format-warn, no block ----
_sa_init
rm -f "$_sa_proj/.mcl/audit.log"
_sa_t2="$_sa_proj/t2.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sa_t2" spec-partial "Edge Cases,Out of Scope"
_sa_out2="$(_sa_run_stop "$_sa_t2")"

if printf '%s' "$_sa_out2" | grep -qE '"decision": "block".*[Ss]pec format|MCL SPEC FORMAT|MCL SPEC RECOVERY'; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [2] missing sections produced spec-format hard block (should be advisory)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [2] missing sections → no spec-format hard block (advisory)\n'
fi
if grep -q "spec-format-warn" "$_sa_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [2] spec-format-warn audit captured (missing sections)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [2] spec-format-warn audit missing\n'
fi

# ---- Case 3: canonical spec → NO warn audit ----
_sa_init
rm -f "$_sa_proj/.mcl/audit.log"
_sa_t3="$_sa_proj/t3.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sa_t3" spec-correct "Test"
_sa_run_stop "$_sa_t3" >/dev/null

if grep -q "spec-format-warn" "$_sa_proj/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [3] canonical spec emitted spec-format-warn (should be silent)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [3] canonical spec → no spec-format-warn audit\n'
fi

# ---- Case 4: Phase 3 Write attempt with bad spec → ALLOWED (advisory) ----
_sa_init
rm -f "$_sa_proj/.mcl/audit.log"
_sa_t4="$_sa_proj/t4.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sa_t4" spec-no-emoji-bare

_sa_payload="$(python3 -c "
import json,sys
print(json.dumps({
  'tool_name':'Write',
  'tool_input':{'file_path':sys.argv[1],'content':'export default 1;'},
  'transcript_path':sys.argv[2],
  'session_id':'sa','cwd':sys.argv[3]
}))" "$_sa_proj/src/x.ts" "$_sa_t4" "$_sa_proj")"

_sa_out4="$(printf '%s' "$_sa_payload" \
  | CLAUDE_PROJECT_DIR="$_sa_proj" \
    MCL_STATE_DIR="$_sa_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null)"

if [ -z "$_sa_out4" ] || ! printf '%s' "$_sa_out4" | grep -q '"permissionDecision": "deny"'; then
  PASS=$((PASS+1))
  printf '  PASS: [4] Phase 3 Write with bad spec → ALLOWED (advisory)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [4] Phase 3 Write blocked despite advisory spec format\n'
  printf '        output: %s\n' "$(printf '%s' "$_sa_out4" | head -c 200)"
fi

cleanup_test_dir "$_sa_proj"
