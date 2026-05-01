#!/bin/bash
# Test: PreToolUse-level askq deny on incomplete spec (since 9.1.4).
#
# Real-session bug: model emits a short `📋 Spec:` block (Project +
# Pages + Stack notes — no canonical 7-section structure) AND an
# AskUserQuestion in the same turn. The Stop-hook partial-spec block
# fires AFTER the askq tool_use was already processed, so the askq
# still reaches the user. User clicks an approve-family option;
# subsequent Write attempts hit the Phase 1 lock (partial-spec
# rewound the transition; state.spec_hash stays null; the 9.1.1
# reclassify fallback cannot latch).
#
# Fix: deny the askq itself at PreToolUse time when the most-recent
# assistant text carries an incomplete spec. Forces re-emit BEFORE
# user is asked to approve.

echo "--- test-askq-incomplete-spec-block ---"

_aqi_proj="$(setup_test_dir)"
_aqi_state="$_aqi_proj/.mcl/state.json"
mkdir -p "$_aqi_proj/.mcl"

_aqi_init_state() {
  local phase="$1"
  python3 - "$phase" <<'PY'
import json, os, sys, time
phase = int(sys.argv[1])
o = {
    "schema_version": 2,
    "current_phase": phase,
    "phase_name": "COLLECT" if phase == 1 else "EXECUTE",
    "spec_approved": phase >= 4,
    "last_update": int(time.time()),
}
open(os.environ["AQI_STATE"], "w").write(json.dumps(o))
PY
}
export AQI_STATE="$_aqi_state"

# Helper: write transcript with a single assistant turn carrying
# arbitrary text, then run mcl-pre-tool.sh on an AskUserQuestion call.
_aqi_run() {
  local transcript_text="$1"
  local out_path="$_aqi_proj/transcript.jsonl"
  python3 - "$out_path" "$transcript_text" <<'PY'
import json, sys
out_path, body = sys.argv[1], sys.argv[2]
turns = [
    {"type":"user","message":{"role":"user","content":"build it"}},
    {"type":"assistant","message":{"role":"assistant","content":[
        {"type":"text","text": body}
    ]}}
]
with open(out_path, "w") as f:
    for t in turns:
        f.write(json.dumps(t) + "\n")
PY
  printf '%s' "{\"tool_name\":\"AskUserQuestion\",\"tool_input\":{\"questions\":[{\"question\":\"MCL 9.1.4 | iyi mi?\",\"options\":[\"Evet, oluştur\",\"Düzenle\"]}]},\"transcript_path\":\"$out_path\",\"session_id\":\"aqi\",\"cwd\":\"$_aqi_proj\"}" \
    | CLAUDE_PROJECT_DIR="$_aqi_proj" \
      MCL_STATE_DIR="$_aqi_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null
}

# ---- Test 1: short spec (Project/Pages/Stack notes) + Phase 1 → DENY ----
_aqi_init_state 1
_aqi_short_spec='📋 Spec:
Project: admin panel
Pages: /login, /users
Stack: React + FastAPI'
_aqi_out1="$(_aqi_run "$_aqi_short_spec")"
assert_contains "Phase 1 + short spec → permissionDecision deny" "$_aqi_out1" '"permissionDecision": "deny"'
assert_contains "Phase 1 + short spec → cites missing sections" "$_aqi_out1" "Objective,MUST"
assert_contains "Phase 1 + short spec → reason cites missing+points to template" "$_aqi_out1" "Re-emit"

# ---- Test 2: complete 7-section spec + Phase 1 → ALLOW ----
_aqi_init_state 1
_aqi_complete_spec='📋 Spec:
## Objective
Build admin panel.
## MUST
- Auth required
## SHOULD
- Pagination
## Acceptance Criteria
- non-admin gets 403
## Edge Cases
- empty list
## Technical Approach
- React + FastAPI
## Out of Scope
- multi-tenant'
_aqi_out2="$(_aqi_run "$_aqi_complete_spec")"
if [ -z "$_aqi_out2" ]; then
  PASS=$((PASS+1))
  printf '  PASS: Phase 1 + complete 7-section spec → allow (no output)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: Phase 1 + complete spec should pass through, got: %s\n' "$(printf '%s' "$_aqi_out2" | head -c 120)"
fi

# ---- Test 3: Phase 4 askq + short spec → ALLOW (out of scope window) ----
# Phase 4.5 risk-review askq has a different intent; the gate is
# scoped to Phase 1-3 (pre-approval window). Phase 4+ askq calls must
# pass through regardless of any spec-shaped text in transcript.
_aqi_init_state 4
_aqi_out3="$(_aqi_run "$_aqi_short_spec")"
if [ -z "$_aqi_out3" ]; then
  PASS=$((PASS+1))
  printf '  PASS: Phase 4 askq + short spec → allow (gate phase-scoped)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: Phase 4 askq should pass, got: %s\n' "$(printf '%s' "$_aqi_out3" | head -c 120)"
fi

# ---- Test 4: Phase 1 askq + no spec block → ALLOW (Phase 1 summary) ----
# The Phase 1 summary-confirm askq fires before the spec is emitted.
# Transcript has no `📋 Spec:` line yet. Partial-spec scanner returns
# rc=2 (no spec to check); deny does NOT fire.
_aqi_init_state 1
_aqi_no_spec='Bu özetle başlayabiliriz:
- intent: kullanıcı paneli
- stack: React'
_aqi_out4="$(_aqi_run "$_aqi_no_spec")"
if [ -z "$_aqi_out4" ]; then
  PASS=$((PASS+1))
  printf '  PASS: Phase 1 + no spec block → allow (summary-confirm path)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: Phase 1 + no spec block should pass, got: %s\n' "$(printf '%s' "$_aqi_out4" | head -c 120)"
fi

# ---- Test 5: audit log captures block-askq-incomplete-spec event ----
if grep -q "block-askq-incomplete-spec" "$_aqi_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: audit captures block-askq-incomplete-spec event\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: audit log missing block-askq-incomplete-spec\n'
fi

cleanup_test_dir "$_aqi_proj"
unset AQI_STATE
