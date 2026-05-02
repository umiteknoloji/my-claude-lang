#!/bin/bash
# Synthetic test: v10.1.2 MEDIUM/HIGH must-resolve invariant.
# When asama-9-4-ambiguous events exist without matching
# asama-9-4-resolved events, open_severity_count > 0. Stop hook
# blocks the Aşama 11 advance until count == 0.

echo "--- test-v10-1-2-must-resolve ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-1-2" > "$_dir/.mcl/trace.log"

# --- Counter: 0 ambiguous, 0 resolved → 0 open ---
: > "$_dir/.mcl/audit.log"

_count_zero="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os, re
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
ambiguous, resolved = set(), set()
def _key(detail):
    m = re.search(r"rule=(\S+)\s+file=(\S+)", detail or "")
    return m.group(0) if m else None
if audit.exists():
    for line in audit.read_text().splitlines():
        if "| asama-9-4-ambiguous |" not in line and "| asama-9-4-resolved |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        parts = line.split("|", 3)
        detail = parts[3].strip() if len(parts) > 3 else ""
        k = _key(detail)
        if not k:
            continue
        if "asama-9-4-ambiguous" in line:
            ambiguous.add(k)
        elif "asama-9-4-resolved" in line:
            resolved.add(k)
print(len(ambiguous - resolved))
PYEOF
)"
assert_equals "no findings → open_count=0" "$_count_zero" "0"

# --- 2 ambiguous, 0 resolved → 2 open ---
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | asama-9-4-ambiguous | stop | rule=missing-helmet file=apps/api/src/index.ts:5
2026-05-02 12:00:02 | asama-9-4-ambiguous | stop | rule=jwt-no-revocation file=apps/api/src/auth.ts:42
EOF

_count_two="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os, re
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
ambiguous, resolved = set(), set()
def _key(detail):
    m = re.search(r"rule=(\S+)\s+file=(\S+)", detail or "")
    return m.group(0) if m else None
if audit.exists():
    for line in audit.read_text().splitlines():
        if "| asama-9-4-ambiguous |" not in line and "| asama-9-4-resolved |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        parts = line.split("|", 3)
        detail = parts[3].strip() if len(parts) > 3 else ""
        k = _key(detail)
        if not k:
            continue
        if "asama-9-4-ambiguous" in line:
            ambiguous.add(k)
        elif "asama-9-4-resolved" in line:
            resolved.add(k)
print(len(ambiguous - resolved))
PYEOF
)"
assert_equals "2 ambiguous, 0 resolved → open=2" "$_count_two" "2"

# --- 2 ambiguous, 1 resolved → 1 open ---
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | asama-9-4-ambiguous | stop | rule=missing-helmet file=apps/api/src/index.ts:5
2026-05-02 12:00:02 | asama-9-4-ambiguous | stop | rule=jwt-no-revocation file=apps/api/src/auth.ts:42
2026-05-02 12:00:10 | asama-9-4-resolved | stop | rule=missing-helmet file=apps/api/src/index.ts:5 status=fixed
EOF

_count_one="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os, re
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
ambiguous, resolved = set(), set()
def _key(detail):
    m = re.search(r"rule=(\S+)\s+file=(\S+)", detail or "")
    return m.group(0) if m else None
if audit.exists():
    for line in audit.read_text().splitlines():
        if "| asama-9-4-ambiguous |" not in line and "| asama-9-4-resolved |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        parts = line.split("|", 3)
        detail = parts[3].strip() if len(parts) > 3 else ""
        k = _key(detail)
        if not k:
            continue
        if "asama-9-4-ambiguous" in line:
            ambiguous.add(k)
        elif "asama-9-4-resolved" in line:
            resolved.add(k)
print(len(ambiguous - resolved))
PYEOF
)"
assert_equals "2 ambiguous, 1 resolved → open=1" "$_count_one" "1"

# --- 2 ambiguous, 2 resolved → 0 open ---
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | asama-9-4-ambiguous | stop | rule=missing-helmet file=apps/api/src/index.ts:5
2026-05-02 12:00:02 | asama-9-4-ambiguous | stop | rule=jwt-no-revocation file=apps/api/src/auth.ts:42
2026-05-02 12:00:10 | asama-9-4-resolved | stop | rule=missing-helmet file=apps/api/src/index.ts:5 status=fixed
2026-05-02 12:00:15 | asama-9-4-resolved | stop | rule=jwt-no-revocation file=apps/api/src/auth.ts:42 status=accepted
EOF

_count_zero2="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os, re
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
ambiguous, resolved = set(), set()
def _key(detail):
    m = re.search(r"rule=(\S+)\s+file=(\S+)", detail or "")
    return m.group(0) if m else None
if audit.exists():
    for line in audit.read_text().splitlines():
        if "| asama-9-4-ambiguous |" not in line and "| asama-9-4-resolved |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        parts = line.split("|", 3)
        detail = parts[3].strip() if len(parts) > 3 else ""
        k = _key(detail)
        if not k:
            continue
        if "asama-9-4-ambiguous" in line:
            ambiguous.add(k)
        elif "asama-9-4-resolved" in line:
            resolved.add(k)
print(len(ambiguous - resolved))
PYEOF
)"
assert_equals "all resolved → open=0 (Aşama 11 unblocked)" "$_count_zero2" "0"

# --- Hook contract checks ---
_hook="$REPO_ROOT/hooks/mcl-stop.sh"

if grep -q "_mcl_open_severity_count" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements _mcl_open_severity_count helper\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: _mcl_open_severity_count missing\n'
fi

if grep -q "MUST-RESOLVE INVARIANT" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook contains MUST-RESOLVE invariant block\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: MUST-RESOLVE block reason missing\n'
fi

if grep -q "open-severity-loop-broken" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: open-severity loop-breaker present\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: open-severity loop-breaker missing\n'
fi

# State default schema includes the new field
_state="$REPO_ROOT/hooks/lib/mcl-state.sh"
if grep -q "open_severity_count" "$_state"; then
  PASS=$((PASS+1))
  printf '  PASS: mcl-state.sh default schema includes open_severity_count\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: open_severity_count missing from default schema\n'
fi

cleanup_test_dir "$_dir"
