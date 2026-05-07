#!/bin/bash
# v13.0.9 — Layer A (active-phase view) + Layer B (phase allowlist).
# Layer C/D deferred to v13.1.

echo "--- test-v1309-active-phase-allowlist ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

_GATE_SPEC="$REPO_ROOT/skills/my-claude-lang/gate-spec.json"
_DSI_LIB="$REPO_ROOT/hooks/lib/mcl-dsi.sh"
_PRE_HOOK="$REPO_ROOT/hooks/mcl-pre-tool.sh"

_state() {
  local phase="$1" approved="$2"
  cat > "$_dir/.mcl/state.json" <<JSON
{"schema_version":3,"current_phase":${phase},"phase_name":"X","spec_approved":${approved},"spec_hash":"x","plugin_gate_active":false,"plugin_gate_missing":[],"ui_flow_active":false,"ui_sub_phase":null,"ui_build_hash":null,"ui_reviewed":false,"scope_paths":[],"pattern_scan_due":false,"pattern_files":[],"pattern_summary":null,"pattern_level":null}
JSON
}

_reset() {
  echo "2026-05-07T10:00:00Z | session_start | t | t1309" > "$_dir/.mcl/trace.log"
  : > "$_dir/.mcl/audit.log"
  echo "2026-05-07T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
  echo "2026-05-07T10:00:02Z | asama-2-complete | model | s" >> "$_dir/.mcl/audit.log"
}

_run_pre() {
  printf '%s' "$1" | \
    CLAUDE_PROJECT_DIR="$_dir" MCL_STATE_DIR="$_dir/.mcl" \
    MCL_GATE_SPEC="$_GATE_SPEC" \
    bash "$_PRE_HOOK" 2>/dev/null
}

