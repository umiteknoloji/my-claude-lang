#!/bin/bash
# Synthetic test: v10.1.6 — Aşama 4 audit-driven progression.
# When the model emits `asama-4-complete` after AskUserQuestion spec-
# approval tool_result, Stop hook scans audit.log and force-progresses
# spec_approved=true + current_phase=7 even when askq classifier
# missed the normal transition. Closes the herta-type "frozen at
# phase 4" gap that v10.1.5 (8+9 only) could not cover.

echo "--- test-v10-1-6-asama-4-progression ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-1-6" > "$_dir/.mcl/trace.log"

# --- Case 1: NO asama-4-complete emit → emitted=0 ---
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | set | mcl-stop.sh | field=current_phase value=4
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
        if "| asama-4-complete |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        hit = 1
        break
print(hit)
PYEOF
)"
assert_equals "no asama-4-complete → emitted=0" "$_emitted" "0"

# --- Case 2: WITH asama-4-complete emit in session → emitted=1 ---
cat >> "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:03 | asama-4-complete | mcl-stop | spec_hash=abc123def456 approver=user
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
        if "| asama-4-complete |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        hit = 1
        break
print(hit)
PYEOF
)"
assert_equals "asama-4-complete in session → emitted=1" "$_emitted2" "1"

# --- Case 3: STALE emit (prev session) → emitted=0 ---
cat > "$_dir/.mcl/trace.log" <<'EOF'
2026-05-02 13:00:00 | session_start | mcl-activate.sh | t10-1-6
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
        if "| asama-4-complete |" not in line:
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

# --- Case 4: similar event names should NOT match (false positive guard) ---
cat > "$_dir/.mcl/trace.log" <<'EOF'
2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-1-6
EOF
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | asama-4-validation | mcl-stop | result=ok
2026-05-02 12:00:02 | asama-4-progression-from-emit | stop | prev_approved=null
2026-05-02 12:00:03 | precision-audit | asama2 | core_gates=2 stack_gates=1
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
        if "| asama-4-complete |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        hit = 1
        break
print(hit)
PYEOF
)"
assert_equals "validation/progression events do NOT match asama-4-complete → emitted=0" "$_emitted4" "0"

# --- Hook contract checks ---
_stop="$REPO_ROOT/hooks/mcl-stop.sh"

if grep -q "_mcl_asama_4_complete_emitted" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements _mcl_asama_4_complete_emitted helper\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: _mcl_asama_4_complete_emitted helper missing from stop hook\n'
fi

if grep -q "asama-4-progression-from-emit" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook emits asama-4-progression-from-emit audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-4-progression-from-emit audit emit missing\n'
fi

# Verify the scanner force-sets spec_approved + current_phase + phase_name.
if grep -A 12 "_A4_EMITTED=" "$_stop" | grep -q "mcl_state_set spec_approved true" \
  && grep -A 12 "_A4_EMITTED=" "$_stop" | grep -q "mcl_state_set current_phase 7" \
  && grep -A 12 "_A4_EMITTED=" "$_stop" | grep -q 'mcl_state_set phase_name'; then
  PASS=$((PASS+1))
  printf '  PASS: scanner sets spec_approved=true + current_phase=7 + phase_name=EXECUTE\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: scanner missing one of spec_approved / current_phase / phase_name writes\n'
fi

# Skill contract: skill must mandate the emit.
_skill="$REPO_ROOT/skills/my-claude-lang/asama4-spec.md"
if grep -q "mcl_audit_log asama-4-complete" "$_skill"; then
  PASS=$((PASS+1))
  printf '  PASS: skill file mandates asama-4-complete emit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-4-complete emit instruction missing from skill file\n'
fi

cleanup_test_dir "$_dir"
