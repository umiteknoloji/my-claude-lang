#!/bin/bash
# v13.0.10 — STRICT phase allowlist (no fail-open) + audit-derived active phase
# for legacy state.current_phase=7 sentinel.

echo "--- test-v1310-strict-allowlist-and-derive ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

_GATE_SPEC="$REPO_ROOT/skills/my-claude-lang/gate-spec.json"
_PRE_HOOK="$REPO_ROOT/hooks/mcl-pre-tool.sh"

_state() {
  local phase="$1"
  cat > "$_dir/.mcl/state.json" <<JSON
{"schema_version":3,"current_phase":${phase},"phase_name":"X","spec_approved":true,"spec_hash":"x","plugin_gate_active":false,"plugin_gate_missing":[],"ui_flow_active":false,"ui_sub_phase":null,"ui_build_hash":null,"ui_reviewed":false,"scope_paths":[],"pattern_scan_due":false,"pattern_files":[],"pattern_summary":null,"pattern_level":null}
JSON
}

_reset() {
  echo "2026-05-07T10:00:00Z | session_start | t | t1310" > "$_dir/.mcl/trace.log"
  : > "$_dir/.mcl/audit.log"
  echo "2026-05-07T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
  echo "2026-05-07T10:00:02Z | precision-audit | model | core_gates=0 stack_gates=0" >> "$_dir/.mcl/audit.log"
  echo "2026-05-07T10:00:03Z | asama-2-complete | model | s" >> "$_dir/.mcl/audit.log"
  echo "2026-05-07T10:00:04Z | engineering-brief | model | s" >> "$_dir/.mcl/audit.log"
  echo "2026-05-07T10:00:05Z | asama-3-complete | model | s" >> "$_dir/.mcl/audit.log"
  echo "2026-05-07T10:00:06Z | asama-4-complete | model | s" >> "$_dir/.mcl/audit.log"
  echo "2026-05-07T10:00:07Z | asama-4-ac-count | model | must=2 should=1" >> "$_dir/.mcl/audit.log"
}

_run_pre() {
  printf '%s' "$1" | \
    CLAUDE_PROJECT_DIR="$_dir" MCL_STATE_DIR="$_dir/.mcl" \
    MCL_GATE_SPEC="$_GATE_SPEC" \
    bash "$_PRE_HOOK" 2>/dev/null
}

_decision() {
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    out = obj.get("hookSpecificOutput") or obj
    print(out.get("permissionDecision") or out.get("decision") or "none")
except Exception:
    print("none")
' 2>/dev/null
}

_reason() {
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    out = obj.get("hookSpecificOutput") or obj
    print(out.get("permissionDecisionReason") or out.get("reason") or "")
except Exception:
    print("")
' 2>/dev/null
}

_assert() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS+1)); printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '  FAIL: %s\n         expected=%s actual=%s\n' "$label" "$expected" "$actual"
  fi
}

_assert_contains() {
  local label="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    PASS=$((PASS+1)); printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '  FAIL: %s\n         needle: %s\n' "$label" "$needle"
  fi
}

# ════════ T1: state=7 (legacy), no Aşama 5 audit → derive active=5 → Write deny ════════
_state 7
_reset
out="$(_run_pre '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.js","content":"x"}}')"
_assert "T1: state=7 + no asama-5 → derive active=5 + Write deny" "$(_decision "$out")" "deny"
_assert_contains "T1: REASON shows derived active_phase=5" "$(_reason "$out")" "Aşama 5"

