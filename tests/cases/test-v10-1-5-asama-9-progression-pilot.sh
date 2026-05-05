#!/bin/bash
# Synthetic test: v10.1.5 PILOT — Aşama 9 audit-driven progression.
# When the model emits `asama-9-complete` via Bash audit at end of
# Aşama 9 quality+tests pipeline, Stop hook scans audit.log and
# force-progresses quality_review_state=complete even when behavioral
# skips bypassed the normal sub-step transition.
#
# Note: This unblocks the STATE machine. The MEDIUM/HIGH must-resolve
# invariant (v10.1.2) is independent and still gates Aşama 11.

echo "--- test-v10-1-5-asama-9-progression-pilot ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-1-5" > "$_dir/.mcl/trace.log"

# --- Case 1: NO asama-9-complete emit → emitted=0 ---
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
        if "| asama-9-complete |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        hit = 1
        break
print(hit)
PYEOF
)"
assert_equals "no asama-9-complete → emitted=0" "$_emitted" "0"

# --- Case 2: WITH asama-9-complete emit in session → emitted=1 ---
cat >> "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:03 | asama-9-complete | mcl-stop | applied=4 skipped=2 ambiguous=0 na=2
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
        if "| asama-9-complete |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        hit = 1
        break
print(hit)
PYEOF
)"
assert_equals "asama-9-complete in session → emitted=1" "$_emitted2" "1"

# --- Case 3: STALE emit (prev session) → emitted=0 ---
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
        if "| asama-9-complete |" not in line:
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

# --- Case 4: similar event name should NOT match (asama-9-1-end vs asama-9-complete) ---
cat > "$_dir/.mcl/trace.log" <<'EOF'
2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-1-5
EOF
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | aşama-9-1-end | mcl-stop | findings=0 fixes=0 skipped=0
2026-05-02 12:00:02 | asama-9-4-ambiguous | mcl-stop | rule=helmet file=app.js:10
EOF

_emitted4="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
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
        if "| asama-9-complete |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        hit = 1
        break
print(hit)
PYEOF
)"
assert_equals "sub-step events do NOT match asama-9-complete → emitted=0" "$_emitted4" "0"

# --- Hook contract checks ---
_stop="$REPO_ROOT/hooks/mcl-stop.sh"

if grep -q "_mcl_asama_9_complete_emitted" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements _mcl_asama_9_complete_emitted helper\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: _mcl_asama_9_complete_emitted helper missing from stop hook\n'
fi

if grep -q "asama-9-progression-from-emit" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook emits asama-9-progression-from-emit audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-9-progression-from-emit audit emit missing\n'
fi

# Skill contract: in v11 architecture (since v10.1.21) the monolithic
# asama9-quality-tests.md skill is split into asama10..17. The v10
# alias `asama-9-complete` is now mandated inside the LAST quality
# phase skill (asama18-load-tests.md) so the existing v10 hook
# enforcement chain continues to operate during the bridge period.
# R8 cutover removes that mandate; this test will be retired or
# rewritten as test-v11-* at that point.
_skill="$REPO_ROOT/skills/my-claude-lang/asama18-load-tests.md"
if grep -q "mcl_audit_log asama-9-complete" "$_skill"; then
  PASS=$((PASS+1))
  printf '  PASS: skill file mandates asama-9-complete emit (v11: asama18-load-tests.md)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-9-complete emit instruction missing from skill file\n'
fi

cleanup_test_dir "$_dir"
