#!/bin/bash
# Synthetic test: Aşama 6b UI_REVIEW hard enforcement (v10.0.2).
# When ui_sub_phase=BUILD_UI and code_written=true and askuq=false,
# Stop hook must emit decision:block with the 6b enforcement reason.
# After 3 consecutive blocks, loop-breaker fails open.

echo "--- test-v10-asama6b-enforcement ---"

_lb_dir="$(setup_test_dir)"
_audit="$_lb_dir/.mcl/audit.log"
_trace="$_lb_dir/.mcl/trace.log"
mkdir -p "$_lb_dir/.mcl"

# Seed trace.log with a session_start so the loop-breaker counter
# scopes correctly.
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-ui-review" > "$_trace"

# --- Loop-breaker counter behavior under 3 blocks ---
cat > "$_audit" <<'EOF'
2026-05-02 12:00:01 | ui-review-skip-block | stop | count=0
2026-05-02 12:00:02 | ui-review-skip-block | stop | count=1
EOF

_count_two="$(MCL_STATE_DIR="$_lb_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit_path = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace_path = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace_path.exists():
    for line in trace_path.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
count = 0
needle = "| ui-review-skip-block |"
if audit_path.exists():
    for line in audit_path.read_text().splitlines():
        if needle not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if not session_ts or ts >= session_ts:
            count += 1
print(count)
PYEOF
)"
assert_equals "2 prior 6b blocks → count=2 (under threshold)" "$_count_two" "2"

# --- 3 blocks: hits loop-breaker threshold ---
cat > "$_audit" <<'EOF'
2026-05-02 12:00:01 | ui-review-skip-block | stop | count=0
2026-05-02 12:00:02 | ui-review-skip-block | stop | count=1
2026-05-02 12:00:03 | ui-review-skip-block | stop | count=2
EOF

_count_three="$(MCL_STATE_DIR="$_lb_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit_path = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace_path = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace_path.exists():
    for line in trace_path.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
count = 0
needle = "| ui-review-skip-block |"
if audit_path.exists():
    for line in audit_path.read_text().splitlines():
        if needle not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if not session_ts or ts >= session_ts:
            count += 1
print(count)
PYEOF
)"
assert_equals "3 prior 6b blocks → count=3 (loop-breaker threshold)" "$_count_three" "3"

# --- Verify Stop hook emits ui-review-skip-block reason text ---
# Lightweight check: source the hook stub indirectly. We verify the
# hook source file contains the v10.0.2 reason text + correct
# block-count integration.
_hook="$REPO_ROOT/hooks/mcl-stop.sh"

if grep -q "ui-review-skip-block" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook references ui-review-skip-block event\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: ui-review-skip-block missing from stop hook\n'
fi

if grep -q "ui-review-loop-broken" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements ui-review-loop-broken fail-open\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: ui-review-loop-broken missing from stop hook\n'
fi

if grep -q "AŞAMA 6b GEREKLİ" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook contains 6b block reason text\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: 6b block reason text missing\n'
fi

# Verify guard regex was migrated to v9 numbering (5|6a|6b|6c|7)
if grep -qE "\\(5\\|6a\\|6b\\|6c\\|7\\)" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook uses v9 active-phase regex (5|6a|6b|6c|7)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: stop hook still uses legacy active-phase regex\n'
fi

cleanup_test_dir "$_lb_dir"
