#!/bin/bash
# Synthetic INTEGRATION test: v10.1.6 audit-driven progression actually
# runs through the real `mcl-stop.sh`. Previous v10.1.5/v10.1.6 tests
# verified the scanner LOGIC by reimplementing it inline; this test
# verifies the ACTUAL hook code executes correctly against synthetic
# audit.log + state.json + trace.log fixtures, making real-project
# verification (e.g., re-running setup.sh in herta) unnecessary.

echo "--- test-v10-1-6-integration-progression ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

# === Case 1: Aşama 4 progression via asama-4-complete emit ===
# Initial state: phase=4, spec_approved=false (the herta-frozen state)
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

echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-6-int" > "$_dir/.mcl/trace.log"

# Audit log: model emitted asama-4-complete (classifier missed the askq approve)
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | precision-audit | asama2 | core_gates=2 stack_gates=0 assumes=4 skipmarks=0 skipped=false
$(date '+%Y-%m-%d %H:%M:%S') | asama-4-complete | mcl-stop | spec_hash=abc123def456 approver=user
EOF

# Empty transcript — hook should not block progression on transcript content
_transcript="$_dir/transcript.jsonl"
: > "$_transcript"

# Run actual mcl-stop.sh
echo "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"${_transcript}\"}" | \
  MCL_STATE_DIR="$_dir/.mcl" \
  MCL_STATE_FILE="$_dir/.mcl/state.json" \
  CLAUDE_PROJECT_DIR="$_dir" \
  MCL_REPO_PATH="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1 || true

# Assert state was progressed by the actual hook
_phase="$(python3 -c "import json; print(json.load(open('$_dir/.mcl/state.json'))['current_phase'])" 2>/dev/null)"
_approved="$(python3 -c "import json; print(str(json.load(open('$_dir/.mcl/state.json'))['spec_approved']).lower())" 2>/dev/null)"
_pa_done="$(python3 -c "import json; print(str(json.load(open('$_dir/.mcl/state.json'))['precision_audit_done']).lower())" 2>/dev/null)"

assert_equals "real mcl-stop.sh — asama-4-complete → current_phase=7" "$_phase" "7"
assert_equals "real mcl-stop.sh — asama-4-complete → spec_approved=true" "$_approved" "true"
assert_equals "real mcl-stop.sh — precision-audit → precision_audit_done=true" "$_pa_done" "true"

# Assert progression audit was emitted by real hook
if grep -q "asama-4-progression-from-emit" "$_dir/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: real hook emitted asama-4-progression-from-emit audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: real hook did not emit asama-4-progression-from-emit\n'
fi

# Assert trace got phase_transition 4,7 (comma-separated args per mcl-trace.sh format)
if grep -q "phase_transition | 4,7" "$_dir/.mcl/trace.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: real hook wrote phase_transition 4,7 to trace\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: real hook did not write phase_transition 4,7\n'
  printf '         trace.log content:\n'
  sed 's/^/           /' "$_dir/.mcl/trace.log" 2>/dev/null
fi

# === Case 2: Aşama 8 progression via asama-8-complete emit ===
# Reset state to phase=7 with risk_review=null (post-Aşama 7 frozen)
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

# Fresh trace + audit for case 2
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-6-int-c2" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | tdd-test-write | post-tool | file=/p/foo.test.js
$(date '+%Y-%m-%d %H:%M:%S') | tdd-prod-write | post-tool | file=/p/foo.js
$(date '+%Y-%m-%d %H:%M:%S') | asama-8-complete | mcl-stop | h_count=1 m_count=0 l_count=0 resolved=1
EOF

echo "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"${_transcript}\"}" | \
  MCL_STATE_DIR="$_dir/.mcl" \
  MCL_STATE_FILE="$_dir/.mcl/state.json" \
  CLAUDE_PROJECT_DIR="$_dir" \
  MCL_REPO_PATH="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1 || true

