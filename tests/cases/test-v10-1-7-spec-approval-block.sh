#!/bin/bash
# Synthetic INTEGRATION test: v10.1.7 — Option 3 (real spec-approval
# block) + Option 1 (escape hatch via asama-4-complete emit).
# Runs the actual mcl-pre-tool.sh, asserts permissionDecision in
# emitted JSON, asserts state.json side effects, asserts loop-breaker
# fires after 3 strikes.

echo "--- test-v10-1-7-spec-approval-block ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

# Helper: write a baseline state.json with spec_approved=false (the
# herta-frozen state). Re-used across cases.
_write_frozen_state() {
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
}

_run_pre_tool() {
  local input="$1"
  local transcript="$_dir/transcript.jsonl"
  : > "$transcript"
  echo "$input" | \
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

_PRE_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/v107test.js","content":"x"},"transcript_path":""}'

# === Case 1: spec_approved=false → REAL deny (Option 3) ===
_write_frozen_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-7-c1" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"

_out1="$(_run_pre_tool "$_PRE_INPUT")"
_dec1="$(_extract_decision "$_out1")"
assert_equals "spec_approved=false → real decision=deny (Option 3)" "$_dec1" "deny"

# Assert spec-approval-block audit was written
if grep -q "spec-approval-block" "$_dir/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: spec-approval-block audit emitted on first deny\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec-approval-block audit not emitted\n'
fi

# === Case 2: asama-4-complete emit → escape hatch unblocks (Option 1) ===
_write_frozen_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-7-c2" > "$_dir/.mcl/trace.log"
# summary-confirm-approve added since v10.1.12 — v10.1.12 asama-1-skip-block
# requires Aşama 1 evidence in audit when SPEC_APPROVED=true. Without this,
# the escape hatch progression triggers asama-1-skip on the next gate. Real
# sessions naturally have this audit from the Aşama 1 askq.
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | summary-confirm-approve | stop | selected=Onayla
$(date '+%Y-%m-%d %H:%M:%S') | asama-4-complete | mcl-stop | spec_hash=def456abc approver=user
EOF

_out2="$(_run_pre_tool "$_PRE_INPUT")"
_dec2="$(_extract_decision "$_out2")"
assert_equals "asama-4-complete in audit → no deny (escape hatch)" "$_dec2" "none"

# State should be progressed
_approved2="$(python3 -c "import json; print(str(json.load(open('$_dir/.mcl/state.json'))['spec_approved']).lower())" 2>/dev/null)"
_phase2="$(python3 -c "import json; print(json.load(open('$_dir/.mcl/state.json'))['current_phase'])" 2>/dev/null)"
assert_equals "escape hatch → spec_approved=true" "$_approved2" "true"
assert_equals "escape hatch → current_phase=7" "$_phase2" "7"

# pre-tool should have emitted the progression audit
if grep -q "asama-4-progression-from-emit" "$_dir/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool emits asama-4-progression-from-emit on escape\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: pre-tool did not emit asama-4-progression-from-emit\n'
fi

# === Case 3: 3-strike loop-breaker → 4th call fails open ===
_write_frozen_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-7-c3" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"

# Strike 1, 2, 3 → all deny (and emit spec-approval-block audit)
for _i in 1 2 3; do
  _out="$(_run_pre_tool "$_PRE_INPUT")"
  _dec="$(_extract_decision "$_out")"
  if [ "$_dec" = "deny" ]; then
    PASS=$((PASS+1))
    printf '  PASS: strike %d → decision=deny\n' "$_i"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: strike %d expected deny, got %s\n' "$_i" "$_dec"
  fi
  # Reset state.json to frozen for next strike (real session would
  # see model retry → state still false → next strike).
  _write_frozen_state
done

# Strike 4 → loop-breaker fail-open
_out4="$(_run_pre_tool "$_PRE_INPUT")"
_dec4="$(_extract_decision "$_out4")"
assert_equals "4th call after 3 strikes → fail-open (decision=allow)" "$_dec4" "allow"

# spec-approval-loop-broken audit should be present
if grep -q "spec-approval-loop-broken" "$_dir/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: spec-approval-loop-broken audit emitted on fail-open\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec-approval-loop-broken audit not emitted\n'
fi

# === Case 4: spec_approved=true → no block, normal allow path ===
cat > "$_dir/.mcl/state.json" <<JSON
{
  "schema_version": 3,
  "current_phase": 7,
  "phase_name": "EXECUTE",
  "spec_approved": true,
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
  "precision_audit_done": true,
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
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-7-c4" > "$_dir/.mcl/trace.log"
# Aşama 1 evidence required since v10.1.12 (real-flow simulation).
echo "$(date '+%Y-%m-%d %H:%M:%S') | summary-confirm-approve | stop | selected=Onayla" > "$_dir/.mcl/audit.log"

_out5="$(_run_pre_tool "$_PRE_INPUT")"
_dec5="$(_extract_decision "$_out5")"
assert_equals "spec_approved=true → no JSON output (allow path, exit 0)" "$_dec5" "none"

# === Hook contract checks ===
_pre="$REPO_ROOT/hooks/mcl-pre-tool.sh"

if grep -q 'REASON_KIND="spec-approval"' "$_pre"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool tracks REASON_KIND for spec-approval source\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: REASON_KIND tracking missing\n'
fi

if grep -q "spec-approval-block" "$_pre"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool emits spec-approval-block audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec-approval-block emit missing from pre-tool\n'
fi

if grep -q '_mcl_loop_breaker_count "spec-approval-block"' "$_pre"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool uses loop-breaker for spec-approval-block\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: pre-tool does not call loop-breaker for spec-approval\n'
fi

# Lib contract — _mcl_loop_breaker_count must be in mcl-state.sh
if grep -q "^_mcl_loop_breaker_count()" "$REPO_ROOT/hooks/lib/mcl-state.sh"; then
  PASS=$((PASS+1))
  printf '  PASS: _mcl_loop_breaker_count helper hosted in mcl-state.sh\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: _mcl_loop_breaker_count helper missing from mcl-state.sh\n'
fi

cleanup_test_dir "$_dir"
