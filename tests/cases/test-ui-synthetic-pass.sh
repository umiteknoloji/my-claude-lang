#!/bin/bash
# Test: UI flow + browser-display verification — SYNTHETIC PASS only.
#
# UI sub-phases (4a BUILD_UI, 4b REVIEW, 4c BACKEND) involve a live
# browser (mcl-claude-in-chrome / playwright / dev-server). These cannot
# be exercised end-to-end in CI without a display + browser binary.
#
# This test exercises the STATE machinery only:
#   - ui_flow_active=true + ui_sub_phase transitions (BUILD_UI → REVIEW
#     → BACKEND) work via state writes
#   - mcl-pre-tool.sh path-exception blocks backend paths in BUILD_UI
#
# **Vaad #2 (browser-rendered UI matches the spec) is SYNTHETIC-PASS;
# real-session confirmation required in production.**

echo "--- test-ui-synthetic-pass ---"

_us_proj="$(setup_test_dir)"

_us_init_4a() {
  python3 - "$_us_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 2, "current_phase": 4, "phase_name": "EXECUTE",
     "spec_approved": True, "spec_hash": "deadbeefcafef00d",
     "ui_flow_active": True, "ui_sub_phase": "BUILD_UI",
     "phase4_5_security_scan_done": True, "phase4_5_db_scan_done": True,
     "phase4_5_ui_scan_done": True, "phase4_5_ops_scan_done": True,
     "phase4_5_perf_scan_done": True,
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_us_init_4a

# Build a Write attempt against a BACKEND path in BUILD_UI sub-phase.
# Pre-tool path-exception should DENY backend writes in BUILD_UI.
_us_t="$_us_proj/t.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_us_t" user-only "build"

_us_payload="$(python3 -c "
import json,sys
print(json.dumps({
  'tool_name':'Write',
  'tool_input':{'file_path':sys.argv[1],'content':'// backend'},
  'transcript_path':sys.argv[2],
  'session_id':'us','cwd':sys.argv[3]
}))" "$_us_proj/src/api/users.ts" "$_us_t" "$_us_proj")"

_us_out_backend="$(printf '%s' "$_us_payload" \
  | CLAUDE_PROJECT_DIR="$_us_proj" \
    MCL_STATE_DIR="$_us_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null)"

assert_contains "[4a BUILD_UI] backend Write → permissionDecision deny" "$_us_out_backend" '"permissionDecision": "deny"'
assert_contains "[4a BUILD_UI] reason mentions UI-BUILD LOCK" "$_us_out_backend" "UI-BUILD LOCK"

# Frontend Write in BUILD_UI → ALLOWED.
_us_payload_fe="$(python3 -c "
import json,sys
print(json.dumps({
  'tool_name':'Write',
  'tool_input':{'file_path':sys.argv[1],'content':'export default function P(){}'},
  'transcript_path':sys.argv[2],
  'session_id':'us2','cwd':sys.argv[3]
}))" "$_us_proj/src/components/UserList.tsx" "$_us_t" "$_us_proj")"

_us_out_frontend="$(printf '%s' "$_us_payload_fe" \
  | CLAUDE_PROJECT_DIR="$_us_proj" \
    MCL_STATE_DIR="$_us_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null)"

if [ -z "$_us_out_frontend" ] || ! printf '%s' "$_us_out_frontend" | grep -q '"permissionDecision": "deny"'; then
  PASS=$((PASS+1))
  printf '  PASS: [4a BUILD_UI] frontend Write → allowed\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [4a BUILD_UI] frontend Write blocked unexpectedly\n'
  printf '        output: %s\n' "$(printf '%s' "$_us_out_frontend" | head -c 200)"
fi

# Transition BUILD_UI → BACKEND via direct state edit (simulates
# successful UI review approval).
python3 -c "
import json
p = '$_us_proj/.mcl/state.json'
d = json.load(open(p))
d['ui_sub_phase'] = 'BACKEND'
d['ui_reviewed'] = True
open(p,'w').write(json.dumps(d))
"

# Same backend Write should now succeed.
_us_out_backend2="$(printf '%s' "$_us_payload" \
  | CLAUDE_PROJECT_DIR="$_us_proj" \
    MCL_STATE_DIR="$_us_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null)"

if [ -z "$_us_out_backend2" ] || ! printf '%s' "$_us_out_backend2" | grep -q '"permissionDecision": "deny"'; then
  PASS=$((PASS+1))
  printf '  PASS: [4c BACKEND] backend Write → allowed after UI review\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [4c BACKEND] backend Write blocked unexpectedly\n'
fi

# Annotation: vaad #2 (browser-rendered UI matches spec) is NOT
# tested here. Synthetic-pass only. See RELEASE_9.2.1_REPORT.md
# Limitation 7.
SKIP=$((SKIP+1))
printf '  SKIP: vaad #2 — browser-rendered UI vs spec match (synthetic-pass; real-session required)\n'

cleanup_test_dir "$_us_proj"
