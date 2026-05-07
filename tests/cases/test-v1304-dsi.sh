#!/bin/bash
# v13.0.4 — Dynamic Status Injection (DSI) birim testleri.
# Tests hooks/lib/mcl-dsi.sh helper across all 6 gate types + edge cases.

echo "--- test-v1304-dsi ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t1304" > "$_dir/.mcl/trace.log"

_GATE_SPEC="$REPO_ROOT/skills/my-claude-lang/gate-spec.json"
_DSI_LIB="$REPO_ROOT/hooks/lib/mcl-dsi.sh"
[ ! -f "$_GATE_SPEC" ] && { FAIL=$((FAIL+1)); printf '  FAIL: gate-spec.json missing\n'; cleanup_test_dir "$_dir"; return; }
[ ! -f "$_DSI_LIB" ]   && { FAIL=$((FAIL+1)); printf '  FAIL: mcl-dsi.sh missing\n';   cleanup_test_dir "$_dir"; return; }

_render() {
  local phase="$1"
  MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir/.mcl" MCL_LANG="${2:-tr}" \
    bash -c ". $_DSI_LIB; _mcl_dsi_render $phase"
}

_seed() {
  echo "$1" >> "$_dir/.mcl/audit.log"
}

_assert_contains() {
  local label="$1" output="$2" needle="$3"
  if [[ "$output" == *"$needle"* ]]; then
    PASS=$((PASS+1))
    printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: %s\n         expected substring: %s\n         got: %s\n' "$label" "$needle" "$output"
  fi
}

# ════════ Test 1: Empty audit, Aşama 5 → next-audit hint ════════
out="$(_render 5)"
_assert_contains "T1: Aşama 5 empty → 'Pattern Matching' header" "$out" "5 — Pattern Matching"
_assert_contains "T1: Aşama 5 empty → 'asama-5-complete' or 'asama-5-skipped' hint" "$out" "asama-5"

# ════════ Test 2: Single phase, audit present → completed ════════
_seed "2026-05-07T10:00:01Z | asama-5-skipped | model | reason=greenfield"
out="$(_render 5)"
_assert_contains "T2: Aşama 5 skipped → 'Tamamlandı' message" "$out" "Tamamlandı"

# ════════ Test 3: List phase (Aşama 10), K missing → MANDATORY directive ════════
out="$(_render 10)"
_assert_contains "T3: Aşama 10 K missing → MANDATORY 'asama-10-items-declared' directive" "$out" "ZORUNLU"
_assert_contains "T3: Aşama 10 K missing → mentions items-declared audit" "$out" "asama-10-items-declared"

# ════════ Test 4: List phase, K=8, 0 resolved → '0/8, current=#1' ════════
_seed "2026-05-07T10:00:10Z | asama-10-items-declared | model | count=8 h_count=5 m_count=3"
out="$(_render 10)"
_assert_contains "T4: Aşama 10 K=8/0 → '0/8 resolved'" "$out" "0/8 resolved"
_assert_contains "T4: Aşama 10 K=8/0 → current #1" "$out" "#1"
_assert_contains "T4: Aşama 10 K=8/0 → next item-1-resolved" "$out" "asama-10-item-1-resolved"

# ════════ Test 5: List phase, K=8, 4 resolved → '4/8, current=#5' ════════
_seed "2026-05-07T10:00:11Z | asama-10-item-1-resolved | model | decision=apply"
_seed "2026-05-07T10:00:12Z | asama-10-item-2-resolved | model | decision=skip"
_seed "2026-05-07T10:00:13Z | asama-10-item-3-resolved | model | decision=rule"
_seed "2026-05-07T10:00:14Z | asama-10-item-4-resolved | model | decision=apply"
out="$(_render 10)"
_assert_contains "T5: Aşama 10 K=8/4 → '4/8 resolved'" "$out" "4/8 resolved"
_assert_contains "T5: Aşama 10 K=8/4 → '4 pending'" "$out" "4 pending"
_assert_contains "T5: Aşama 10 K=8/4 → current #5" "$out" "#5"
_assert_contains "T5: Aşama 10 K=8/4 → next item-5" "$out" "asama-10-item-5-resolved"

# ════════ Test 6: List phase, K=8, all 8 resolved → completed ════════
for n in 5 6 7 8; do
  _seed "2026-05-07T10:00:2${n}Z | asama-10-item-${n}-resolved | model | decision=apply"
done
out="$(_render 10)"
_assert_contains "T6: Aşama 10 K=8/8 → 'Tamamlandı'" "$out" "Tamamlandı"

# ════════ Test 7: Iterative (Aşama 11), no scan → directive ════════
_dir2="$(setup_test_dir)"
mkdir -p "$_dir2/.mcl"
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t1304b" > "$_dir2/.mcl/trace.log"
_render2() {
  MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir2/.mcl" MCL_LANG=tr \
    bash -c ". $_DSI_LIB; _mcl_dsi_render $1"
}
_seed2() { echo "$1" >> "$_dir2/.mcl/audit.log"; }
out="$(_render2 11)"
_assert_contains "T7: Aşama 11 no scan → 'asama-11-scan' directive" "$out" "asama-11-scan"

