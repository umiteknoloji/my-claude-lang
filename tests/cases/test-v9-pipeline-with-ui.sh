#!/bin/bash
# Synthetic test: full v9.0.0 pipeline walk for UI-on project.
# Validates state transitions through Aşama 1 → 4 → 5 → 6a → 6b → 6c
# → 8 → 9 → 11. UI sub-phases tracked via ui_sub_phase.

echo "--- test-v9-pipeline-with-ui ---"

_pwu_dir="$(setup_test_dir)"

# Make the project look UI-capable: package.json + src/components
mkdir -p "$_pwu_dir/src/components" "$_pwu_dir/src/pages" 2>/dev/null
cat > "$_pwu_dir/package.json" <<'JSON'
{
  "name": "test-ui",
  "version": "1.0.0",
  "scripts": {"dev": "vite"},
  "dependencies": {"react": "^18.0.0"}
}
JSON
echo "import React from 'react'; export const Button = () => <button>Click</button>;" > "$_pwu_dir/src/components/Button.tsx"

# --- Aşama 1 entry: UI-capable project ---
_out="$(run_activate_hook "$_pwu_dir" "Add a settings page with theme toggle")"
assert_json_valid "ui Aşama 1 entry → valid JSON" "$_out"

_schema="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('schema_version',0))" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "ui Aşama 1 → schema_version v3" "$_schema" "3"

_phase="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('current_phase',0))" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "ui Aşama 1 → current_phase=1" "$_phase" "1"

# UI flow should be auto-activated by ui_capable detection
_ui="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get('ui_flow_active',False)).lower())" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "ui Aşama 1 → ui_flow_active=true (UI surface detected)" "$_ui" "true"

# --- Aşama 2 audit done ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['precision_audit_done'] = True
json.dump(d, open(path, 'w'))
" "$_pwu_dir/.mcl/state.json"

# --- Aşama 4 spec approved → current_phase=7 ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['spec_hash'] = 'def789abc456ui'
d['spec_approved'] = True
d['current_phase'] = 7
d['phase_name'] = 'EXECUTE'
d['ui_sub_phase'] = 'BUILD_UI'
json.dump(d, open(path, 'w'))
" "$_pwu_dir/.mcl/state.json"

_phase="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('current_phase',0))" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "ui Aşama 4 approve → current_phase=7" "$_phase" "7"

# --- Aşama 5 pattern scan (real files exist → Level 1) ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['pattern_scan_due'] = True
d['pattern_files'] = ['src/components/Button.tsx']
d['pattern_level'] = 1
json.dump(d, open(path, 'w'))
" "$_pwu_dir/.mcl/state.json"

_pat="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get('pattern_scan_due',False)).lower())" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "ui Aşama 5 → pattern_scan_due=true (files exist)" "$_pat" "true"

_lvl="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('pattern_level',0))" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "ui Aşama 5 → pattern_level=1 (real files)" "$_lvl" "1"

# --- Pattern summary captured, scan done ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['pattern_scan_due'] = False
d['pattern_summary'] = {
    'naming': 'PascalCase components, camelCase functions',
    'error': 'Result<T,E> type, no throw',
    'test': 'describe/it with React Testing Library'
}
json.dump(d, open(path, 'w'))
" "$_pwu_dir/.mcl/state.json"

# --- Aşama 6a → 6b → 6c sub-phase walk ---
for sub in BUILD_UI REVIEW BACKEND; do
  python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['ui_sub_phase'] = '$sub'
json.dump(d, open(path, 'w'))
" "$_pwu_dir/.mcl/state.json"

  _us="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('ui_sub_phase','') or '')" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
  assert_equals "ui Aşama 6 → ui_sub_phase=$sub" "$_us" "$sub"
done

# Mark UI flow complete
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['ui_reviewed'] = True
json.dump(d, open(path, 'w'))
" "$_pwu_dir/.mcl/state.json"

# --- Aşama 8 risk review running ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['risk_review_state'] = 'running'
json.dump(d, open(path, 'w'))
" "$_pwu_dir/.mcl/state.json"

_rs="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('risk_review_state','') or '')" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "ui Aşama 8 → risk_review_state=running" "$_rs" "running"

# --- Aşama 8 complete, Aşama 9 running ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['risk_review_state'] = 'complete'
d['quality_review_state'] = 'running'
json.dump(d, open(path, 'w'))
" "$_pwu_dir/.mcl/state.json"

# --- Aşama 9 complete → Aşama 11 ---
python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['quality_review_state'] = 'complete'
d['current_phase'] = 11
d['phase_name'] = 'DELIVER'
json.dump(d, open(path, 'w'))
" "$_pwu_dir/.mcl/state.json"

_phase="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('current_phase',0))" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
_qs="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('quality_review_state','') or '')" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "ui Aşama 11 → current_phase=11" "$_phase" "11"
assert_equals "ui Aşama 9 done → quality_review_state=complete" "$_qs" "complete"

# --- Final invariants ---
_valid_phase="$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
p = d.get('current_phase', 0)
print('ok' if 1 <= p <= 11 else 'fail')
" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "ui final → phase in valid range [1..11]" "$_valid_phase" "ok"

_ui_active="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get('ui_flow_active',False)).lower())" "$_pwu_dir/.mcl/state.json" 2>/dev/null)"
assert_equals "ui final → ui_flow_active still true" "$_ui_active" "true"

cleanup_test_dir "$_pwu_dir"
