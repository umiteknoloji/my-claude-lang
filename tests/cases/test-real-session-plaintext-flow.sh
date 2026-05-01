#!/bin/bash
# Test: real-session plaintext flow — Bug 1/3/4 (10.0.3) + Bug 2 (10.0.6 enforcement).
#
# Reproduces the EXACT scenario from `cd /tmp/test && claude → backoffice yap`
# that revealed 4 critical bugs in 10.0.2:
#   Bug 1: UserPromptSubmit hook returned JSON missing hookEventName.
#   Bug 2: Phase 1 → 2/3 transition never fired because Claude Code asks
#          Phase 1 questions in plain prose (no AskUserQuestion call).
#   Bug 3: 📋 Spec block emitted while state.current_phase=1.
#   Bug 4: Hook block reasons did not surface /mcl-restart escape hatch.
#
# 10.0.3 fixed Bug 2 with a plain-text approve fallback (whitelist of
# TR+EN approve words synthesizing ASKQ_INTENT=summary-confirm). 10.0.6
# REMOVED that fallback — a finite whitelist can't cover natural-
# language approvals ("doğru", "uygundur", "tabii", ...) and silent
# rejection is a worse UX than asking explicitly. Plain-text "evet"
# now sets state.summary_askq_skipped=true and triggers a context
# injection on the next UserPromptSubmit demanding AskUserQuestion.
#
# Acceptance criteria — when this test is GREEN, the regressed session
# walks through cleanly:
#   1. Initial prompt with state at phase=1, is_ui_project=true.
#   2. Synthetic transcript: assistant emits 3 plain-text clarifying
#      questions, the developer answers each, the assistant emits a
#      brief summary (Özet section), and the developer responds "evet".
#   3. (10.0.6) Stop hook sets summary_askq_skipped=true; current_phase
#      stays at 1 (no plaintext fallback, no transition).
#   4. Pre-tool Write attempt at frontend path stays blocked (phase=1).
#   5. Self-project guard early-exit JSON includes hookEventName.

echo "--- test-real-session-plaintext-flow ---"

_rs_proj="$(setup_test_dir)"
_rs_state="$_rs_proj/.mcl/state.json"

# ---- Setup state: Phase 1, UI project flagged ----
python3 - "$_rs_state" <<'PY'
import json, sys, time
o = {
    "schema_version": 3,
    "current_phase": 1,
    "phase_name": "INTENT",
    "is_ui_project": True,
    "design_approved": False,
    "spec_hash": None,
    "phase1_intent": "backoffice yap",
    "last_update": int(time.time()),
}
open(sys.argv[1], "w").write(json.dumps(o))
PY

# ---- Bug 1 regression: UserPromptSubmit early-exit JSON valid ----
# The self-project guard fires when CLAUDE_PROJECT_DIR == MCL_REPO_PATH.
# Drive it and assert hookEventName is present.
_rs_b1_out="$(printf '{"prompt":"hi","session_id":"rs1","cwd":"%s"}' "$REPO_ROOT" \
  | CLAUDE_PROJECT_DIR="$REPO_ROOT" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-activate.sh" 2>/dev/null)"
if printf '%s' "$_rs_b1_out" | grep -q '"hookEventName"[[:space:]]*:[[:space:]]*"UserPromptSubmit"'; then
  PASS=$((PASS+1))
  printf '  PASS: [Bug 1] self-project guard emits hookEventName=UserPromptSubmit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [Bug 1] hookEventName missing from self-project guard JSON\n'
  printf '        output: %s\n' "$(printf '%s' "$_rs_b1_out" | head -c 250)"
fi

