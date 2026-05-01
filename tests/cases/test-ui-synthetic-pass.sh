#!/bin/bash
# Test: 10.0.0 UI flow Phase 2 → Phase 3 — SYNTHETIC PASS only.
#
# In 10.0.0 the old 4a/4b/4c sub-phases collapse into:
#   - Phase 2 DESIGN_REVIEW: UI skeleton writes allowed, backend blocked
#   - Phase 3 IMPLEMENTATION: all writes unlocked (UI + backend)
# design_approved=true is the single transition trigger.
#
# This test exercises the STATE machinery only:
#   - Phase 2 + is_ui_project=true: pre-tool denies backend writes,
#     allows frontend writes
#   - After design_approved=true + transition to Phase 3: backend writes
#     succeed
#
# **Vaad #2 (browser-rendered UI matches the spec) is SYNTHETIC-PASS;
# real-session confirmation required in production.**

echo "--- test-ui-synthetic-pass ---"

_us_proj="$(setup_test_dir)"

_us_init_phase2() {
  python3 - "$_us_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 2, "phase_name": "DESIGN_REVIEW",
     "is_ui_project": True, "design_approved": False,
     "spec_hash": "deadbeefcafef00d",
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_us_init_phase2

# Build a Write attempt against a BACKEND path in Phase 2 DESIGN_REVIEW.
# Pre-tool path-exception should DENY backend writes in Phase 2.
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

assert_contains "[Phase 2] backend Write → permissionDecision deny" "$_us_out_backend" '"permissionDecision": "deny"'
assert_contains "[Phase 2] reason mentions DESIGN_REVIEW" "$_us_out_backend" "DESIGN_REVIEW"

# Frontend Write in Phase 2 DESIGN_REVIEW → ALLOWED.
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
  printf '  PASS: [Phase 2] frontend Write → allowed\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [Phase 2] frontend Write blocked unexpectedly\n'
  printf '        output: %s\n' "$(printf '%s' "$_us_out_frontend" | head -c 200)"
fi

# Transition Phase 2 → Phase 3 IMPLEMENTATION via direct state edit
# (simulates successful design askq approval).
python3 -c "
import json
p = '$_us_proj/.mcl/state.json'
d = json.load(open(p))
d['current_phase'] = 3
d['phase_name'] = 'IMPLEMENTATION'
d['design_approved'] = True
open(p,'w').write(json.dumps(d))
"

# Same backend Write should now succeed in Phase 3.
_us_out_backend2="$(printf '%s' "$_us_payload" \
  | CLAUDE_PROJECT_DIR="$_us_proj" \
    MCL_STATE_DIR="$_us_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null)"

if [ -z "$_us_out_backend2" ] || ! printf '%s' "$_us_out_backend2" | grep -q '"permissionDecision": "deny"'; then
  PASS=$((PASS+1))
  printf '  PASS: [Phase 3] backend Write → allowed after design approval\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [Phase 3] backend Write blocked unexpectedly\n'
fi

# Annotation: vaad #2 (browser-rendered UI matches spec) is NOT
# tested here. Synthetic-pass only.
SKIP=$((SKIP+1))
printf '  SKIP: vaad #2 — browser-rendered UI vs spec match (synthetic-pass; real-session required)\n'

cleanup_test_dir "$_us_proj"
