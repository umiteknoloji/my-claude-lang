#!/bin/bash
# Test: 10.0.0 Phase 2 DESIGN_REVIEW askq trigger detection.
#
# When the project is in Phase 2 DESIGN_REVIEW (UI), the model writes
# at least 3 frontend skeleton files, opens a dev server (localhost
# URL appears in the last assistant turn), but does NOT call
# AskUserQuestion — the Stop hook must inject design-askq guidance
# into the next turn (additionalContext or block decision).

echo "--- test-design-review-askq-trigger ---"


_drt_proj="$(setup_test_dir)"

_drt_init() {
  python3 - "$_drt_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 2, "phase_name": "DESIGN_REVIEW",
     "is_ui_project": True, "design_approved": False,
     "spec_hash": "deadbeefcafef00d",
     "dev_server": {"active": True, "url": "http://localhost:5173"},
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

# Plant a dev-server-started audit pattern (some hooks read audit.log
# for dev server signals).
_drt_seed_audit() {
  mkdir -p "$_drt_proj/.mcl"
  cat >> "$_drt_proj/.mcl/audit.log" <<'AUDIT'
2026-05-01 00:00:00 | session_start | mcl-activate | new
2026-05-01 00:00:05 | dev-server-started | mcl-stop | url=http://localhost:5173
AUDIT
}

_drt_init
_drt_seed_audit

# Build transcript: ≥3 frontend Write tool calls + last turn contains
# localhost URL.
_drt_t="$_drt_proj/t.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_drt_t" design-skeleton-emit \
  "src/components/UserList.tsx,src/pages/Index.tsx,src/components/Header.tsx"

_drt_out="$(printf '%s' "{\"transcript_path\":\"${_drt_t}\",\"session_id\":\"drt\",\"cwd\":\"${_drt_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_drt_proj" \
    MCL_STATE_DIR="$_drt_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"

# Hook should inject design-askq guidance (block + askq instruction).
if printf '%s' "$_drt_out" | grep -qE "Tasarımı onaylıyor musun|Approve this design|AskUserQuestion"; then
  PASS=$((PASS+1))
  printf '  PASS: design-askq guidance injected into Stop output\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: design-askq guidance not injected\n'
  printf '        output preview: %s\n' "$(printf '%s' "$_drt_out" | head -c 300)"
fi

# decision:block expected because design_approved=false and frontend
# skeleton was emitted without an askq.
assert_contains "Phase 2 design askq trigger → decision:block" "$_drt_out" '"decision": "block"'

if grep -qE "design-review-gate-block|design-askq-trigger" "$_drt_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: design-review-gate audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: design-review-gate audit missing\n'
fi

cleanup_test_dir "$_drt_proj"
