#!/bin/bash
# Test: hooks/lib/mcl-phase-detect.py — brief parsing + marker extraction.
#
# The helper is the deterministic fallback that lets mcl-stop.sh populate
# state fields without depending on the model invoking skill prose Bash.
# These cases pin down the contract: brief parses Task/Requirements/
# Context, stack inference matches canonical tags, marker payloads are
# JSON-decoded, fail-open behavior on bad input.

echo "--- test-phase-detect ---"

_pd_helper="$REPO_ROOT/hooks/lib/mcl-phase-detect.py"

if [ ! -f "$_pd_helper" ]; then
  skip_test "phase-detect" "helper missing"
  return 0 2>/dev/null || true
fi

# Helper to write a synthetic transcript and run the detector. Echoes
# the JSON output. Caller asserts via assert_contains / equals.
_pd_run() {
  local body_text="$1"
  local tr
  tr="$(mktemp)"
  python3 -c "
import json, sys
out = sys.argv[1]
body = sys.argv[2]
with open(out, 'w') as f:
    f.write(json.dumps({'type':'user','message':{'role':'user','content':'q'}}) + '\n')
    f.write(json.dumps({
        'type':'assistant',
        'message':{
            'role':'assistant',
            'content':[{'type':'text','text': body}]
        }
    }) + '\n')
" "$tr" "$body_text"
  python3 "$_pd_helper" "$tr"
  rm -f "$tr"
}

# Pull a single field out of the helper's JSON output. Caller passes the
# field name; we use python3 (jq is not assumed installed).
_pd_field() {
  local json="$1" field="$2"
  printf '%s' "$json" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read() or '{}')
v = d.get(sys.argv[1])
print('null' if v is None else json.dumps(v))
" "$field"
}

# ---- Test 1: empty / missing transcript → all-null shell ----

_pd_out_empty="$(python3 "$_pd_helper" /dev/null)"
assert_json_valid "empty input → valid JSON" "$_pd_out_empty"
_pd_intent_empty="$(_pd_field "$_pd_out_empty" phase1_intent)"
assert_equals "empty input → phase1_intent=null" "$_pd_intent_empty" "null"

# ---- Test 2: canonical brief — STATIC_CONTEXT format ----

_pd_brief1='<details><summary>🔄 Engineering Brief [EN]</summary>
[MCL TRANSLATOR PASS — tr → EN]
Task: render paginated admin user table with role gating
Requirements: React + FastAPI + Postgres, role=admin
Success criteria: admin sees list, non-admin 403
Context: greenfield, Docker Compose local
</details>'

_pd_out2="$(_pd_run "$_pd_brief1")"
assert_json_valid "brief STATIC_CONTEXT format → valid JSON" "$_pd_out2"

_pd_intent2="$(_pd_field "$_pd_out2" phase1_intent)"
assert_contains "brief → phase1_intent extracted" "$_pd_intent2" "render paginated admin user table"

_pd_constraints2="$(_pd_field "$_pd_out2" phase1_constraints)"
assert_contains "brief → phase1_constraints extracted" "$_pd_constraints2" "React + FastAPI + Postgres"

_pd_stack2="$(_pd_field "$_pd_out2" phase1_stack_declared)"
assert_contains "brief → stack_declared infers react-frontend" "$_pd_stack2" "react-frontend"
assert_contains "brief → stack_declared infers python (FastAPI)" "$_pd_stack2" "python"
assert_contains "brief → stack_declared infers db-postgres" "$_pd_stack2" "db-postgres"

# ---- Test 3: marker-emit (phase1-7-ops + phase1-7-perf + ui-sub-phase) ----

_pd_markers='Some prose before.

<mcl_state_emit kind="phase1-7-ops">{"deployment_target":"docker","observability_tier":"basic","test_policy":"pragmatic","doc_level":"internal"}</mcl_state_emit>

<mcl_state_emit kind="phase1-7-perf">{"budget_tier":"strict"}</mcl_state_emit>

