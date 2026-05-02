#!/bin/bash
# Synthetic test: v10.1.7 spec-approval block — coverage across all
# mutating tool variants AND non-mutating tools AND emit-before-block
# ordering. Catches bugs the herta-scenario e2e test cannot:
#   - tool_input shape differences (MultiEdit edits[], NotebookEdit
#     notebook_path) potentially breaking the block
#   - non-mutating tools accidentally blocked
#   - escape hatch firing INLINE (no intermediate deny needed when
#     emit precedes first Write)

echo "--- test-v10-1-7-tool-coverage ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

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

# === Coverage 1: All four mutating tool variants → all blocked ===
# Each tool has a distinct tool_input shape. The block must work for
# each. If the REASON-setting code accidentally relies on `file_path`,
# MultiEdit's `edits[]` or NotebookEdit's `notebook_path` would slip.

declare -a _MUT_INPUTS=(
  '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.js","content":"x"},"transcript_path":""}'
  '{"tool_name":"Edit","tool_input":{"file_path":"/p/foo.js","old_string":"a","new_string":"b"},"transcript_path":""}'
  '{"tool_name":"MultiEdit","tool_input":{"file_path":"/p/foo.js","edits":[{"old_string":"a","new_string":"b"}]},"transcript_path":""}'
  '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/p/foo.ipynb","new_source":"x"},"transcript_path":""}'
)
declare -a _MUT_NAMES=("Write" "Edit" "MultiEdit" "NotebookEdit")

for _i in 0 1 2 3; do
  _write_frozen_state
  echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-7-tc-${_MUT_NAMES[$_i]}" > "$_dir/.mcl/trace.log"
  : > "$_dir/.mcl/audit.log"

  _out="$(_run_pre_tool "${_MUT_INPUTS[$_i]}")"
  _dec="$(_extract_decision "$_out")"
  assert_equals "${_MUT_NAMES[$_i]} at spec_approved=false → decision=deny" "$_dec" "deny"
done

# === Coverage 2: Non-mutating tools → no block ===
# Read, Grep, Glob, TodoWrite, Bash (read-only commands) must NEVER
# be blocked by the spec-approval gate. Pre-tool exits 0 with no
# JSON output for these (line 495 fast-path).

_write_frozen_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-7-tc-readonly" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"

declare -a _RO_INPUTS=(
  '{"tool_name":"Read","tool_input":{"file_path":"/p/foo.js"},"transcript_path":""}'
  '{"tool_name":"Grep","tool_input":{"pattern":"foo","path":"/p"},"transcript_path":""}'
  '{"tool_name":"Glob","tool_input":{"pattern":"**/*.js"},"transcript_path":""}'
)
declare -a _RO_NAMES=("Read" "Grep" "Glob")

for _i in 0 1 2; do
  _out="$(_run_pre_tool "${_RO_INPUTS[$_i]}")"
  _dec="$(_extract_decision "$_out")"
  assert_equals "${_RO_NAMES[$_i]} at spec_approved=false → no block (decision=none)" "$_dec" "none"
done

# Verify state stayed unchanged after read-only tools — no accidental
# state mutations on the read path.
_ro_phase="$(python3 -c "import json; print(json.load(open('$_dir/.mcl/state.json'))['current_phase'])" 2>/dev/null)"
_ro_approved="$(python3 -c "import json; print(str(json.load(open('$_dir/.mcl/state.json'))['spec_approved']).lower())" 2>/dev/null)"
assert_equals "read-only tools left state untouched (phase=4)" "$_ro_phase" "4"
assert_equals "read-only tools left state untouched (spec_approved=false)" "$_ro_approved" "false"

# Verify NO spec-approval-block audits emitted for read-only tools
if grep -q "spec-approval-block" "$_dir/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: read-only tools accidentally triggered spec-approval-block audit\n'
else
  PASS=$((PASS+1))
  printf '  PASS: no spec-approval-block audit for read-only tools\n'
fi

# === Coverage 3: Emit BEFORE first Write — escape hatch fires inline ===
# Well-behaved model could emit asama-4-complete BEFORE its first
# Write attempt (e.g., via Bash audit immediately after AskUserQuestion
# tool_result returns approve). The first Write must succeed without
# any intermediate deny — escape hatch fires before block evaluation.
_write_frozen_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-7-tc-emit-first" > "$_dir/.mcl/trace.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') | asama-4-complete | mcl-stop | spec_hash=preemit approver=user" > "$_dir/.mcl/audit.log"

_out_first="$(_run_pre_tool "${_MUT_INPUTS[0]}")"
_dec_first="$(_extract_decision "$_out_first")"
assert_equals "emit before first Write → first Write allowed (no prior deny)" "$_dec_first" "none"

# State should be progressed after first call
_ef_phase="$(python3 -c "import json; print(json.load(open('$_dir/.mcl/state.json'))['current_phase'])" 2>/dev/null)"
_ef_approved="$(python3 -c "import json; print(str(json.load(open('$_dir/.mcl/state.json'))['spec_approved']).lower())" 2>/dev/null)"
assert_equals "emit-first → state progressed phase=7 on first Write" "$_ef_phase" "7"
assert_equals "emit-first → spec_approved=true on first Write" "$_ef_approved" "true"

# CRITICALLY: spec-approval-block audit must NOT fire when emit
# precedes the Write. The escape hatch wins before block code runs.
if grep -q "spec-approval-block" "$_dir/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: emit-first → spec-approval-block fired (escape hatch did not win inline)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: emit-first → no spec-approval-block (escape hatch wins inline)\n'
fi

# Progression audit must be present
if grep -q "asama-4-progression-from-emit | pre-tool" "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1))
  printf '  PASS: emit-first → pre-tool emitted progression audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: emit-first → progression audit missing\n'
fi

# === Coverage 4: Bash command (general — not block-target) → no block ===
# Bash is a special tool — pre-tool has Bash-specific logic but the
# spec-approval gate at line 493-496 fast-paths it out before reaching
# the spec-approval check. (Bash safety lives in a separate block.)
_write_frozen_state
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-7-tc-bash" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"

_bash_input='{"tool_name":"Bash","tool_input":{"command":"echo hello","description":"echo"},"transcript_path":""}'
_bash_out="$(_run_pre_tool "$_bash_input")"
_bash_dec="$(_extract_decision "$_bash_out")"
assert_equals "Bash at spec_approved=false → not gated by spec-approval (allow path)" "$_bash_dec" "none"

# Verify NO spec-approval-block audit for Bash
if grep -q "spec-approval-block" "$_dir/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: Bash accidentally triggered spec-approval-block\n'
else
  PASS=$((PASS+1))
  printf '  PASS: Bash bypasses spec-approval gate (correct — separate safety layer)\n'
fi

cleanup_test_dir "$_dir"
