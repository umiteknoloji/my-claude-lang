#!/bin/bash
# v13.0.13 — Runtime / devtime REASON ayrımı.
# Kullanıcının projesinde (runtime) kısa Türkçe mesaj; MCL repo'sunda
# (devtime) tam İngilizce debug metni.

echo "--- test-v1313-runtime-reason ---"

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
  echo "2026-05-08T10:00:00Z | session_start | t | t1313" > "$_dir/.mcl/trace.log"
  : > "$_dir/.mcl/audit.log"
}

# Run with explicit DEVTIME / RUNTIME mode (override default test env)
_run_pre_runtime() {
  printf '%s' "$1" | \
    MCL_DEVTIME= \
    CLAUDE_PROJECT_DIR="$_dir" MCL_STATE_DIR="$_dir/.mcl" \
    MCL_GATE_SPEC="$_GATE_SPEC" \
    bash "$_PRE_HOOK" 2>/dev/null
}

_run_pre_devtime() {
  printf '%s' "$1" | \
    MCL_DEVTIME=1 \
    CLAUDE_PROJECT_DIR="$_dir" MCL_STATE_DIR="$_dir/.mcl" \
    MCL_GATE_SPEC="$_GATE_SPEC" \
    bash "$_PRE_HOOK" 2>/dev/null
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

_assert_contains() {
  local label="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    PASS=$((PASS+1)); printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '  FAIL: %s\n         needle: %s\n' "$label" "$needle"
  fi
}

_assert_not_contains() {
  local label="$1" hay="$2" needle="$3"
  if [[ "$hay" != *"$needle"* ]]; then
    PASS=$((PASS+1)); printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '  FAIL: %s\n         unexpected: %s\n' "$label" "$needle"
  fi
}

# ════════ T1: MCL LOCK runtime — kısa Türkçe ════════
_state 1 false
_reset
out="$(_run_pre_runtime '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.js","content":"x"}}')"
reason="$(_extract_reason "$out")"
_assert_contains "T1: runtime → 'Önce spec onayı gerekli'" "$reason" "Önce spec onayı gerekli"
_assert_not_contains "T1: runtime → 'Sirayla yap: (1) Asama 1' uzun debug DEĞİL" "$reason" "Sirayla yap: (1) Asama 1 — gelistiricinin"
if [ "${#reason}" -lt 250 ] 2>/dev/null; then
  PASS=$((PASS+1)); printf '  PASS: T1: runtime REASON kısa (%s char < 250)\n' "${#reason}"
else
  FAIL=$((FAIL+1)); printf '  FAIL: T1: runtime REASON uzun (%s char)\n' "${#reason}"
fi

# ════════ T2: MCL LOCK devtime — uzun debug ════════
out="$(_run_pre_devtime '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.js","content":"x"}}')"
reason="$(_extract_reason "$out")"
_assert_contains "T2: devtime → 'Sirayla yap: (1) Asama 1' uzun debug" "$reason" "Sirayla yap: (1) Asama 1 — gelistiricinin"
if [ "${#reason}" -gt 500 ] 2>/dev/null; then
  PASS=$((PASS+1)); printf '  PASS: T2: devtime REASON uzun (%s char > 500)\n' "${#reason}"
else
  FAIL=$((FAIL+1)); printf '  FAIL: T2: devtime REASON kısa (%s char)\n' "${#reason}"
fi

# ════════ T3: Phase Allowlist runtime — kısa ════════
_state 9 true
_reset
echo "2026-05-08T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
echo "2026-05-08T10:00:02Z | asama-2-complete | model | s" >> "$_dir/.mcl/audit.log"
out="$(_run_pre_runtime '{"tool_name":"AskUserQuestion","tool_input":{"question":"random","options":[]}}')"
reason="$(_extract_reason "$out")"
_assert_contains "T3: runtime phase-allowlist → 'aracı kullanılamaz'" "$reason" "aracı kullanılamaz"
_assert_not_contains "T3: runtime → 'Layer B STRICT' devtime detail YOK" "$reason" "Layer B STRICT"

# ════════ T4: Phase Allowlist devtime — uzun ════════
out="$(_run_pre_devtime '{"tool_name":"AskUserQuestion","tool_input":{"question":"random","options":[]}}')"
reason="$(_extract_reason "$out")"
_assert_contains "T4: devtime phase-allowlist → 'Layer B STRICT'" "$reason" "Layer B STRICT"
_assert_contains "T4: devtime → 'gate-spec.json'" "$reason" "gate-spec.json"

# ════════ T5: Path-lock runtime — kısa ════════
_state 6 true
_reset
echo "2026-05-08T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
echo "2026-05-08T10:00:02Z | asama-2-complete | model | s" >> "$_dir/.mcl/audit.log"
out="$(_run_pre_runtime '{"tool_name":"Edit","tool_input":{"file_path":"src/api/foo.js","old_string":"a","new_string":"b"}}')"
reason="$(_extract_reason "$out")"
_assert_contains "T5: runtime path-lock → 'backend yollarına yazmaz'" "$reason" "backend yollarına yazmaz"

# ════════ T6: _mcl_is_devtime helper — MCL repo path ════════
v="$(CLAUDE_PROJECT_DIR=/Users/umitduman/my-claude-lang \
  bash -c "source $REPO_ROOT/hooks/lib/mcl-state.sh; _mcl_is_devtime && echo 'devtime' || echo 'runtime'")"
_assert_contains "T6: CLAUDE_PROJECT_DIR=*my-claude-lang* → devtime" "$v" "devtime"

# ════════ T7: _mcl_is_devtime helper — runtime path ════════
v="$(CLAUDE_PROJECT_DIR=/tmp/onuc MCL_DEVTIME= \
  bash -c "source $REPO_ROOT/hooks/lib/mcl-state.sh; _mcl_is_devtime && echo 'devtime' || echo 'runtime'")"
_assert_contains "T7: CLAUDE_PROJECT_DIR=/tmp/onuc → runtime" "$v" "runtime"

# ════════ T8: MCL_DEVTIME=1 env override ════════
v="$(CLAUDE_PROJECT_DIR=/tmp/onuc MCL_DEVTIME=1 \
  bash -c "source $REPO_ROOT/hooks/lib/mcl-state.sh; _mcl_is_devtime && echo 'devtime' || echo 'runtime'")"
_assert_contains "T8: MCL_DEVTIME=1 override → devtime" "$v" "devtime"

cleanup_test_dir "$_dir"
