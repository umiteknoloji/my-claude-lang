#!/bin/bash
# Test: Phase 6 (a) HIGH soft fail when audit log records `deny-write`
# attempts (since 9.0.0).
#
# `mcl_state_set` rejects unauthorized callers with a `deny-write`
# audit line. Pre-9.0 those lines were forensic-only — Phase 6 didn't
# surface them. 9.0.0 promotes any `deny-write | <caller> | unauthorized`
# occurrence to a HIGH soft fail in `check_state_hack_attempts`, so the
# operator sees the misalignment in the Phase 6 report.

echo "--- test-state-hack-soft-fail ---"

_sh_dir="$(mktemp -d)"
_sh_audit="$_sh_dir/audit.log"

# Helper: invoke the Phase 6 helper directly. It exposes
# check_state_hack_attempts; we test it without needing the full
# Phase 6 pipeline.
_sh_run_check() {
  python3 - <<PY 2>/dev/null
import importlib.util, json, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location(
    "p6", "$REPO_ROOT/hooks/lib/mcl-phase6.py"
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
findings = m.check_state_hack_attempts(Path("$_sh_audit"))
print(json.dumps(findings))
PY
}

# ---- Test 1: empty audit log → no findings ----
: > "$_sh_audit"
_sh_out1="$(_sh_run_check)"
assert_json_valid "empty audit → valid JSON" "$_sh_out1"
assert_equals "empty audit → 0 findings" "$_sh_out1" "[]"

# ---- Test 2: one deny-write entry → HIGH soft fail ----
printf '%s\n' "2026-04-30 12:00:00 | deny-write | bash | unauthorized" >> "$_sh_audit"
_sh_out2="$(_sh_run_check)"
assert_contains "1 deny-write → severity=HIGH" "$_sh_out2" '"severity": "HIGH"'
assert_contains "1 deny-write → rule_id state-hack-attempt" "$_sh_out2" "P6-A-state-hack-attempt"
assert_contains "1 deny-write → message references count" "$_sh_out2" "1 unauthorized state.json write"

# ---- Test 3: multiple deny-write entries → count aggregates ----
printf '%s\n' "2026-04-30 12:00:01 | deny-write | bash | unauthorized" >> "$_sh_audit"
printf '%s\n' "2026-04-30 12:00:02 | deny-write | bash | unauthorized" >> "$_sh_audit"
_sh_out3="$(_sh_run_check)"
assert_contains "3 deny-write → message says 3" "$_sh_out3" "3 unauthorized state.json write"

# ---- Test 4: irrelevant audit lines do NOT trigger the finding ----
printf '%s\n' "2026-04-30 12:00:03 | set | mcl-stop | field=current_phase value=4" > "$_sh_audit"
printf '%s\n' "2026-04-30 12:00:04 | precision-audit | phase1-7 | core_gates=2" >> "$_sh_audit"
_sh_out4="$(_sh_run_check)"
assert_equals "non-deny-write audit → 0 findings" "$_sh_out4" "[]"

# ---- Test 5: deny-write WITHOUT 'unauthorized' qualifier → not counted ----
# (Defensive — only the auth-check rejection path is forensically
# significant; other deny-write reasons are out of scope.)
printf '%s\n' "2026-04-30 12:00:05 | deny-write | bash | other-reason" > "$_sh_audit"
_sh_out5="$(_sh_run_check)"
assert_equals "deny-write w/o unauthorized → 0 findings" "$_sh_out5" "[]"

rm -rf "$_sh_dir"
