#!/bin/bash
# Test: 10.0.0 simplified phase model — Phase 1 summary-confirm → Phase 3
# (non-UI) or → Phase 2 DESIGN_REVIEW (UI). Spec emit is advisory format,
# not a state gate.
#
# 3 things must work end-to-end:
#   (A) Phase 1 summary-confirm approve (non-UI) → state advances to phase=3
#   (B) Phase 3 Write/Edit unlocked (no design_approved check for non-UI)
#   (C) Spec emit on Phase 3: format valid → records hash + saves spec
#       (no state change). Format invalid → spec-format-warn audit (advisory).

echo "--- test-canonical-flow ---"

_cf_proj="$(setup_test_dir)"

_cf_init_phase1() {
  python3 - "$_cf_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 1, "phase_name": "INTENT",
     "is_ui_project": False, "design_approved": False,
     "spec_hash": None, "last_update": int(time.time())}
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

# ---- Build summary-confirm askq fixture ----
_cf_build_summary_confirm_transcript() {
  local out="$1" selected="${2:-Onayla}"
  python3 - "$out" "$selected" <<'PY'
import json, sys
out, selected = sys.argv[1], sys.argv[2]
question = "MCL 10.0.0 | Bu özet doğru mu?"
turns = [
    {"type":"user","timestamp":"2026-05-01T00:00:00.000Z",
     "message":{"role":"user","content":"build it"}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:30.000Z",
     "message":{"role":"assistant","content":[
         {"type":"text","text":"━━━━━\nI understood:\n- intent: x\n- stack: y\n━━━━━"}]}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:40.000Z",
     "message":{"role":"assistant","content":[
         {"type":"tool_use","id":"toolu_sc1","name":"AskUserQuestion",
          "input":{"questions":[{"question":question,
            "options":[{"label":selected,"description":""},{"label":"Düzenle","description":""},{"label":"İptal","description":""}]}]}}]}},
    {"type":"user","timestamp":"2026-05-01T00:00:50.000Z",
     "message":{"role":"user","content":[
         {"type":"tool_result","tool_use_id":"toolu_sc1",
          "content":f"User has answered your questions: \"{question}\"=\"{selected}\"."}]}},
]
with open(out,"w") as f:
    for t in turns: f.write(json.dumps(t)+"\n")
PY
}

# ---- Step A: Phase 1 summary-confirm approve (non-UI) → state=3 ----
_cf_init_phase1
_cf_t_sc="$_cf_proj/t_sc.jsonl"
_cf_build_summary_confirm_transcript "$_cf_t_sc" "Onayla"

_cf_run_stop "$_cf_t_sc" >/dev/null

_cf_phase="$(_cf_state_field current_phase)"
assert_equals "[A] summary-confirm approve (non-UI) → current_phase=3" "$_cf_phase" "3"

_cf_phase_name="$(_cf_state_field phase_name)"
assert_equals "[A] phase_name=IMPLEMENTATION" "$_cf_phase_name" "IMPLEMENTATION"

if grep -q "phase-transition-to-implementation.*1->3" "$_cf_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [A] phase-transition-to-implementation audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [A] phase-transition-to-implementation audit missing\n'
  grep "phase-transition\|summary-confirm" "$_cf_proj/.mcl/audit.log" 2>/dev/null | tail -3
fi

# ---- Step B: Phase 3 Write attempt → ALLOWED ----
_cf_out_b="$(_cf_run_pretool_write "$_cf_t_sc" "$_cf_proj/src/index.ts")"
if [ -z "$_cf_out_b" ] || printf '%s' "$_cf_out_b" | grep -q '"permissionDecision": "allow"'; then
  PASS=$((PASS+1))
  printf '  PASS: [B] Phase 3 Write → allowed\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [B] Phase 3 Write should be allowed, got: %s\n' "$(printf '%s' "$_cf_out_b" | head -c 200)"
fi

# ---- Step C: spec emit on Phase 3 → records hash, no state change ----
_cf_t_spec="$_cf_proj/t_spec.jsonl"
# Build transcript: summary-confirm then spec emit
python3 - "$_cf_t_spec" <<'PY'
import json, sys
out = sys.argv[1]
spec = """📋 Spec:

## [Admin]

## Objective
build admin panel

## MUST
- auth

## SHOULD
- pagination

## Acceptance Criteria
- [ ] works

## Edge Cases
- empty list

## Technical Approach
- React + FastAPI

## Out of Scope
- multi-tenant
"""
question = "MCL 10.0.0 | Bu özet doğru mu?"
turns = [
    {"type":"user","timestamp":"2026-05-01T00:00:00.000Z",
     "message":{"role":"user","content":"build it"}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:40.000Z",
     "message":{"role":"assistant","content":[
         {"type":"tool_use","id":"toolu_sc1","name":"AskUserQuestion",
          "input":{"questions":[{"question":question,
            "options":[{"label":"Onayla","description":""},{"label":"Düzenle","description":""}]}]}}]}},
    {"type":"user","timestamp":"2026-05-01T00:00:50.000Z",
     "message":{"role":"user","content":[
         {"type":"tool_result","tool_use_id":"toolu_sc1",
          "content":f"User has answered your questions: \"{question}\"=\"Onayla\"."}]}},
    {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
     "message":{"role":"assistant","content":[{"type":"text","text":spec}]}},
]
with open(out,"w") as f:
    for t in turns: f.write(json.dumps(t)+"\n")
PY

_cf_run_stop "$_cf_t_spec" >/dev/null

_cf_phase_c="$(_cf_state_field current_phase)"
_cf_hash_c="$(_cf_state_field spec_hash)"
assert_equals "[C] post-spec-emit current_phase=3 (no transition on spec)" "$_cf_phase_c" "3"
if [ -n "$_cf_hash_c" ] && [ "$_cf_hash_c" != "null" ]; then
  PASS=$((PASS+1))
  printf '  PASS: [C] spec_hash recorded (%s)\n' "${_cf_hash_c:0:12}"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [C] spec_hash missing (got: %s)\n' "$_cf_hash_c"
fi

if grep -q "spec-emit" "$_cf_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [C] spec-emit audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [C] spec-emit audit missing\n'
fi

# ---- Negative control: Phase 1 Write (no summary-confirm yet) → DENIED ----
_cf_init_phase1
_cf_t_p1="$_cf_proj/t_p1.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_cf_t_p1" user-only "build it"
_cf_out_neg="$(_cf_run_pretool_write "$_cf_t_p1" "$_cf_proj/src/x.ts")"
assert_contains "[neg] Phase 1 Write → permissionDecision deny" "$_cf_out_neg" '"permissionDecision": "deny"'
assert_contains "[neg] reason mentions Phase 1" "$_cf_out_neg" "Phase 1"

cleanup_test_dir "$_cf_proj"
