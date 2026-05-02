#!/bin/bash
# Synthetic E2E test: replays the herta v10.1.4 silent-bypass scenario
# against v10.1.7 stack. Proves the full protective chain works
# end-to-end:
#   1. spec_approved=false + Write → real block (Option 3)
#   2. Model emits asama-4-complete via Bash → escape hatch fires
#      (Option 1) → state progresses inline
#   3. Same Write retried → allowed
#   4. Code-write activity continues (post-tool)
#   5. Model emits asama-8-complete + asama-9-complete
#   6. Stop hook end-of-turn → state reflects full pipeline run
#
# Each step uses the ACTUAL hooks (pre-tool, post-tool, stop) — no
# inline reimplementation. This is the closest synthetic substitute
# for re-running herta with v10.1.7 deployed.

echo "--- test-v10-1-7-herta-scenario-e2e ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

# Initial state: herta-frozen — phase=4, spec_approved=false
cat > "$_dir/.mcl/state.json" <<JSON
{
  "schema_version": 3,
  "current_phase": 4,
  "phase_name": "SPEC_REVIEW",
  "spec_approved": false,
  "spec_hash": "abc123def456",
  "plugin_gate_active": false,
  "plugin_gate_missing": [],
  "ui_flow_active": false,
  "ui_sub_phase": null,
  "ui_build_hash": null,
  "ui_reviewed": false,
  "scope_paths": [],
  "pattern_scan_due": false,
  "pattern_files": [],
  "pattern_summary": null,
  "pattern_level": null,
  "pattern_ask_pending": false,
  "precision_audit_done": false,
  "risk_review_state": null,
  "quality_review_state": null,
  "open_severity_count": 0,
  "tdd_compliance_score": null,
  "rollback_sha": null,
  "rollback_notice_shown": false,
  "tdd_last_green": null,
  "last_write_ts": null,
  "plan_critique_done": false,
  "restart_turn_ts": null,
  "last_update": 1777747000,
  "partial_spec": false,
  "partial_spec_body_sha": null
}
JSON

echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-7-e2e" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"

_transcript="$_dir/transcript.jsonl"
: > "$_transcript"

_run_pre_tool() {
  local input="$1"
  echo "$input" | \
    MCL_STATE_DIR="$_dir/.mcl" \
    MCL_STATE_FILE="$_dir/.mcl/state.json" \
    CLAUDE_PROJECT_DIR="$_dir" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null
}

_run_post_tool() {
  local input="$1"
  echo "$input" | \
    MCL_STATE_DIR="$_dir/.mcl" \
    MCL_STATE_FILE="$_dir/.mcl/state.json" \
    CLAUDE_PROJECT_DIR="$_dir" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-post-tool.sh" 2>/dev/null
}

_run_stop() {
  echo "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"${_transcript}\"}" | \
    MCL_STATE_DIR="$_dir/.mcl" \
    MCL_STATE_FILE="$_dir/.mcl/state.json" \
    CLAUDE_PROJECT_DIR="$_dir" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

_get_state_field() {
  python3 -c "
import json, sys
try:
    obj = json.load(open('$_dir/.mcl/state.json'))
    val = obj.get(sys.argv[1])
    if isinstance(val, bool):
        print(str(val).lower())
    else:
        print('' if val is None else val)
except Exception:
    print('')
" "$1" 2>/dev/null
}

_extract_decision() {
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("hookSpecificOutput",{}).get("permissionDecision","none"))
except Exception:
    print("none")
' 2>/dev/null
}

# -----------------------------------------------------------------
# STEP 1: Try to write code at spec_approved=false → REAL block
# -----------------------------------------------------------------
_input='{"tool_name":"Write","tool_input":{"file_path":"/herta/auth.js","content":"x"},"transcript_path":""}'
_step1_out="$(_run_pre_tool "$_input")"
_step1_dec="$(_extract_decision "$_step1_out")"
assert_equals "STEP 1 — herta-frozen Write attempt → decision=deny" "$_step1_dec" "deny"

