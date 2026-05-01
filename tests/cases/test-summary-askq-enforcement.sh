#!/bin/bash
# Test: 10.0.6 Phase 1 summary AskUserQuestion enforcement.
#
# 10.0.3 plain-text approve fallback removed. Phase 1 → 2/3 transition
# now requires a real AskUserQuestion(summary-confirm) tool call. When
# the assistant emits a Phase 1 summary marker but skips AskUserQuestion,
# the Stop hook sets state.summary_askq_skipped=true so the next
# UserPromptSubmit injects an enforcement message.
#
# Acceptance:
#   1. Phase 1 + summary marker + no askq + plain "doğru"
#      → state.summary_askq_skipped=true + audit summary-askq-skipped
#      → state.current_phase stays 1 (no transition).
#   2. Phase 1 + assistant text WITHOUT summary marker + plain "evet"
#      → flag NOT set, no audit. (False-positive guard.)
#   3. Phase 2 + summary marker + plain "doğru"
#      → flag NOT set. (Enforcement is Phase 1 scoped.)
#   4. Plain "evet" with summary marker (a token that WAS accepted by
#      the old fallback) → flag IS set, no transition.
#      Confirms the fallback is fully gone — even formerly-whitelisted
#      tokens require AskUserQuestion now.

echo "--- test-summary-askq-enforcement ---"

_sa_make_transcript() {
  local path="$1"
  local last_assistant="$2"
  local last_user="$3"
  python3 - "$path" "$last_assistant" "$last_user" <<'PY'
import json, sys
path, last_assistant, last_user = sys.argv[1], sys.argv[2], sys.argv[3]
turns = [
    {"type":"user","timestamp":"2026-05-01T00:00:00Z",
     "message":{"role":"user","content":"backoffice yap"}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:30Z",
     "message":{"role":"assistant","content":[{"type":"text","text": last_assistant}]}},
    {"type":"user","timestamp":"2026-05-01T00:00:45Z",
     "message":{"role":"user","content": last_user}},
]
with open(path, "w") as fh:
    for t in turns:
        fh.write(json.dumps(t) + "\n")
PY
}

