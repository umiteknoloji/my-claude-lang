#!/bin/bash
# Synthetic INTEGRATION test: v10.1.12 — Aşama 1 skip-block.
# When SPEC_APPROVED=true (passed v10.1.7 gate) but no audit
# evidence of Aşama 1 (intent gathering) exists in current session,
# pre-tool blocks the next mutating tool. Recovery via:
#   - asama-1-complete Bash audit emit, OR
#   - re-run of summary-confirm askq cycle, OR
#   - precision-audit asama2 emit (transitively confirms Aşama 1)
#
# This closes the highest-severity gap from the "model unutursa"
# review: model jumping from prompt directly to spec-emit + spec-
# approval without parameter verification → wrong code on assumed
# parameters regardless of how many downstream gates pass.

echo "--- test-v10-1-12-asama1-skip-block ---"

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

# === Case 1: spec_approved=true + NO Aşama 1 evidence → block ===
_write_post_spec_state
echo "2020-01-01 00:00:00 | session_start | mcl-activate.sh | t10-1-12-c1" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"

_out1="$(_run_pre_tool "$_PRE_INPUT")"
_dec1="$(_extract_decision "$_out1")"
assert_equals "spec_approved=true + no Aşama 1 evidence → decision=deny" "$_dec1" "deny"

if grep -q "asama-1-skip-block" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: asama-1-skip-block audit emitted\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-1-skip-block audit missing\n'
fi

# === Case 2: summary-confirm-approve present → no block ===
_write_post_spec_state
echo "2020-01-01 00:00:00 | session_start | mcl-activate.sh | t10-1-12-c2" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<'EOF'
2020-01-01 00:00:01 | summary-confirm-approve | stop | selected=Onayla
EOF

_out2="$(_run_pre_tool "$_PRE_INPUT")"
_dec2="$(_extract_decision "$_out2")"
assert_equals "summary-confirm-approve in audit → no block" "$_dec2" "none"

# === Case 3: precision-audit (Aşama 2) present → no block (transitively confirms Aşama 1) ===
_write_post_spec_state
echo "2020-01-01 00:00:00 | session_start | mcl-activate.sh | t10-1-12-c3" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<'EOF'
2020-01-01 00:00:01 | precision-audit | asama2 | core_gates=2 stack_gates=1 assumes=4
EOF

_out3="$(_run_pre_tool "$_PRE_INPUT")"
_dec3="$(_extract_decision "$_out3")"
assert_equals "precision-audit present → no block (Aşama 1 transitively confirmed)" "$_dec3" "none"

# === Case 4: asama-1-complete recovery emit → no block ===
_write_post_spec_state
echo "2020-01-01 00:00:00 | session_start | mcl-activate.sh | t10-1-12-c4" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<'EOF'
2020-01-01 00:00:01 | asama-1-complete | mcl-stop | params=intent+constraints+success+context confirmed
EOF

_out4="$(_run_pre_tool "$_PRE_INPUT")"
_dec4="$(_extract_decision "$_out4")"
assert_equals "asama-1-complete recovery emit → no block" "$_dec4" "none"

# === Case 5: 3-strike loop-breaker → 4th call fails open ===
_write_post_spec_state
echo "2020-01-01 00:00:00 | session_start | mcl-activate.sh | t10-1-12-c5" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"

for _i in 1 2 3; do
  _out="$(_run_pre_tool "$_PRE_INPUT")"
  _dec="$(_extract_decision "$_out")"
  if [ "$_dec" = "deny" ]; then
    PASS=$((PASS+1))
    printf '  PASS: asama-1 strike %d → decision=deny\n' "$_i"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: asama-1 strike %d expected deny got %s\n' "$_i" "$_dec"
  fi
done

_out_final="$(_run_pre_tool "$_PRE_INPUT")"
_dec_final="$(_extract_decision "$_out_final")"
assert_equals "asama-1 4th call after 3 strikes → fail-open" "$_dec_final" "allow"

if grep -q "asama-1-skip-loop-broken" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: asama-1-skip-loop-broken audit on fail-open\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-1-skip-loop-broken audit missing\n'
fi

# === Case 6: spec_approved=false → spec-approval-block has priority ===
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
echo "2020-01-01 00:00:00 | session_start | mcl-activate.sh | t10-1-12-c6" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"

_out6="$(_run_pre_tool "$_PRE_INPUT")"
_dec6="$(_extract_decision "$_out6")"
assert_equals "spec_approved=false → still blocked" "$_dec6" "deny"

if grep -q "spec-approval-block" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: spec-approval-block fires first when SPEC_APPROVED=false\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec-approval-block expected but missing\n'
fi

# Asama-1-skip-block should NOT fire here (priority order)
if ! grep -q "asama-1-skip-block" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: asama-1-skip-block does NOT fire when spec-approval-block claims first\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-1-skip-block leaked when spec-approval-block should claim\n'
fi

# === Hook contract checks ===
_pre="$REPO_ROOT/hooks/mcl-pre-tool.sh"

if grep -q 'REASON_KIND="asama-1-skip"' "$_pre"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool sets REASON_KIND for asama-1-skip\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: REASON_KIND for asama-1-skip missing\n'
fi

# Audit emission verified by Case 1 (real run). Source-level grep
# matches the variable form `asama-${_SKIP_PH_NUM}-skip-block` since
# v10.1.12 reuses the v10.1.8 cascading branch.
if grep -q 'asama-${_SKIP_PH_NUM}-skip-block' "$_pre"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool reuses v10.1.8 skip-block emission template\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: skip-block emission template missing\n'
fi

# Read-only tool not blocked
_write_post_spec_state
echo "2020-01-01 00:00:00 | session_start | mcl-activate.sh | t10-1-12-readonly" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"

_read_input='{"tool_name":"Read","tool_input":{"file_path":"/p/foo.js"},"transcript_path":""}'
_out7="$(_run_pre_tool "$_read_input")"
_dec7="$(_extract_decision "$_out7")"
assert_equals "Read tool with no Aşama 1 evidence → not blocked" "$_dec7" "none"

cleanup_test_dir "$_dir"
