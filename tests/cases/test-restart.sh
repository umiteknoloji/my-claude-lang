#!/bin/bash
# Test: mcl-restart resets state and emits MCL_RESTART_MODE.

echo "--- test-restart ---"

_rs_dir="$(setup_test_dir)"

# Pre-write a non-default state (phase 4, spec approved).
python3 -c "
import json, sys
path = sys.argv[1]
state = {
    'schema_version': 2, 'current_phase': 4, 'phase_name': 'EXECUTE',
    'spec_approved': True, 'spec_hash': 'abc123def456',
    'plugin_gate_active': False, 'plugin_gate_missing': [],
    'ui_flow_active': False, 'ui_sub_phase': None,
    'ui_build_hash': None, 'ui_reviewed': False,
    'last_update': 1700000000
}
with open(path, 'w') as f:
    json.dump(state, f)
" "$_rs_dir/.mcl/state.json"

_out="$(run_activate_hook "$_rs_dir" "/mcl-restart")"

assert_json_valid  "mcl-restart → valid JSON"           "$_out"
assert_contains    "mcl-restart → MCL_RESTART_MODE"     "$_out" "MCL_RESTART_MODE"

# Verify state was reset by the hook.
if [ -f "$_rs_dir/.mcl/state.json" ]; then
  _phase="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('current_phase',9))" "$_rs_dir/.mcl/state.json" 2>/dev/null)"
  _approved="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get('spec_approved',True)).lower())" "$_rs_dir/.mcl/state.json" 2>/dev/null)"
  assert_equals "mcl-restart → current_phase reset to 1"       "$_phase"    "1"
  assert_equals "mcl-restart → spec_approved reset to false"   "$_approved" "false"
fi

cleanup_test_dir "$_rs_dir"
