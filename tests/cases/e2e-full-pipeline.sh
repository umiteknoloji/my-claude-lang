#!/bin/bash
# MCL End-to-End Pipeline Test (Hybrid)
#
# Strategy: real hooks + real state + real helpers. Steps that depend on
# Claude Code session model behavior (AskUserQuestion turns, skill prose
# Bash actually being called by the model, npm-driven dev server) are
# documented in tests/e2e/manual-checklist.md and are NOT executed here.
#
# This file evolves phase-by-phase, one solid step per turn. Currently:
#
#   Phase 1 — Wrapper init + Phase 1 handoff Bash auth-check measurement
#
# The auth-check measurement is the canonical gate for 8.17.0: it records
# the BASELINE behavior (skill prose `bash -c 'mcl_state_set ...'` is
# rejected by `_mcl_state_auth_check`) so that after the 8.17.0 token
# path lands, the same test inverts a single expectation and proves the
# fix lifted plumbing into a working state.
#
# Run directly:
#   bash tests/cases/e2e-full-pipeline.sh
#
# Not auto-collected by tests/run-tests.sh (no `test-` prefix). E2E is
# kept out of the unit suite because it has different timing and
# external-tool assumptions.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/tests/lib/test-helpers.sh"

PASS=0
FAIL=0
SKIP=0

# Per-phase summary buffers — populated as phases run, printed at end so
# the operator sees a coverage matrix without scrolling.
PHASE_NAMES=()
PHASE_RESULTS=()

phase_header() {
  printf '\n=== E2E PHASE: %s ===\n' "$1"
}

phase_record() {
  PHASE_NAMES+=("$1")
  PHASE_RESULTS+=("$2")
}

# Helper: read one field from a state.json with jq-via-python (no jq dep).
state_get_field() {
  local state_file="$1" field="$2"
  python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get(sys.argv[2])
    print('null' if v is None else json.dumps(v))
except Exception as e:
    print(f'__error__:{e}', file=sys.stderr)
    sys.exit(1)
" "$state_file" "$field"
}

# Helper: count audit.log lines matching an event name.
audit_count() {
  local audit_log="$1" event="$2"
  if [ ! -f "$audit_log" ]; then
    echo 0
    return
  fi
  awk -F ' \\| ' -v ev="$event" '$2 == ev { n++ } END { print n+0 }' "$audit_log"
}

# ---------------------------------------------------------------------
# PHASE 1 — Wrapper init + Phase 1 handoff Bash auth-check measurement
# ---------------------------------------------------------------------

phase_1_wrapper_init() {
  phase_header "1.A — Wrapper init (project dir + state init via real hook)"

  local proj
  proj="$(setup_test_dir)"
  E2E_PROJECT_DIR="$proj"
  E2E_STATE_DIR="$proj/.mcl"

  # Drive mcl-activate.sh as the wrapper would (real UserPromptSubmit
  # input). The hook initializes state.json on first run.
  local out
  out="$(run_activate_hook "$proj" "admin paneli yap, kullanıcıları listele, sadece adminler görsün, audit log tutsun, hızlı olsun")"

  assert_json_valid "wrapper activate → valid JSON" "$out"

  if [ -f "$E2E_STATE_DIR/state.json" ]; then
    PASS=$((PASS+1))
    printf '  PASS: state.json created at %s\n' "$E2E_STATE_DIR/state.json"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: state.json not created — wrapper init incomplete\n'
    printf '        expected: %s\n' "$E2E_STATE_DIR/state.json"
  fi

  # current_phase must be 1 immediately after wrapper init.
  if [ -f "$E2E_STATE_DIR/state.json" ]; then
    local cp
    cp="$(state_get_field "$E2E_STATE_DIR/state.json" current_phase 2>/dev/null)"
    assert_equals "current_phase = 1 after init" "$cp" "1"
  else
    skip_test "current_phase check" "state.json missing"
  fi

  # phase1_intent must be null (untouched by wrapper init).
  if [ -f "$E2E_STATE_DIR/state.json" ]; then
    local pi
    pi="$(state_get_field "$E2E_STATE_DIR/state.json" phase1_intent 2>/dev/null)"
    assert_equals "phase1_intent null after init (no skill prose yet)" "$pi" "null"
  fi
}

