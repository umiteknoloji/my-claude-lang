#!/bin/bash
# Test: partial-spec detection is gated on spec_approved=false (9.1.2).
#
# Real-session bug: model emitted a short ad-hoc spec in Phase 4
# prose (Project + Pages + Stack notes) AFTER the actual spec was
# already approved and Phase 4 work had succeeded. mcl-stop.sh
# partial-spec detector matched the short prose, treated it as a
# truncated spec, and emitted "MCL SPEC RECOVERY" — a confusing
# error block AT THE END of a successful session.
#
# Fix: guard the partial-spec branch with spec_approved=false.
# Once the developer has approved a spec, the recovery path retires;
# any subsequent assistant text containing a `📋 Spec:` line (or
# a quoted snippet, or freeform Phase 4 notes that the scanner
# misreads) is left alone.

echo "--- test-partial-spec-post-approval ---"

_psp_proj="$(setup_test_dir)"
_psp_state="$_psp_proj/.mcl/state.json"
mkdir -p "$_psp_proj/.mcl"

export PSP_STATE="$_psp_state"

# Plant: spec_approved=true + current_phase=4 (post-approval, mid-
# Phase-4-work). spec_hash present (the approved spec's hash).
python3 - <<'PY'
import json, os, time
o = {
    "schema_version": 2,
    "current_phase": 4,
    "phase_name": "EXECUTE",
    "spec_approved": True,
    "spec_hash": "deadbeefcafef00d1234567890abcdef",
    "last_update": int(time.time()),
}
open(os.environ["PSP_STATE"], "w").write(json.dumps(o))
PY

# Synthetic transcript: a Phase 4 assistant turn that includes a
# SHORT spec-style block (no 7 required headers). Pre-9.1.2 the
# partial-spec detector reads this and fires recovery. 9.1.2: skip.
_psp_transcript="$_psp_proj/transcript.jsonl"
python3 -c '
import json, sys
out = sys.argv[1]
short_spec = """📋 Spec:

Project: admin panel
Pages: /login, /users, /audit
Stack: React + FastAPI + Postgres
"""
turns = [
    {"type":"user","message":{"role":"user","content":"build it"}},
    {"type":"assistant","message":{"role":"assistant","content":[
        {"type":"text","text": short_spec + "\n\nDevam edip kalan implementasyonu yazıyorum."}
    ]}},
]
with open(out, "w") as f:
    for t in turns:
        f.write(json.dumps(t) + "\n")
' "$_psp_transcript"

_psp_run_stop() {
  printf '%s' "{\"transcript_path\":\"${_psp_transcript}\",\"session_id\":\"psp\",\"cwd\":\"${_psp_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_psp_proj" \
      MCL_STATE_DIR="$_psp_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

# Capture stop hook output and audit-log delta. Tolerate a missing
# audit.log (the wrapper init wasn't run for this synthetic fixture).
_psp_audit_count() {
  if [ -f "$_psp_proj/.mcl/audit.log" ]; then
    awk -F ' \\| ' '$2=="partial-spec" {n++} END{print n+0}' \
      "$_psp_proj/.mcl/audit.log" 2>/dev/null || echo 0
  else
    echo 0
  fi
}
_psp_audit_pre="$(_psp_audit_count)"
_psp_out="$(_psp_run_stop || true)"
_psp_audit_post="$(_psp_audit_count)"

# ---- Test 1: hook output does NOT contain the SPEC RECOVERY block ----
if printf '%s' "$_psp_out" | grep -q "MCL SPEC RECOVERY"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: post-approval partial-spec STILL fired SPEC RECOVERY\n'
else
  PASS=$((PASS+1))
  printf '  PASS: post-approval — no SPEC RECOVERY block emitted\n'
fi

# ---- Test 2: no `partial-spec` audit line was added this run ----
if [ "$_psp_audit_post" = "$_psp_audit_pre" ]; then
  PASS=$((PASS+1))
  printf '  PASS: partial-spec audit count unchanged (detector skipped)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: partial-spec audit grew (%s → %s)\n' "$_psp_audit_pre" "$_psp_audit_post"
fi

# ---- Test 3: state.spec_approved still true; not flipped backward ----
_psp_appr_after="$(python3 -c "import json; print(json.load(open('$_psp_state'))['spec_approved'])")"
assert_equals "spec_approved stays true after post-approval Stop" \
  "$_psp_appr_after" "True"

# ---- Test 4: pre-approval branch still works (regression guard) ----
# Same fixture, but spec_approved=false. Detector must fire and
# emit the SPEC RECOVERY block. This proves the guard is scoped to
# post-approval only — it doesn't kill the legitimate detection.
python3 - <<'PY'
import json, os, time
o = {
    "schema_version": 2,
    "current_phase": 1,
    "phase_name": "COLLECT",
    "spec_approved": False,
    "spec_hash": None,
    "last_update": int(time.time()),
}
open(os.environ["PSP_STATE"], "w").write(json.dumps(o))
PY

_psp_out_pre="$(_psp_run_stop || true)"
if printf '%s' "$_psp_out_pre" | grep -q "MCL SPEC RECOVERY"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-approval — partial-spec detector still fires legitimately\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: pre-approval branch broken (recovery should fire here)\n'
  printf '        output snippet: %s\n' "$(printf '%s' "$_psp_out_pre" | head -c 200)"
fi

cleanup_test_dir "$_psp_proj"
unset PSP_STATE