<mcl_state_emit kind="ui-sub-phase">UI_REVIEW</mcl_state_emit>'

_pd_out3="$(_pd_run "$_pd_markers")"
assert_json_valid "markers-only → valid JSON" "$_pd_out3"

_pd_ops3="$(_pd_field "$_pd_out3" phase1_ops)"
assert_contains "marker → phase1_ops.deployment_target" "$_pd_ops3" '"deployment_target": "docker"'
assert_contains "marker → phase1_ops.observability_tier" "$_pd_ops3" '"observability_tier": "basic"'

_pd_perf3="$(_pd_field "$_pd_out3" phase1_perf)"
assert_contains "marker → phase1_perf.budget_tier" "$_pd_perf3" '"budget_tier": "strict"'

_pd_ui3="$(_pd_field "$_pd_out3" ui_sub_phase_signal)"
assert_equals "marker → ui_sub_phase_signal=UI_REVIEW" "$_pd_ui3" '"UI_REVIEW"'

# ---- Test 4: phase4-5-override accumulates into a list ----

_pd_overrides='<mcl_state_emit kind="phase4-5-override">{"rule_id":"SEC-A01","severity":"HIGH","reason":"legacy auth, scheduled rewrite"}</mcl_state_emit>
<mcl_state_emit kind="phase4-5-override">{"rule_id":"DB-N1","severity":"MEDIUM","reason":"low-volume, indexed elsewhere"}</mcl_state_emit>'

_pd_out4="$(_pd_run "$_pd_overrides")"
_pd_ovr4="$(_pd_field "$_pd_out4" phase4_5_overrides)"
assert_contains "two override markers → list with both" "$_pd_ovr4" "SEC-A01"
assert_contains "two override markers → list with both" "$_pd_ovr4" "DB-N1"

# ---- Test 5: malformed marker payload → field stays null (no crash) ----

_pd_bad='<mcl_state_emit kind="phase1-7-ops">{not valid json</mcl_state_emit>'

_pd_out5="$(_pd_run "$_pd_bad")"
assert_json_valid "malformed payload → still valid JSON envelope" "$_pd_out5"
_pd_ops5="$(_pd_field "$_pd_out5" phase1_ops)"
# Bad JSON falls back to null (helper requires dict shape).
assert_equals "malformed payload → phase1_ops null" "$_pd_ops5" "null"

# ---- Test 6: stack inference covers a wider set ----

_pd_brief2='<details><summary>🔄 Engineering Brief [EN]</summary>
Task: build a TypeScript Vue frontend talking to a Go backend
Requirements: Vue + TypeScript, Go service, MySQL database
Context: monorepo, MariaDB-compatible
</details>'
_pd_out6="$(_pd_run "$_pd_brief2")"
_pd_stack6="$(_pd_field "$_pd_out6" phase1_stack_declared)"
assert_contains "stack infers vue-frontend" "$_pd_stack6" "vue-frontend"
assert_contains "stack infers typescript" "$_pd_stack6" "typescript"
assert_contains "stack infers go" "$_pd_stack6" "go"
assert_contains "stack infers db-mysql" "$_pd_stack6" "db-mysql"

# ---- 9.1.0 modes -------------------------------------------------

# Helper: drive a specific --mode against an inline body.
_pd_run_mode() {
  local mode="$1" body_text="$2"
  local tr
  tr="$(mktemp)"
  python3 -c "
import json, sys
out = sys.argv[1]
body = sys.argv[2]
with open(out, 'w') as f:
    f.write(json.dumps({'type':'user','message':{'role':'user','content':'q'}}) + '\n')
    f.write(json.dumps({
        'type':'assistant',
        'message':{'role':'assistant','content':[{'type':'text','text': body}]}
    }) + '\n')
" "$tr" "$body_text"
  python3 "$_pd_helper" --mode="$mode" "$tr"
  rm -f "$tr"
}

# ---- Test 7: --mode=spec-markers counts [assumed:] / [unspecified:] ----