phase_1_handoff_authcheck_baseline() {
  phase_header "1.B — Phase 1 handoff Bash auth-check (BASELINE — pre-8.17.0)"

  # Simulate the EXACT invocation skill prose emits today (8.15.0/8.16.0
  # template): bash -c '... source mcl-state.sh; mcl_state_set ...'.
  # Expected baseline: $0=bash → _mcl_state_auth_check returns 1 →
  # mcl_state_set writes "deny-write" to audit.log AND state.json
  # phase1_intent stays null.
  #
  # When 8.17.0 token path lands, this test will be REPEATED with
  # MCL_SKILL_TOKEN set; the expectations invert (auth pass + state
  # populated). Keeping the baseline test live documents the regression
  # surface — if someone deletes the auth check entirely, this test
  # catches it.

  local audit_log="$E2E_STATE_DIR/audit.log"
  local state_file="$E2E_STATE_DIR/state.json"
  local deny_before
  deny_before="$(audit_count "$audit_log" deny-write)"

  # Skill-prose-shaped invocation. Stderr captured to inspect deny msg.
  local skill_stderr
  skill_stderr="$(MCL_STATE_DIR="$E2E_STATE_DIR" bash -c '
    source "'"$REPO_ROOT"'/hooks/lib/mcl-state.sh"
    mcl_state_set phase1_intent "list admins, audit, fast" >/dev/null
    mcl_state_set phase1_constraints "react+fastapi+postgres,auth=admin" >/dev/null
    mcl_state_set phase1_stack_declared "react-frontend,python,db-postgres" >/dev/null
  ' 2>&1 >/dev/null)"

  # ASSERT 1: deny-write audit count incremented
  local deny_after
  deny_after="$(audit_count "$audit_log" deny-write)"
  if [ "$deny_after" -gt "$deny_before" ]; then
    PASS=$((PASS+1))
    printf '  PASS: deny-write audit count incremented (%d → %d) — auth-check engaged\n' \
      "$deny_before" "$deny_after"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: deny-write audit not incremented — auth-check may have allowed write\n'
    printf '        before=%d after=%d\n' "$deny_before" "$deny_after"
    printf '        stderr was: %s\n' "$skill_stderr"
  fi

  # ASSERT 2: stderr mentions unauthorized caller
  if printf '%s' "$skill_stderr" | grep -qF "write denied"; then
    PASS=$((PASS+1))
    printf '  PASS: stderr reports "write denied" — caller surfaced to operator\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: stderr does not contain "write denied"\n'
    printf '        actual stderr: %s\n' "$skill_stderr"
  fi

  # ASSERT 3: state.json field still null — confirms write was rejected
  local pi
  pi="$(state_get_field "$state_file" phase1_intent 2>/dev/null)"
  assert_equals "phase1_intent still null (write rejected)" "$pi" "null"

  local pc
  pc="$(state_get_field "$state_file" phase1_constraints 2>/dev/null)"
  assert_equals "phase1_constraints still null (write rejected)" "$pc" "null"

  local psd
  psd="$(state_get_field "$state_file" phase1_stack_declared 2>/dev/null)"
  # phase1_stack_declared is not in default schema; absent == null
  assert_equals "phase1_stack_declared absent/null (write rejected)" "$psd" "null"

  # ASSERT 4: caller field in audit log shows "bash" (entry $0)
  local last_deny
  last_deny="$(grep "deny-write" "$audit_log" 2>/dev/null | tail -1)"
  if printf '%s' "$last_deny" | awk -F ' \\| ' '{print $3}' | grep -q '^bash$'; then
    PASS=$((PASS+1))
    printf '  PASS: audit caller="bash" — confirms $0 is "bash" in skill-prose invocation\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: audit caller field unexpected\n'
    printf '        last deny line: %s\n' "$last_deny"
  fi
}

