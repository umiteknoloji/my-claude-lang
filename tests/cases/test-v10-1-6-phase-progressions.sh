#!/bin/bash
# Synthetic test: v10.1.6 — Aşama 1→2, 10, 11, 12 audit-driven progression.
# Aşama 1→2 reuses existing `precision-audit asama2` audit; sets
# precision_audit_done=true (previously dead state field).
# Aşama 10/11 require explicit asama-N-complete emit.
# Aşama 12 reuses existing `localize-report asama12` audit.

echo "--- test-v10-1-6-phase-progressions ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-1-6" > "$_dir/.mcl/trace.log"

# === Aşama 1→2 (precision_audit_done) ===
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | precision-audit | asama2 | core_gates=2 stack_gates=1 assumes=4 skipmarks=0 stack_tags=js skipped=false
EOF

_pa_emitted="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
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
        if "| precision-audit |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        hit = 1
        break
print(hit)
PYEOF
)"
assert_equals "precision-audit emit in session → emitted=1" "$_pa_emitted" "1"

# === Aşama 10 (asama-10-complete) ===
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | asama-10-complete | mcl-stop | impacts=2 resolved=2
EOF

_a10_fire="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
emitted, already = False, False
if audit.exists():
    for line in audit.read_text().splitlines():
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if "| asama-10-complete |" in line:
            emitted = True
        if "| asama-10-progression-from-emit |" in line:
            already = True
print(1 if (emitted and not already) else 0)
PYEOF
)"
assert_equals "asama-10-complete emit, no progression yet → fire=1" "$_a10_fire" "1"

# Idempotency: progression-from-emit already present → fire=0
cat >> "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:02 | asama-10-progression-from-emit | stop |
EOF

_a10_idem="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
emitted, already = False, False
if audit.exists():
    for line in audit.read_text().splitlines():
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if "| asama-10-complete |" in line:
            emitted = True
        if "| asama-10-progression-from-emit |" in line:
            already = True
print(1 if (emitted and not already) else 0)
PYEOF
)"
assert_equals "idempotent — progression already emitted → fire=0" "$_a10_idem" "0"

# === Aşama 12 (localize-report reused) ===
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | localize-report | asama12 | lang=tr skipped=false
EOF

_a12_fire="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
emitted, already = False, False
if audit.exists():
    for line in audit.read_text().splitlines():
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if "| localize-report |" in line:
            emitted = True
        if "| asama-12-progression-from-emit |" in line:
            already = True
print(1 if (emitted and not already) else 0)
PYEOF
)"
assert_equals "localize-report emit (skipped=false) → fire=1" "$_a12_fire" "1"

# === Hook contract checks ===
_stop="$REPO_ROOT/hooks/mcl-stop.sh"

if grep -q "_mcl_precision_audit_emitted" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements _mcl_precision_audit_emitted helper\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: _mcl_precision_audit_emitted helper missing\n'
fi

if grep -q "_mcl_audit_emitted_in_session" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements generic _mcl_audit_emitted_in_session helper\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: _mcl_audit_emitted_in_session helper missing\n'
fi

if grep -q "asama-2-progression-from-emit" "$_stop" \
  && grep -q "asama-10-progression-from-emit" "$_stop" \
  && grep -q "asama-11-progression-from-emit" "$_stop" \
  && grep -q "asama-12-progression-from-emit" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook emits asama-{2,10,11,12}-progression-from-emit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: at least one asama-N-progression-from-emit missing\n'
fi

# Skill contracts
_skill10="$REPO_ROOT/skills/my-claude-lang/asama10-impact-review.md"
_skill11="$REPO_ROOT/skills/my-claude-lang/asama11-verify-report.md"

if grep -q "mcl_audit_log asama-10-complete" "$_skill10"; then
  PASS=$((PASS+1))
  printf '  PASS: asama10 skill mandates asama-10-complete emit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama10 skill missing asama-10-complete instruction\n'
fi

if grep -q "mcl_audit_log asama-11-complete" "$_skill11"; then
  PASS=$((PASS+1))
  printf '  PASS: asama11 skill mandates asama-11-complete emit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama11 skill missing asama-11-complete instruction\n'
fi

cleanup_test_dir "$_dir"