# State should be unchanged
_s1_phase="$(_get_state_field current_phase)"
_s1_approved="$(_get_state_field spec_approved)"
assert_equals "STEP 1 — state still phase=4 (no progression)" "$_s1_phase" "4"
assert_equals "STEP 1 — state still spec_approved=false" "$_s1_approved" "false"

# -----------------------------------------------------------------
# STEP 2: Model emits asama-4-complete (the recovery emit)
# -----------------------------------------------------------------
echo "$(date '+%Y-%m-%d %H:%M:%S') | asama-4-complete | mcl-stop | spec_hash=abc123def456 approver=user" >> "$_dir/.mcl/audit.log"

# -----------------------------------------------------------------
# STEP 3: Retry the Write → escape hatch fires, decision flips to allow
# -----------------------------------------------------------------
_step3_out="$(_run_pre_tool "$_input")"
_step3_dec="$(_extract_decision "$_step3_out")"
assert_equals "STEP 3 — after asama-4-complete emit → decision=allow (no JSON output)" "$_step3_dec" "none"

# Pre-tool inline progression should have updated state
_s3_phase="$(_get_state_field current_phase)"
_s3_approved="$(_get_state_field spec_approved)"
_s3_phase_name="$(_get_state_field phase_name)"
assert_equals "STEP 3 — escape hatch → current_phase=7" "$_s3_phase" "7"
assert_equals "STEP 3 — escape hatch → spec_approved=true" "$_s3_approved" "true"
assert_equals "STEP 3 — escape hatch → phase_name=EXECUTE" "$_s3_phase_name" "EXECUTE"

# Verify audit trail
if grep -q "asama-4-progression-from-emit | pre-tool" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: STEP 3 — pre-tool emitted asama-4-progression-from-emit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: STEP 3 — progression audit missing\n'
fi

# -----------------------------------------------------------------
# STEP 4: Code-write activity (post-tool fires for prod + test files)
# -----------------------------------------------------------------
_post_input_test='{"tool_name":"Write","tool_input":{"file_path":"/herta/auth.test.js","content":"x"},"tool_response":""}'
_post_input_prod='{"tool_name":"Write","tool_input":{"file_path":"/herta/auth.js","content":"x"},"tool_response":""}'
_run_post_tool "$_post_input_test" >/dev/null
_run_post_tool "$_post_input_prod" >/dev/null

# Verify TDD classifier emitted both audit kinds
if grep -q "tdd-test-write" "$_dir/.mcl/audit.log" && grep -q "tdd-prod-write" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: STEP 4 — post-tool emitted tdd-test-write + tdd-prod-write\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: STEP 4 — post-tool TDD audits missing\n'
fi

# -----------------------------------------------------------------
# STEP 5: Model emits asama-8-complete + asama-9-complete
# -----------------------------------------------------------------
cat >> "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | asama-8-complete | mcl-stop | h_count=1 m_count=0 l_count=0 resolved=1
$(date '+%Y-%m-%d %H:%M:%S') | asama-9-complete | mcl-stop | applied=2 skipped=4 ambiguous=0 na=2
EOF

# -----------------------------------------------------------------
# STEP 6: Stop hook fires at end of turn → progresses Aşama 8 & 9
# -----------------------------------------------------------------
_run_stop >/dev/null

_s6_rr="$(_get_state_field risk_review_state)"
_s6_qr="$(_get_state_field quality_review_state)"
assert_equals "STEP 6 — Stop processes asama-8-complete → risk_review_state=complete" "$_s6_rr" "complete"
assert_equals "STEP 6 — Stop processes asama-9-complete → quality_review_state=complete" "$_s6_qr" "complete"

# TDD compliance score should have been computed (1 test before 1 prod = 100%)
_s6_tdd="$(_get_state_field tdd_compliance_score)"
assert_equals "STEP 6 — TDD compliance computed (test before prod = 100%)" "$_s6_tdd" "100"

