#!/bin/bash
# Test: 10.0.0 state.json schema v2 → v3 migration.
#
# When mcl_state_init runs (via mcl-activate.sh) and finds an existing
# state.json with schema_version=2, it must:
#   1. Renumber current_phase (old 4 EXECUTE → new 3 IMPLEMENTATION)
#   2. Set phase_name to the new label
#   3. Carry spec_approved=true → design_approved=true
#   4. Default is_ui_project=true (safe non-trigger)
#   5. Rename phase4_5_*_scan_done → phase4_*_scan_done
#   6. Drop spec_approved, phase_review_state, precision_audit_block_count
#   7. Bump schema_version to 3
#   8. Write `state-migrated-10.0.0` audit event
#   9. Leave a backup at .mcl/state.json.backup.pre-v3

echo "--- test-state-migration-v3 ---"

_sm_proj="$(setup_test_dir)"
_sm_state="$_sm_proj/.mcl/state.json"

# Plant a v2 state typical of pre-10.0.0: phase=4 (old EXECUTE),
# spec_approved=true, phase_review_state="running", and renamed gate flags.
python3 - "$_sm_state" <<'PY'
import json, sys, time
o = {
    "schema_version": 2,
    "current_phase": 4,
    "phase_name": "EXECUTE",
    "spec_approved": True,
    "spec_hash": "abc123def456",
    "ui_flow_active": False,
    "ui_sub_phase": None,
    "phase4_5_security_scan_done": True,
    "phase4_5_db_scan_done": False,
    "phase4_5_ui_scan_done": False,
    "phase4_5_ops_scan_done": False,
    "phase4_5_perf_scan_done": False,
    "phase4_5_high_baseline": {"security": 0, "db": 0, "ui": 0, "ops": 0, "perf": 0},
    "phase4_5_batch_decision": None,
    "phase_review_state": "running",
    "precision_audit_block_count": 0,
    "precision_audit_skipped": False,
    "phase1_turn_count": 3,
    "last_update": 1700000000,
}
open(sys.argv[1], "w").write(json.dumps(o, indent=2))
PY

# Drive the activate hook (which runs mcl_state_init internally).
_sm_payload="{\"prompt\":\"continue\",\"session_id\":\"sm\",\"cwd\":\"${_sm_proj}\"}"
printf '%s' "$_sm_payload" \
  | CLAUDE_PROJECT_DIR="$_sm_proj" \
    MCL_STATE_DIR="$_sm_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-activate.sh" >/dev/null 2>&1

# ---- Verify migrated state ----
_sm_field() {
  python3 -c "
import json, sys
d = json.load(open('$_sm_state'))
v = d.get('$1', '__MISSING__')
print('null' if v is None else (str(v).lower() if isinstance(v,bool) else v))
"
}
_sm_has() {
  python3 -c "
import json, sys
d = json.load(open('$_sm_state'))
print('yes' if '$1' in d else 'no')
"
}

assert_equals "schema_version migrated to 3"            "$(_sm_field schema_version)"  "3"
assert_equals "current_phase renumbered (old 4 → new 3)" "$(_sm_field current_phase)"   "3"
assert_equals "phase_name=IMPLEMENTATION"                "$(_sm_field phase_name)"      "IMPLEMENTATION"
assert_equals "design_approved carried from spec_approved=true" "$(_sm_field design_approved)" "true"
assert_equals "is_ui_project default=true (safe non-trigger)"   "$(_sm_field is_ui_project)"   "true"
assert_equals "phase4_security_scan_done renamed (was phase4_5_*)" "$(_sm_field phase4_security_scan_done)" "true"
assert_equals "phase4_db_scan_done renamed"             "$(_sm_field phase4_db_scan_done)" "false"

# Removed fields must be absent.
assert_equals "spec_approved removed"            "$(_sm_has spec_approved)"            "no"
assert_equals "phase_review_state removed"       "$(_sm_has phase_review_state)"       "no"
assert_equals "precision_audit_block_count removed" "$(_sm_has precision_audit_block_count)" "no"
assert_equals "precision_audit_skipped removed"  "$(_sm_has precision_audit_skipped)"  "no"

# Old phase4_5_* keys must NOT linger.
assert_equals "phase4_5_security_scan_done removed (renamed)" "$(_sm_has phase4_5_security_scan_done)" "no"
assert_equals "phase4_5_high_baseline removed (renamed)"      "$(_sm_has phase4_5_high_baseline)"      "no"
assert_equals "phase4_5_batch_decision removed (renamed)"     "$(_sm_has phase4_5_batch_decision)"     "no"
assert_equals "phase4_high_baseline present (renamed)"        "$(_sm_has phase4_high_baseline)"        "yes"

# ---- Audit log records the migration ----
if grep -q "state-migrated-10.0.0" "$_sm_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: state-migrated-10.0.0 audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: state-migrated-10.0.0 audit missing\n'
  tail -10 "$_sm_proj/.mcl/audit.log" 2>/dev/null
fi

# ---- Backup file present ----
if [ -f "$_sm_proj/.mcl/state.json.backup.pre-v3" ]; then
  PASS=$((PASS+1))
  printf '  PASS: backup file at .mcl/state.json.backup.pre-v3\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: backup file missing at .mcl/state.json.backup.pre-v3\n'
fi

# ---- Backup retains old schema (v2) ----
if [ -f "$_sm_proj/.mcl/state.json.backup.pre-v3" ]; then
  _sm_old_version="$(python3 -c "import json; print(json.load(open('$_sm_proj/.mcl/state.json.backup.pre-v3')).get('schema_version'))")"
  assert_equals "backup retains schema_version=2" "$_sm_old_version" "2"
fi

cleanup_test_dir "$_sm_proj"
