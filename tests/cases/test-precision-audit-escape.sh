#!/bin/bash
# Test: precision-audit-block counter + /mcl-skip-precision-audit
# escape keyword (since 9.0.0).
#
# When the precision-audit block fires repeatedly, mcl-stop.sh
# increments `precision_audit_block_count`. mcl-activate.sh exposes
# `/mcl-skip-precision-audit` as a keyword that bypasses Phase 1.7 —
# but ONLY after the count reaches 3 (the rule budget). Below 3 the
# keyword is rejected with an audit line.

echo "--- test-precision-audit-escape ---"

_pe_proj="$(setup_test_dir)"
_pe_state="$_pe_proj/.mcl/state.json"
mkdir -p "$_pe_proj/.mcl"

_pe_init_state() {
  local count="$1"
  python3 -c "
import json, time
o = {
    'schema_version':2, 'current_phase':1, 'phase_name':'COLLECT',
    'spec_approved':False,
    'precision_audit_block_count': $count,
    'precision_audit_skipped': False,
    'last_update':int(time.time()),
}
open('$_pe_state','w').write(json.dumps(o))
"
}

_pe_skip_keyword() {
  printf '%s' "{\"prompt\":\"/mcl-skip-precision-audit\",\"session_id\":\"pe\",\"cwd\":\"${_pe_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_pe_proj" \
      MCL_STATE_DIR="$_pe_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-activate.sh" 2>/dev/null
}

# ---- Test 1: keyword with count=0 → rejected (too early) ----
_pe_init_state 0
_pe_out1="$(_pe_skip_keyword)"
assert_json_valid "skip @ count=0 → valid JSON" "$_pe_out1"
assert_contains "skip @ count=0 → too-early notice" "$_pe_out1" "TOO_EARLY"

# Skipped flag must NOT be set.
_pe_skipped1="$(python3 -c "import json; print(json.load(open('$_pe_state'))['precision_audit_skipped'])")"
assert_equals "skip @ count=0 → flag stays false" "$_pe_skipped1" "False"

# Audit captures the early-attempt forensically.
if [ -f "$_pe_proj/.mcl/audit.log" ]; then
  if grep -q "precision-audit-skip-attempt-too-early" "$_pe_proj/.mcl/audit.log" 2>/dev/null; then
    PASS=$((PASS+1))
    printf '  PASS: audit captures too-early skip attempt\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: audit missing too-early skip attempt\n'
  fi
fi

# ---- Test 2: keyword with count=2 → still rejected ----
_pe_init_state 2
_pe_out2="$(_pe_skip_keyword)"
assert_contains "skip @ count=2 → still too-early" "$_pe_out2" "TOO_EARLY"

# ---- Test 3: keyword with count=3 → accepted ----
_pe_init_state 3
_pe_out3="$(_pe_skip_keyword)"
assert_json_valid "skip @ count=3 → valid JSON" "$_pe_out3"
assert_contains "skip @ count=3 → accepted (skip notice)" "$_pe_out3" "SKIP_PRECISION_AUDIT"
assert_contains "skip @ count=3 → directs to mark hook-default" "$_pe_out3" "hook-default"

# Skipped flag set; counter reset.
_pe_skipped3="$(python3 -c "import json; print(json.load(open('$_pe_state'))['precision_audit_skipped'])")"
assert_equals "skip @ count=3 → flag set true" "$_pe_skipped3" "True"

_pe_count_after="$(python3 -c "import json; print(json.load(open('$_pe_state'))['precision_audit_block_count'])")"
assert_equals "skip @ count=3 → counter reset to 0" "$_pe_count_after" "0"

# Audit captures the accepted skip.
if grep -q "precision-audit-skip-accepted" "$_pe_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: audit captures accepted skip with prior count\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: audit missing accepted-skip line\n'
fi

# ---- Test 4: keyword with count=5 (high) → also accepted ----
_pe_init_state 5
_pe_out4="$(_pe_skip_keyword)"
assert_contains "skip @ count=5 → accepted" "$_pe_out4" "SKIP_PRECISION_AUDIT"

cleanup_test_dir "$_pe_proj"