# ════════ Test 8: Iterative scan=3 fixed=2 rescan_pending → 'rescan due' ════════
_seed2 "2026-05-07T10:00:30Z | asama-11-scan | model | count=3"
_seed2 "2026-05-07T10:00:31Z | asama-11-issue-1-fixed | model | rule=naming"
_seed2 "2026-05-07T10:00:32Z | asama-11-issue-2-fixed | model | rule=dead-code"
out="$(_render2 11)"
_assert_contains "T8: Aşama 11 scan=3 fixed=2 → next 'asama-11-issue-3-fixed'" "$out" "asama-11-issue-3-fixed"

# ════════ Test 9: Substep (Aşama 9), AC count missing → directive ════════
_dir3="$(setup_test_dir)"
mkdir -p "$_dir3/.mcl"
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t1304c" > "$_dir3/.mcl/trace.log"
_render3() {
  MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir3/.mcl" MCL_LANG=tr \
    bash -c ". $_DSI_LIB; _mcl_dsi_render $1"
}
_seed3() { echo "$1" >> "$_dir3/.mcl/audit.log"; }
_seed3 "2026-05-07T10:00:01Z | asama-4-ac-count | model | must=2 should=1"
out="$(_render3 9)"
_assert_contains "T9: Aşama 9 no triples → AC 1 red-first" "$out" "asama-9-ac-1-red"
_assert_contains "T9: Aşama 9 substep header → 'AC 1/3'" "$out" "AC 1/3"

# ════════ Test 10: Substep, AC1 red+green done → next 'refactor' ════════
_seed3 "2026-05-07T10:00:02Z | asama-9-ac-1-red | model | ac=1"
_seed3 "2026-05-07T10:00:03Z | asama-9-ac-1-green | model | ac=1"
out="$(_render3 9)"
_assert_contains "T10: Aşama 9 AC1 red+green → next 'refactor'" "$out" "asama-9-ac-1-refactor"
_assert_contains "T10: Aşama 9 AC1 red+green → 'red ✓ green ✓ refactor ✗'" "$out" "refactor ✗"

# ════════ Test 11: Self-check (Aşama 22), 20/21 complete → 'Aşama 21 missing' ════════
_dir4="$(setup_test_dir)"
mkdir -p "$_dir4/.mcl"
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t1304d" > "$_dir4/.mcl/trace.log"
_render4() {
  MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir4/.mcl" MCL_LANG=tr \
    bash -c ". $_DSI_LIB; _mcl_dsi_render $1"
}
for n in $(seq 1 20); do
  echo "2026-05-07T10:00:50Z | asama-${n}-complete | stop | gate=passed" >> "$_dir4/.mcl/audit.log"
done
out="$(_render4 22)"
_assert_contains "T11: Aşama 22 20/21 → '20/21 phases verified'" "$out" "20/21"
_assert_contains "T11: Aşama 22 missing → 'deep-dive Aşama 21'" "$out" "Aşama 21"

# ════════ Test 12: Partial spec recovery override ════════
_dir5="$(setup_test_dir)"
mkdir -p "$_dir5/.mcl"
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t1304e" > "$_dir5/.mcl/trace.log"
cat > "$_dir5/.mcl/state.json" <<JSON
{"schema_version":3,"current_phase":4,"partial_spec":true}
JSON
out="$(MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir5/.mcl" MCL_LANG=tr \
  bash -c ". $_DSI_LIB; _mcl_dsi_render 4")"
_assert_contains "T12: partial_spec=true → recovery override" "$out" "PARTIAL SPEC RECOVERY"

# ════════ Test 13: English language → EN labels (fresh dir, K=3/1) ════════
_dir7="$(setup_test_dir)"
mkdir -p "$_dir7/.mcl"
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t1304g" > "$_dir7/.mcl/trace.log"
echo "2026-05-07T10:00:01Z | asama-10-items-declared | model | count=3" > "$_dir7/.mcl/audit.log"
echo "2026-05-07T10:00:02Z | asama-10-item-1-resolved | model | decision=apply" >> "$_dir7/.mcl/audit.log"
out="$(MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir7/.mcl" MCL_LANG=en \
  bash -c ". $_DSI_LIB; _mcl_dsi_render 10")"
_assert_contains "T13: lang=en → 'Currently discussing' label" "$out" "Currently discussing"
_assert_contains "T13: lang=en → '1/3 resolved'" "$out" "1/3 resolved"

# ════════ Test 14: K=8 K extension to K=10 (re-emit) → use last count ════════
_dir6="$(setup_test_dir)"
mkdir -p "$_dir6/.mcl"
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t1304f" > "$_dir6/.mcl/trace.log"
echo "2026-05-07T10:00:01Z | asama-10-items-declared | model | count=8" > "$_dir6/.mcl/audit.log"
echo "2026-05-07T10:00:02Z | asama-10-items-declared | model | count=10" >> "$_dir6/.mcl/audit.log"
out="$(MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir6/.mcl" MCL_LANG=tr \
  bash -c ". $_DSI_LIB; _mcl_dsi_render 10")"
_assert_contains "T14: K extended 8→10 (parse_kv_last) → '0/10 resolved'" "$out" "0/10 resolved"

cleanup_test_dir "$_dir"
cleanup_test_dir "$_dir2"
cleanup_test_dir "$_dir3"
cleanup_test_dir "$_dir4"
cleanup_test_dir "$_dir5"
cleanup_test_dir "$_dir6"
cleanup_test_dir "$_dir7"
