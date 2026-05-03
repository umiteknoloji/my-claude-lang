#!/bin/bash
# Synthetic test: v10.1.11 — two real-world bug fixes from the grom
# backoffice case study:
#   1. Aşama 9 auto-complete in Stop hook when all 8 sub-step audits
#      present but model forgot the asama-9-complete summary emit.
#   2. UI autodetect heuristic extension for raw HTML/JS frontends
#      (public/, views/*.ejs, etc.) — catches Express/EJS, Flask,
#      Go-with-static patterns the framework-marker checks missed.
#   3. UI re-evaluation in post-tool — bumps ui_flow_active=true when
#      a UI-pattern file is written mid-session even though autodetect
#      correctly returned false at session_start (empty project).

echo "--- test-v10-1-11-asama9-and-ui-fixes ---"

_dir="$(setup_test_dir)"
_stack_lib="$REPO_ROOT/hooks/lib/mcl-stack-detect.sh"

# === Part 1: Aşama 9 auto-complete logic ===

mkdir -p "$_dir/.mcl"
# Use a fixed past date so audit entries (also fixed past) are not
# filtered out as pre-session.
echo "2020-01-01 00:00:00 | session_start | mcl-activate.sh | t10-1-11-a9" > "$_dir/.mcl/trace.log"

# Case 1A: All 8 sub-step audits present, no asama-9-complete → auto-fire condition
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-03 09:33:46 | asama-9-1-end | asama9 | findings=4 fixed=4
2026-05-03 09:33:46 | asama-9-2-end | asama9 | findings=0
2026-05-03 09:33:46 | asama-9-3-end | asama9 | findings=0
2026-05-03 09:33:46 | asama-9-4-end | asama9 | findings=0
2026-05-03 09:33:46 | asama-9-5-not-applicable | asama9 | reason=tests-out-of-scope
2026-05-03 09:33:46 | asama-9-6-not-applicable | asama9 | reason=tests-out-of-scope
2026-05-03 09:33:46 | asama-9-7-not-applicable | asama9 | reason=tests-out-of-scope
2026-05-03 09:33:46 | asama-9-8-not-applicable | asama9 | reason=tests-out-of-scope
EOF

_a9_result="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
done = {n: False for n in range(1, 9)}
if audit.exists():
    for line in audit.read_text().splitlines():
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        for n in range(1, 9):
            if (f"| asama-9-{n}-end |" in line or
                f"| asama-9-{n}-not-applicable |" in line):
                done[n] = True
all_done = all(done.values())
done_count = sum(1 for v in done.values() if v)
print(f"{done_count}|{1 if all_done else 0}")
PYEOF
)"
assert_equals "all 8 sub-steps audited (4 end + 4 not-applicable) → 8|1" "$_a9_result" "8|1"

# Case 1B: Only 6 sub-steps audited → auto-fire should NOT trigger
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-03 09:33:46 | asama-9-1-end | asama9 | findings=0
2026-05-03 09:33:46 | asama-9-2-end | asama9 | findings=0
2026-05-03 09:33:46 | asama-9-3-end | asama9 | findings=0
2026-05-03 09:33:46 | asama-9-4-end | asama9 | findings=0
2026-05-03 09:33:46 | asama-9-5-end | asama9 | findings=0
2026-05-03 09:33:46 | asama-9-6-end | asama9 | findings=0
EOF

_a9_partial="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
done = {n: False for n in range(1, 9)}
if audit.exists():
    for line in audit.read_text().splitlines():
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        for n in range(1, 9):
            if (f"| asama-9-{n}-end |" in line or
                f"| asama-9-{n}-not-applicable |" in line):
                done[n] = True
all_done = all(done.values())
done_count = sum(1 for v in done.values() if v)
print(f"{done_count}|{1 if all_done else 0}")
PYEOF
)"
assert_equals "only 6 sub-steps audited → 6|0 (no auto-fire)" "$_a9_partial" "6|0"

# Hook contract: stop hook implements helper + audit emits asama-9-complete with mcl-stop-auto caller
_stop="$REPO_ROOT/hooks/mcl-stop.sh"
if grep -q "_mcl_asama_9_substeps_complete" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements _mcl_asama_9_substeps_complete helper\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: helper missing\n'
fi
if grep -q 'mcl_audit_log "asama-9-complete" "mcl-stop-auto"' "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook emits asama-9-complete with mcl-stop-auto caller on auto-fire\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: auto-emit instruction missing or wrong caller\n'
fi

# === Part 2: UI autodetect heuristic extension ===

# Case 2A: views/ with *.ejs → ui-capable=true
_ui1="$_dir/ui1"
mkdir -p "$_ui1/views"
echo "<html><body><%= title %></body></html>" > "$_ui1/views/index.ejs"
_v2a="$(bash "$_stack_lib" ui-capable "$_ui1" 2>/dev/null)"
assert_equals "views/*.ejs → ui-capable=true" "$_v2a" "true"