# ---- Build the real-session transcript ----
_rs_t="$_rs_proj/transcript.jsonl"
python3 - "$_rs_t" <<'PY'
import json, sys
turns = [
    {"type":"user",     "timestamp":"2026-05-01T00:00:00Z",
     "message":{"role":"user","content":"backoffice yap"}},

    # Plain-text question 1 (no AskUserQuestion tool call)
    {"type":"assistant","timestamp":"2026-05-01T00:00:30Z",
     "message":{"role":"assistant","content":[{"type":"text",
       "text":"🌐 MCL 10.0.3 — Phase 1 INTENT\n\nAnladım. Birkaç netleştirme sorusu sorayım:\n\n1) Hangi rolleri yöneteceğiz? (örn: admin, editor, viewer)"}]}},
    {"type":"user",     "timestamp":"2026-05-01T00:00:45Z",
     "message":{"role":"user","content":"admin ve viewer yeterli"}},

    # Question 2
    {"type":"assistant","timestamp":"2026-05-01T00:01:00Z",
     "message":{"role":"assistant","content":[{"type":"text",
       "text":"2) Auth nasıl olsun? (e-posta+parola, OAuth, magic link)"}]}},
    {"type":"user",     "timestamp":"2026-05-01T00:01:15Z",
     "message":{"role":"user","content":"e-posta ve parola"}},

    # Question 3
    {"type":"assistant","timestamp":"2026-05-01T00:01:30Z",
     "message":{"role":"assistant","content":[{"type":"text",
       "text":"3) Stack tercihi? (React + FastAPI varsayalım mı?)"}]}},
    {"type":"user",     "timestamp":"2026-05-01T00:01:45Z",
     "message":{"role":"user","content":"react fastapi olur"}},

    # Plain-text summary turn (the trigger surface for plaintext fallback)
    {"type":"assistant","timestamp":"2026-05-01T00:02:00Z",
     "message":{"role":"assistant","content":[{"type":"text",
       "text":(
         "Özet:\n"
         "- intent: admin paneli (backoffice)\n"
         "- roles: admin, viewer\n"
         "- auth: e-posta + parola\n"
         "- stack: React + FastAPI + Postgres\n"
         "- pages: /login, /users, /audit\n\n"
         "Onaylıyor musun? Onaylarsan implementasyona başlıyorum."
       )}]}},

    # Developer's clean approve
    {"type":"user",     "timestamp":"2026-05-01T00:02:10Z",
     "message":{"role":"user","content":"evet"}},
]
with open(sys.argv[1], "w") as fh:
    for t in turns:
        fh.write(json.dumps(t) + "\n")
PY

