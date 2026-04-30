#!/bin/bash
# Test: 9.2.1 spec block format enforcement.
#
# Real-session bug: model emitted spec-LIKE text without `📋 Spec:`
# prefix → scanner returned spec_hash="" → Phase 1→2 transition never
# fired → Write blocked indefinitely. 9.2.1 fix: hook detects three
# spec-attempt patterns and emits `decision:block` forcing re-emit
# with the canonical template.
#
# Patterns covered:
#   1. Bare "Spec:" (no 📋 emoji)
#   2. "## Spec" H2 heading
#   3. "## Faz N — Spec" H2 heading (the actual real-session form)
#   4. Canonical 📋 Spec: + 7 sections → no block (rc=1, complete)
#   5. 📋 Spec: with missing headers → existing rc=0 path still works

echo "--- test-spec-format-enforcement ---"

if [ "${MCL_MINIMAL_CORE:-0}" = "1" ]; then
  printf '  SKIP: test-spec-format-enforcement disabled (MCL_MINIMAL_CORE=1)\n'
  return 0 2>/dev/null || true
fi

_sf_proj="$(setup_test_dir)"

_sf_init_state() {
  python3 - "$_sf_proj/.mcl/state.json" <<'PY'
import json, os, sys, time
o = {"schema_version": 2, "current_phase": 1, "phase_name": "COLLECT",
     "spec_approved": False, "spec_hash": None, "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_sf_run_partial_check() {
  local transcript="$1"
  set +e
  _SF_LAST_OUT="$(bash "$REPO_ROOT/hooks/lib/mcl-partial-spec.sh" check "$transcript" 2>/dev/null)"
  _SF_LAST_RC=$?
  set -e
  return 0
}

_sf_run_stop() {
  local transcript="$1"
  printf '%s' "{\"transcript_path\":\"${transcript}\",\"session_id\":\"sf\",\"cwd\":\"${_sf_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_sf_proj" \
      MCL_STATE_DIR="$_sf_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

# ---- Case 1: bare "Spec:" without 📋 ----
_sf_init_state
_sf_t1="$_sf_proj/t1.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t1" spec-no-emoji-bare
_sf_run_partial_check "$_sf_t1"
assert_equals "bare 'Spec:' → partial-spec rc=3" "$_SF_LAST_RC" "3"

_sf_out1="$(_sf_run_stop "$_sf_t1")"
assert_contains "bare 'Spec:' → stop emits decision:block" "$_sf_out1" '"decision": "block"'
assert_contains "bare 'Spec:' → reason mentions 📋 Spec:" "$_sf_out1" "📋 Spec:"
assert_contains "bare 'Spec:' → reason mentions MCL SPEC FORMAT" "$_sf_out1" "MCL SPEC FORMAT"
if grep -q "spec-no-emoji-block" "$_sf_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: bare Spec: → spec-no-emoji-block audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec-no-emoji-block audit missing\n'
fi

# ---- Case 2: "## Spec" H2 heading ----
_sf_init_state
rm -f "$_sf_proj/.mcl/audit.log"
_sf_t2="$_sf_proj/t2.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t2" spec-h2-heading
_sf_run_partial_check "$_sf_t2"
assert_equals "## Spec heading → partial-spec rc=3" "$_SF_LAST_RC" "3"

# ---- Case 3: "## Faz 2 — Spec" heading (real-session form) ----
_sf_init_state
rm -f "$_sf_proj/.mcl/audit.log"
_sf_t3="$_sf_proj/t3.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t3" spec-faz-heading
_sf_run_partial_check "$_sf_t3"
assert_equals "## Faz N — Spec heading → partial-spec rc=3" "$_SF_LAST_RC" "3"

_sf_out3="$(_sf_run_stop "$_sf_t3")"
assert_contains "Faz heading → reason has canonical template" "$_sf_out3" "## [Feature/Change Title]"

# ---- Case 4: canonical complete spec → rc=1, no block ----
_sf_init_state
rm -f "$_sf_proj/.mcl/audit.log"
_sf_t4="$_sf_proj/t4.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t4" spec-correct "Admin Panel"
_sf_run_partial_check "$_sf_t4"
assert_equals "canonical spec → partial-spec rc=1 (complete)" "$_SF_LAST_RC" "1"

# ---- Case 5: 📋 Spec: with missing sections → rc=0 (existing path) ----
_sf_init_state
rm -f "$_sf_proj/.mcl/audit.log"
_sf_t5="$_sf_proj/t5.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t5" spec-partial "Edge Cases,Out of Scope"
_sf_run_partial_check "$_sf_t5"
assert_equals "missing sections → partial-spec rc=0" "$_SF_LAST_RC" "0"

_sf_out5="$(_sf_run_stop "$_sf_t5")"
assert_contains "missing sections → MCL SPEC RECOVERY block" "$_sf_out5" "MCL SPEC RECOVERY"
assert_contains "missing sections → cites Edge Cases" "$_sf_out5" "Edge Cases"

# ---- Case 6: empty transcript → rc=2 ----
_sf_init_state
rm -f "$_sf_proj/.mcl/audit.log"
_sf_t6="$_sf_proj/t6.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t6" user-only "build it"
_sf_run_partial_check "$_sf_t6"
assert_equals "no spec at all → partial-spec rc=2" "$_SF_LAST_RC" "2"

cleanup_test_dir "$_sf_proj"
