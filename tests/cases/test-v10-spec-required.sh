#!/bin/bash
# Synthetic test: Aşama 4 spec-presence enforcement (v10.0.3).
# Edit/Write/MultiEdit/NotebookEdit tool calls require a 📋 Spec:
# block in the current assistant turn. Pre-tool hook blocks tool
# call when no spec is present. After 3 strikes loop-breaker fails
# open.

echo "--- test-v10-spec-required ---"

_sr_dir="$(setup_test_dir)"
_audit="$_sr_dir/.mcl/audit.log"
_trace="$_sr_dir/.mcl/trace.log"
mkdir -p "$_sr_dir/.mcl"

# Counter starts at zero
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-spec-req" > "$_trace"

_count_zero="$(MCL_STATE_DIR="$_sr_dir/.mcl" python3 - <<'PYEOF'
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
needle = "| spec-required-block |"
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
assert_equals "no prior spec-blocks → counter=0" "$_count_zero" "0"

# 3 prior blocks → loop-breaker threshold
cat > "$_audit" <<'EOF'
2026-05-02 12:00:01 | spec-required-block | pre-tool | tool=Write count=0
2026-05-02 12:00:02 | spec-required-block | pre-tool | tool=Edit count=1
2026-05-02 12:00:03 | spec-required-block | pre-tool | tool=Write count=2
EOF

_count_three="$(MCL_STATE_DIR="$_sr_dir/.mcl" python3 - <<'PYEOF'
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
needle = "| spec-required-block |"
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
assert_equals "3 prior spec-blocks → counter=3 (loop-breaker threshold)" "$_count_three" "3"

# --- Hook source contract checks ---
_hook="$REPO_ROOT/hooks/mcl-pre-tool.sh"

if grep -q "spec-required-block" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool references spec-required-block event\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec-required-block missing from pre-tool\n'
fi

if grep -q "spec-required-loop-broken" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool implements spec-required-loop-broken fail-open\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec-required-loop-broken missing from pre-tool\n'
fi

if grep -q "AŞAMA 4 SPEC-PRESENCE GATE" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: pre-tool contains spec-presence block reason text\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec-presence block reason text missing\n'
fi

# --- Transcript scan: verify the SPEC_RE matches the same tolerant pattern ---
_tx="$_sr_dir/.mcl/transcript.jsonl"
python3 - "$_tx" <<'PYEOF'
import json
import sys
path = sys.argv[1]
events = [
    {"message": {"role": "user", "content": [{"type": "text", "text": "küçük tweak"}]}},
    {"message": {"role": "assistant", "content": [
        {"type": "text", "text": "📋 Spec:\nChanges: tweak the button label.\nBehavioral contract: same handler.\nOut of scope: layout."},
    ]}},
]
with open(path, "w") as f:
    for e in events:
        f.write(json.dumps(e) + "\n")
PYEOF

# Run the same Python detector logic the pre-tool uses
_present="$(python3 - "$_tx" <<'PYEOF'
import json, re, sys
path = sys.argv[1]
SPEC_RE = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec\b[^\n:]*:", re.MULTILINE)
last_user = -1
events = []
with open(path) as f:
    for i, line in enumerate(f):
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        msg = obj.get("message") or obj
        role = msg.get("role")
        content = msg.get("content")
        if role == "user":
            last_user = len(events)
            events.append(("user", None))
        elif role == "assistant":
            texts = []
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get("type") == "text":
                        t = item.get("text")
                        if isinstance(t, str):
                            texts.append(t)
            events.append(("assistant", "\n".join(texts)))
asst_text = "\n".join(t for r, t in events[last_user + 1:] if r == "assistant" and t)
print("yes" if SPEC_RE.search(asst_text) else "no")
PYEOF
)"
assert_equals "transcript with 📋 Spec: → detector returns yes" "$_present" "yes"

# Negative: no spec → no
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
    {"message": {"role": "user", "content": [{"type": "text", "text": "küçük tweak"}]}},
    {"message": {"role": "assistant", "content": [
        {"type": "text", "text": "Tamam, butonu güncelliyorum hemen."},
    ]}},
]
with open(path, "w") as f:
    for e in events:
        f.write(json.dumps(e) + "\n")
PYEOF

_absent="$(python3 - "$_tx" <<'PYEOF'
import json, re, sys
path = sys.argv[1]
SPEC_RE = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec\b[^\n:]*:", re.MULTILINE)
last_user = -1
events = []
with open(path) as f:
    for i, line in enumerate(f):
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        msg = obj.get("message") or obj
        role = msg.get("role")
        content = msg.get("content")
        if role == "user":
            last_user = len(events)
            events.append(("user", None))
        elif role == "assistant":
            texts = []
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get("type") == "text":
                        t = item.get("text")
                        if isinstance(t, str):
                            texts.append(t)
            events.append(("assistant", "\n".join(texts)))
asst_text = "\n".join(t for r, t in events[last_user + 1:] if r == "assistant" and t)
print("yes" if SPEC_RE.search(asst_text) else "no")
PYEOF
)"
assert_equals "transcript without 📋 Spec: → detector returns no (block path)" "$_absent" "no"

cleanup_test_dir "$_sr_dir"
