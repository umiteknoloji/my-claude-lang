#!/bin/bash
# Synthetic test: v10.1.5 PILOT — Aşama 8 audit-driven progression.
# When the model emits `asama-8-complete` via Bash audit at end of
# risk review, Stop hook scans audit.log and force-progresses
# risk_review_state=complete even when askq classifier missed the
# normal transition. Catches classifier-coverage gaps that left the
# herta project at risk_review_state=null under v10.1.4.

echo "--- test-v10-1-5-asama-8-progression-pilot ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-1-5" > "$_dir/.mcl/trace.log"

# --- Case 1: NO asama-8-complete emit → emitted=0 ---
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | tdd-test-write | post-tool | file=src/foo.test.ts
2026-05-02 12:00:02 | tdd-prod-write | post-tool | file=src/foo.ts
EOF

_emitted="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
hit = 0
if audit.exists():
    for line in audit.read_text().splitlines():
        if "| asama-8-complete |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        hit = 1
        break
print(hit)
PYEOF
)"
assert_equals "no asama-8-complete → emitted=0" "$_emitted" "0"

# --- Case 2: WITH asama-8-complete emit in session → emitted=1 ---
cat >> "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:03 | asama-8-complete | mcl-stop | h_count=2 m_count=1 l_count=0 resolved=3
EOF

_emitted2="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
hit = 0
if audit.exists():
    for line in audit.read_text().splitlines():
        if "| asama-8-complete |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        hit = 1
        break
print(hit)
PYEOF
)"
assert_equals "asama-8-complete in session → emitted=1" "$_emitted2" "1"

# --- Case 3: STALE emit (prev session) → emitted=0 ---
# Bump session_start past the existing emit timestamp; emit should be
# considered stale and ignored.
cat > "$_dir/.mcl/trace.log" <<'EOF'
2026-05-02 13:00:00 | session_start | mcl-activate.sh | t10-1-5
EOF

_emitted3="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
hit = 0
if audit.exists():
    for line in audit.read_text().splitlines():
        if "| asama-8-complete |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        hit = 1
        break
print(hit)
PYEOF
)"
assert_equals "stale emit (prev session) → emitted=0" "$_emitted3" "0"

# --- Hook contract checks ---
_stop="$REPO_ROOT/hooks/mcl-stop.sh"

if grep -q "_mcl_asama_8_complete_emitted" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements _mcl_asama_8_complete_emitted helper\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: _mcl_asama_8_complete_emitted helper missing from stop hook\n'
fi

if grep -q "asama-8-progression-from-emit" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook emits asama-8-progression-from-emit audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-8-progression-from-emit audit emit missing\n'
fi

# Skill contract: skill must mandate the emit.
_skill="$REPO_ROOT/skills/my-claude-lang/asama9-risk-review.md"
if grep -q "mcl_audit_log asama-8-complete" "$_skill"; then
  PASS=$((PASS+1))
  printf '  PASS: skill file mandates asama-8-complete emit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-8-complete emit instruction missing from skill file\n'
fi

cleanup_test_dir "$_dir"
