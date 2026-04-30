#!/bin/bash
# Test: 9.2.1 simplified canonical flow — spec emit auto-advances to Phase 4.
#
# 9.2.1 removed AskUserQuestion-based spec approval entirely. The flow:
#   (A) Phase 1: model gathers info via clarifying questions
#   (B) Phase 2: model emits 📋 Spec: block with 7 sections
#   (C) Stop hook detects valid spec → auto-transition to Phase 4
#       (current_phase=4, spec_approved=true)
#   (D) Phase 4: Write/Edit unlocked

echo "--- test-canonical-flow ---"

_cf_proj="$(setup_test_dir)"

_cf_init_phase1() {
  python3 - "$_cf_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 2, "current_phase": 1, "phase_name": "COLLECT",
     "spec_approved": False, "spec_hash": None, "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_cf_run_stop() {
  local transcript="$1"
  printf '%s' "{\"transcript_path\":\"${transcript}\",\"session_id\":\"cf\",\"cwd\":\"${_cf_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_cf_proj" \
      MCL_STATE_DIR="$_cf_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

_cf_run_pretool_write() {
  local transcript="$1" file_path="$2"
  printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${file_path}\",\"content\":\"// hi\"},\"transcript_path\":\"${transcript}\",\"session_id\":\"cf\",\"cwd\":\"${_cf_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_cf_proj" \
      MCL_STATE_DIR="$_cf_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null
}

_cf_state_field() {
  python3 -c "import json; d=json.load(open('$_cf_proj/.mcl/state.json')); v=d.get('$1'); print('null' if v is None else (str(v).lower() if isinstance(v,bool) else v))"
}

# ---- Step A/B/C: spec emit → auto-advance to Phase 4 ----
_cf_init_phase1
_cf_t_spec="$_cf_proj/t_spec.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_cf_t_spec" spec-correct "Admin Panel"

_cf_run_stop "$_cf_t_spec" >/dev/null

_cf_phase="$(_cf_state_field current_phase)"
_cf_appr="$(_cf_state_field spec_approved)"
_cf_hash="$(_cf_state_field spec_hash)"

assert_equals "[A→C] spec emit → current_phase=4 (auto-advance)" "$_cf_phase" "4"
assert_equals "[A→C] spec emit → spec_approved=true (auto-advance)" "$_cf_appr" "true"
if [ -n "$_cf_hash" ] && [ "$_cf_hash" != "null" ]; then
  PASS=$((PASS+1))
  printf '  PASS: [A→C] spec_hash populated (%s)\n' "${_cf_hash:0:12}"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [A→C] spec_hash missing (got: %s)\n' "$_cf_hash"
fi

if grep -q "auto-approve-spec" "$_cf_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [A→C] auto-approve-spec audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [A→C] auto-approve-spec audit missing\n'
fi

# ---- Step D: Phase 4 Write attempt → ALLOWED ----
_cf_out_d="$(_cf_run_pretool_write "$_cf_t_spec" "$_cf_proj/src/index.ts")"
if [ -z "$_cf_out_d" ]; then
  PASS=$((PASS+1))
  printf '  PASS: [D] Phase 4 Write → allowed (passthrough, no output)\n'
elif printf '%s' "$_cf_out_d" | grep -q '"permissionDecision": "allow"'; then
  PASS=$((PASS+1))
  printf '  PASS: [D] Phase 4 Write → explicit allow\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [D] Phase 4 Write should have been allowed, got: %s\n' "$(printf '%s' "$_cf_out_d" | head -c 200)"
fi

# ---- Negative control 1: Phase 1 Write (no spec emitted) → DENIED ----
_cf_init_phase1
_cf_t_p1="$_cf_proj/t_p1.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_cf_t_p1" user-only "build it"
_cf_out_neg1="$(_cf_run_pretool_write "$_cf_t_p1" "$_cf_proj/src/x.ts")"
assert_contains "[neg1] Phase 1 Write → permissionDecision deny" "$_cf_out_neg1" '"permissionDecision": "deny"'
assert_contains "[neg1] Phase 1 Write → MCL LOCK reason" "$_cf_out_neg1" "spec_approved=false"

# ---- Same-turn JIT: spec + Write in same transcript, Stop hasn't fired ----
# Pre-tool's JIT auto-advance should detect the spec and unlock the Write.
_cf_init_phase1
rm -f "$_cf_proj/.mcl/audit.log"
_cf_t_jit="$_cf_proj/t_jit.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_cf_t_jit" spec-correct "Admin Panel"
# Note: state is still phase=1, but transcript HAS the spec.
_cf_out_jit="$(_cf_run_pretool_write "$_cf_t_jit" "$_cf_proj/src/main.ts")"

_cf_phase_jit="$(_cf_state_field current_phase)"
_cf_appr_jit="$(_cf_state_field spec_approved)"
assert_equals "[JIT] same-turn spec + Write → current_phase=4 (jit advance)" "$_cf_phase_jit" "4"
assert_equals "[JIT] same-turn spec + Write → spec_approved=true" "$_cf_appr_jit" "true"

if grep -q "auto-approve-spec-jit" "$_cf_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [JIT] auto-approve-spec-jit audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [JIT] pre-tool auto-approve audit missing\n'
fi

# ---- Negative control 2: spec WITHOUT 📋 prefix → no auto-advance ----
_cf_init_phase1
rm -f "$_cf_proj/.mcl/audit.log"
_cf_t_bad="$_cf_proj/t_bad.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_cf_t_bad" spec-no-emoji-bare
_cf_run_stop "$_cf_t_bad" >/dev/null

_cf_phase_bad="$(_cf_state_field current_phase)"
_cf_appr_bad="$(_cf_state_field spec_approved)"
assert_equals "[neg2] no-emoji spec → current_phase stays 1" "$_cf_phase_bad" "1"
assert_equals "[neg2] no-emoji spec → spec_approved stays false" "$_cf_appr_bad" "false"

cleanup_test_dir "$_cf_proj"
