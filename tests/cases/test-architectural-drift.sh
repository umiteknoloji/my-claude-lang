#!/bin/bash
# Test: 10.0.0 architectural drift detection (Phase 4 RISK_GATE).
#
# When the project declared scope_paths in Technical Approach (e.g.
# "src/components/**", "src/pages/**") and Phase 1 intent was
# "frontend dashboard, no DB", a Write to a different layer
# (e.g. `prisma/schema.prisma`) should produce a drift finding with
# severity matching the scope mismatch — typically MEDIUM, escalating
# to HIGH for cross-stack mismatches (frontend project writing DB).
# Stack-agnostic — works for any language.

echo "--- test-architectural-drift ---"


_ad_proj="$(setup_test_dir)"

_ad_init() {
  python3 - "$_ad_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 4, "phase_name": "RISK_GATE",
     "is_ui_project": True, "design_approved": True,
     "spec_hash": "deadbeefcafef00d",
     "phase1_intent": "frontend dashboard, no DB",
     "phase1_constraints": "React + Tailwind, static, no backend",
     "scope_paths": ["src/components/**", "src/pages/**"],
     "phase4_security_scan_done": False,
     "phase4_db_scan_done": False,
     "phase4_ui_scan_done": False,
     "phase4_ops_scan_done": False,
     "phase4_perf_scan_done": False,
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

_ad_init

# Plant a real Prisma schema file (different layer = drift).
mkdir -p "$_ad_proj/prisma"
cat > "$_ad_proj/prisma/schema.prisma" <<'PRISMA'
datasource db { provider = "postgresql" url = env("DATABASE_URL") }
generator client { provider = "prisma-client-js" }
model User { id Int @id }
PRISMA

# Build transcript with Write to prisma/schema.prisma — outside scope_paths.
_ad_t="$_ad_proj/t.jsonl"
python3 - "$_ad_t" <<'PY'
import json, sys
out = sys.argv[1]
spec = """📋 Spec:

## [Frontend Dashboard]

## Objective
Build static dashboard, no DB.

## MUST
- React + Tailwind

## SHOULD
- responsive

## Acceptance Criteria
- [ ] renders

## Edge Cases
- empty list

## Technical Approach
- src/components/**, src/pages/**

## Out of Scope
- backend, DB, auth
"""
turns = [
    {"type":"user","timestamp":"2026-05-01T00:00:00.000Z",
     "message":{"role":"user","content":"build dashboard"}},
    {"type":"assistant","timestamp":"2026-05-01T00:00:30.000Z",
     "message":{"role":"assistant","content":[{"type":"text","text":spec}]}},
    {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
     "message":{"role":"assistant","content":[
         {"type":"tool_use","id":"toolu_w","name":"Write",
          "input":{"file_path":"prisma/schema.prisma","content":"model User {}"}}]}},
]
with open(out,"w") as f:
    for t in turns: f.write(json.dumps(t)+"\n")
PY

# Run drift scanner directly.
_ad_drift="$(python3 "$REPO_ROOT/hooks/lib/mcl-drift-scan.py" \
  --state-dir "$_ad_proj/.mcl" \
  --project-dir "$_ad_proj" \
  --transcript "$_ad_t" 2>/dev/null)"

_ad_count="$(printf '%s' "$_ad_drift" | python3 -c \
  'import json,sys; r=json.loads(sys.stdin.read() or "{}"); print(len(r.get("drift_findings",[])))' 2>/dev/null)"
_ad_max_sev="$(printf '%s' "$_ad_drift" | python3 -c \
  'import json,sys
r=json.loads(sys.stdin.read() or "{}")
sevs=[f.get("severity","") for f in r.get("drift_findings",[])]
order={"HIGH":3,"MEDIUM":2,"LOW":1}
print(max(sevs, key=lambda s: order.get(s,0)) if sevs else "NONE")' 2>/dev/null)"

if [ "$_ad_count" -ge 1 ] 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: drift detected (%s finding(s), max severity=%s)\n' "$_ad_count" "$_ad_max_sev"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: drift not detected. output: %s\n' "$(printf '%s' "$_ad_drift" | head -c 250)"
fi

# Severity must be MEDIUM or HIGH (frontend → DB layer mismatch).
case "$_ad_max_sev" in
  HIGH|MEDIUM)
    PASS=$((PASS+1))
    printf '  PASS: drift severity is MEDIUM or HIGH (cross-layer mismatch)\n'
    ;;
  *)
    FAIL=$((FAIL+1))
    printf '  FAIL: drift severity %s, expected MEDIUM or HIGH\n' "$_ad_max_sev"
    ;;
esac

# Run stop hook → drift audit captured.
printf '%s' "{\"transcript_path\":\"${_ad_t}\",\"session_id\":\"ad\",\"cwd\":\"${_ad_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_ad_proj" \
    MCL_STATE_DIR="$_ad_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1

if grep -qE "phase4-drift|drift-finding" "$_ad_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: drift audit captured by stop hook\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: drift audit missing from stop hook run\n'
fi

cleanup_test_dir "$_ad_proj"