_pd_spec_body='📋 Spec:
## Objective
Build admin panel.
## MUST
- Auth required [assumed: JWT cookie]
- Audit log [assumed: append-only]
## SHOULD
- Pagination [assumed: 20/page]
## Acceptance Criteria
## Edge Cases
[unspecified: no SLA stated]
## Technical Approach
## Out of Scope'

_pd_out7="$(_pd_run_mode spec-markers "$_pd_spec_body")"
assert_json_valid "spec-markers → valid JSON" "$_pd_out7"
_pd_assumed="$(printf '%s' "$_pd_out7" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["assumed_count"])')"
assert_equals "spec-markers counts 3 [assumed:]" "$_pd_assumed" "3"
_pd_unspec="$(printf '%s' "$_pd_out7" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["unspecified_count"])')"
assert_equals "spec-markers counts 1 [unspecified:]" "$_pd_unspec" "1"

# ---- Test 8: --mode=ui-review-signal positive ----

_pd_ui_pos='UI hazır ve tarayıcıda açıldı: http://localhost:5173/admin — incele.'
_pd_out8="$(_pd_run_mode ui-review-signal "$_pd_ui_pos")"
_pd_sig8="$(printf '%s' "$_pd_out8" | python3 -c 'import json,sys; print("true" if json.loads(sys.stdin.read())["ui_review_signal"] else "false")')"
assert_equals "ui-review-signal positive (URL + prose)" "$_pd_sig8" "true"

# ---- Test 9: --mode=ui-review-signal negative (URL only, no prose) ----

_pd_ui_neg='Configured proxy at http://localhost:8080.'
_pd_out9="$(_pd_run_mode ui-review-signal "$_pd_ui_neg")"
_pd_sig9="$(printf '%s' "$_pd_out9" | python3 -c 'import json,sys; print("true" if json.loads(sys.stdin.read())["ui_review_signal"] else "false")')"
assert_equals "ui-review-signal negative (URL but no prose)" "$_pd_sig9" "false"

# ---- Test 10: --mode=phase5-verify-detected — TR header ----

_pd_p5_tr='## Doğrulama Raporu

### Spec Coverage
| Requirement | Test |'
_pd_out10="$(_pd_run_mode phase5-verify-detected "$_pd_p5_tr")"
_pd_det10="$(printf '%s' "$_pd_out10" | python3 -c 'import json,sys; print("true" if json.loads(sys.stdin.read())["phase5_verify_detected"] else "false")')"
assert_equals "phase5-verify TR header detected" "$_pd_det10" "true"

# ---- Test 11: --mode=phase5-verify-detected — EN canonical ----

_pd_p5_en='# Verification Report

This is the final summary.'
_pd_out11="$(_pd_run_mode phase5-verify-detected "$_pd_p5_en")"
_pd_det11="$(printf '%s' "$_pd_out11" | python3 -c 'import json,sys; print("true" if json.loads(sys.stdin.read())["phase5_verify_detected"] else "false")')"
assert_equals "phase5-verify EN canonical detected" "$_pd_det11" "true"

# ---- Test 12: --mode=phase5-verify-detected — no header (negative) ----

_pd_p5_no='Just code, no report header here.'
_pd_out12="$(_pd_run_mode phase5-verify-detected "$_pd_p5_no")"
_pd_det12="$(printf '%s' "$_pd_out12" | python3 -c 'import json,sys; print("true" if json.loads(sys.stdin.read())["phase5_verify_detected"] else "false")')"
assert_equals "phase5-verify no header → false" "$_pd_det12" "false"

# ---- Test 13: spec-markers when no spec block present (graceful) ----

_pd_out13="$(_pd_run_mode spec-markers "Just brief text, no spec block.")"
_pd_assumed_empty="$(printf '%s' "$_pd_out13" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["assumed_count"])')"
assert_equals "spec-markers no spec → 0 assumed" "$_pd_assumed_empty" "0"