phase_1_handoff_token_path_probe() {
  phase_header "1.C — MCL_SKILL_TOKEN path (8.17.0: token authorizes write)"

  # 8.17.0 inverted this test: skill prose Bash now succeeds when the
  # MCL_SKILL_TOKEN env matches the token file written by mcl-activate.sh.
  # Three sub-tests: (1) matching token allows write, (2) wrong token
  # rejects, (3) rotation invalidates the previous token.

  local audit_log="$E2E_STATE_DIR/audit.log"
  local state_file="$E2E_STATE_DIR/state.json"

  # mcl-activate.sh has already rotated a token during 1.A. Read it.
  if [ ! -f "$E2E_STATE_DIR/skill-token" ]; then
    FAIL=$((FAIL+1))
    printf '  FAIL: skill-token file missing after wrapper init — rotation not wired\n'
    return
  fi
  PASS=$((PASS+1))
  printf '  PASS: skill-token file written by mcl-activate.sh (8.17.0 rotation wired)\n'

  local correct_token
  correct_token="$(cat "$E2E_STATE_DIR/skill-token")"

  # (1) Matching token → write succeeds, audit caller=skill-prose
  local set_skill_before
  set_skill_before="$(awk -F ' \\| ' '$2=="set" && $3=="skill-prose"{n++} END{print n+0}' "$audit_log" 2>/dev/null)"
  MCL_STATE_DIR="$E2E_STATE_DIR" \
  MCL_SKILL_TOKEN="$correct_token" \
    bash -c '
      source "'"$REPO_ROOT"'/hooks/lib/mcl-state.sh"
      mcl_state_set phase1_intent "via-correct-token" >/dev/null 2>&1
    ' 2>/dev/null

  local pi
  pi="$(state_get_field "$state_file" phase1_intent 2>/dev/null)"
  assert_equals 'phase1_intent populated via skill-prose token' "$pi" '"via-correct-token"'

  local set_skill_after
  set_skill_after="$(awk -F ' \\| ' '$2=="set" && $3=="skill-prose"{n++} END{print n+0}' "$audit_log" 2>/dev/null)"
  if [ "$set_skill_after" -gt "$set_skill_before" ]; then
    PASS=$((PASS+1))
    printf '  PASS: audit set caller=skill-prose (token path tagged correctly)\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: no `set | skill-prose` audit line emitted (%d → %d)\n' \
      "$set_skill_before" "$set_skill_after"
  fi

  # (2) Wrong token → reject
  local deny_before
  deny_before="$(audit_count "$audit_log" deny-write)"
  MCL_STATE_DIR="$E2E_STATE_DIR" \
  MCL_SKILL_TOKEN="not-the-real-token" \
    bash -c '
      source "'"$REPO_ROOT"'/hooks/lib/mcl-state.sh"
      mcl_state_set phase1_constraints "should-not-stick" >/dev/null
    ' 2>/dev/null
  local deny_after
  deny_after="$(audit_count "$audit_log" deny-write)"
  if [ "$deny_after" -gt "$deny_before" ]; then
    PASS=$((PASS+1))
    printf '  PASS: wrong token → deny-write audit (token verified, not just presence-checked)\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: wrong token did NOT trigger deny-write\n'
  fi
  local pc
  pc="$(state_get_field "$state_file" phase1_constraints 2>/dev/null)"
  assert_equals "phase1_constraints unchanged after wrong-token attempt" "$pc" "null"

  # (3) Rotation: re-run activate; old token must now reject.
  local old_token="$correct_token"
  run_activate_hook "$E2E_PROJECT_DIR" "next turn" >/dev/null
  local new_token
  new_token="$(cat "$E2E_STATE_DIR/skill-token")"
  if [ "$old_token" != "$new_token" ]; then
    PASS=$((PASS+1))
    printf '  PASS: token rotated on next UserPromptSubmit (%s… → %s…)\n' \
      "${old_token:0:8}" "${new_token:0:8}"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: token did not rotate — replay surface still open\n'
  fi

  local deny_before2
  deny_before2="$(audit_count "$audit_log" deny-write)"
  MCL_STATE_DIR="$E2E_STATE_DIR" \
  MCL_SKILL_TOKEN="$old_token" \
    bash -c '
      source "'"$REPO_ROOT"'/hooks/lib/mcl-state.sh"
      mcl_state_set phase1_constraints "via-stale-token" >/dev/null
    ' 2>/dev/null
  local deny_after2
  deny_after2="$(audit_count "$audit_log" deny-write)"
  if [ "$deny_after2" -gt "$deny_before2" ]; then
    PASS=$((PASS+1))
    printf '  PASS: stale (pre-rotation) token → reject (no replay window)\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: stale token accepted — rotation does not invalidate previous turn\n'
  fi
}

