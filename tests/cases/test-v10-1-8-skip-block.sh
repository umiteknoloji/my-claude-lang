#!/bin/bash
# Synthetic INTEGRATION test: v10.1.8 — Aşama 8/9 skip-block.
# When Stop hook detected `asama-{8,9}-emit-missing` (model wrote
# production code without running risk review / quality+tests),
# pre-tool blocks subsequent mutating tools until model emits the
# missing `asama-N-complete` audit. Mirrors v10.1.7 spec-approval-block
# pattern but for behavioral skip detection.
#
# Triggered by the grom backoffice case: model wrote 29 prod files
# without Aşama 8 dialog, soft visibility surfaced the skip, but
# 7 security findings (independently audited) still landed. v10.1.8
# turns the emit-missing audit into an actionable block.

echo "--- test-v10-1-8-skip-block ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

_write_post_spec_state() {
  cat > "$_dir/.mcl/state.json" <<JSON
{
  "schema_version": 3,
  "current_phase": 7,
  "phase_name": "EXECUTE",
  "spec_approved": true,
  "spec_hash": "post-spec-v1",
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
  "precision_audit_done": true,
  "risk_review_state": null,
  "quality_review_state": null,
  "open_severity_count": 0,
  "tdd_compliance_score": 0,
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
}

_run_pre_tool() {
  echo "$1" | \
    MCL_STATE_DIR="$_dir/.mcl" \
    MCL_STATE_FILE="$_dir/.mcl/state.json" \
    CLAUDE_PROJECT_DIR="$_dir" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null
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

_PRE_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/p/foo.js","content":"x"},"transcript_path":""}'

# === Case 1: asama-8-emit-missing present, no asama-8-complete → block ===
_write_post_spec_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-8-c1" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | summary-confirm-approve | stop | selected=Onayla
$(date '+%Y-%m-%d %H:%M:%S') | tdd-prod-write | post-tool | file=/p/foo.js
$(date '+%Y-%m-%d %H:%M:%S') | asama-8-emit-missing | stop | skip-detect prod-write-without-emit
EOF

_out1="$(_run_pre_tool "$_PRE_INPUT")"
_dec1="$(_extract_decision "$_out1")"
assert_equals "asama-8-emit-missing + no asama-8-complete → decision=deny" "$_dec1" "deny"

if grep -q "asama-8-skip-block" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: asama-8-skip-block audit emitted\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-8-skip-block audit not emitted\n'
fi

# === Case 2: asama-8-complete present → no block ===
_write_post_spec_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-8-c2" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | summary-confirm-approve | stop | selected=Onayla
$(date '+%Y-%m-%d %H:%M:%S') | tdd-prod-write | post-tool | file=/p/foo.js
$(date '+%Y-%m-%d %H:%M:%S') | asama-8-emit-missing | stop | skip-detect prod-write-without-emit
$(date '+%Y-%m-%d %H:%M:%S') | asama-8-complete | mcl-stop | h_count=1 m_count=2 l_count=0 resolved=3
$(date '+%Y-%m-%d %H:%M:%S') | asama-9-emit-missing | stop | skip-detect prod-write-without-emit
EOF

_out2="$(_run_pre_tool "$_PRE_INPUT")"
_dec2="$(_extract_decision "$_out2")"
assert_equals "asama-8-complete present BUT asama-9 still missing → block on 9" "$_dec2" "deny"

if grep -q "asama-9-skip-block" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: asama-9-skip-block emitted (cascading enforcement)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-9-skip-block missing despite asama-9-emit-missing\n'
fi

# === Case 3: both 8+9 complete → no block ===
_write_post_spec_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-8-c3" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | summary-confirm-approve | stop | selected=Onayla
$(date '+%Y-%m-%d %H:%M:%S') | tdd-prod-write | post-tool | file=/p/foo.js
$(date '+%Y-%m-%d %H:%M:%S') | asama-8-emit-missing | stop | skip-detect prod-write-without-emit
$(date '+%Y-%m-%d %H:%M:%S') | asama-9-emit-missing | stop | skip-detect prod-write-without-emit
$(date '+%Y-%m-%d %H:%M:%S') | asama-8-complete | mcl-stop | h_count=0 m_count=0 l_count=0 resolved=0
$(date '+%Y-%m-%d %H:%M:%S') | asama-9-complete | mcl-stop | applied=2 skipped=4 ambiguous=0 na=2
EOF

_out3="$(_run_pre_tool "$_PRE_INPUT")"
_dec3="$(_extract_decision "$_out3")"
assert_equals "both 8 + 9 complete → no block (decision=none)" "$_dec3" "none"

# === Case 4: 3-strike loop-breaker on asama-8-skip-block → 4th allows ===
_write_post_spec_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-8-c4" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | summary-confirm-approve | stop | selected=Onayla
$(date '+%Y-%m-%d %H:%M:%S') | tdd-prod-write | post-tool | file=/p/foo.js
$(date '+%Y-%m-%d %H:%M:%S') | asama-8-emit-missing | stop | skip-detect prod-write-without-emit
EOF

# Strikes 1, 2, 3 → all deny
for _i in 1 2 3; do
  _out="$(_run_pre_tool "$_PRE_INPUT")"
  _dec="$(_extract_decision "$_out")"
  if [ "$_dec" = "deny" ]; then
    PASS=$((PASS+1))
    printf '  PASS: asama-8 strike %d → decision=deny\n' "$_i"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: asama-8 strike %d expected deny, got %s\n' "$_i" "$_dec"
  fi
done

# 4th → loop-breaker fail-open
_out4="$(_run_pre_tool "$_PRE_INPUT")"
_dec4="$(_extract_decision "$_out4")"
assert_equals "asama-8 4th call after 3 strikes → fail-open" "$_dec4" "allow"

if grep -q "asama-8-skip-loop-broken" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: asama-8-skip-loop-broken audit emitted on fail-open\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-8-skip-loop-broken audit missing\n'
fi

# === Case 5: read-only tool not blocked even with emit-missing ===
_write_post_spec_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-8-c5" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | summary-confirm-approve | stop | selected=Onayla
$(date '+%Y-%m-%d %H:%M:%S') | tdd-prod-write | post-tool | file=/p/foo.js
$(date '+%Y-%m-%d %H:%M:%S') | asama-8-emit-missing | stop | skip-detect prod-write-without-emit
EOF

_read_input='{"tool_name":"Read","tool_input":{"file_path":"/p/foo.js"},"transcript_path":""}'
_out5="$(_run_pre_tool "$_read_input")"
_dec5="$(_extract_decision "$_out5")"
assert_equals "Read tool with emit-missing → not blocked (decision=none)" "$_dec5" "none"

if grep -q "asama-8-skip-block" "$_dir/.mcl/audit.log"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: Read accidentally triggered asama-8-skip-block\n'
else
  PASS=$((PASS+1))
  printf '  PASS: Read does not trigger skip-block\n'
fi

# === Case 6: spec_approved=false → spec-approval-block has priority ===
# The herta-frozen state still hits spec-approval-block first; the new
# v10.1.8 gate only fires when SPEC_APPROVED=true.
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
  "tdd_compliance_score": 0,
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
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-8-c6" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | summary-confirm-approve | stop | selected=Onayla
$(date '+%Y-%m-%d %H:%M:%S') | tdd-prod-write | post-tool | file=/p/foo.js
$(date '+%Y-%m-%d %H:%M:%S') | asama-8-emit-missing | stop | skip-detect prod-write-without-emit
EOF

_out6="$(_run_pre_tool "$_PRE_INPUT")"
_dec6="$(_extract_decision "$_out6")"
assert_equals "spec_approved=false → still blocked (priority to spec-approval)" "$_dec6" "deny"

# spec-approval-block (v10.1.7) audit should fire — NOT asama-8-skip-block
if grep -q "spec-approval-block" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: spec-approval-block fires first when SPEC_APPROVED=false\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec-approval-block expected but missing\n'
fi

# === Hook contract checks ===
_pre="$REPO_ROOT/hooks/mcl-pre-tool.sh"

if grep -q 'REASON_KIND="asama-${_SKIP_PH}-skip"' "$_pre"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool sets REASON_KIND for asama-N-skip\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: REASON_KIND for asama-N-skip missing\n'
fi

if grep -q "asama-.*-skip-block" "$_pre"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool emits asama-N-skip-block audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-N-skip-block emit missing\n'
fi

if grep -q "_mcl_audit_emitted_in_session" "$REPO_ROOT/hooks/lib/mcl-state.sh"; then
  PASS=$((PASS+1))
  printf '  PASS: _mcl_audit_emitted_in_session helper hosted in mcl-state.sh\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: _mcl_audit_emitted_in_session helper missing from lib\n'
fi

cleanup_test_dir "$_dir"
