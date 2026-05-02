#!/bin/bash
# Synthetic test: v10.1.0 Aşama 8 + 9 hard-enforcement.
# Aşama 8 risk-pending → block (re-enabled from v9 era).
# Aşama 9 quality-pending → block (new).
# Both with loop-breakers.

echo "--- test-v10-1-asama8-9-enforcement ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-1" > "$_dir/.mcl/trace.log"

_hook="$REPO_ROOT/hooks/mcl-stop.sh"

# Contract: scan for the literal block + reason combo using python (avoids awk
# multi-line escape headaches).
_v8_block_check="$(python3 - "$_hook" <<'PYEOF'
import sys, re
content = open(sys.argv[1]).read()
# Look for backslash-escaped decision:block followed within 200 chars by
# "MCL PHASE REVIEW ENFORCEMENT". Stop hook uses \" escaping inside printf.
pattern = re.compile(r'\\"decision\\":\s*\\"block\\"[\s\S]{0,300}MCL PHASE REVIEW ENFORCEMENT')
print("yes" if pattern.search(content) else "no")
PYEOF
)"
if [ "$_v8_block_check" = "yes" ]; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook re-emits decision:block for Aşama 8 risk-review-pending\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: Aşama 8 enforcement still decision:approve (v10.0.0 advisory)\n'
fi

if grep -q "AŞAMA 9 ENFORCEMENT" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements Aşama 9 enforcement\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: Aşama 9 enforcement missing from stop hook\n'
fi

if grep -q "quality-review-pending" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook emits quality-review-pending audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: quality-review-pending audit event missing\n'
fi

if grep -q "quality-review-loop-broken" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: Aşama 9 has loop-breaker (3 strikes fail-open)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: Aşama 9 loop-breaker missing\n'
fi

# Contract: STATIC_CONTEXT references the no-fast-path rule
_activate="$REPO_ROOT/hooks/mcl-activate.sh"
if grep -q "asama-8-9-no-fast-path" "$_activate"; then
  PASS=$((PASS+1))
  printf '  PASS: STATIC_CONTEXT has asama-8-9-no-fast-path constraint\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-8-9-no-fast-path constraint missing from STATIC_CONTEXT\n'
fi

# Loop-breaker counter behavior — 3 prior quality-review-pending blocks
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | quality-review-pending | stop | count=0
2026-05-02 12:00:02 | quality-review-pending | stop | count=1
2026-05-02 12:00:03 | quality-review-pending | stop | count=2
EOF

_count="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
count = 0
needle = "| quality-review-pending |"
if audit.exists():
    for line in audit.read_text().splitlines():
        if needle not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if not session_ts or ts >= session_ts:
            count += 1
print(count)
PYEOF
)"
assert_equals "3 prior quality-review-pending → counter=3 (loop-breaker threshold)" "$_count" "3"

cleanup_test_dir "$_dir"