_rr="$(python3 -c "import json; print(json.load(open('$_dir/.mcl/state.json')).get('risk_review_state') or '')" 2>/dev/null)"
assert_equals "real mcl-stop.sh — asama-8-complete → risk_review_state=complete" "$_rr" "complete"

# === Case 3: Aşama 9 progression via asama-9-complete emit ===
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
  "risk_review_state": "complete",
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

echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-6-int-c3" > "$_dir/.mcl/trace.log"
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | asama-9-complete | mcl-stop | applied=2 skipped=4 ambiguous=0 na=2
EOF

echo "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"${_transcript}\"}" | \
  MCL_STATE_DIR="$_dir/.mcl" \
  MCL_STATE_FILE="$_dir/.mcl/state.json" \
  CLAUDE_PROJECT_DIR="$_dir" \
  MCL_REPO_PATH="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1 || true

_qr="$(python3 -c "import json; print(json.load(open('$_dir/.mcl/state.json')).get('quality_review_state') or '')" 2>/dev/null)"
assert_equals "real mcl-stop.sh — asama-9-complete → quality_review_state=complete" "$_qr" "complete"

# === Case 4: Skip-detection — code written, no asama-{4,8,9}-complete ===
# Reset state to phase=4 frozen (the herta v10.1.4 scenario)
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

echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-6-int-c4" > "$_dir/.mcl/trace.log"
# Multiple prod writes, NO emit (the herta scenario)
cat > "$_dir/.mcl/audit.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | tdd-prod-write | post-tool | file=/p/auth.js
$(date '+%Y-%m-%d %H:%M:%S') | tdd-prod-write | post-tool | file=/p/api.js
$(date '+%Y-%m-%d %H:%M:%S') | tdd-prod-write | post-tool | file=/p/db.js
EOF

echo "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"${_transcript}\"}" | \
  MCL_STATE_DIR="$_dir/.mcl" \
  MCL_STATE_FILE="$_dir/.mcl/state.json" \
  CLAUDE_PROJECT_DIR="$_dir" \
  MCL_REPO_PATH="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1 || true

# All three skip-detection audits should be present after Stop runs
_missing4="$(grep -c "asama-4-emit-missing" "$_dir/.mcl/audit.log" 2>/dev/null || echo 0)"
_missing8="$(grep -c "asama-8-emit-missing" "$_dir/.mcl/audit.log" 2>/dev/null || echo 0)"
_missing9="$(grep -c "asama-9-emit-missing" "$_dir/.mcl/audit.log" 2>/dev/null || echo 0)"

if [ "$_missing4" -ge 1 ] && [ "$_missing8" -ge 1 ] && [ "$_missing9" -ge 1 ]; then
  PASS=$((PASS+1))
  printf '  PASS: real hook skip-detected all three missing emits (4, 8, 9)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: skip-detection — got 4=%s 8=%s 9=%s (expected each ≥1)\n' \
    "$_missing4" "$_missing8" "$_missing9"
fi

if grep -q "phase_emit_missing" "$_dir/.mcl/trace.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: real hook wrote phase_emit_missing trace entries\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: real hook did not write phase_emit_missing trace\n'
fi

# Re-run with skip-detect already-present should be idempotent
echo "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"${_transcript}\"}" | \
  MCL_STATE_DIR="$_dir/.mcl" \
  MCL_STATE_FILE="$_dir/.mcl/state.json" \
  CLAUDE_PROJECT_DIR="$_dir" \
  MCL_REPO_PATH="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1 || true

_missing4_after="$(grep -c "asama-4-emit-missing" "$_dir/.mcl/audit.log" 2>/dev/null || echo 0)"
if [ "$_missing4_after" = "$_missing4" ]; then
  PASS=$((PASS+1))
  printf '  PASS: skip-detect idempotent on re-run (count stable: %s)\n' "$_missing4"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: skip-detect re-emitted on re-run (was=%s now=%s — should be stable)\n' \
    "$_missing4" "$_missing4_after"
fi

cleanup_test_dir "$_dir"
