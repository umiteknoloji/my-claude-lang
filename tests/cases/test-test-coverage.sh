#!/bin/bash
# Test: hooks/lib/mcl-test-coverage.py — manifest scan + finding rules.
#
# Validates that the test-coverage helper:
#   - Detects unit/integration/e2e/load frameworks from manifests
#   - Surfaces TST-T01 only when source code exists but no unit framework
#   - TST-T02 always when integration framework absent
#   - TST-T03 only when ui_flow_active=true AND e2e missing
#   - TST-T04 only when backend stack + production deployment + no load tool
#   - Returns valid JSON shape on every input

echo "--- test-test-coverage ---"

_tc_helper="$REPO_ROOT/hooks/lib/mcl-test-coverage.py"
if [ ! -f "$_tc_helper" ]; then
  skip_test "test-coverage" "helper missing"
  return 0 2>/dev/null || true
fi

# Helper: run helper with optional args and echo stdout JSON.
_tc_run() {
  python3 "$_tc_helper" "$@"
}

# Helper: extract a top-level field from result JSON.
_tc_field() {
  local json="$1" field="$2"
  printf '%s' "$json" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read() or '{}')
v = d.get(sys.argv[1])
print('null' if v is None else json.dumps(v))
" "$field"
}

# Helper: count findings whose rule_id matches a regex.
_tc_count_rule() {
  local json="$1" pattern="$2"
  printf '%s' "$json" | python3 -c "
import json, re, sys
d = json.loads(sys.stdin.read() or '{}')
n = sum(1 for f in d.get('findings', []) if re.match(sys.argv[1], f.get('rule_id', '')))
print(n)
" "$pattern"
}

# ---- Test 1: empty project (no source, no manifests) ----
_tc_p1="$(mktemp -d)"
_tc_out1="$(_tc_run --project-dir "$_tc_p1")"
assert_json_valid "empty project → valid JSON" "$_tc_out1"
_tc_t1_count="$(_tc_count_rule "$_tc_out1" '^TST-T01$')"
assert_equals "no source → no TST-T01 (HIGH unit-missing not raised)" "$_tc_t1_count" "0"
rm -rf "$_tc_p1"

# ---- Test 2: source code present, no test framework → TST-T01 HIGH ----
_tc_p2="$(mktemp -d)"
mkdir -p "$_tc_p2/src"
printf 'function add(a,b){return a+b}\n' > "$_tc_p2/src/util.ts"
printf '%s\n' '{"name":"x"}' > "$_tc_p2/package.json"  # no test deps
_tc_out2="$(_tc_run --project-dir "$_tc_p2")"
_tc_t1_count2="$(_tc_count_rule "$_tc_out2" '^TST-T01$')"
assert_equals "source + no unit framework → TST-T01 raised" "$_tc_t1_count2" "1"
rm -rf "$_tc_p2"

# ---- Test 3: vitest in deps → unit category present, no TST-T01 ----
_tc_p3="$(mktemp -d)"
mkdir -p "$_tc_p3/src"
printf 'export const x = 1;\n' > "$_tc_p3/src/util.ts"
printf '%s\n' '{"name":"x","devDependencies":{"vitest":"^1.0.0"}}' > "$_tc_p3/package.json"
_tc_out3="$(_tc_run --project-dir "$_tc_p3")"
_tc_t1_count3="$(_tc_count_rule "$_tc_out3" '^TST-T01$')"
assert_equals "vitest detected → no TST-T01" "$_tc_t1_count3" "0"
_tc_present3="$(_tc_field "$_tc_out3" categories_present)"
assert_contains "vitest detected → unit in categories_present" "$_tc_present3" "unit"
rm -rf "$_tc_p3"

# ---- Test 4: ui_flow_active=true + no e2e → TST-T03 ----
_tc_p4="$(mktemp -d)"
printf '%s\n' '{"name":"x","devDependencies":{"vitest":"^1.0.0"}}' > "$_tc_p4/package.json"
_tc_out4="$(_tc_run --project-dir "$_tc_p4" --ui-flow-active true)"
_tc_t3_count4="$(_tc_count_rule "$_tc_out4" '^TST-T03$')"
assert_equals "ui_flow_active + no e2e → TST-T03 raised" "$_tc_t3_count4" "1"
rm -rf "$_tc_p4"

# ---- Test 5: ui_flow_active=true WITH playwright → no TST-T03 ----
_tc_p5="$(mktemp -d)"
printf '%s\n' '{"name":"x","devDependencies":{"vitest":"^1.0.0","@playwright/test":"^1.40.0"}}' > "$_tc_p5/package.json"
_tc_out5="$(_tc_run --project-dir "$_tc_p5" --ui-flow-active true)"
_tc_t3_count5="$(_tc_count_rule "$_tc_out5" '^TST-T03$')"
assert_equals "playwright detected → no TST-T03" "$_tc_t3_count5" "0"
rm -rf "$_tc_p5"

# ---- Test 6: TST-T04 — backend + production + no load tool ----
_tc_p6="$(mktemp -d)"
printf 'fastapi==0.100\npytest==7.4\n' > "$_tc_p6/requirements.txt"
_tc_out6="$(_tc_run --project-dir "$_tc_p6" --stack-tags "python,db-postgres" --deployment-target production)"
_tc_t4_count6="$(_tc_count_rule "$_tc_out6" '^TST-T04$')"
assert_equals "backend + prod + no load tool → TST-T04" "$_tc_t4_count6" "1"
rm -rf "$_tc_p6"

# ---- Test 7: TST-T04 negative — same project but k6 in deps ----
_tc_p7="$(mktemp -d)"
printf 'fastapi==0.100\npytest==7.4\nk6==0.1\n' > "$_tc_p7/requirements.txt"
_tc_out7="$(_tc_run --project-dir "$_tc_p7" --stack-tags "python,db-postgres" --deployment-target production)"
_tc_t4_count7="$(_tc_count_rule "$_tc_out7" '^TST-T04$')"
assert_equals "k6 detected → no TST-T04" "$_tc_t4_count7" "0"
rm -rf "$_tc_p7"

# ---- Test 8: TST-T04 negative — backend + internal-only deployment ----
_tc_p8="$(mktemp -d)"
printf 'fastapi==0.100\npytest==7.4\n' > "$_tc_p8/requirements.txt"
_tc_out8="$(_tc_run --project-dir "$_tc_p8" --stack-tags "python" --deployment-target internal)"
_tc_t4_count8="$(_tc_count_rule "$_tc_out8" '^TST-T04$')"
assert_equals "backend + internal → no TST-T04" "$_tc_t4_count8" "0"
rm -rf "$_tc_p8"

# ---- Test 9: malformed deployment-target → no TST-T04, valid JSON ----
_tc_p9="$(mktemp -d)"
_tc_out9="$(_tc_run --project-dir "$_tc_p9")"
assert_json_valid "no args other than dir → still valid JSON" "$_tc_out9"
