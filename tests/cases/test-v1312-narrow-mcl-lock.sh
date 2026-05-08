#!/bin/bash
# v13.0.12 — MCL LOCK narrowed to mutating tools only.
# AskUserQuestion is the canonical state-advance channel; blocking it at
# spec_approved=false caused chicken-and-egg deadlock + 3-strike fail-open
# spirals. Layer B (line ~875) handles per-phase askq permissions.

echo "--- test-v1312-narrow-mcl-lock ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

_GATE_SPEC="$REPO_ROOT/skills/my-claude-lang/gate-spec.json"
_PRE_HOOK="$REPO_ROOT/hooks/mcl-pre-tool.sh"

_state() {
  local phase="$1" approved="$2"
  cat > "$_dir/.mcl/state.json" <<JSON
{"schema_version":3,"current_phase":${phase},"phase_name":"X","spec_approved":${approved},"spec_hash":"x","plugin_gate_active":false,"plugin_gate_missing":[],"ui_flow_active":false,"scope_paths":[],"pattern_files":[]}
JSON
}

_reset() {
  echo "2026-05-08T10:00:00Z | session_start | t | t1312" > "$_dir/.mcl/trace.log"
  : > "$_dir/.mcl/audit.log"
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

_assert() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS+1)); printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '  FAIL: %s\n         expected=%s actual=%s\n' "$label" "$expected" "$actual"
  fi
}

# ════════ T1: Aşama 1 + AskUserQuestion + spec_approved=false → ALLOW (chicken-and-egg fixed) ════════
_state 1 false
_reset
out="$(_run_pre '{"tool_name":"AskUserQuestion","tool_input":{"question":"MCL 13.0.12 | Faz 1 — Niyet özeti onayı","options":[]}}')"
if [ "$(_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T1: Aşama 1 + askq + spec_approved=false → not denied (chicken-and-egg fixed)\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T1: askq still denied at Aşama 1 — chicken-and-egg regression\n'
fi

# ════════ T2: Aşama 1 + Write + spec_approved=false → DENY (mutating tool MCL LOCK still active) ════════
out="$(_run_pre '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.js","content":"x"}}')"
_assert "T2: Aşama 1 + Write + spec_approved=false → deny" "$(_decision "$out")" "deny"

# ════════ T3: Aşama 1 + Edit + spec_approved=false → DENY ════════
out="$(_run_pre '{"tool_name":"Edit","tool_input":{"file_path":"/p/foo.js","old_string":"a","new_string":"b"}}')"
_assert "T3: Aşama 1 + Edit + spec_approved=false → deny" "$(_decision "$out")" "deny"

# ════════ T4: Aşama 1 + MultiEdit + spec_approved=false → DENY ════════
out="$(_run_pre '{"tool_name":"MultiEdit","tool_input":{"file_path":"/p/foo.js","edits":[]}}')"
_assert "T4: Aşama 1 + MultiEdit + spec_approved=false → deny" "$(_decision "$out")" "deny"

# ════════ T5: Aşama 9 (post-spec-approval) + AskUserQuestion → Layer B DENY (askq not in allowed_tools) ════════
_state 9 true
_reset
echo "2026-05-08T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
echo "2026-05-08T10:00:02Z | asama-2-complete | model | s" >> "$_dir/.mcl/audit.log"
out="$(_run_pre '{"tool_name":"AskUserQuestion","tool_input":{"question":"random","options":[]}}')"
_assert "T5: Aşama 9 + askq + spec_approved=true → Layer B deny" "$(_decision "$out")" "deny"

# ════════ T6: Aşama 10 (Risk Review) + AskUserQuestion → ALLOW (Layer B allows askq for Aşama 10) ════════
_state 10 true
_reset
echo "2026-05-08T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
echo "2026-05-08T10:00:02Z | asama-2-complete | model | s" >> "$_dir/.mcl/audit.log"
out="$(_run_pre '{"tool_name":"AskUserQuestion","tool_input":{"question":"risk q","options":[]}}')"
if [ "$(_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T6: Aşama 10 + askq → allow (Layer B permits askq at Aşama 10)\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T6: Aşama 10 askq unexpectedly denied\n'
fi

# ════════ T7: Aşama 2 + AskUserQuestion + spec_approved=false → ALLOW (precision-audit closing askq) ════════
_state 2 false
_reset
echo "2026-05-08T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
out="$(_run_pre '{"tool_name":"AskUserQuestion","tool_input":{"question":"MCL 13.0.12 | Faz 2 — Precision-audit niyet onayı","options":[]}}')"
if [ "$(_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T7: Aşama 2 + askq + spec_approved=false → allow (closing askq permitted)\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T7: Aşama 2 askq blocked — chicken-and-egg in precision audit phase\n'
fi

cleanup_test_dir "$_dir"
