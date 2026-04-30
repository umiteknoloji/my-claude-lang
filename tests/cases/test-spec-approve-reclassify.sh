#!/bin/bash
# Test: state-aware spec-approve reclassification (since 9.1.1).
#
# The askq-scanner classifies AskUserQuestion intent by question-body
# tokens. Real-session bug: when the model phrases the spec-approval
# question outside the recognized token set, intent="other", no
# transition fires, and the user sees "MCL LOCK Phase 1" because
# spec_approved stays false.
#
# 9.1.1 fix: when intent="other" but state context indicates a spec
# is awaiting approval (current_phase ∈ {2,3} + spec_hash set) AND
# the developer's selected label matches approve-family, reclassify
# the askq as spec-approve. Phase 4 transition fires; Write tool
# unlocks.

echo "--- test-spec-approve-reclassify ---"

_sar_proj="$(setup_test_dir)"
_sar_state="$_sar_proj/.mcl/state.json"
mkdir -p "$_sar_proj/.mcl"

_sar_init() {
  # phase=2 + spec_hash present mirrors the moment AFTER spec emission
  # but BEFORE approval. Pre-9.1.1, the user is stuck here with an
  # unrecognized question body. Pass hash as JSON-literal text
  # ("null" or '"hex"') so Python sees it verbatim.
  local phase="$1" hash_val="$2"
  python3 - "$phase" "$hash_val" <<'PY'
import json, sys, time
phase = int(sys.argv[1])
raw = sys.argv[2]
hash_v = json.loads(raw)
o = {
    "schema_version": 2,
    "current_phase": phase,
    "phase_name": "SPEC_REVIEW" if phase == 2 else "USER_VERIFY",
    "spec_approved": False,
    "spec_hash": hash_v,
    "last_update": int(time.time()),
}
import os
open(os.environ["SAR_STATE"], "w").write(json.dumps(o))
PY
}
export SAR_STATE="$_sar_state"

# Helper: build a transcript with a spec-bearing assistant turn +
# AskUserQuestion turn + tool_result. The question body and selected
# label are parameterized so we can exercise multiple shapes.
_sar_transcript() {
  local question_body="$1" selected_label="$2"
  local out="$_sar_proj/transcript.jsonl"
  python3 -c '
import json, sys
out = sys.argv[1]
qbody = sys.argv[2]
sel = sys.argv[3]
spec = """📋 Spec:

## Objective
Build admin panel.

## MUST
- Auth required

## SHOULD
- Pagination

## Acceptance Criteria
## Edge Cases
## Technical Approach
## Out of Scope
"""
turns = [
    {"type":"user","message":{"role":"user","content":"build it"}},
    {"type":"assistant","message":{"role":"assistant","content":[
        {"type":"text","text": spec}
    ]}},
    {"type":"assistant","message":{"role":"assistant","content":[
        {"type":"tool_use","id":"tu_q","name":"AskUserQuestion","input":{
            "questions":[{"question":"MCL 9.1.1 | " + qbody, "options":[sel,"Düzenle","İptal"]}]
        }}
    ]}},
    {"type":"user","message":{"role":"user","content":[
        {"type":"tool_result","tool_use_id":"tu_q","content": sel}
    ]}},
]
with open(out, "w") as f:
    for t in turns:
        f.write(json.dumps(t) + "\n")
' "$out" "$question_body" "$selected_label"
  printf '%s' "$out"
}

