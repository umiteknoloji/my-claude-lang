#!/bin/bash
# Test: full Phase 4 RISK_GATE security gate scan → block path.
#
# Plants an Express-style fixture with a real HIGH-severity finding
# (G01-sql-string-concat) in $CLAUDE_PROJECT_DIR. Drives a Phase 4
# code-write Stop turn. Asserts:
#   1. mcl-security-scan.py finds the HIGH
#   2. Stop hook emits decision:block with `MCL SECURITY` reason
#   3. security-scan-block audit captured
#   4. phase4_security_scan_done STAYS FALSE (gate is sticky on HIGH)
#   5. After fix (rewrite without the SQL concat), gate clears

echo "--- test-security-full-scan-blocks ---"


_sf_proj="$(setup_test_dir)"

_sf_init_phase4() {
  python3 - "$_sf_proj/.mcl/state.json" <<'PY'
import json, sys, time
o = {"schema_version": 3, "current_phase": 4, "phase_name": "RISK_GATE",
     "is_ui_project": False, "design_approved": True,
     "spec_hash": "deadbeefcafef00d",
     "phase4_security_scan_done": False,
     "phase4_db_scan_done": False,
     "phase4_ui_scan_done": False,
     "phase4_ops_scan_done": False,
     "phase4_perf_scan_done": False,
     "last_update": int(time.time())}
open(sys.argv[1], "w").write(json.dumps(o))
PY
}

# Plant Express+auth fixture with a real G01 SQL-concat HIGH finding.
mkdir -p "$_sf_proj/src"
cat > "$_sf_proj/src/users.js" <<'JS'
// Express + raw SQL — typical admin lookup
const express = require("express");
const router = express.Router();

router.get("/users/:id", async (req, res) => {
  // BAD: SQL string concat — G01-sql-string-concat (HIGH)
  const result = await db.query("SELECT * FROM users WHERE id = " + req.params.id);
  res.json(result);
});

module.exports = router;
JS

_sf_init_phase4

# Build transcript with Phase 4 Write tool call (triggers code_written).
_sf_t="$_sf_proj/t.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_sf_t" spec-correct "Users API"
python3 - "$_sf_t" <<'PY'
import json, sys
extra = {"type":"assistant","timestamp":"2026-05-01T00:01:00.000Z",
         "message":{"role":"assistant","content":[
             {"type":"tool_use","id":"toolu_w1","name":"Write",
              "input":{"file_path":"src/users.js","content":"// stub"}}]}}
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(extra) + "\n")
PY

# Sanity check first (before any hook runs / caches): scanner detects HIGH.
# --mode=full produces JSON (--mode=report produces markdown). Ensure
# fresh cache so the scan doesn't skip the file.
rm -f "$_sf_proj/.mcl/security-cache.json"
_sf_direct="$(python3 "$REPO_ROOT/hooks/lib/mcl-security-scan.py" \
  --mode=full --state-dir "$_sf_proj/.mcl" \
  --project-dir "$_sf_proj" --lang en 2>/dev/null \
  | python3 -c 'import json,sys; r=json.loads(sys.stdin.read() or "{}"); print(sum(1 for f in r.get("findings",[]) if f.get("severity")=="HIGH"))' 2>/dev/null)"

if [ "$_sf_direct" -ge 1 ] 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: scanner finds HIGH directly (%s finding(s))\n' "$_sf_direct"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: scanner did not detect SQL concat (got HIGH=%s)\n' "$_sf_direct"
fi

# Drive Stop hook → security gate runs full scan.
rm -f "$_sf_proj/.mcl/security-cache.json"  # ensure fresh scan
_sf_out="$(printf '%s' "{\"transcript_path\":\"${_sf_t}\",\"session_id\":\"sf\",\"cwd\":\"${_sf_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_sf_proj" \
    MCL_STATE_DIR="$_sf_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"

# Hook emits decision:block with security-specific reason.
assert_contains "Stop emits decision:block" "$_sf_out" '"decision": "block"'
assert_contains "block reason mentions MCL SECURITY" "$_sf_out" "MCL SECURITY"
assert_contains "block reason mentions Phase 4 START" "$_sf_out" "Phase 4 START"
assert_contains "block reason cites G01" "$_sf_out" "G01"

if grep -q "security-scan-block" "$_sf_proj/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: security-scan-block audit captured\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: security-scan-block audit missing\n'
fi

# State must NOT mark security scan done — HIGH unresolved keeps gate pending.
_sf_done="$(python3 -c "import json; print(json.load(open('$_sf_proj/.mcl/state.json')).get('phase4_security_scan_done', False))")"
assert_equals "phase4_security_scan_done STAYS False on HIGH" "$_sf_done" "False"

# ---- Recovery: fix the file, re-run, gate should clear (HIGH=0) ----
cat > "$_sf_proj/src/users.js" <<'JS'
// Express + parameterized query
const express = require("express");
const router = express.Router();

router.get("/users/:id", async (req, res) => {
  // GOOD: parameterized query
  const result = await db.query("SELECT * FROM users WHERE id = $1", [req.params.id]);
  res.json(result);
});

module.exports = router;
JS

# Reset scan-done flag and re-drive.
_sf_init_phase4
rm -f "$_sf_proj/.mcl/audit.log"

_sf_out2="$(printf '%s' "{\"transcript_path\":\"${_sf_t}\",\"session_id\":\"sf2\",\"cwd\":\"${_sf_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_sf_proj" \
    MCL_STATE_DIR="$_sf_proj/.mcl" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" 2>/dev/null)"

_sf_done2="$(python3 -c "import json; print(json.load(open('$_sf_proj/.mcl/state.json')).get('phase4_security_scan_done', False))")"
assert_equals "after fix → phase4_security_scan_done=True (HIGH=0)" "$_sf_done2" "True"

# Baseline written via dotted-key (mcl_state_set "phase4_high_baseline.security" 0).
# This stores a flat key in state.json, not a nested dict update — read accordingly.
_sf_baseline="$(python3 -c "import json; d=json.load(open('$_sf_proj/.mcl/state.json')); print(d.get('phase4_high_baseline.security','MISSING'))")"
assert_equals "after fix → security baseline=0 recorded (flat key)" "$_sf_baseline" "0"

cleanup_test_dir "$_sf_proj"
