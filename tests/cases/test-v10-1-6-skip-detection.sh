#!/bin/bash
# Synthetic test: v10.1.6 Layer 3 skip-detection.
# When code-write activity occurred (tdd-prod-write events) but the
# corresponding asama-N-complete emit is missing for phase
# N ∈ {4, 8, 9}, Stop hook writes asama-N-emit-missing audit. Pure
# visibility, no block — surfaces in /mcl-checkup so the developer
# can see when the model bypassed the explicit phase-completion
# contract (the herta v10.1.4 scenario, retrospectively visible).

echo "--- test-v10-1-6-skip-detection ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-1-6" > "$_dir/.mcl/trace.log"

# === Case 1: Code written but ALL emits missing → 4, 8, 9 all flagged ===
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | tdd-prod-write | post-tool | file=/p/foo.js
2026-05-02 12:00:02 | tdd-prod-write | post-tool | file=/p/bar.js
EOF

_missing="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
prod_write = False
emits = {"4": False, "8": False, "9": False}
already = {"4": False, "8": False, "9": False}
if audit.exists():
    for line in audit.read_text().splitlines():
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if "| tdd-prod-write |" in line:
            prod_write = True
        for n in ("4", "8", "9"):
            if f"| asama-{n}-complete |" in line:
                emits[n] = True
            if f"| asama-{n}-emit-missing |" in line:
                already[n] = True
missing = []
if prod_write:
    for n in ("4", "8", "9"):
        if not emits[n] and not already[n]:
            missing.append(n)
print(" ".join(missing))
PYEOF
)"
assert_equals "code written, no emits → missing=4 8 9" "$_missing" "4 8 9"

# === Case 2: Aşama 4 emit present, 8 + 9 missing ===
cat >> "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:03 | asama-4-complete | mcl-stop | spec_hash=abc12345 approver=user
EOF

_missing2="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
prod_write = False
emits = {"4": False, "8": False, "9": False}
already = {"4": False, "8": False, "9": False}
if audit.exists():
    for line in audit.read_text().splitlines():
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if "| tdd-prod-write |" in line:
            prod_write = True
        for n in ("4", "8", "9"):
            if f"| asama-{n}-complete |" in line:
                emits[n] = True
            if f"| asama-{n}-emit-missing |" in line:
                already[n] = True
missing = []
if prod_write:
    for n in ("4", "8", "9"):
        if not emits[n] and not already[n]:
            missing.append(n)
print(" ".join(missing))
PYEOF
)"
assert_equals "asama-4-complete present → missing=8 9" "$_missing2" "8 9"

# === Case 3: All 3 emits present → no missing ===
cat >> "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:04 | asama-8-complete | mcl-stop | h_count=1 m_count=0 l_count=0 resolved=1
2026-05-02 12:00:05 | asama-9-complete | mcl-stop | applied=2 skipped=4 ambiguous=0 na=2
EOF

_missing3="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
prod_write = False
emits = {"4": False, "8": False, "9": False}
already = {"4": False, "8": False, "9": False}
if audit.exists():
    for line in audit.read_text().splitlines():
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if "| tdd-prod-write |" in line:
            prod_write = True
        for n in ("4", "8", "9"):
            if f"| asama-{n}-complete |" in line:
                emits[n] = True
            if f"| asama-{n}-emit-missing |" in line:
                already[n] = True
missing = []
if prod_write:
    for n in ("4", "8", "9"):
        if not emits[n] and not already[n]:
            missing.append(n)
print(" ".join(missing))
PYEOF
)"
assert_equals "all emits present → no missing" "$_missing3" ""

# === Case 4: NO code-write activity → no flags (Read-only session) ===
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | set | mcl-stop.sh | field=current_phase value=4
EOF

_missing4="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
prod_write = False
emits = {"4": False, "8": False, "9": False}
already = {"4": False, "8": False, "9": False}
if audit.exists():
    for line in audit.read_text().splitlines():
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if "| tdd-prod-write |" in line:
            prod_write = True
        for n in ("4", "8", "9"):
            if f"| asama-{n}-complete |" in line:
                emits[n] = True
            if f"| asama-{n}-emit-missing |" in line:
                already[n] = True
missing = []
if prod_write:
    for n in ("4", "8", "9"):
        if not emits[n] and not already[n]:
            missing.append(n)
print(" ".join(missing))
PYEOF
)"
assert_equals "no code-write → skip-detect silent (no false positives)" "$_missing4" ""

# === Case 5: Idempotency — already-flagged missing stays unflagged ===
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | tdd-prod-write | post-tool | file=/p/foo.js
2026-05-02 12:00:02 | asama-8-emit-missing | stop | skip-detect prod-write-without-emit
EOF

_missing5="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
prod_write = False
emits = {"4": False, "8": False, "9": False}
already = {"4": False, "8": False, "9": False}
if audit.exists():
    for line in audit.read_text().splitlines():
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if "| tdd-prod-write |" in line:
            prod_write = True
        for n in ("4", "8", "9"):
            if f"| asama-{n}-complete |" in line:
                emits[n] = True
            if f"| asama-{n}-emit-missing |" in line:
                already[n] = True
missing = []
if prod_write:
    for n in ("4", "8", "9"):
        if not emits[n] and not already[n]:
            missing.append(n)
print(" ".join(missing))
PYEOF
)"
assert_equals "asama-8-emit-missing already present → skip 8 (only 4 9)" "$_missing5" "4 9"

# === Hook contract checks ===
_stop="$REPO_ROOT/hooks/mcl-stop.sh"

if grep -q "_mcl_skip_detection" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements _mcl_skip_detection helper\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: _mcl_skip_detection helper missing\n'
fi

if grep -q "asama-.*-emit-missing" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook emits asama-N-emit-missing audit on skip-detect\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-N-emit-missing audit emit missing\n'
fi

cleanup_test_dir "$_dir"