_sar_run_stop() {
  local transcript="$1"
  printf '%s' "{\"transcript_path\":\"${transcript}\",\"session_id\":\"sar\",\"cwd\":\"${_sar_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_sar_proj" \
      MCL_STATE_DIR="$_sar_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

# ---- Test 1: question body NOT in token set + approve-family selected ----
# Pre-9.1.1: askq-scanner returns intent="other"; no transition.
# 9.1.1: state-context fallback reclassifies → spec-approved.
_sar_init 2 '"deadbeefcafef00d"'
_sar_t1="$(_sar_transcript "Bu plan uygun mu?" "Onayla, başla")"
_sar_run_stop "$_sar_t1" >/dev/null

_sar_phase="$(python3 -c "import json; print(json.load(open('$_sar_state'))['current_phase'])")"
_sar_appr="$(python3 -c "import json; print(json.load(open('$_sar_state'))['spec_approved'])")"
assert_equals "untokenized question + Onayla → current_phase=4" "$_sar_phase" "4"
assert_equals "untokenized question + Onayla → spec_approved=true" "$_sar_appr" "True"

# Audit captures the reclassification with state-context-fallback source.
if grep -q "askq-reclassified-spec-approve.*source=state-context-fallback" "$_sar_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: audit captures state-context-fallback reclassification\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: reclassification audit missing\n'
  grep "askq-reclassified" "$_sar_proj/.mcl/audit.log" 2>/dev/null | head -3 || true
fi

# ---- Test 2: question body IN token set → original path, no reclassify ----
# When the scanner already classifies as spec-approve, the fallback
# is a no-op (its guard is `intent == "other"`).
_sar_init 2 '"cafef00ddeadbeef"'
rm -f "$_sar_proj/.mcl/audit.log"
_sar_t2="$(_sar_transcript "Spec'i onayla?" "Onayla")"
_sar_run_stop "$_sar_t2" >/dev/null

_sar_phase2="$(python3 -c "import json; print(json.load(open('$_sar_state'))['current_phase'])")"
assert_equals "tokenized question → still advances to phase 4" "$_sar_phase2" "4"
# No reclassify audit because the original path already fired.
if grep -q "askq-reclassified-spec-approve" "$_sar_proj/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: tokenized question should NOT trigger reclassify\n'
else
  PASS=$((PASS+1))
  printf '  PASS: tokenized question goes through original path\n'
fi

# ---- Test 3: untokenized question + non-approve selected → no reclassify ----
# Selected="Düzenle" (Edit) is not approve-family. Even though state
# context matches the awaiting-approval window, the fallback should
# not fire — selected option is the source of truth.
_sar_init 2 '"abcdef0123456789"'
rm -f "$_sar_proj/.mcl/audit.log"
_sar_t3="$(_sar_transcript "Bu plan uygun mu?" "Düzenle")"
_sar_run_stop "$_sar_t3" >/dev/null

_sar_phase3="$(python3 -c "import json; print(json.load(open('$_sar_state'))['current_phase'])")"
assert_equals "untokenized + Düzenle → still phase 2" "$_sar_phase3" "2"
_sar_appr3="$(python3 -c "import json; print(json.load(open('$_sar_state'))['spec_approved'])")"
assert_equals "untokenized + Düzenle → spec_approved=false" "$_sar_appr3" "False"

# ---- Test 4: phase=1 (no spec emitted) + approve-family → no reclassify ----
# Summary-confirm AskUserQuestion in Phase 1 also uses approve-family
# options. The fallback's `phase ∈ {2,3} + spec_hash` guard prevents
# false-positive on Phase 1 questions. Without the guard, every
# "Onayla, başla" on a summary-confirm would fast-forward to Phase 4
# without an actual spec.
_sar_init 1 'null'
rm -f "$_sar_proj/.mcl/audit.log"
_sar_t4="$(_sar_transcript "Bu özet doğru mu?" "Onayla, başla")"
_sar_run_stop "$_sar_t4" >/dev/null

_sar_phase4="$(python3 -c "import json; print(json.load(open('$_sar_state'))['current_phase'])")"
# Phase 1 → 2 transition can fire because the transcript also has a
# `📋 Spec:` block (mcl-stop.sh detects spec independently of approval).
# What we're verifying: NO jump to Phase 4 and NO spec_approved=true.
_sar_appr4="$(python3 -c "import json; print(json.load(open('$_sar_state'))['spec_approved'])")"
assert_equals "phase=1 + approve-family → spec_approved stays false" "$_sar_appr4" "False"
if grep -q "askq-reclassified-spec-approve" "$_sar_proj/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: phase=1 should NOT reclassify (guard breach)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: phase=1 + approve-family → no reclassify (guard works)\n'
fi

cleanup_test_dir "$_sar_proj"
