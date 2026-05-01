#!/bin/bash
# Test: When multiple `📋 Spec:` blocks appear in the same transcript,
# the LAST spec-bearing turn wins (canonical behavior since 6.5.5).
# Used for the partial-spec → re-emit recovery flow.

echo "--- test-multi-spec-latest-wins ---"

_ms_proj="$(setup_test_dir)"

_ms_init() {
  python3 - "$_ms_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 1, "phase_name": "INTENT",
     "is_ui_project": False, "design_approved": False,
     "spec_hash": None, "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_ms_run_partial_check() {
  local transcript="$1"
  set +e
  _MS_LAST_OUT="$(bash "$REPO_ROOT/hooks/lib/mcl-partial-spec.sh" check "$transcript" 2>/dev/null)"
  _MS_LAST_RC=$?
  set -e
}

# Build a transcript with TWO spec attempts: first incomplete (rc=0
# territory), second complete. Expectation: scanner uses the LAST text
# containing 📋 Spec: → returns rc=1.
_ms_init
_ms_t="$_ms_proj/t.jsonl"
python3 - "$_ms_t" <<'PY'
import json, sys
out = sys.argv[1]
incomplete_spec = """📋 Spec:
## [Admin Panel]
## Objective
build it
## MUST
- auth
"""
complete_spec = """📋 Spec:

## [Admin Panel]

## Objective
Build admin panel.

## MUST
- Auth required

## SHOULD
- Pagination

## Acceptance Criteria
- [ ] Works

## Edge Cases
- empty list

## Technical Approach
- React + FastAPI

## Out of Scope
- multi-tenant
"""
turns = [
    {"type":"user","timestamp":"2026-05-01T00:00:00.000Z","message":{"role":"user","content":"build it"}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:10.000Z",
     "message":{"role":"assistant","content":[{"type":"text","text":incomplete_spec}]}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:20.000Z",
     "message":{"role":"assistant","content":[{"type":"text","text":"OK, eksik. Re-emit ediyorum."}]}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:30.000Z",
     "message":{"role":"assistant","content":[{"type":"text","text":complete_spec}]}},
]
with open(out, "w") as f:
    for t in turns:
        f.write(json.dumps(t) + "\n")
PY

_ms_run_partial_check "$_ms_t"
assert_equals "multi-spec: latest complete spec wins → rc=1" "$_MS_LAST_RC" "1"

# 10.0.0: spec emit no longer auto-advances. Phase 1 spec-emit is a no-op
# state tag (records hash for reference). State stays at phase=1 until
# summary-confirm askq fires.
_ms_init
printf '%s' "{\"transcript_path\":\"${_ms_t}\",\"session_id\":\"ms\",\"cwd\":\"${_ms_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_ms_proj" \
    MCL_STATE_DIR="$_ms_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1

_ms_phase="$(python3 -c "import json; d=json.load(open('$_ms_proj/.mcl/state.json')); print(d.get('current_phase'))")"
assert_equals "multi-spec on Phase 1 → state stays at 1 (10.0.0 no auto-advance)" "$_ms_phase" "1"

# Reverse case: latest spec is INCOMPLETE → block fires.
_ms_init
_ms_t2="$_ms_proj/t2.jsonl"
python3 - "$_ms_t2" <<'PY'
import json, sys
out = sys.argv[1]
complete = """📋 Spec:

## [X]

## Objective
ok

## MUST
- a

## SHOULD
- b

## Acceptance Criteria
- [ ] c

## Edge Cases
- d

## Technical Approach
- e

## Out of Scope
- f
"""
incomplete = """📋 Spec:
## [X]
## Objective
ok
"""
turns = [
    {"type":"user","timestamp":"2026-05-01T00:00:00.000Z","message":{"role":"user","content":"build"}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:10.000Z",
     "message":{"role":"assistant","content":[{"type":"text","text":complete}]}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:20.000Z",
     "message":{"role":"assistant","content":[{"type":"text","text":incomplete}]}},
]
with open(out, "w") as f:
    for t in turns:
        f.write(json.dumps(t) + "\n")
PY
_ms_run_partial_check "$_ms_t2"
assert_equals "multi-spec: latest INCOMPLETE → rc=0 (block, not 1)" "$_MS_LAST_RC" "0"

cleanup_test_dir "$_ms_proj"
