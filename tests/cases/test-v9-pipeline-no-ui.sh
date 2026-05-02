#!/bin/bash
# Synthetic test: full v9.0.0 pipeline walk for UI-off project.
# Validates state transitions through Aşama 1 → 4 → 7 → 8 → 9 → 11
# (UI sub-phases skipped; pattern-matching skipped for empty project).

echo "--- test-v9-pipeline-no-ui ---"

_pno_dir="$(setup_test_dir)"

# --- Aşama 1 entry: fresh state, current_phase=1, no UI surface ---
_out="$(run_activate_hook "$_pno_dir" "Build a CLI tool that processes log files")"
assert_json_valid "no-ui Aşama 1 entry → valid JSON" "$_out"

# Verify state initialized with v3 schema
_schema="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('schema_version',0))" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui Aşama 1 → schema_version v3" "$_schema" "3"

_phase="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('current_phase',0))" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui Aşama 1 → current_phase=1" "$_phase" "1"

_ui="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get('ui_flow_active',True)).lower())" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui Aşama 1 → ui_flow_active=false" "$_ui" "false"

# --- Aşama 2 audit completion: precision_audit_done=true ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['precision_audit_done'] = True
json.dump(d, open(path, 'w'))
" "$_pno_dir/.mcl/state.json"

_aud="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get('precision_audit_done',False)).lower())" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui Aşama 2 → precision_audit_done=true" "$_aud" "true"

# --- Aşama 4 spec emit + approval: spec_hash set, current_phase=4 → 7, spec_approved=true ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['spec_hash'] = 'abc123def456cli'
d['spec_approved'] = True
d['current_phase'] = 7
d['phase_name'] = 'EXECUTE'
json.dump(d, open(path, 'w'))
" "$_pno_dir/.mcl/state.json"

_phase="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('current_phase',0))" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui Aşama 4 approve → current_phase=7" "$_phase" "7"

_approved="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get('spec_approved',False)).lower())" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui Aşama 4 approve → spec_approved=true" "$_approved" "true"

# --- Aşama 5 skip (empty project, no source files): pattern_scan_due stays false ---
_pat="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get('pattern_scan_due',True)).lower())" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui Aşama 5 → pattern_scan_due=false (empty project skip)" "$_pat" "false"

# --- Aşama 7 → Aşama 8 risk review starts: risk_review_state=running ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['risk_review_state'] = 'running'
json.dump(d, open(path, 'w'))
" "$_pno_dir/.mcl/state.json"

_rs="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('risk_review_state','') or '')" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui Aşama 8 → risk_review_state=running" "$_rs" "running"

# --- Aşama 8 complete → Aşama 9 quality_review_state=running ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['risk_review_state'] = 'complete'
d['quality_review_state'] = 'running'
json.dump(d, open(path, 'w'))
" "$_pno_dir/.mcl/state.json"

_rs="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('risk_review_state','') or '')" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
_qs="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('quality_review_state','') or '')" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui Aşama 8→9 → risk_review_state=complete" "$_rs" "complete"
assert_equals "no-ui Aşama 9 → quality_review_state=running" "$_qs" "running"

# --- Aşama 9 complete → Aşama 11 verify: current_phase=11 ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['quality_review_state'] = 'complete'
d['current_phase'] = 11
d['phase_name'] = 'DELIVER'
json.dump(d, open(path, 'w'))
" "$_pno_dir/.mcl/state.json"

_phase="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('current_phase',0))" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
_qs="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('quality_review_state','') or '')" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui Aşama 11 → current_phase=11" "$_phase" "11"
assert_equals "no-ui Aşama 9 done → quality_review_state=complete" "$_qs" "complete"

# Final state validates against schema (1 ≤ phase ≤ 11)
_valid_phase="$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
p = d.get('current_phase', 0)
print('ok' if 1 <= p <= 11 else 'fail')
" "$_pno_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "no-ui final → phase in valid range [1..11]" "$_valid_phase" "ok"

cleanup_test_dir "$_pno_dir"
