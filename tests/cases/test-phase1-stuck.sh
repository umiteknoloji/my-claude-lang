#!/bin/bash
# Test: Phase 1 stuck advisory + forced AskUserQuestion (since 9.0.0).
#
# mcl-stop.sh increments `phase1_turn_count` once per Stop turn while
# current_phase=1. mcl-activate.sh reads the value on the next
# UserPromptSubmit and surfaces:
#   - count >= 10 (and < 20): PHASE1_STUCK_NOTICE advisory
#   - count >= 20: PHASE1_STUCK_NOTICE forced AskUserQuestion talimatı
#
# Phase >= 2 does NOT trigger the notice regardless of count (counter
# is reset on the 1→2 transition; this test plants a high count and
# Phase 2 to verify the activate hook ignores it).

echo "--- test-phase1-stuck ---"

_p1s_proj="$(setup_test_dir)"
_p1s_state="$_p1s_proj/.mcl/state.json"
mkdir -p "$_p1s_proj/.mcl"

_p1s_init() {
  local phase="$1" count="$2"
  python3 -c "
import json, time
o = {
    'schema_version':2, 'current_phase':$phase,
    'phase_name':'COLLECT' if $phase == 1 else 'SPEC_REVIEW',
    'spec_approved': False if $phase == 1 else True,
    'phase1_turn_count': $count,
    'precision_audit_block_count': 0,
    'last_update':int(time.time()),
}
open('$_p1s_state','w').write(json.dumps(o))
"
}

_p1s_activate() {
  local prompt="$1"
  printf '%s' "{\"prompt\":\"${prompt}\",\"session_id\":\"p1s\",\"cwd\":\"${_p1s_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_p1s_proj" \
      MCL_STATE_DIR="$_p1s_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-activate.sh" 2>/dev/null
}

# ---- Test 1: count=5 (below 10) → no PHASE1_STUCK_NOTICE ----
_p1s_init 1 5
_p1s_out1="$(_p1s_activate "merhaba")"
assert_json_valid "count=5 activate → valid JSON" "$_p1s_out1"
if printf '%s' "$_p1s_out1" | grep -q "phase1-stuck"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: count=5 should NOT inject phase1-stuck notice\n'
else
  PASS=$((PASS+1))
  printf '  PASS: count=5 → no phase1-stuck notice\n'
fi

# ---- Test 2: count=10 → advisory notice ----
_p1s_init 1 10
_p1s_out2="$(_p1s_activate "devam")"
assert_contains "count=10 → phase1-stuck-advisory injected" "$_p1s_out2" "phase1-stuck-advisory"
assert_contains "count=10 → /mcl-restart hint mentioned" "$_p1s_out2" "/mcl-restart"

# ---- Test 3: count=15 (between 10 and 20) → still advisory ----
_p1s_init 1 15
_p1s_out3="$(_p1s_activate "devam")"
assert_contains "count=15 → still advisory" "$_p1s_out3" "phase1-stuck-advisory"

# ---- Test 4: count=20 → forced AskUserQuestion ----
_p1s_init 1 20
_p1s_out4="$(_p1s_activate "devam")"
assert_contains "count=20 → forced-askuq" "$_p1s_out4" "phase1-stuck-forced-askuq"
assert_contains "count=20 → 3-option AskUserQuestion talimatı" "$_p1s_out4" "AskUserQuestion"
assert_contains "count=20 → mentions /mcl-finish" "$_p1s_out4" "/mcl-finish"

# ---- Test 5: count=20 BUT phase=2 → notice NOT injected ----
_p1s_init 2 20
_p1s_out5="$(_p1s_activate "devam")"
if printf '%s' "$_p1s_out5" | grep -q "phase1-stuck"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: phase=2 with high count should NOT inject phase1-stuck\n'
else
  PASS=$((PASS+1))
  printf '  PASS: phase=2 ignores phase1_turn_count\n'
fi

cleanup_test_dir "$_p1s_proj"