# ---------------------------------------------------------------------
# PHASE 14 — Phase 4.5 START sticky-pause + 5 sequential gates
# ---------------------------------------------------------------------
# Two sub-tests:
#   14.A Sticky-pause short-circuits Phase 4.5 START (no gate runs)
#   14.B Each gate's scan helper returns valid JSON with HIGH=0 on a
#        clean project (the "would proceed" baseline for every gate)
#
# Driving the full sequential gate ordering through mcl-stop.sh requires
# a transcript fixture that triggers `code_written=true` from
# mcl-phase-review-guard.py — that's a separate phase. 14.A + 14.B prove
# the two preconditions: pause guard fires before gates; gates' helpers
# emit valid JSON when there is nothing to find.

# Write state.json directly as a test fixture, bypassing mcl_state_set
# auth-check. Justified: the test owns the project dir and is asserting
# downstream HOOK behavior, not exercising the writer.
_e2e_write_state() {
  local state_file="$1" python_payload="$2"
  python3 -c "
import json, sys, time
fp = sys.argv[1]
patch = json.loads(sys.argv[2])
try:
    obj = json.loads(open(fp).read())
except Exception:
    obj = {}
obj.update(patch)
obj['last_update'] = int(time.time())
open(fp, 'w').write(json.dumps(obj, indent=2))
" "$state_file" "$python_payload"
}

phase_14_sticky_pause_blocks_gates() {
  phase_header "14.A — Sticky-pause short-circuits Phase 4.5 START"

  local proj
  proj="$(setup_test_dir)"
  local state_file="$proj/.mcl/state.json"
  local audit_log="$proj/.mcl/audit.log"

  # Initialize state via real wrapper.
  run_activate_hook "$proj" "init" >/dev/null

  # Force pause-on-error active. Real flow would go through mcl_pause_set
  # from a hook context; here we patch state directly so we isolate the
  # sticky-pause CHECK in mcl-stop.sh, not the setter.
  _e2e_write_state "$state_file" '{
    "current_phase": 4,
    "phase_name": "EXECUTE",
    "spec_approved": true,
    "phase_review_state": "pending",
    "paused_on_error": {
      "active": true,
      "reason": "synthetic e2e fixture",
      "ts": 1000
    }
  }'

  # Provide a minimal transcript file. mcl-stop.sh requires
  # transcript_path to exist; even a trivial one-message transcript is
  # enough — sticky-pause check fires before the transcript is read for
  # phase-review purposes.
  local transcript="$proj/transcript.jsonl"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"go"},"timestamp":"2026-04-30T00:00:00Z"}' > "$transcript"

  local pause_before
  pause_before="$(audit_count "$audit_log" pause-sticky-block)"
  local sec_block_before
  sec_block_before="$(audit_count "$audit_log" security-scan-block)"

  # Run mcl-stop.sh end-to-end with the prepared input.
  local stop_input stop_out
  stop_input="$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "e2e", "cwd": sys.argv[2]}))' "$transcript" "$proj")"
  stop_out="$(printf '%s' "$stop_input" \
    | CLAUDE_PROJECT_DIR="$proj" \
      MCL_STATE_DIR="$proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"

  # ASSERT 1: output is valid JSON with decision=block
  assert_json_valid "stop hook → valid JSON under sticky pause" "$stop_out"

  local decision
  decision="$(printf '%s' "$stop_out" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("decision",""))' 2>/dev/null)"
  assert_equals "decision=block under sticky pause" "$decision" "block"

  # ASSERT 2: pause-sticky-block audit incremented
  local pause_after
  pause_after="$(audit_count "$audit_log" pause-sticky-block)"
  if [ "$pause_after" -gt "$pause_before" ]; then
    PASS=$((PASS+1))
    printf '  PASS: pause-sticky-block audit incremented (%d → %d)\n' "$pause_before" "$pause_after"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: pause-sticky-block audit NOT incremented (%d → %d)\n' "$pause_before" "$pause_after"
  fi

  # ASSERT 3: NO security gate ran (sticky-pause must short-circuit BEFORE gates)
  local sec_block_after
  sec_block_after="$(audit_count "$audit_log" security-scan-block)"
  assert_equals "no security-scan-block emitted under pause" "$sec_block_after" "$sec_block_before"

  # ASSERT 4: scan_done flags untouched (gates did not execute)
  local sec_done
  sec_done="$(state_get_field "$state_file" phase4_5_security_scan_done 2>/dev/null)"
  assert_equals "phase4_5_security_scan_done still false (gate did not run)" "$sec_done" "false"

  cleanup_test_dir "$proj"
}

