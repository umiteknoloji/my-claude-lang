#!/bin/bash
# Synthetic test: v10.1.9 — askq scanner inline-spec fallback hash.
# When the model embeds spec content in the askq question body
# (no separate `📋 Spec:` block in assistant text), classifier
# correctly identifies spec-approve intent but spec_hash was empty
# under v10.1.8 → JIT askq advance refused to fire → user lockout
# despite correct classification. v10.1.9 falls back to hashing the
# question body itself with an "inline-" prefix.
#
# Driven by real-world v10.1.8 grom-like deployment where model
# wrote spec parameters as bullets inside the AskUserQuestion
# question rather than emitting a preceding 📋 Spec: block.

echo "--- test-v10-1-9-inline-spec-fallback ---"

_dir="$(setup_test_dir)"
_scanner="$REPO_ROOT/hooks/lib/mcl-askq-scanner.py"

# === Case 1: spec block PRESENT → block-derived hash (no fallback) ===
_t1="$_dir/t1.jsonl"
cat > "$_t1" <<'EOF'
{"timestamp":"2026-05-03T00:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"📋 Spec:\n<details open><summary>spec</summary>\nObjective: build X\nMUST: Y\n</details>"}]}}
{"timestamp":"2026-05-03T00:00:02Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"u1","name":"AskUserQuestion","input":{"questions":[{"question":"MCL 10.1.9 | Spec onayı?","options":["Onayla","Revize","İptal"]}]}}]}}
{"timestamp":"2026-05-03T00:00:03Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"u1","content":"Onayla"}]}}
EOF

_out1="$(python3 "$_scanner" "$_t1" 2>/dev/null)"
_intent1="$(printf '%s' "$_out1" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["intent"])')"
_hash1="$(printf '%s' "$_out1" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["spec_hash"])')"
assert_equals "spec block present → intent=spec-approve" "$_intent1" "spec-approve"

if [ -n "$_hash1" ] && [ "${_hash1#inline-}" = "$_hash1" ]; then
  PASS=$((PASS+1))
  printf '  PASS: spec block present → block-derived hash (no inline- prefix)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: expected block-derived hash, got %s\n' "$_hash1"
fi

# === Case 2: spec block ABSENT, askq carries inline spec content → fallback fires ===
_t2="$_dir/t2.jsonl"
cat > "$_t2" <<'EOF'
{"timestamp":"2026-05-03T00:00:01Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"u1","name":"AskUserQuestion","input":{"questions":[{"question":"MCL 10.1.9 | Faz 4 spec onayı: Aşağıdaki kararlarla kod yazımına geçeyim mi?\n\n• Stack: Node.js + Express\n• Auth: session-based\n• Roller: admin/yetkili/personel","options":["Onaylıyorum, kodu yaz","Revize","İptal"]}]}}]}}
{"timestamp":"2026-05-03T00:00:02Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"u1","content":"Onaylıyorum, kodu yaz"}]}}
EOF

_out2="$(python3 "$_scanner" "$_t2" 2>/dev/null)"
_intent2="$(printf '%s' "$_out2" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["intent"])')"
_hash2="$(printf '%s' "$_out2" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["spec_hash"])')"
_selected2="$(printf '%s' "$_out2" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["selected"])')"

assert_equals "inline-spec askq → intent=spec-approve" "$_intent2" "spec-approve"
assert_equals "inline-spec askq → selected=Onaylıyorum, kodu yaz" "$_selected2" "Onaylıyorum, kodu yaz"

if [ "${_hash2#inline-}" != "$_hash2" ] && [ ${#_hash2} -gt 7 ]; then
  PASS=$((PASS+1))
  printf '  PASS: inline-spec askq → spec_hash with inline- prefix (%s)\n' "$_hash2"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: expected inline- prefixed hash, got "%s"\n' "$_hash2"
fi

# === Case 3: no spec, no approve verb → other intent, no hash ===
_t3="$_dir/t3.jsonl"
cat > "$_t3" <<'EOF'
{"timestamp":"2026-05-03T00:00:01Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"u1","name":"AskUserQuestion","input":{"questions":[{"question":"MCL 10.1.9 | Hangi renk?","options":["Kırmızı","Mavi","Yeşil"]}]}}]}}
{"timestamp":"2026-05-03T00:00:02Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"u1","content":"Kırmızı"}]}}
EOF

_out3="$(python3 "$_scanner" "$_t3" 2>/dev/null)"
_intent3="$(printf '%s' "$_out3" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["intent"])')"
_hash3="$(printf '%s' "$_out3" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["spec_hash"])')"

assert_equals "non-spec, non-approve askq → intent=other" "$_intent3" "other"
assert_equals "non-spec, non-approve askq → hash empty (no fallback)" "$_hash3" ""

# === Case 4: approve verb in question body BUT no spec → summary-confirm fallback (existing behavior, unchanged) ===
_t4="$_dir/t4.jsonl"
cat > "$_t4" <<'EOF'
{"timestamp":"2026-05-03T00:00:01Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"u1","name":"AskUserQuestion","input":{"questions":[{"question":"MCL 10.1.9 | Onaylıyor musun?","options":["Onayla","İptal"]}]}}]}}
{"timestamp":"2026-05-03T00:00:02Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"u1","content":"Onayla"}]}}
EOF

_out4="$(python3 "$_scanner" "$_t4" 2>/dev/null)"
_intent4="$(printf '%s' "$_out4" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["intent"])')"
_hash4="$(printf '%s' "$_out4" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["spec_hash"])')"
assert_equals "approve verb only, no spec context → intent=summary-confirm" "$_intent4" "summary-confirm"
assert_equals "summary-confirm → spec_hash empty (no fallback for non-spec intent)" "$_hash4" ""

# === Hook contract checks ===
if grep -q "Inline-spec fallback" "$_scanner"; then
  PASS=$((PASS+1))
  printf '  PASS: scanner has inline-spec fallback comment (since v10.1.9)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: inline-spec fallback comment missing from scanner\n'
fi

if grep -q '"inline-"' "$_scanner"; then
  PASS=$((PASS+1))
  printf '  PASS: scanner uses inline- prefix for synthetic hash\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: inline- prefix missing from scanner\n'
fi

cleanup_test_dir "$_dir"
