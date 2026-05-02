#!/bin/bash
# Synthetic test: askq scanner accepts tolerant spec headers.
# Real-use bug: model emits `📋 Spec (revised):` or
# `📋 Spec — Web Calculator:`; old regex required strict `📋 Spec:`
# and silently failed → JIT askq advance never fired → infinite
# spec-approve loop ("MCL LOCK — spec_approved=false" repeats).
# v9.0.0 patch: scanner SPEC_LINE_RE allows any non-colon text
# between Spec and the body anchor `:`.

echo "--- test-v9-spec-line-tolerant ---"

_sl_dir="$(setup_test_dir)"
_tx="$_sl_dir/.mcl/transcript.jsonl"
mkdir -p "$_sl_dir/.mcl"

# Build a synthetic transcript with three spec variants:
# (a) bare 📋 Spec:
# (b) 📋 Spec (revised):
# (c) 📋 Spec — Calculator project:
# Plus a matching AskUserQuestion + tool_result approval pair using
# the (c) variant (most permissive — would have failed under old regex).
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
  # Spec emit (variant c — Spec followed by em-dash and title before colon)
  {"message": {"role": "assistant", "content": [
      {"type": "text", "text": "📋 Spec — Calculator project:\n\nObjective: build a calculator.\nMUST: 4 ops.\n\nAcceptance: keypad + display."}
  ]}},
  # AskUserQuestion approval
  {"message": {"role": "assistant", "content": [
      {"type": "tool_use", "name": "AskUserQuestion", "id": "tu_001",
       "input": {"questions": [{
         "question": "MCL 9.0.0 | Bu spec'i onaylıyor musun?",
         "options": ["Onaylıyorum, kodu yaz", "Düzelt", "İptal"]
       }]}}
  ]}},
  # User reply
  {"message": {"role": "user", "content": [
      {"type": "tool_result", "tool_use_id": "tu_001",
       "content": "Onaylıyorum, kodu yaz"}
  ]}},
]
with open(path, "w") as f:
  for e in events:
    f.write(json.dumps(e) + "\n")
PYEOF

# Run scanner against the transcript
_scan="$(python3 "$REPO_ROOT/hooks/lib/mcl-askq-scanner.py" "$_tx" 2>/dev/null)"

assert_json_valid "tolerant spec line → scanner returns valid JSON" "$_scan"

_intent="$(printf '%s' "$_scan" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("intent",""))')"
assert_equals "tolerant spec line → intent=spec-approve" "$_intent" "spec-approve"

_selected="$(printf '%s' "$_scan" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("selected",""))')"
assert_equals "tolerant spec line → selected=Onaylıyorum, kodu yaz" "$_selected" "Onaylıyorum, kodu yaz"

_hash="$(printf '%s' "$_scan" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("spec_hash",""))')"
if [ -n "$_hash" ] && [ "${#_hash}" -ge 40 ]; then
  PASS=$((PASS+1))
  printf '  PASS: tolerant spec line → spec_hash computed (%s)\n' "${_hash:0:12}"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: tolerant spec line → spec_hash empty (regression)\n'
fi

# --- Variant (b): "📋 Spec (revised):" — exact form from the test10 bug ---
python3 - "$_tx" <<'PYEOF'
import json, sys
path = sys.argv[1]
events = [
  {"message": {"role": "assistant", "content": [
      {"type": "text", "text": "📋 Spec (revised):\n\nObjective: rev2 spec.\nMUST: keep it simple."}
  ]}},
  {"message": {"role": "assistant", "content": [
      {"type": "tool_use", "name": "AskUserQuestion", "id": "tu_002",
       "input": {"questions": [{
         "question": "MCL 9.0.0 | Düzeltilmiş spec'i onaylıyor musun?",
         "options": ["Onaylıyorum, kodu yaz", "İptal"]
       }]}}
  ]}},
  {"message": {"role": "user", "content": [
      {"type": "tool_result", "tool_use_id": "tu_002",
       "content": "Onaylıyorum, kodu yaz"}
  ]}},
]
with open(path, "w") as f:
  for e in events:
    f.write(json.dumps(e) + "\n")
PYEOF

_scan2="$(python3 "$REPO_ROOT/hooks/lib/mcl-askq-scanner.py" "$_tx" 2>/dev/null)"
_hash2="$(printf '%s' "$_scan2" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("spec_hash",""))')"

if [ -n "$_hash2" ]; then
  PASS=$((PASS+1))
  printf '  PASS: 📋 Spec (revised): → spec_hash computed (%s)\n' "${_hash2:0:12}"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: 📋 Spec (revised): → spec_hash empty (test10 regression)\n'
fi

cleanup_test_dir "$_sl_dir"