phase_14_gates_helpers_clean_baseline() {
  phase_header "14.B — Five gate scan helpers return HIGH=0 on clean project"

  local proj
  proj="$(setup_test_dir)"

  # Each helper uses --mode=full as mcl-stop.sh does. Empty project →
  # no findings → HIGH=0 → gate would mark scan_done=true and proceed.
  # Security scan invokes semgrep + SCA tooling which is the slow
  # outlier (~10-15s); others are sub-second.
  local g out high schema_ok
  for g in security db ui ops perf; do
    out="$(python3 "$REPO_ROOT/hooks/lib/mcl-${g}-scan.py" \
      --mode=full \
      --state-dir "$proj/.mcl" \
      --project-dir "$proj" \
      --lang tr 2>/dev/null)"

    if printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1; then
      PASS=$((PASS+1))
      printf '  PASS: %s scan → valid JSON\n' "$g"
    else
      FAIL=$((FAIL+1))
      printf '  FAIL: %s scan → invalid JSON\n' "$g"
      printf '        first 200 chars: %s\n' "$(printf '%s' "$out" | head -c 200)"
      continue
    fi

    high="$(printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read() or "{}")
hc = d.get("high_count")
if hc is None:
    hc = sum(1 for f in d.get("findings", []) if f.get("severity") == "HIGH")
print(hc)
' 2>/dev/null)"
    assert_equals "$g scan HIGH=0 on clean project (would set baseline=0)" "$high" "0"

    # Sanity: helper output exposes the shape mcl-stop.sh consumes.
    schema_ok="$(printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read() or "{}")
print("ok" if "findings" in d and isinstance(d["findings"], list) else "bad")
' 2>/dev/null)"
    assert_equals "$g scan exposes findings[] list" "$schema_ok" "ok"
  done

  cleanup_test_dir "$proj"
}

phase_14_sequential_gate_ordering() {
  phase_header "14.C — Sequential gate ordering through real Stop hook"

  # Drive the full mcl-stop.sh Phase 4.5 START enforcement: a clean
  # project + a transcript with an Edit tool_use in the last assistant
  # turn → mcl-phase-review-guard reports code_written=true →
  # phase_review_state transitions to pending → all 5 gates run in order
  # (security → db → ui → ops → perf), each sets scan_done=true and
  # high_baseline.X=0 because the project has no findings.
  #
  # Slowest path in the suite (~12-15s on first run, mostly semgrep);
  # subsequent runs would hit the scan_done short-circuit if state were
  # preserved. We use a fresh project each invocation, so this is the
  # canonical "first Phase 4.5 turn" measurement.

  local proj
  proj="$(setup_test_dir)"
  local state_file="$proj/.mcl/state.json"
  local audit_log="$proj/.mcl/audit.log"

  run_activate_hook "$proj" "init" >/dev/null

  # Phase 4 active, code already approved + executing, no scan done yet.
  # Leave phase_review_state=null so this is the FIRST transition.
  _e2e_write_state "$state_file" '{
    "current_phase": 4,
    "phase_name": "EXECUTE",
    "spec_approved": true,
    "spec_hash": "deadbeef",
    "phase_review_state": null,
    "phase4_5_security_scan_done": false,
    "phase4_5_db_scan_done": false,
    "phase4_5_ui_scan_done": false,
    "phase4_5_ops_scan_done": false,
    "phase4_5_perf_scan_done": false
  }'

  # Transcript fixture: one assistant turn ending with an Edit tool_use.
  # mcl-phase-review-guard.py scans only the LAST assistant turn for
  # tool_use entries — a single message is sufficient.
  local transcript="$proj/transcript.jsonl"
  python3 -c '