# ════════ T2: state=7 + asama-5-skipped emit → derive active=6 → Write allowed (Aşama 6 has Write) ════════
_state 7
_reset
echo "2026-05-07T10:00:08Z | asama-5-skipped | model | reason=greenfield" >> "$_dir/.mcl/audit.log"
out="$(_run_pre '{"tool_name":"Write","tool_input":{"file_path":"src/components/Button.tsx","content":"x"}}')"
if [ "$(_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T2: state=7 + asama-5-skipped → derive active=6 + frontend Write allow\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T2: derived active phase 6 should allow frontend Write\n'
fi

# ════════ T3: state=7 + asama-5-skipped + Edit src/api/ → Aşama 6 denied_paths → deny ════════
out="$(_run_pre '{"tool_name":"Edit","tool_input":{"file_path":"src/api/foo.js","old_string":"a","new_string":"b"}}')"
_assert "T3: derived Aşama 6 + backend path → deny" "$(_decision "$out")" "deny"

# ════════ T4: STRICT — 6 ardışık deny, hepsi block (NO fail-open) ════════
_state 7
_reset
PASS_DENY=0
for i in 1 2 3 4 5 6; do
  out="$(_run_pre '{"tool_name":"Write","tool_input":{"file_path":"/p/x.js","content":"x"}}')"
  [ "$(_decision "$out")" = "deny" ] && PASS_DENY=$((PASS_DENY+1))
done
if [ "$PASS_DENY" -eq 6 ]; then
  PASS=$((PASS+1)); printf '  PASS: T4: 6/6 deny — STRICT mode no fail-open\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T4: STRICT mode broken — only %s/6 deny\n' "$PASS_DENY"
fi

# ════════ T5: 5+ strikes → escalation audit emitted ════════
if grep -qE 'phase-allowlist-tool-escalate' "$_dir/.mcl/audit.log"; then
  PASS=$((PASS+1)); printf '  PASS: T5: phase-allowlist-tool-escalate audit emitted after 5 strikes\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T5: escalate audit missing\n'
fi

# ════════ T6: state=9 (canonical v12+, NOT legacy 7) → use as-is, NOT derived ════════
_state 9
_reset
out="$(_run_pre '{"tool_name":"Edit","tool_input":{"file_path":"/p/foo.js","old_string":"a","new_string":"b"}}')"
if [ "$(_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T6: state=9 canonical + Edit → allow (no derive, no regress v13.0.9)\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T6: state=9 + Edit unexpectedly denied\n'
fi

# ════════ T7: state=10 + AskUserQuestion → use as-is, allow ════════
_state 10
_reset
out="$(_run_pre '{"tool_name":"AskUserQuestion","tool_input":{"question":"risk q","options":[]}}')"
if [ "$(_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T7: state=10 canonical + AskUserQuestion → allow\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T7: state=10 askq unexpectedly denied\n'
fi

# ════════ T8: activate hook surfaces escalation notice when present ════════
# Seed plugin_gate_session=v1310 so activate hook doesn't re-emit
# session_start (which would shift the boundary past our seeded audit).
cat > "$_dir/.mcl/state.json" <<JSON
{"schema_version":3,"current_phase":7,"phase_name":"X","spec_approved":true,"spec_hash":"x","plugin_gate_active":false,"plugin_gate_missing":[],"plugin_gate_session":"v1310","ui_flow_active":false,"ui_sub_phase":null,"ui_build_hash":null,"ui_reviewed":false,"scope_paths":[],"pattern_scan_due":false,"pattern_files":[],"pattern_summary":null,"pattern_level":null}
JSON
echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | v1310" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"
echo "2026-05-07T10:00:08Z | phase-allowlist-tool-escalate | pre-tool | count=5 tool=Write" >> "$_dir/.mcl/audit.log"
echo "2026-05-07T10:00:09Z | phase-allowlist-tool-block | pre-tool | tool=Write state_phase=7 active_phase=5" >> "$_dir/.mcl/audit.log"
echo '{"prompt":"x","session_id":"v1310"}' | \
  CLAUDE_PROJECT_DIR="$_dir" MCL_STATE_DIR="$_dir/.mcl" \
  MCL_GATE_SPEC="$_GATE_SPEC" \
  REPO_LIB="$REPO_ROOT/hooks/lib" \
  bash "$REPO_ROOT/hooks/mcl-activate.sh" 2>/dev/null > "$_dir/activate_out.json"
ctx="$(python3 -c "import json; print(json.load(open('$_dir/activate_out.json'))['hookSpecificOutput']['additionalContext'])" 2>/dev/null)"
_assert_contains "T8: escalation notice in activate output" "$ctx" "PHASE ALLOWLIST ESCALATION"

cleanup_test_dir "$_dir"