# Case 2B: public/ with .html .css .js → ui-capable=true
_ui2="$_dir/ui2"
mkdir -p "$_ui2/public/js" "$_ui2/public/css"
echo "console.log(1)" > "$_ui2/public/js/app.js"
echo "body{}" > "$_ui2/public/css/style.css"
_v2b="$(bash "$_stack_lib" ui-capable "$_ui2" 2>/dev/null)"
assert_equals "public/{js,css} → ui-capable=true" "$_v2b" "true"

# Case 2C: empty project → ui-capable=false
_ui3="$_dir/ui3"
mkdir -p "$_ui3"
_v2c="$(bash "$_stack_lib" ui-capable "$_ui3" 2>/dev/null)"
assert_equals "empty project → ui-capable=false" "$_v2c" "false"

# Case 2D: pure backend (server.js + routes/, no public, no views) → ui-capable=false
_ui4="$_dir/ui4"
mkdir -p "$_ui4/routes"
echo "module.exports={}" > "$_ui4/server.js"
echo "module.exports={}" > "$_ui4/routes/api.js"
_v2d="$(bash "$_stack_lib" ui-capable "$_ui4" 2>/dev/null)"
assert_equals "pure backend (no views/public) → ui-capable=false" "$_v2d" "false"

# Case 2E: bare templates/ with *.html → ui-capable=true (final-resort signal)
_ui5="$_dir/ui5"
mkdir -p "$_ui5/templates"
echo "<html></html>" > "$_ui5/templates/page.html"
_v2e="$(bash "$_stack_lib" ui-capable "$_ui5" 2>/dev/null)"
assert_equals "bare templates/*.html → ui-capable=true" "$_v2e" "true"

# === Part 3: UI re-evaluation in post-tool ===

_post="$REPO_ROOT/hooks/mcl-post-tool.sh"
if grep -q "ui-flow-reevaluated" "$_post"; then
  PASS=$((PASS+1))
  printf '  PASS: post-tool emits ui-flow-reevaluated audit on UI write\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: ui-flow-reevaluated audit missing from post-tool\n'
fi

# Real integration: ui_flow_active=false, write public/js/x.js → re-evaluation bumps to true
_ui6="$_dir/ui6"
mkdir -p "$_ui6/.mcl"
cat > "$_ui6/.mcl/state.json" <<JSON
{
  "schema_version": 3,
  "current_phase": 7,
  "phase_name": "EXECUTE",
  "spec_approved": true,
  "spec_hash": "abc",
  "plugin_gate_active": false,
  "plugin_gate_missing": [],
  "ui_flow_active": false,
  "ui_sub_phase": null,
  "ui_build_hash": null,
  "ui_reviewed": false,
  "scope_paths": [],
  "pattern_scan_due": false,
  "pattern_files": [],
  "pattern_summary": null,
  "pattern_level": null,
  "pattern_ask_pending": false,
  "precision_audit_done": true,
  "risk_review_state": null,
  "quality_review_state": null,
  "open_severity_count": 0,
  "tdd_compliance_score": null,
  "rollback_sha": null,
  "rollback_notice_shown": false,
  "tdd_last_green": null,
  "last_write_ts": null,
  "plan_critique_done": false,
  "restart_turn_ts": null,
  "last_update": 1777747000,
  "partial_spec": false,
  "partial_spec_body_sha": null
}
JSON
echo "$(date '+%Y-%m-%d %H:%M:%S') | session_start | mcl-activate.sh | t10-1-11-uire" > "$_ui6/.mcl/trace.log"
: > "$_ui6/.mcl/audit.log"

# Simulate post-tool with a Write to public/js/app.js
_post_input='{"tool_name":"Write","tool_input":{"file_path":"/proj/public/js/app.js","content":"x"},"tool_response":""}'
echo "$_post_input" | \
  MCL_STATE_DIR="$_ui6/.mcl" \
  MCL_STATE_FILE="$_ui6/.mcl/state.json" \
  CLAUDE_PROJECT_DIR="$_ui6" \
  MCL_REPO_PATH="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/mcl-post-tool.sh" >/dev/null 2>&1 || true

_ui_after="$(python3 -c "import json; print(str(json.load(open('$_ui6/.mcl/state.json'))['ui_flow_active']).lower())" 2>/dev/null)"
assert_equals "post-tool re-eval — Write to public/js/*.js → ui_flow_active=true" "$_ui_after" "true"

if grep -q "ui-flow-reevaluated" "$_ui6/.mcl/audit.log" 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: post-tool emitted ui-flow-reevaluated audit on real run\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: ui-flow-reevaluated audit missing after real run\n'
fi

cleanup_test_dir "$_dir"