import json, sys
out = sys.argv[1]
with open(out, "w") as f:
    f.write(json.dumps({
        "type": "user",
        "message": {"role": "user", "content": "do the thing"},
        "timestamp": "2026-04-30T00:00:00Z"
    }) + "\n")
    f.write(json.dumps({
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [
                {"type": "text", "text": "Adding the change."},
                {"type": "tool_use", "id": "tu_1", "name": "Edit",
                 "input": {"file_path": "/tmp/x.py", "old_string": "a", "new_string": "b"}}
            ]
        },
        "timestamp": "2026-04-30T00:00:01Z"
    }) + "\n")
' "$transcript"

  local pending_before
  pending_before="$(audit_count "$audit_log" phase-review-pending)"
  local sec_block_before
  sec_block_before="$(audit_count "$audit_log" security-scan-block)"

  local stop_input stop_out
  stop_input="$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "e2e", "cwd": sys.argv[2]}))' "$transcript" "$proj")"
  stop_out="$(printf '%s' "$stop_input" \
    | CLAUDE_PROJECT_DIR="$proj" \
      MCL_STATE_DIR="$proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"

  # ASSERT 1: stop hook emitted valid JSON and decision=block
  # (Phase 4.5 START reminder once all 5 gates pass with HIGH=0).
  assert_json_valid "stop hook → valid JSON (Phase 4.5 START)" "$stop_out"

  local decision
  decision="$(printf '%s' "$stop_out" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("decision",""))' 2>/dev/null)"
  assert_equals "decision=block (Phase 4.5 START reminder)" "$decision" "block"

  # ASSERT 2: phase-review-pending audit incremented (transition fired)
  local pending_after
  pending_after="$(audit_count "$audit_log" phase-review-pending)"
  if [ "$pending_after" -gt "$pending_before" ]; then
    PASS=$((PASS+1))
    printf '  PASS: phase-review-pending audit incremented (%d → %d) — code_written detected\n' \
      "$pending_before" "$pending_after"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: phase-review-pending NOT incremented — guard did not see Edit\n'
    printf '        before=%d after=%d\n' "$pending_before" "$pending_after"
  fi

  # ASSERT 3: phase_review_state transitioned to "pending"
  local prs
  prs="$(state_get_field "$state_file" phase_review_state 2>/dev/null)"
  assert_equals 'phase_review_state = "pending" after first Phase 4 stop' "$prs" '"pending"'

  # ASSERT 4: NO security-scan-block (clean project → HIGH=0 path taken)
  local sec_block_after
  sec_block_after="$(audit_count "$audit_log" security-scan-block)"
  assert_equals "no security-scan-block (clean project HIGH=0)" "$sec_block_after" "$sec_block_before"

  # ASSERT 5: all 5 scan_done flags now true (each gate ran and proceeded)
  local g flag
  for g in security db ui ops perf; do
    flag="$(state_get_field "$state_file" "phase4_5_${g}_scan_done" 2>/dev/null)"
    assert_equals "phase4_5_${g}_scan_done = true (gate ran)" "$flag" "true"
  done

  # ASSERT 6: high_baseline.X = 0 for each gate (recorded for Phase 6 (b))
  local baseline
  baseline="$(python3 -c "
import json
d = json.load(open('$state_file'))
hb = d.get('phase4_5_high_baseline', {}) or {}
print(','.join(str(hb.get(k, 'missing')) for k in ['security','db','ui','ops','perf']))
" 2>/dev/null)"
  assert_equals "phase4_5_high_baseline = {sec=0,db=0,ui=0,ops=0,perf=0}" "$baseline" "0,0,0,0,0"

  cleanup_test_dir "$proj"
}

# ---------------------------------------------------------------------
# PHASE 25 — Pause-on-error trigger (mock helper returns broken JSON)
# ---------------------------------------------------------------------
# Drives `mcl-pre-tool.sh` end-to-end with an Edit tool input on a
# Python file (triggers the security-scan incremental path). The trick:
# we run mcl-pre-tool.sh from a MIRROR hooks/ directory in /tmp where
# every lib file is symlinked back to the real repo EXCEPT
# `mcl-security-scan.py`, which is replaced by a stub that emits
# `{"error":"simulated helper failure"}`.
#
# Why mirror not PATH override: mcl-pre-tool.sh resolves the helper
# path from `SCRIPT_DIR` (its own dirname) — it does not consult PATH.
# Mirroring the hooks dir is the lowest-impact way to swap the helper
# while keeping auth-check valid (the auth check whitelists hook entry
# scripts by absolute path; both real and mirror dirs match the pattern
# because BASH_SOURCE of mcl-state.sh resolves to the mirror dir).

