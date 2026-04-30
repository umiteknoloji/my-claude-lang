#!/bin/bash
# Test: 9.1.0 hook-first precision-audit fallback through real mcl-stop.sh.
#
# Pre-9.1.0: spec emitted + summary approved + no skill-prose
# `precision-audit` audit → mcl-stop.sh emits `decision:block`,
# rewinds Phase 1→2, model retries (often loops). 9.1.0: hook
# auto-emits the audit from the spec body's [assumed:] / [unspecified:]
# counts plus stack-detect output, transition is smooth, no block.

echo "--- test-precision-audit-fallback ---"

_paf_proj="$(setup_test_dir)"

# Plant: post-summary-approval state, no spec_hash yet (transition
# fires on the spec-emit Stop). This mirrors the post-AskUserQuestion-
# approve session where the next assistant turn writes the spec.
_paf_state="$_paf_proj/.mcl/state.json"
mkdir -p "$_paf_proj/.mcl"
python3 -c "
import json, time
o = {
    'schema_version': 2,
    'current_phase': 1,
    'phase_name': 'COLLECT',
    'spec_approved': False,
    'spec_hash': None,
    'last_update': int(time.time()),
}
open('$_paf_state','w').write(json.dumps(o))
"

# Synthetic transcript: assistant turn emitting a complete spec block
# with [assumed:] markers for SILENT-ASSUME dimensions and one
# [unspecified:] marker. No precision-audit Bash invocation in the
# transcript (skill prose Bash skipped — the failure mode 9.1.0
# fixes).
_paf_transcript="$_paf_proj/transcript.jsonl"
python3 -c '
import json, sys
out = sys.argv[1]
spec = """📋 Spec:

## Objective
Build admin panel that lists users; only admins can access.

## MUST
- AuthZ check on every endpoint [assumed: middleware-based]
- Audit log entries for state-changing actions [assumed: append-only JSONL]
- Pagination [assumed: 20/page]

## SHOULD
- Index on user.role [assumed: btree]

## Acceptance Criteria
- [ ] non-admin gets 403

## Edge Cases
- empty user list
[unspecified: no SLA stated]

## Technical Approach
- React + FastAPI + Postgres

## Out of Scope
- multi-tenant
"""
with open(out, "w") as f:
    f.write(json.dumps({
        "type":"user",
        "message":{"role":"user","content":"build it"}
    }) + "\n")
    f.write(json.dumps({
        "type":"assistant",
        "message":{"role":"assistant","content":[{"type":"text","text": spec}]}
    }) + "\n")
' "$_paf_transcript"

# Run mcl-stop.sh end-to-end. Pre-9.1.0 expectation: decision:block
# (precision-audit-block fires). 9.1.0 expectation: no block, audit
# auto-emitted by the hook.
_paf_input="$(python3 -c '
import json, sys
print(json.dumps({"transcript_path": sys.argv[1], "session_id": "paf", "cwd": sys.argv[2]}))
' "$_paf_transcript" "$_paf_proj")"

_paf_out="$(printf '%s' "$_paf_input" \
  | CLAUDE_PROJECT_DIR="$_paf_proj" \
    MCL_STATE_DIR="$_paf_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"

# ---- Test 1: hook output is NOT a decision:block JSON ----
# 9.1.0 success case emits no JSON (or a non-block JSON for downstream
# notices). Pre-9.1.0 emitted `{"decision":"block","reason":"⚠️ MCL
# PHASE 1.7 ..."}`. Asserting the absence of that string is the
# transition-smoothness signal.
if printf '%s' "$_paf_out" | grep -q "MCL PHASE 1.7 PRECISION AUDIT (mandatory)"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: hook still emitted precision-audit-block (fallback did not fire)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: no precision-audit-block emitted (transition smooth)\n'
fi

# ---- Test 2: precision-audit audit was auto-emitted by hook ----
_paf_audit="$_paf_proj/.mcl/audit.log"
if grep -q "| precision-audit | mcl-stop |.*source=hook-fallback" "$_paf_audit" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: precision-audit audit emitted with caller=mcl-stop, source=hook-fallback\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: precision-audit hook-fallback audit missing\n'
  grep "precision-audit" "$_paf_audit" 2>/dev/null | head -3 || true
fi

# ---- Test 3: counts derived from spec body ----
# Spec has 4 [assumed:] and 1 [unspecified:]. Audit detail must reflect.
_paf_audit_line="$(grep "precision-audit | mcl-stop" "$_paf_audit" 2>/dev/null | tail -1)"
if printf '%s' "$_paf_audit_line" | grep -q "assumes=4"; then
  PASS=$((PASS+1))
  printf '  PASS: assumes count reflects spec [assumed:] markers\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: assumes count wrong\n'
  printf '        line: %s\n' "$_paf_audit_line"
fi
if printf '%s' "$_paf_audit_line" | grep -q "skipmarks=1"; then
  PASS=$((PASS+1))
  printf '  PASS: skipmarks count reflects [unspecified:] marker\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: skipmarks count wrong\n'
fi

# ---- Test 4: phase1_ops auto-filled with industry defaults ----
_paf_ops_dt="$(python3 -c "
import json
d = json.load(open('$_paf_state'))
o = d.get('phase1_ops') or {}
print(o.get('deployment_target') or '')
" 2>/dev/null)"
assert_equals "phase1_ops.deployment_target=docker-compose (hook default)" \
  "$_paf_ops_dt" "docker-compose"

_paf_ops_obs="$(python3 -c "
import json
d = json.load(open('$_paf_state'))
o = d.get('phase1_ops') or {}
print(o.get('observability_tier') or '')
" 2>/dev/null)"
assert_equals "phase1_ops.observability_tier=basic" "$_paf_ops_obs" "basic"

# ---- Test 5: phase1_perf auto-filled ----
_paf_perf_bt="$(python3 -c "
import json
d = json.load(open('$_paf_state'))
o = d.get('phase1_perf') or {}
print(o.get('budget_tier') or '')
" 2>/dev/null)"
assert_equals "phase1_perf.budget_tier=pragmatic" "$_paf_perf_bt" "pragmatic"

# ---- Test 6: idempotency — second Stop run does not duplicate ----
_paf_pre_count="$(grep -c "| precision-audit |" "$_paf_audit" 2>/dev/null || echo 0)"
printf '%s' "$_paf_input" \
  | CLAUDE_PROJECT_DIR="$_paf_proj" \
    MCL_STATE_DIR="$_paf_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1
_paf_post_count="$(grep -c "| precision-audit |" "$_paf_audit" 2>/dev/null || echo 0)"
# Second run finds audit already present → fallback skips. Count
# stays at _paf_pre_count.
if [ "$_paf_post_count" = "$_paf_pre_count" ]; then
  PASS=$((PASS+1))
  printf '  PASS: idempotent — second Stop run does not re-emit audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: audit count grew on re-run (%d → %d)\n' "$_paf_pre_count" "$_paf_post_count"
fi

cleanup_test_dir "$_paf_proj"
