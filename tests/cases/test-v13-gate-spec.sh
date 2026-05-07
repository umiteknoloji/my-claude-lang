#!/bin/bash
# v13.0 — Universal gate engine birim testleri
# Tests all 6 gate types: single, section, list, iterative, substep, self-check.

echo "--- test-v13-gate-spec ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

# Session boundary
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t13" > "$_dir/.mcl/trace.log"

# Gate spec'i lokal repo'dan kullan (kurulu plugin yerine)
_GATE_SPEC="$REPO_ROOT/skills/my-claude-lang/gate-spec.json"
[ ! -f "$_GATE_SPEC" ] && { FAIL=$((FAIL+1)); printf '  FAIL: gate-spec.json missing at %s\n' "$_GATE_SPEC"; cleanup_test_dir "$_dir"; return; }

_check() {
  local phase="$1"
  MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir/.mcl" \
    bash -c "source $REPO_ROOT/hooks/lib/mcl-gate.sh; _mcl_gate_check $phase"
}

_seed() {
  echo "$1" >> "$_dir/.mcl/audit.log"
}

# ════════ single-gate ════════
_seed "2026-05-07T10:00:01Z | summary-confirm-approve | model | selected=Onayla"
assert_equals "single (Faz 1): summary-confirm-approve present → complete" "$(_check 1)" "complete"

# Faz 2 — required_audits: asama-2-complete (missing)
assert_equals "single (Faz 2): asama-2-complete missing → incomplete" "$(_check 2)" "incomplete"
_seed "2026-05-07T10:00:02Z | asama-2-complete | stop | selected=Onayla"
assert_equals "single (Faz 2): asama-2-complete present → complete" "$(_check 2)" "complete"

# Faz 2 auto-complete (v13.0.1) — fresh test dir to isolate from above seeds
_dir2="$(setup_test_dir)"
mkdir -p "$_dir2/.mcl"
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t13b" > "$_dir2/.mcl/trace.log"
_check2() {
  MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir2/.mcl" \
    bash -c "source $REPO_ROOT/hooks/lib/mcl-gate.sh; _mcl_gate_check $1"
}
_seed2() {
  echo "$1" >> "$_dir2/.mcl/audit.log"
}

# auto-complete: no gates (all SILENT-ASSUME)
_seed2 "2026-05-07T10:01:00Z | precision-audit | asama2 | core_gates=0 stack_gates=0 assumes=7 skipmarks=0 stack_tags= skipped=false"
assert_equals "Faz 2 auto-complete: core_gates=0 stack_gates=0 → complete" "$(_check2 2)" "complete"

# fresh dir for next case (avoid prior seed)
_dir3="$(setup_test_dir)"
mkdir -p "$_dir3/.mcl"
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t13c" > "$_dir3/.mcl/trace.log"
_check3() {
  MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir3/.mcl" \
    bash -c "source $REPO_ROOT/hooks/lib/mcl-gate.sh; _mcl_gate_check $1"
}
_seed3() {
  echo "$1" >> "$_dir3/.mcl/audit.log"
}
# auto-complete: skipped=true (English session)
_seed3 "2026-05-07T10:01:00Z | precision-audit | asama2 | core_gates=0 stack_gates=0 assumes=0 skipmarks=0 stack_tags= skipped=true"
assert_equals "Faz 2 auto-complete: skipped=true → complete" "$(_check3 2)" "complete"

# negative: gates>0 + no asama-2-complete → STILL incomplete
_dir4="$(setup_test_dir)"
mkdir -p "$_dir4/.mcl"
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t13d" > "$_dir4/.mcl/trace.log"
_check4() {
  MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir4/.mcl" \
    bash -c "source $REPO_ROOT/hooks/lib/mcl-gate.sh; _mcl_gate_check $1"
}
_seed4() {
  echo "$1" >> "$_dir4/.mcl/audit.log"
}
_seed4 "2026-05-07T10:01:00Z | precision-audit | asama2 | core_gates=2 stack_gates=1 assumes=4 skipmarks=0 stack_tags=react-frontend skipped=false"
assert_equals "Faz 2 with gates>0, no asama-2-complete → incomplete" "$(_check4 2)" "incomplete"

cleanup_test_dir "$_dir2"
cleanup_test_dir "$_dir3"
cleanup_test_dir "$_dir4"

