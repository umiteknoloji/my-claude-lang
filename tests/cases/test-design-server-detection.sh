#!/bin/bash
# Test: 10.0.0 Phase 2 DESIGN_REVIEW dev server detection.
#
# When in Phase 2 DESIGN_REVIEW with is_ui_project=true and the
# transcript shows: a dev-server-started audit pattern, a localhost
# URL in the last assistant turn, AND ≥3 frontend project files
# written, the Stop hook must inject guidance directing the model to
# call AskUserQuestion now (the design askq).

echo "--- test-design-server-detection ---"

if [ "${MCL_MINIMAL_CORE:-0}" = "1" ]; then
  printf '  SKIP: design-server-detection disabled (MCL_MINIMAL_CORE=1)\n'
  return 0 2>/dev/null || true
fi

_dsd_proj="$(setup_test_dir)"

_dsd_init() {
  python3 - "$_dsd_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 2, "phase_name": "DESIGN_REVIEW",
     "is_ui_project": True, "design_approved": False,
     "spec_hash": "deadbeefcafef00d",
     "dev_server": {"active": True, "url": "http://localhost:5173"},
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

# Plant dev-server-started audit (some hooks read it for signals).
_dsd_seed_audit() {
  mkdir -p "$_dsd_proj/.mcl"
  cat >> "$_dsd_proj/.mcl/audit.log" <<'AUDIT'
2026-05-01 00:00:00 | session_start | mcl-activate | new
2026-05-01 00:00:05 | dev-server-started | mcl-stop | url=http://localhost:5173 port=5173
AUDIT
}

_dsd_init
_dsd_seed_audit

# Transcript: ≥3 project file writes + last turn contains localhost URL.
_dsd_t="$_dsd_proj/t.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_dsd_t" design-skeleton-emit \
  "src/components/UserList.tsx,src/pages/Index.tsx,src/components/Header.tsx,package.json"

_dsd_out="$(printf '%s' "{\"transcript_path\":\"${_dsd_t}\",\"session_id\":\"dsd\",\"cwd\":\"${_dsd_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_dsd_proj" \
    MCL_STATE_DIR="$_dsd_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"

# Hook should inject guidance about calling AskUserQuestion now.
if printf '%s' "$_dsd_out" | grep -qE "AskUserQuestion|Tasarımı onaylıyor musun|Approve this design"; then
  PASS=$((PASS+1))
  printf '  PASS: design askq guidance injected (AskUserQuestion mention present)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: design askq guidance not injected\n'
  printf '        output preview: %s\n' "$(printf '%s' "$_dsd_out" | head -c 300)"
fi

# decision:block expected (design_approved still false, skeleton + URL emitted).
assert_contains "design server + skeleton + no askq → decision:block" "$_dsd_out" '"decision": "block"'

# Audit captures the trigger.
if grep -qE "design-review-gate-block|design-askq-trigger|design-server-detected" "$_dsd_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: design-server detection audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: design-server detection audit missing\n'
fi

cleanup_test_dir "$_dsd_proj"