_sa_init_state() {
  local state_file="$1"
  local phase="$2"
  python3 - "$state_file" "$phase" <<'PY'
import json, sys, time
o = {
    "schema_version": 3,
    "current_phase": int(sys.argv[2]),
    "phase_name": "DESIGN_REVIEW" if sys.argv[2]=="2" else ("IMPLEMENTATION" if sys.argv[2]=="3" else "INTENT"),
    "is_ui_project": True,
    "design_approved": False,
    "ui_flow_active": False,
    "ui_sub_phase": None,
    "ui_reviewed": False,
    "risk_accepted": False,
    "spec_gate_passed": False,
    "phase4_security_scan_done": False,
    "phase4_db_scan_done": False,
    "phase4_ui_scan_done": False,
    "phase4_ops_scan_done": False,
    "phase6_double_check_done": False,
    "pattern_scan_due": False,
    "phase1_turn_count": 0,
    "summary_askq_skipped": False,
    "spec_hash": None,
    "last_update": int(time.time()),
}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_sa_run_stop() {
  local proj="$1"
  local transcript="$2"
  printf '%s' "{\"transcript_path\":\"${transcript}\",\"session_id\":\"sa\",\"cwd\":\"${proj}\"}" \
    | CLAUDE_PROJECT_DIR="$proj" \
      MCL_STATE_DIR="$proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

_SUMMARY_TEXT='Özet:

**What you want:**
A general backoffice with auth, dashboard, users, items.

**Constraints:**
TypeScript, Postgres, Prisma.

**Success looks like:**
Working CRUD with admin login.'

_NON_SUMMARY_TEXT='Hangi domain için backoffice istiyorsun? (a) e-ticaret (b) saas (c) cms?'

# ============================================================
# Case 1: Phase 1 + summary + no askq + "doğru" → flag set
# ============================================================
_sa_proj1="$(setup_test_dir)"
_sa_init_state "$_sa_proj1/.mcl/state.json" 1
_sa_t1="$_sa_proj1/t1.jsonl"
_sa_make_transcript "$_sa_t1" "$_SUMMARY_TEXT" "doğru"
_sa_run_stop "$_sa_proj1" "$_sa_t1" >/dev/null

_sa_phase1="$(python3 -c "import json; print(json.load(open('$_sa_proj1/.mcl/state.json')).get('current_phase'))")"
_sa_flag1="$(python3 -c "import json; print(json.load(open('$_sa_proj1/.mcl/state.json')).get('summary_askq_skipped'))")"

assert_equals "[1] Phase 1 stays at 1 (no transition on plain-text)" "$_sa_phase1" "1"
assert_equals "[1] summary_askq_skipped flag set true" "$_sa_flag1" "True"

if grep -q "summary-askq-skipped" "$_sa_proj1/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: [1] summary-askq-skipped audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: [1] summary-askq-skipped audit missing\n'
fi

cleanup_test_dir "$_sa_proj1"

# ============================================================
# Case 2: Phase 1 + NO summary marker + "evet" → flag NOT set
# ============================================================
_sa_proj2="$(setup_test_dir)"
_sa_init_state "$_sa_proj2/.mcl/state.json" 1
_sa_t2="$_sa_proj2/t2.jsonl"
_sa_make_transcript "$_sa_t2" "$_NON_SUMMARY_TEXT" "evet"
_sa_run_stop "$_sa_proj2" "$_sa_t2" >/dev/null

_sa_flag2="$(python3 -c "import json; print(json.load(open('$_sa_proj2/.mcl/state.json')).get('summary_askq_skipped'))")"
assert_equals "[2] no summary marker → flag stays false" "$_sa_flag2" "False"

if grep -q "summary-askq-skipped" "$_sa_proj2/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [2] flag fired without summary marker (false-positive)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [2] no summary marker → no enforcement audit\n'
fi

cleanup_test_dir "$_sa_proj2"

# ============================================================
# Case 3: Phase 2 + summary marker → flag NOT set (Phase 1 only)
# ============================================================
_sa_proj3="$(setup_test_dir)"
_sa_init_state "$_sa_proj3/.mcl/state.json" 2
_sa_t3="$_sa_proj3/t3.jsonl"
_sa_make_transcript "$_sa_t3" "$_SUMMARY_TEXT" "doğru"
_sa_run_stop "$_sa_proj3" "$_sa_t3" >/dev/null

_sa_flag3="$(python3 -c "import json; print(json.load(open('$_sa_proj3/.mcl/state.json')).get('summary_askq_skipped'))")"
assert_equals "[3] Phase 2 → enforcement is Phase 1 scoped, flag stays false" "$_sa_flag3" "False"

cleanup_test_dir "$_sa_proj3"

# ============================================================
# Case 4: Phase 1 + summary + "evet" → flag SET (fallback fully gone)
# ============================================================
_sa_proj4="$(setup_test_dir)"
_sa_init_state "$_sa_proj4/.mcl/state.json" 1
_sa_t4="$_sa_proj4/t4.jsonl"
_sa_make_transcript "$_sa_t4" "$_SUMMARY_TEXT" "evet"
_sa_run_stop "$_sa_proj4" "$_sa_t4" >/dev/null

_sa_phase4="$(python3 -c "import json; print(json.load(open('$_sa_proj4/.mcl/state.json')).get('current_phase'))")"
_sa_flag4="$(python3 -c "import json; print(json.load(open('$_sa_proj4/.mcl/state.json')).get('summary_askq_skipped'))")"

assert_equals "[4] Phase 1 stays at 1 (whitelist-token no longer auto-transitions)" "$_sa_phase4" "1"
assert_equals "[4] summary_askq_skipped flag set true" "$_sa_flag4" "True"

if grep -q "plaintext-summary-confirm-detected" "$_sa_proj4/.mcl/audit.log" 2>/dev/null; then
  FAIL=$((FAIL+1))
  printf '  FAIL: [4] removed plaintext fallback still firing\n'
else
  PASS=$((PASS+1))
  printf '  PASS: [4] plaintext-summary-confirm-detected audit absent (fallback removed)\n'
fi

cleanup_test_dir "$_sa_proj4"
