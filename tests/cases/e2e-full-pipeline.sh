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
  phase_header "1.C — MCL_SKILL_TOKEN path probe (PRE-8.17.0: must still reject)"

  # Pre-8.17.0 the env var has no effect — auth-check ignores it. This
  # probe records the current behavior so 8.17.0 implementation can flip
  # the expectation in a single line and the diff is auditable.
  #
  # Post-8.17.0 expected: with a valid token written to skill-token file
  # and matching env var, the write succeeds and audit shows
  # caller=skill-prose. This probe will then INVERT.

  local audit_log="$E2E_STATE_DIR/audit.log"
  local state_file="$E2E_STATE_DIR/state.json"

  # Pre-create a fake token file (post-8.17.0 helper would do this; we
  # do it manually to probe whether auth-check honors the env var today).
  printf '%s' "deadbeefcafef00d1234567890abcdef" > "$E2E_STATE_DIR/skill-token"
  chmod 600 "$E2E_STATE_DIR/skill-token" 2>/dev/null || true

  local deny_before
  deny_before="$(audit_count "$audit_log" deny-write)"

  MCL_STATE_DIR="$E2E_STATE_DIR" \
  MCL_SKILL_TOKEN="deadbeefcafef00d1234567890abcdef" \
    bash -c '
      source "'"$REPO_ROOT"'/hooks/lib/mcl-state.sh"
      mcl_state_set phase1_intent "with-token-attempt" >/dev/null
    ' 2>/dev/null

  local deny_after
  deny_after="$(audit_count "$audit_log" deny-write)"

  # PRE-8.17.0 expectation: still rejected (token not honored)
  if [ "$deny_after" -gt "$deny_before" ]; then
    PASS=$((PASS+1))
    printf '  PASS: pre-8.17.0 — token-bearing invocation still rejected (auth-check unchanged)\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: token invocation accepted unexpectedly — auth-check already token-aware?\n'
    printf '        before=%d after=%d\n' "$deny_before" "$deny_after"
  fi

  local pi
  pi="$(state_get_field "$state_file" phase1_intent 2>/dev/null)"
  assert_equals "phase1_intent still null (pre-8.17.0 token path inactive)" "$pi" "null"

  rm -f "$E2E_STATE_DIR/skill-token"
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

  printf '\n=== E2E SUMMARY ===\n'
  printf 'Pass:  %d\n' "$PASS"
  printf 'Fail:  %d\n' "$FAIL"
  printf 'Skip:  %d\n' "$SKIP"
  printf '\nPhase coverage so far: 1 of ~9 phases populated.\n'
  printf 'See tests/e2e/manual-checklist.md for model-dependent steps.\n'

  if [ "$FAIL" -gt 0 ]; then
    return 1
  fi
  return 0
}

main "$@"
