#!/bin/bash
# Synthetic test: scanner classifier fallback heuristic.
# Real-use bug: model emits AskUserQuestion as
# "Şartname yukarıdaki gibi. Onaylıyor musun?" — strict
# SPEC_APPROVE_TOKENS didn't include "şartname" or generic
# approve verbs, classifier returned `intent="other"`, JIT
# advance skipped, mcl-pre-tool blocked Write with
# "spec_approved=false" → infinite loop.
# v9.0.0 patch: token list expanded + fallback heuristic
# (spec exists in transcript + approve verb in question/option/
# selected → spec-approve).

echo "--- test-v9-classifier-fallback ---"

_cf_dir="$(setup_test_dir)"
_tx="$_cf_dir/.mcl/transcript.jsonl"
mkdir -p "$_cf_dir/.mcl"

# Scenario A: question uses "Şartname" (Turkish for specification),
# not "Spec" — strict tokens won't match. Spec exists in transcript.
# Selected option contains an approve verb.
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
  # Spec emit (clean format, post-tolerant-regex compatible)
  {"message": {"role": "assistant", "content": [
      {"type": "text", "text": "📋 Spec:\n\nObjective: build admin panel.\nMUST: CRUD."}
  ]}},
  # AskUserQuestion using "Şartname" wording
  {"message": {"role": "assistant", "content": [
      {"type": "tool_use", "name": "AskUserQuestion", "id": "tu_001",
       "input": {"questions": [{
         "question": "MCL 9.0.0 | Şartname yukarıdaki gibi. Onaylıyor musun?",
         "options": ["onayla", "düzelt", "iptal"]
       }]}}
  ]}},
  # User reply
  {"message": {"role": "user", "content": [
      {"type": "tool_result", "tool_use_id": "tu_001", "content": "onayla"}
  ]}},
]
with open(path, "w") as f:
  for e in events:
    f.write(json.dumps(e) + "\n")
PYEOF

_scan="$(python3 "$REPO_ROOT/hooks/lib/mcl-askq-scanner.py" "$_tx" 2>/dev/null)"

assert_json_valid "şartname-fallback → scanner returns valid JSON" "$_scan"

_intent="$(printf '%s' "$_scan" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("intent",""))')"
assert_equals "şartname-fallback → intent=spec-approve (via fallback)" "$_intent" "spec-approve"

_selected="$(printf '%s' "$_scan" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("selected",""))')"
assert_equals "şartname-fallback → selected=onayla" "$_selected" "onayla"

_hash="$(printf '%s' "$_scan" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("spec_hash",""))')"
if [ -n "$_hash" ]; then
  PASS=$((PASS+1))
  printf '  PASS: şartname-fallback → spec_hash computed (%s)\n' "${_hash:0:12}"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: şartname-fallback → spec_hash empty\n'
fi

# Scenario B: explicit Turkish "şartname onay" token now in list
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
  {"message": {"role": "assistant", "content": [
      {"type": "text", "text": "📋 Spec:\n\nObjective: rev2."}
  ]}},
  {"message": {"role": "assistant", "content": [
      {"type": "tool_use", "name": "AskUserQuestion", "id": "tu_002",
       "input": {"questions": [{
         "question": "MCL 9.0.0 | Bu şartname onaylıyor musun?",
         "options": ["onayla", "iptal"]
       }]}}
  ]}},
  {"message": {"role": "user", "content": [
      {"type": "tool_result", "tool_use_id": "tu_002", "content": "onayla"}
  ]}},
]
with open(path, "w") as f:
  for e in events:
    f.write(json.dumps(e) + "\n")
PYEOF

_scan2="$(python3 "$REPO_ROOT/hooks/lib/mcl-askq-scanner.py" "$_tx" 2>/dev/null)"
_intent2="$(printf '%s' "$_scan2" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("intent",""))')"
assert_equals "şartname-explicit-token → intent=spec-approve" "$_intent2" "spec-approve"

# Scenario C: no spec emitted, generic approve question → summary-confirm
# (Aşama 1 summary path, NOT spec-approve)
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
  {"message": {"role": "assistant", "content": [
      {"type": "tool_use", "name": "AskUserQuestion", "id": "tu_003",
       "input": {"questions": [{
         "question": "MCL 9.0.0 | Yukarıdaki özet doğru mu?",
         "options": ["onayla", "düzelt"]
       }]}}
  ]}},
  {"message": {"role": "user", "content": [
      {"type": "tool_result", "tool_use_id": "tu_003", "content": "onayla"}
  ]}},
]
with open(path, "w") as f:
  for e in events:
    f.write(json.dumps(e) + "\n")
PYEOF

_scan3="$(python3 "$REPO_ROOT/hooks/lib/mcl-askq-scanner.py" "$_tx" 2>/dev/null)"
_intent3="$(printf '%s' "$_scan3" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("intent",""))')"
# "özet doğru mu" matches summary-confirm token → strict path returns summary-confirm
assert_equals "no-spec-question → intent=summary-confirm (strict token)" "$_intent3" "summary-confirm"

# Scenario D: no spec, generic approve question without summary keyword →
# fallback returns summary-confirm (Aşama 1 default)
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
  {"message": {"role": "assistant", "content": [
      {"type": "tool_use", "name": "AskUserQuestion", "id": "tu_004",
       "input": {"questions": [{
         "question": "MCL 9.0.0 | Bu plan ile devam edelim mi?",
         "options": ["onayla", "iptal"]
       }]}}
  ]}},
  {"message": {"role": "user", "content": [
      {"type": "tool_result", "tool_use_id": "tu_004", "content": "onayla"}
  ]}},
]
with open(path, "w") as f:
  for e in events:
    f.write(json.dumps(e) + "\n")
PYEOF

_scan4="$(python3 "$REPO_ROOT/hooks/lib/mcl-askq-scanner.py" "$_tx" 2>/dev/null)"
_intent4="$(printf '%s' "$_scan4" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("intent",""))')"
assert_equals "no-spec-generic-approve → intent=summary-confirm (fallback)" "$_intent4" "summary-confirm"

# Scenario E: Japanese spec approve via 仕様 (specification)
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
  {"message": {"role": "assistant", "content": [
      {"type": "text", "text": "📋 Spec:\n\nObjective: 日本語のテスト."}
  ]}},
  {"message": {"role": "assistant", "content": [
      {"type": "tool_use", "name": "AskUserQuestion", "id": "tu_005",
       "input": {"questions": [{
         "question": "MCL 9.0.0 | この仕様を承認しますか?",
         "options": ["承認", "編集", "キャンセル"]
       }]}}
  ]}},
  {"message": {"role": "user", "content": [
      {"type": "tool_result", "tool_use_id": "tu_005", "content": "承認"}
  ]}},
]
with open(path, "w") as f:
  for e in events:
    f.write(json.dumps(e) + "\n")
PYEOF

_scan5="$(python3 "$REPO_ROOT/hooks/lib/mcl-askq-scanner.py" "$_tx" 2>/dev/null)"
_intent5="$(printf '%s' "$_scan5" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("intent",""))')"
assert_equals "japanese-jiyou → intent=spec-approve" "$_intent5" "spec-approve"

cleanup_test_dir "$_cf_dir"