_extract_decision() {
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

_extract_reason() {
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

# ════════ Layer A: Active phase render ════════

# T1: Active phase 6 render contains expected markers
out="$(MCL_GATE_SPEC="$_GATE_SPEC" MCL_LANG=tr \
  bash -c ". $_DSI_LIB; _mcl_dsi_render_active_phase 6")"
_assert_contains "T1: active phase 6 → 'AKTİF FAZ: Aşama 6'" "$out" "AKTİF FAZ: Aşama 6"
_assert_contains "T1: shows skill file path" "$out" "asama6-ui-build.md"
_assert_contains "T1: shows TÜM FAZLAR index" "$out" "TÜM FAZLAR"
_assert_contains "T1: marks current with ← AKTİF" "$out" "6 UI Build ← AKTİF"
_assert_contains "T1: NO MID-PIPELINE STOP RULE header" "$out" "NO MID-PIPELINE STOP RULE"

# T2: Active phase 22 → no next-phase preview (last phase)
out="$(MCL_GATE_SPEC="$_GATE_SPEC" MCL_LANG=tr \
  bash -c ". $_DSI_LIB; _mcl_dsi_render_active_phase 22")"
_assert_contains "T2: phase 22 → AKTİF FAZ: Aşama 22" "$out" "AKTİF FAZ: Aşama 22"
if [[ "$out" != *"SONRAKİ FAZ:"* ]]; then
  PASS=$((PASS+1)); printf '  PASS: T2: phase 22 → no SONRAKİ FAZ block (last phase)\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T2: phase 22 unexpectedly shows SONRAKİ FAZ\n'
fi

# T3: EN language render
out="$(MCL_GATE_SPEC="$_GATE_SPEC" MCL_LANG=en \
  bash -c ". $_DSI_LIB; _mcl_dsi_render_active_phase 6")"
_assert_contains "T3: lang=en → 'ACTIVE PHASE:'" "$out" "ACTIVE PHASE:"
_assert_contains "T3: lang=en → 'ALL PHASES:'" "$out" "ALL PHASES:"

# ════════ Layer B: Phase allowlist ════════

# T4: Aşama 9 + AskUserQuestion → DENY (askq not in allowed_tools)
_state 9 true
_reset
out="$(_run_pre '{"tool_name":"AskUserQuestion","tool_input":{"question":"random","options":[]}}')"
_assert "T4: Aşama 9 + AskUserQuestion → deny" "$(_extract_decision "$out")" "deny"
_assert_contains "T4: REASON mentions 'PHASE ALLOWLIST'" "$(_extract_reason "$out")" "PHASE ALLOWLIST"

# T5: Aşama 9 + Edit → ALLOW (Edit in allowed_tools)
out="$(_run_pre '{"tool_name":"Edit","tool_input":{"file_path":"/p/foo.js","old_string":"a","new_string":"b"}}')"
if [ "$(_extract_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T5: Aşama 9 + Edit → not denied (allowed)\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T5: Aşama 9 + Edit → unexpectedly denied\n'
fi

# T6: Aşama 6 (UI) + Edit src/api/foo.js → DENY (denied_paths)
_state 6 true
_reset
out="$(_run_pre '{"tool_name":"Edit","tool_input":{"file_path":"src/api/foo.js","old_string":"a","new_string":"b"}}')"
_assert "T6: Aşama 6 + Edit src/api/** → deny:path" "$(_extract_decision "$out")" "deny"
_assert_contains "T6: REASON mentions 'PATH-LOCK'" "$(_extract_reason "$out")" "PATH-LOCK"

# T7: Aşama 6 + Edit src/components/Button.tsx → ALLOW (frontend path)
out="$(_run_pre '{"tool_name":"Edit","tool_input":{"file_path":"src/components/Button.tsx","old_string":"a","new_string":"b"}}')"
if [ "$(_extract_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T7: Aşama 6 + frontend path → allow\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T7: Aşama 6 + frontend path → unexpectedly denied\n'
fi

# T8: Aşama 10 (Risk Review) + AskUserQuestion → ALLOW (askq in allowed_tools)
_state 10 true
_reset
out="$(_run_pre '{"tool_name":"AskUserQuestion","tool_input":{"question":"risk q","options":[]}}')"
if [ "$(_extract_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T8: Aşama 10 + AskUserQuestion → allow\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T8: Aşama 10 + AskUserQuestion → unexpectedly denied\n'
fi

# T9: Read at any phase → ALLOW (read-only global-always-allowed)
_state 9 true
_reset
out="$(_run_pre '{"tool_name":"Read","tool_input":{"file_path":"/p/foo.js"}}')"
if [ "$(_extract_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T9: Read at any phase → allow (always-allowed)\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T9: Read denied\n'
fi

# T10: Bash at any phase → ALLOW
out="$(_run_pre '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}')"
if [ "$(_extract_decision "$out")" != "deny" ]; then
  PASS=$((PASS+1)); printf '  PASS: T10: Bash at any phase → allow (always-allowed)\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T10: Bash denied\n'
fi

# ════════ Integration: activate hook output ════════

# T11: activate hook injects <mcl_active_phase_directive> block
mkdir -p "$_dir/active_smoke/.mcl"
echo '{"prompt":"x","session_id":"v1309-smoke"}' | \
  CLAUDE_PROJECT_DIR="$_dir/active_smoke" MCL_STATE_DIR="$_dir/active_smoke/.mcl" \
  MCL_GATE_SPEC="$_GATE_SPEC" \
  REPO_LIB="$REPO_ROOT/hooks/lib" \
  bash "$REPO_ROOT/hooks/mcl-activate.sh" 2>/dev/null > "$_dir/active_out.json"
ctx_size="$(python3 -c "import json; print(len(json.load(open('$_dir/active_out.json'))['hookSpecificOutput']['additionalContext']))" 2>/dev/null)"
ctx="$(python3 -c "import json; print(json.load(open('$_dir/active_out.json'))['hookSpecificOutput']['additionalContext'])" 2>/dev/null)"
_assert_contains "T11: activate output has <mcl_active_phase_directive>" "$ctx" "mcl_active_phase_directive"
_assert_contains "T11: activate output has DİNAMİK FAZ DİREKTİFİ pointer" "$ctx" "DİNAMİK FAZ DİREKTİFİ"
if [ -n "$ctx_size" ] && [ "$ctx_size" -lt 55000 ] 2>/dev/null; then
  PASS=$((PASS+1)); printf '  PASS: T11: prompt size %s < 55000 chars (attention-decay improved)\n' "$ctx_size"
else
  FAIL=$((FAIL+1)); printf '  FAIL: T11: prompt size %s >= 55000 (regression)\n' "$ctx_size"
fi

cleanup_test_dir "$_dir"
