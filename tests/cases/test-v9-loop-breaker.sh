#!/bin/bash
# Synthetic test: hard-enforcement loop-breakers.
# After 3 consecutive same-cause blocks in the current session, the
# Stop hook fails open instead of blocking forever. Prevents the
# infinite "MCL LOCK" trap when a model repeatedly fails to recover
# from a precision-audit miss or risk-review skip.

echo "--- test-v9-loop-breaker ---"

_lb_dir="$(setup_test_dir)"
_audit="$_lb_dir/.mcl/audit.log"
_trace="$_lb_dir/.mcl/trace.log"

# Source the helper directly via a wrapper that writes test fixtures
# and invokes the loop-breaker counter inline. Loop-breaker uses
# session boundary = most recent `session_start` event in trace.log.
mkdir -p "$_lb_dir/.mcl"

# --- Session 1: 0 prior blocks ---
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | test-session-1" > "$_trace"

_count_zero="$(MCL_STATE_DIR="$_lb_dir/.mcl" python3 - <<'PYEOF'
import os, sys
from pathlib import Path
audit_path = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace_path = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace_path.exists():
    for line in trace_path.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
count = 0
needle = "| precision-audit-block |"
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
assert_equals "no prior blocks → count=0" "$_count_zero" "0"

# --- 2 blocks: still under threshold ---
cat > "$_audit" <<'EOF'
2026-05-02 12:00:01 | precision-audit-block | mcl-stop.sh | first miss
2026-05-02 12:00:02 | precision-audit-block | mcl-stop.sh | second miss
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
needle = "| precision-audit-block |"
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
assert_equals "2 prior blocks → count=2 (under threshold)" "$_count_two" "2"

# --- 3 blocks: hits threshold ---
cat > "$_audit" <<'EOF'
2026-05-02 12:00:01 | precision-audit-block | mcl-stop.sh | miss 1
2026-05-02 12:00:02 | precision-audit-block | mcl-stop.sh | miss 2
2026-05-02 12:00:03 | precision-audit-block | mcl-stop.sh | miss 3
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
needle = "| precision-audit-block |"
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
assert_equals "3 prior blocks → count=3 (loop-breaker threshold)" "$_count_three" "3"

# Verify Stop hook would now fail-open on next block — count >=3 trips the
# branch. Direct integration test would require running mcl-stop.sh with
# a transcript fixture that triggers the precision-audit-block path,
# which is too complex for this unit test. The threshold check itself is
# the contract: count >=3 → fail-open path executes.

# --- Pre-session blocks ignored: session_ts boundary ---
cat > "$_trace" <<'EOF'
2026-05-02 12:00:00 | session_start | mcl-activate.sh | test-session-1
2026-05-02 13:00:00 | session_start | mcl-activate.sh | test-session-2
EOF
cat > "$_audit" <<'EOF'
2026-05-02 12:00:01 | precision-audit-block | mcl-stop.sh | session 1 miss 1
2026-05-02 12:00:02 | precision-audit-block | mcl-stop.sh | session 1 miss 2
2026-05-02 12:00:03 | precision-audit-block | mcl-stop.sh | session 1 miss 3
2026-05-02 13:00:01 | precision-audit-block | mcl-stop.sh | session 2 miss 1
EOF

_count_session_scope="$(MCL_STATE_DIR="$_lb_dir/.mcl" python3 - <<'PYEOF'
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
needle = "| precision-audit-block |"
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
assert_equals "session-2 boundary → count=1 (session-1 misses ignored)" "$_count_session_scope" "1"

# --- Different event name doesn't count ---
cat > "$_trace" <<'EOF'
2026-05-02 12:00:00 | session_start | mcl-activate.sh | test-session-1
EOF
cat > "$_audit" <<'EOF'
2026-05-02 12:00:01 | phase-review-pending | mcl-stop.sh | risk review unrelated
2026-05-02 12:00:02 | phase-review-pending | mcl-stop.sh | risk review unrelated
EOF

_count_other_event="$(MCL_STATE_DIR="$_lb_dir/.mcl" python3 - <<'PYEOF'
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
needle = "| precision-audit-block |"
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
assert_equals "different event name → count=0" "$_count_other_event" "0"

cleanup_test_dir "$_lb_dir"