# Faz 5 — required_audits_any
assert_equals "single (Faz 5): nothing → incomplete" "$(_check 5)" "incomplete"
_seed "2026-05-07T10:00:03Z | asama-5-skipped | model | reason=greenfield"
assert_equals "single-or-skip (Faz 5): asama-5-skipped present → complete" "$(_check 5)" "complete"

# Faz 6 — single-or-skip (no UI flow)
_seed "2026-05-07T10:00:04Z | asama-6-skipped | model | reason=no-ui-flow"
assert_equals "single-or-skip (Faz 6): asama-6-skipped → complete" "$(_check 6)" "complete"

# ════════ list-gate (Faz 10) ════════
assert_equals "list (Faz 10): no items-declared → incomplete" "$(_check 10)" "incomplete"
_seed "2026-05-07T10:00:10Z | asama-10-items-declared | model | count=3 h_count=2 m_count=1"
assert_equals "list (Faz 10): declared=3 resolved=0 → incomplete" "$(_check 10)" "incomplete"
_seed "2026-05-07T10:00:11Z | asama-10-item-1-resolved | model | decision=apply"
_seed "2026-05-07T10:00:12Z | asama-10-item-2-resolved | model | decision=skip"
assert_equals "list (Faz 10): declared=3 resolved=2 → incomplete" "$(_check 10)" "incomplete"
_seed "2026-05-07T10:00:13Z | asama-10-item-3-resolved | model | decision=rule"
assert_equals "list (Faz 10): declared=3 resolved=3 → complete" "$(_check 10)" "complete"

# ════════ iterative-gate (Faz 11) ════════
assert_equals "iterative (Faz 11): no scan → incomplete" "$(_check 11)" "incomplete"
_seed "2026-05-07T10:00:20Z | asama-11-scan | model | count=2"
_seed "2026-05-07T10:00:21Z | asama-11-issue-1-fixed | model | rule=naming"
_seed "2026-05-07T10:00:22Z | asama-11-issue-2-fixed | model | rule=dead-code"
_seed "2026-05-07T10:00:23Z | asama-11-rescan | model | count=1"
assert_equals "iterative (Faz 11): rescan count=1 → incomplete" "$(_check 11)" "incomplete"
_seed "2026-05-07T10:00:24Z | asama-11-issue-3-fixed | model | rule=validation"
_seed "2026-05-07T10:00:25Z | asama-11-rescan | model | count=0"
assert_equals "iterative (Faz 11): rescan count=0 → complete" "$(_check 11)" "complete"

# ════════ substep-gate (Faz 9) ════════
# AC count source missing
assert_equals "substep (Faz 9): no ac-count → incomplete" "$(_check 9)" "incomplete"
_seed "2026-05-07T10:00:30Z | asama-4-ac-count | model | must=2 should=1"
assert_equals "substep (Faz 9): 0/9 triples → incomplete" "$(_check 9)" "incomplete"
for i in 1 2 3; do
  for tag in red green refactor; do
    _seed "2026-05-07T10:00:3${i}Z | asama-9-ac-${i}-${tag} | model | ac_index=${i}"
  done
done
assert_equals "substep (Faz 9): 9/9 triples (3 AC × 3) → complete" "$(_check 9)" "complete"

# ════════ section-gate (Faz 20) ════════
assert_equals "section (Faz 20): no required sections → incomplete" "$(_check 20)" "incomplete"
_seed "2026-05-07T10:00:40Z | asama-20-complete | model | covered=5"
assert_equals "section (Faz 20): only 1/2 sections → complete (legacy fallback)" "$(_check 20)" "complete"
# Note: legacy fallback (asama-20-complete present) auto-completes; v13 strict mode would need both sections.

# ════════ self-check (Faz 22) ════════
# Tüm 1-21 *-complete'leri seed et (bu test gate engine'in self-check tipini doğrular,
# universal completeness loop'u değil — test izolasyonu için tüm complete'leri elle veriyoruz).
for n in $(seq 1 21); do
  _seed "2026-05-07T10:00:50Z | asama-${n}-complete | stop-auto | gate=passed"
done
assert_equals "self-check (Faz 22): all 21 prior phases complete → complete" "$(_check 22)" "complete"

cleanup_test_dir "$_dir"
