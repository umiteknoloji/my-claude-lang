#!/bin/bash
# Synthetic test: Aşama 4 spec-presence audit (v10.0.4).
# v10.0.3 attempted pre-tool block but failed due to transcript timing
# (in-progress assistant text not flushed at PreToolUse fire time).
# v10.0.4 moves enforcement to Stop hook audit-warn — turn-complete
# transcript IS flushed at Stop fire time, so detection is reliable.

echo "--- test-v10-spec-required ---"

_sr_dir="$(setup_test_dir)"
_tx="$_sr_dir/.mcl/transcript.jsonl"
mkdir -p "$_sr_dir/.mcl"

# --- Hook source contract checks ---
_hook="$REPO_ROOT/hooks/mcl-stop.sh"

if grep -q "spec-required-warn" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook references spec-required-warn audit event\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: spec-required-warn missing from stop hook\n'
fi

if grep -q "_mcl_spec_presence_audit" "$_hook"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements _mcl_spec_presence_audit helper\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: _mcl_spec_presence_audit missing from stop hook\n'
fi

# --- Pre-tool should NOT have spec-required-block (v10.0.4 reverted) ---
_pretool="$REPO_ROOT/hooks/mcl-pre-tool.sh"
if grep -q "spec-required-block" "$_pretool"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: pre-tool still has spec-required-block (v10.0.3 not reverted)\n'
else
  PASS=$((PASS+1))
  printf '  PASS: pre-tool no longer hard-blocks on spec presence (v10.0.4 advisory)\n'
fi

# --- Detector: assistant message with Edit + preceding spec → ok ---
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
    {"message": {"role": "user", "content": [{"type": "text", "text": "tweak"}]}},
    {"message": {"role": "assistant", "content": [
        {"type": "text", "text": "📋 Spec:\nChanges: tweak X.\nBehavioral contract: Y.\nOut of scope: Z."},
        {"type": "tool_use", "name": "Edit", "id": "tu_1", "input": {"file_path": "/x"}},
    ]}},
]
with open(path, "w") as f:
    for e in events:
        f.write(json.dumps(e) + "\n")
PYEOF

_verdict_ok="$(python3 - "$_tx" <<'PYEOF'
import json, re, sys
path = sys.argv[1]
SPEC_RE = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec\b[^\n:]*:", re.MULTILINE)
EDIT_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
last_assistant_blocks = None
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        msg = obj.get("message") or obj
        if msg.get("role") == "assistant":
            content = msg.get("content")
            if isinstance(content, list):
                last_assistant_blocks = content
edit_called = False
spec_seen_before_edit = False
for block in (last_assistant_blocks or []):
    btype = block.get("type")
    if btype == "text":
        t = block.get("text") or ""
        if SPEC_RE.search(t) and not edit_called:
            spec_seen_before_edit = True
    elif btype == "tool_use" and (block.get("name") or "") in EDIT_TOOLS:
        edit_called = True
        break
print("warn" if (edit_called and not spec_seen_before_edit) else "ok")
PYEOF
)"
assert_equals "Edit with preceding 📋 Spec: → audit verdict=ok" "$_verdict_ok" "ok"

# --- Detector: assistant message with Edit and NO spec → warn ---
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
    {"message": {"role": "user", "content": [{"type": "text", "text": "tweak"}]}},
    {"message": {"role": "assistant", "content": [
        {"type": "text", "text": "Tamam, butonu güncelliyorum hemen."},
        {"type": "tool_use", "name": "Edit", "id": "tu_2", "input": {"file_path": "/x"}},
    ]}},
]
with open(path, "w") as f:
    for e in events:
        f.write(json.dumps(e) + "\n")
PYEOF

_verdict_warn="$(python3 - "$_tx" <<'PYEOF'
import json, re, sys
path = sys.argv[1]
SPEC_RE = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec\b[^\n:]*:", re.MULTILINE)
EDIT_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
last_assistant_blocks = None
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        msg = obj.get("message") or obj
        if msg.get("role") == "assistant":
            content = msg.get("content")
            if isinstance(content, list):
                last_assistant_blocks = content
edit_called = False
spec_seen_before_edit = False
for block in (last_assistant_blocks or []):
    btype = block.get("type")
    if btype == "text":
        t = block.get("text") or ""
        if SPEC_RE.search(t) and not edit_called:
            spec_seen_before_edit = True
    elif btype == "tool_use" and (block.get("name") or "") in EDIT_TOOLS:
        edit_called = True
        break
print("warn" if (edit_called and not spec_seen_before_edit) else "ok")
PYEOF
)"
assert_equals "Edit without preceding spec → audit verdict=warn" "$_verdict_warn" "warn"

# --- Detector: spec AFTER Edit → still warn (order matters) ---
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
    {"message": {"role": "user", "content": [{"type": "text", "text": "tweak"}]}},
    {"message": {"role": "assistant", "content": [
        {"type": "tool_use", "name": "Write", "id": "tu_3", "input": {"file_path": "/x"}},
        {"type": "text", "text": "📋 Spec: (post-hoc, too late)"},
    ]}},
]
with open(path, "w") as f:
    for e in events:
        f.write(json.dumps(e) + "\n")
PYEOF

_verdict_late="$(python3 - "$_tx" <<'PYEOF'
import json, re, sys
path = sys.argv[1]
SPEC_RE = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec\b[^\n:]*:", re.MULTILINE)
EDIT_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
last_assistant_blocks = None
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        msg = obj.get("message") or obj
        if msg.get("role") == "assistant":
            content = msg.get("content")
            if isinstance(content, list):
                last_assistant_blocks = content
edit_called = False
spec_seen_before_edit = False
for block in (last_assistant_blocks or []):
    btype = block.get("type")
    if btype == "text":
        t = block.get("text") or ""
        if SPEC_RE.search(t) and not edit_called:
            spec_seen_before_edit = True
    elif btype == "tool_use" and (block.get("name") or "") in EDIT_TOOLS:
        edit_called = True
        break
print("warn" if (edit_called and not spec_seen_before_edit) else "ok")
PYEOF
)"
assert_equals "Spec emitted AFTER Edit → audit verdict=warn (order matters)" "$_verdict_late" "warn"

cleanup_test_dir "$_sr_dir"