# ---- Bug 2 (10.0.6 update): plain-text fallback removed ----
# 10.0.3 added a plain-text approve fallback so "evet" advanced the
# Phase 1 → 2/3 transition without an AskUserQuestion call. 10.0.6
# removed the fallback (a finite TR+EN whitelist can't cover natural-
# language approvals like "doğru", "uygundur", "tabii"). Plain-text
# "evet" now triggers the summary-askq-skipped enforcement flag
# instead, so the next UserPromptSubmit prompts the model to re-emit
# the summary via AskUserQuestion.
_rs_stop_out="$(printf '%s' "{\"transcript_path\":\"${_rs_t}\",\"session_id\":\"rs2\",\"cwd\":\"${_rs_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_rs_proj" \
    MCL_STATE_DIR="$_rs_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"

_rs_phase_after="$(python3 -c "import json; print(json.load(open('$_rs_state')).get('current_phase'))")"
_rs_flag_after="$(python3 -c "import json; print(json.load(open('$_rs_state')).get('summary_askq_skipped'))")"
assert_equals "[Bug 2] plaintext 'evet' no longer advances phase (stays 1)" \
  "$_rs_phase_after" "1"
assert_equals "[Bug 2] summary_askq_skipped flag set true" \
  "$_rs_flag_after" "True"

if grep -q "summary-askq-skipped" "$_rs_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [Bug 2] summary-askq-skipped enforcement audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [Bug 2] summary-askq-skipped audit missing\n'
fi

if grep -q "plaintext-summary-confirm-detected" "$_rs_proj/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [Bug 2] removed plaintext-fallback audit still firing (regression)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [Bug 2] plaintext-fallback audit absent (10.0.3 fallback fully removed)\n'
fi

if grep -qE "phase-transition-to-(design-review|implementation)" "$_rs_proj/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [Bug 2] phase-transition fired without AskUserQuestion (regression)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [Bug 2] no phase-transition audit (askq required)\n'
fi

# ---- Bug 3 regression: spec emission at phase=1 must block ----
# Re-init state to phase=1 with no askq, build a transcript that emits
# 📋 Spec without any plaintext approval. Stop hook must emit a
# decision:block citing premature spec.
_rs_b3_state="$_rs_proj/b3.json"
python3 - "$_rs_b3_state" <<'PY'
import json, sys, time
o = {"schema_version":3,"current_phase":1,"phase_name":"INTENT",
     "is_ui_project":False,"design_approved":False,
     "spec_hash":None,"last_update":int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY

_rs_b3_t="$_rs_proj/b3.jsonl"
python3 - "$_rs_b3_t" <<'PY'
import json, sys
spec = (
    "📋 Spec:\n\n"
    "## Objective\nBuild backoffice.\n\n"
    "## MUST\n- /users page\n- auth\n\n"
    "## SHOULD\n- pagination\n\n"
    "## Acceptance Criteria\n- [ ] login works\n\n"
    "## Edge Cases\n- empty list\n\n"
    "## Technical Approach\n- React + FastAPI\n\n"
    "## Out of Scope\n- multi-tenant\n"
)
turns = [
    {"type":"user","timestamp":"2026-05-01T00:00:00Z",
     "message":{"role":"user","content":"backoffice yap"}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:30Z",
     "message":{"role":"assistant","content":[{"type":"text","text":spec}]}},
]
with open(sys.argv[1], "w") as fh:
    for t in turns:
        fh.write(json.dumps(t) + "\n")
PY
rm -f "$_rs_proj/.mcl/audit.log"
_rs_b3_out="$(printf '%s' "{\"transcript_path\":\"${_rs_b3_t}\",\"session_id\":\"rs3\",\"cwd\":\"${_rs_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_rs_proj" \
    MCL_STATE_FILE="$_rs_b3_state" \
    MCL_STATE_DIR="$_rs_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"
if printf '%s' "$_rs_b3_out" | grep -q '"decision": "block"'; then
  PASS=$((PASS+1))
  printf '  PASS: [Bug 3] premature spec at phase=1 → decision:block\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [Bug 3] premature spec at phase=1 should be blocked\n'
  printf '        output: %s\n' "$(printf '%s' "$_rs_b3_out" | head -c 250)"
fi
if printf '%s' "$_rs_b3_out" | grep -q "/mcl-restart"; then
  PASS=$((PASS+1))
  printf '  PASS: [Bug 3+4] block reason surfaces /mcl-restart escape hatch\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [Bug 4] block reason missing /mcl-restart guidance\n'
fi

# ---- Bug 4 regression: project's .mcl/state.json Read is allowed ----
# Pre-tool hook should NOT block Read of <project>/.mcl/state.json even
# at phase=1, so the developer can diagnose stuck states.
_rs_b4_payload="$(python3 -c "
import json
print(json.dumps({
    'tool_name':'Read',
    'tool_input':{'file_path':'$_rs_proj/.mcl/state.json'},
    'session_id':'rs4',
    'cwd':'$_rs_proj'
}))")"
_rs_b4_out="$(printf '%s' "$_rs_b4_payload" \
  | CLAUDE_PROJECT_DIR="$_rs_proj" \
    MCL_STATE_DIR="$_rs_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null)"
if [ -z "$_rs_b4_out" ] || ! printf '%s' "$_rs_b4_out" | grep -q '"permissionDecision": "deny"'; then
  PASS=$((PASS+1))
  printf '  PASS: [Bug 4] Read of project .mcl/state.json allowed at phase=1\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [Bug 4] Read of project .mcl/state.json blocked (regression)\n'
  printf '        output: %s\n' "$(printf '%s' "$_rs_b4_out" | head -c 250)"
fi

# ---- Acceptance (10.0.6 update): Phase 1 Write stays blocked ----
# Plain-text approval no longer transitions Phase 1 → 2. State remains
# phase=1, so Write stays blocked until the model re-emits the summary
# via AskUserQuestion and the developer's tool_result lands.
mkdir -p "$_rs_proj/src/components"
_rs_w_payload="$(python3 -c "
import json
print(json.dumps({
    'tool_name':'Write',
    'tool_input':{'file_path':'$_rs_proj/src/components/Header.tsx',
                  'content':'export const Header = () => <h1>Hi</h1>;'},
    'session_id':'rs5',
    'cwd':'$_rs_proj'
}))")"
_rs_w_out="$(printf '%s' "$_rs_w_payload" \
  | CLAUDE_PROJECT_DIR="$_rs_proj" \
    MCL_STATE_DIR="$_rs_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-pre-tool.sh" 2>/dev/null)"
if printf '%s' "$_rs_w_out" | grep -q '"permissionDecision": "deny"'; then
  PASS=$((PASS+1))
  printf '  PASS: [Acceptance] Phase 1 Write stays blocked (askq required for transition)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [Acceptance] Phase 1 Write allowed without AskUserQuestion (regression)\n'
  printf '        output: %s\n' "$(printf '%s' "$_rs_w_out" | head -c 250)"
fi

cleanup_test_dir "$_rs_proj"