# -----------------------------------------------------------------
# STEP 7: NO emit-missing audits should fire (full compliance)
# -----------------------------------------------------------------
if grep -q "emit-missing" "$_dir/.mcl/audit.log"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: STEP 7 — emit-missing audit fired despite full compliance\n'
  grep "emit-missing" "$_dir/.mcl/audit.log" | sed 's/^/         /'
else
  PASS=$((PASS+1))
  printf '  PASS: STEP 7 — no emit-missing audits (full compliance path)\n'
fi

# -----------------------------------------------------------------
# STEP 8: Final state.json — proves the herta scenario is impossible
# -----------------------------------------------------------------
_s8_phase="$(_get_state_field current_phase)"
_s8_approved="$(_get_state_field spec_approved)"
assert_equals "STEP 8 — final current_phase=7 (was stuck at 4 in herta)" "$_s8_phase" "7"
assert_equals "STEP 8 — final spec_approved=true (was false in herta)" "$_s8_approved" "true"

# -----------------------------------------------------------------
# COUNTERFACTUAL: same scenario WITHOUT asama-4-complete emit
# Confirms that bypass requires the explicit recovery path
# -----------------------------------------------------------------
cat > "$_dir/.mcl/state.json" <<JSON
{
  "schema_version": 3,
  "current_phase": 4,
  "phase_name": "SPEC_REVIEW",
  "spec_approved": false,
  "spec_hash": null,
  "plugin_gate_active": false,
  "plugin_gate_missing": [],
  "ui_flow_active": false,
  "ui_sub_phase": null,
  "ui_build_hash": null,
  "ui_reviewed": false,
  "scope_paths": [],
  "pattern_scan_due": false,
  "pattern_files": [],
  "pattern_summary": null,
  "pattern_level": null,
  "pattern_ask_pending": false,
  "precision_audit_done": false,
  "risk_review_state": null,
  "quality_review_state": null,
  "open_severity_count": 0,
  "tdd_compliance_score": null,
  "rollback_sha": null,
  "rollback_notice_shown": false,
  "tdd_last_green": null,
  "last_write_ts": null,
  "plan_critique_done": false,
  "restart_turn_ts": null,
  "last_update": 1777747000,
  "partial_spec": false,
  "partial_spec_body_sha": null
}
JSON
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-7-e2e-cf" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"

# Try 3 writes in a row — all should be denied
_cf_strikes=0
for _i in 1 2 3; do
  _cf_out="$(_run_pre_tool "$_input")"
  _cf_dec="$(_extract_decision "$_cf_out")"
  if [ "$_cf_dec" = "deny" ]; then
    _cf_strikes=$((_cf_strikes + 1))
  fi
done
assert_equals "COUNTERFACTUAL — without emit, 3 writes all denied" "$_cf_strikes" "3"

# 4th would fail-open per loop-breaker
_cf_4th="$(_run_pre_tool "$_input")"
_cf_4th_dec="$(_extract_decision "$_cf_4th")"
assert_equals "COUNTERFACTUAL — 4th write triggers loop-breaker fail-open" "$_cf_4th_dec" "allow"

# But state STILL phase=4 (loop-breaker doesn't lie about state)
_cf_phase="$(_get_state_field current_phase)"
_cf_approved="$(_get_state_field spec_approved)"
assert_equals "COUNTERFACTUAL — loop-broken but state still phase=4" "$_cf_phase" "4"
assert_equals "COUNTERFACTUAL — loop-broken but spec_approved=false" "$_cf_approved" "false"

# Visibility audit: spec-approval-loop-broken should be present
if grep -q "spec-approval-loop-broken" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: COUNTERFACTUAL — fail-open recorded as spec-approval-loop-broken audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: COUNTERFACTUAL — loop-broken audit missing\n'
fi

cleanup_test_dir "$_dir"
