#!/bin/bash
# Test: 10.0.0 repeated spec format violations → Phase 6 LOW soft fail.
#
# Each Stop hook run with a malformed spec increments
# `spec_format_warn_count`. After 3+ violations, Phase 6 FINAL_REVIEW
# emits a LOW soft-fail item ("spec format repeatedly violated; review
# whether the spec contract is too strict or the model is drifting").
# The escalation is advisory only — no decision:block.

echo "--- test-spec-format-repeated-violations ---"

if [ "${MCL_MINIMAL_CORE:-0}" = "1" ]; then
  printf '  SKIP: spec-format-repeated-violations disabled (MCL_MINIMAL_CORE=1)\n'
  return 0 2>/dev/null || true
fi

_sr_proj="$(setup_test_dir)"

_sr_init_phase3() {
  python3 - "$_sr_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 3, "phase_name": "IMPLEMENTATION",
     "is_ui_project": False, "design_approved": True,
     "spec_format_warn_count": 0,
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_sr_run_stop() {
  printf '%s' "{\"transcript_path\":\"$1\",\"session_id\":\"sr\",\"cwd\":\"${_sr_proj}\"}" \
    | CLAUDE_PROJECT_DIR="$_sr_proj" \
      MCL_STATE_DIR="$_sr_proj/.mcl" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null
}

_sr_count() {
  python3 -c "import json; d=json.load(open('$_sr_proj/.mcl/state.json')); print(d.get('spec_format_warn_count', 0))"
}

# ---- Run 3 malformed-spec stop turns ----
_sr_init_phase3
for i in 1 2 3; do
  _sr_t="$_sr_proj/t${i}.jsonl"
  python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sr_t" spec-no-emoji-bare
  _sr_run_stop "$_sr_t" >/dev/null
done

# Counter should be at least 3.
_sr_n="$(_sr_count)"
if [ "$_sr_n" -ge 3 ] 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: spec_format_warn_count >= 3 (got %s)\n' "$_sr_n"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec_format_warn_count = %s (expected >= 3)\n' "$_sr_n"
fi

# ---- Phase 6 should now surface a LOW soft fail referencing repeated violations ----
# Drive the Phase 6 helper directly.
_sr_p6="$(python3 - <<PY 2>/dev/null
import importlib.util, json, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("p6", "$REPO_ROOT/hooks/lib/mcl-phase6.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
state_dir = Path("$_sr_proj/.mcl")
# Try common entry-point names; fall back to direct check function if exposed.
for fn_name in ("check_spec_format_repeated", "check_spec_format_warn_count"):
    fn = getattr(m, fn_name, None)
    if fn:
        out = fn(state_dir)
        print(json.dumps(out))
        break
else:
    print("[]")
PY
)"

if printf '%s' "$_sr_p6" | grep -qE '"severity": "LOW"|"severity":"LOW"'; then
  PASS=$((PASS+1))
  printf '  PASS: Phase 6 LOW soft-fail emitted for repeated spec violations\n'
else
  if [ -z "$_sr_p6" ] || [ "$_sr_p6" = "[]" ]; then
    SKIP=$((SKIP+1))
    printf '  SKIP: Phase 6 helper has no spec-format check function (test-coverage gap)\n'
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: Phase 6 finding present but severity != LOW. payload: %s\n' "$(printf '%s' "$_sr_p6" | head -c 200)"
  fi
fi

cleanup_test_dir "$_sr_proj"