_e2e_build_mirror_hooks() {
  # $1 = mirror_dir (will hold mcl-*.sh + lib/)
  # $2 = security_scan_stub_payload (raw stdout the stub will print)
  local mirror="$1" stub_payload="$2"
  mkdir -p "$mirror/lib"

  # Symlink top-level hook entry scripts so $0 resolves into the mirror
  # (auth-check whitelist matches by exact absolute path).
  local f
  for f in "$REPO_ROOT"/hooks/*.sh; do
    ln -s "$f" "$mirror/$(basename "$f")"
  done

  # Symlink every lib file EXCEPT mcl-security-scan.py.
  for f in "$REPO_ROOT"/hooks/lib/*; do
    local bn
    bn="$(basename "$f")"
    if [ "$bn" = "mcl-security-scan.py" ]; then
      continue
    fi
    ln -s "$f" "$mirror/lib/$bn"
  done

  # Drop the stub helper — it must accept the same flags
  # (--mode=incremental --state-dir --project-dir --target --lang) and
  # print the supplied payload.
  # Pass payload as a JSON literal embedded via Python json.dumps so it
  # survives any quoting issues in shell (bash 3.2 has no @Q operator).
  python3 -c '
import json, sys, os
out_path, payload = sys.argv[1], sys.argv[2]
script = (
    "#!/usr/bin/env python3\n"
    "import sys\n"
    "sys.stdout.write(" + json.dumps(payload) + ")\n"
    "sys.stdout.flush()\n"
)
open(out_path, "w").write(script)
os.chmod(out_path, 0o755)
' "$mirror/lib/mcl-security-scan.py" "$stub_payload"
}

phase_25_pause_on_scan_helper_error() {
  phase_header "25 — Pause-on-error: scan helper returns {\"error\": ...}"

  local proj
  proj="$(setup_test_dir)"
  local state_file="$proj/.mcl/state.json"
  local audit_log="$proj/.mcl/audit.log"

  # Real wrapper init.
  run_activate_hook "$proj" "init" >/dev/null

  # Patch state into Phase 4 so the security incremental scan path is
  # active (mcl-pre-tool.sh gates the scan on phase >= 4).
  _e2e_write_state "$state_file" '{
    "current_phase": 4,
    "phase_name": "EXECUTE",
    "spec_approved": true,
    "spec_hash": "deadbeef"
  }'

  # Build mirror hooks dir with stub security-scan.py.
  local mirror="$proj/_mirror_hooks"
  _e2e_build_mirror_hooks "$mirror" '{"error": "simulated helper failure"}'

  # Create the file the Edit tool will target — incremental scan path
  # only fires on existing source files.
  local target_py="$proj/main.py"
  printf '%s\n' "x = 1" > "$target_py"

  # PreToolUse input shape: tool_name + tool_input for an Edit on .py.
  local pre_input
  pre_input="$(python3 -c '
import json, sys
print(json.dumps({
    "tool_name": "Edit",
    "tool_input": {
        "file_path": sys.argv[1],
        "old_string": "x = 1",
        "new_string": "x = 2"
    },
    "session_id": "e2e-25",
    "cwd": sys.argv[2]
}))
' "$target_py" "$proj")"

  local pause_audit_before
  pause_audit_before="$(audit_count "$audit_log" pause-on-error)"
  local pause_active_before
  pause_active_before="$(python3 -c "
import json
d = json.load(open('$state_file'))
p = d.get('paused_on_error') or {}
print('true' if p.get('active') else 'false')
" 2>/dev/null)"

  # Run mirror's mcl-pre-tool.sh — auth check sees entry_abs=$mirror/mcl-pre-tool.sh,
  # hooks_dir=$mirror (BASH_SOURCE of mcl-state.sh symlink resolved to
  # mirror). Match → write allowed → pause set → state.paused_on_error.active=true.
  local pre_out
  pre_out="$(printf '%s' "$pre_input" \
    | CLAUDE_PROJECT_DIR="$proj" \
      MCL_STATE_DIR="$proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$mirror/mcl-pre-tool.sh" 2>/dev/null)"

  # ASSERT 1: pre-tool emitted valid JSON
  assert_json_valid "pre-tool → valid JSON under helper error" "$pre_out"

  # ASSERT 2: permissionDecision = deny (mcl_pause_on_scan_error path)
  local decision
  decision="$(printf '%s' "$pre_out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read() or "{}")
hso = d.get("hookSpecificOutput", {}) or {}
print(hso.get("permissionDecision", ""))
' 2>/dev/null)"
  assert_equals "permissionDecision=deny on helper error" "$decision" "deny"

  # ASSERT 3: pause-on-error audit incremented
  local pause_audit_after
  pause_audit_after="$(audit_count "$audit_log" pause-on-error)"
  if [ "$pause_audit_after" -gt "$pause_audit_before" ]; then
    PASS=$((PASS+1))
    printf '  PASS: pause-on-error audit incremented (%d → %d)\n' \
      "$pause_audit_before" "$pause_audit_after"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: pause-on-error audit NOT incremented (%d → %d)\n' \
      "$pause_audit_before" "$pause_audit_after"
  fi

  # ASSERT 4: state.paused_on_error.active = true (real persistence path)
  local pause_active_after
  pause_active_after="$(python3 -c "
import json
d = json.load(open('$state_file'))
p = d.get('paused_on_error') or {}
print('true' if p.get('active') else 'false')
" 2>/dev/null)"
  assert_equals "paused_on_error.active=true after helper error" "$pause_active_after" "true"

  # ASSERT 5: paused_on_error carries the error_msg from the stub
  local err_msg
  err_msg="$(python3 -c "
import json
d = json.load(open('$state_file'))
p = d.get('paused_on_error') or {}
print(p.get('error_msg', ''))
" 2>/dev/null)"
  if printf '%s' "$err_msg" | grep -qF "simulated helper failure"; then
    PASS=$((PASS+1))
    printf '  PASS: paused_on_error.error_msg propagates stub payload\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: paused_on_error.error_msg missing stub payload (got: %s)\n' "$err_msg"
  fi

  # ASSERT 6: source = "scan-helper" (correct provenance for resume UI)
  local src
  src="$(python3 -c "
import json
d = json.load(open('$state_file'))
p = d.get('paused_on_error') or {}
print(p.get('source', ''))
" 2>/dev/null)"
  assert_equals "paused_on_error.source = scan-helper" "$src" "scan-helper"

  cleanup_test_dir "$proj"
}


# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------

main() {
  printf 'MCL E2E Full Pipeline Test\n'
  printf 'Repo: %s\n' "$REPO_ROOT"
  printf 'Date: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"

  E2E_PROJECT_DIR=""
  E2E_STATE_DIR=""

  phase_1_wrapper_init
  phase_record "Phase 1.A wrapper init" "$( [ "$FAIL" -eq 0 ] && echo PASS || echo PARTIAL )"

  phase_1_handoff_authcheck_baseline
  phase_1_handoff_token_path_probe

  if [ -n "$E2E_PROJECT_DIR" ] && [ -d "$E2E_PROJECT_DIR" ]; then
    cleanup_test_dir "$E2E_PROJECT_DIR"
  fi

  phase_14_sticky_pause_blocks_gates
  phase_14_gates_helpers_clean_baseline
  phase_14_sequential_gate_ordering
  phase_25_pause_on_scan_helper_error

  printf '\n=== E2E SUMMARY ===\n'
  printf 'Pass:  %d\n' "$PASS"
  printf 'Fail:  %d\n' "$FAIL"
  printf 'Skip:  %d\n' "$SKIP"
  printf '\nPhase coverage so far: 1, 14 (partial) of ~9 phases.\n'
  printf 'See tests/e2e/manual-checklist.md for model-dependent steps.\n'

  if [ "$FAIL" -gt 0 ]; then
    return 1
  fi
  return 0
}

main "$@"
