#!/bin/bash
# v13.0.5 — 3-layer pre-hoc deterministic enforcement.
# L1: MCL LOCK enriched with Aşama 1 directive when audit is empty
# L2: AskUserQuestion @ Aşama 4 spec-approval requires precision-audit
# L3: DSI loud forbidden-list mode when phase=1 + no audit

echo "--- test-v1305-deterministic-gates ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

_PRE_HOOK="$REPO_ROOT/hooks/mcl-pre-tool.sh"
_DSI_LIB="$REPO_ROOT/hooks/lib/mcl-dsi.sh"
_GATE_SPEC="$REPO_ROOT/skills/my-claude-lang/gate-spec.json"

_run_pre() {
  local input="$1"
  printf '%s' "$input" | \
    CLAUDE_PROJECT_DIR="$_dir" MCL_STATE_DIR="$_dir/.mcl" \
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

_assert_contains() {
  local label="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    PASS=$((PASS+1)); printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '  FAIL: %s\n         needle: %s\n' "$label" "$needle"
  fi
}

_state_v13() {
  local phase="$1" approved="$2"
  cat > "$_dir/.mcl/state.json" <<JSON
{"schema_version":3,"current_phase":${phase},"phase_name":"GATHER","spec_approved":${approved},"plugin_gate_active":false,"plugin_gate_missing":[],"ui_flow_active":false,"ui_sub_phase":null,"ui_build_hash":null,"ui_reviewed":false,"scope_paths":[],"pattern_scan_due":false,"pattern_files":[],"pattern_summary":null,"pattern_level":null}
JSON
}

# ════════ L1: MCL LOCK enrichment ════════
# T1.1: empty audit + Write → enriched message with Aşama 1 directive
_state_v13 1 false
echo "2026-05-07T10:00:00Z | session_start | t | t1305-1" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"
out="$(_run_pre '{"tool_name":"Write","tool_input":{"file_path":"/p/x","content":"y"}}')"
reason="$(_extract_reason "$out")"
_assert_contains "L1.1: empty audit Write → MCL LOCK fires" "$(_extract_decision "$out")" "deny"
_assert_contains "L1.1: empty audit → directive 'yeni oturum'" "$reason" "yeni oturum, hicbir Asama 1-4 audit"
_assert_contains "L1.1: empty audit → 'Sirayla yap: (1) Asama 1'" "$reason" "Sirayla yap: (1) Asama 1"

# T1.2: with summary-confirm-approve, Write → fallback to original recovery message
echo "2026-05-07T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
out="$(_run_pre '{"tool_name":"Write","tool_input":{"file_path":"/p/x","content":"y"}}')"
reason="$(_extract_reason "$out")"
_assert_contains "L1.2: A1 audit present → original 'Recovery options: (A)' message (backward compat)" "$reason" "Recovery options: (A) re-emit AskUserQuestion"

# T1.3: with precision-audit (no asama-1 explicit), Write → still original recovery (precision is A1+ marker)
: > "$_dir/.mcl/audit.log"
echo "2026-05-07T10:00:01Z | precision-audit | mcl-stop | g=2" >> "$_dir/.mcl/audit.log"
out="$(_run_pre '{"tool_name":"Write","tool_input":{"file_path":"/p/x","content":"y"}}')"
reason="$(_extract_reason "$out")"
_assert_contains "L1.3: precision-audit present → fallback recovery (transitive A1)" "$reason" "Recovery options: (A) re-emit"

# ════════ L2: Aşama 4 askq gate ════════
# T2.1: Faz 4 spec-approval askq w/o precision-audit → block
_state_v13 4 false
echo "2026-05-07T10:00:00Z | session_start | t | t1305-2" > "$_dir/.mcl/trace.log"
: > "$_dir/.mcl/audit.log"
echo "2026-05-07T10:00:01Z | asama-1-question-1 | model | q=intent" >> "$_dir/.mcl/audit.log"
askq_input='{"tool_name":"AskUserQuestion","tool_input":{"question":"MCL 13.0.5 | Faz 4 — spec onayı:","options":[]}}'
out="$(_run_pre "$askq_input")"
_assert_contains "L2.1: Faz 4 askq w/o precision → 'block' decision" "$(_extract_decision "$out")" "block"
reason="$(_extract_reason "$out")"
_assert_contains "L2.1: Faz 4 askq w/o precision → 'ASAMA 4 ASKQ GATE' reason" "$reason" "ASAMA 4 ASKQ GATE"
_assert_contains "L2.1: Faz 4 askq w/o precision → mentions 'asama-2-complete'" "$reason" "asama-2-complete"

# T2.2: Faz 4 askq WITH asama-2-complete → bypass L2 gate
echo "2026-05-07T10:00:02Z | asama-2-complete | mcl-stop | s=Onayla" >> "$_dir/.mcl/audit.log"
out="$(_run_pre "$askq_input")"
reason="$(_extract_reason "$out")"
if [[ "$reason" != *"ASAMA 4 ASKQ GATE"* ]]; then
  PASS=$((PASS+1)); printf '  PASS: L2.2: Faz 4 askq WITH precision → L2 gate bypassed\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: L2.2: Faz 4 askq WITH precision → L2 gate STILL FIRED\n'
fi

# T2.3: Faz 7 askq (UI review) → L2 gate doesn't fire
askq_f7='{"tool_name":"AskUserQuestion","tool_input":{"question":"MCL 13.0.5 | Faz 7 — UI onayı:","options":[]}}'
: > "$_dir/.mcl/audit.log"
out="$(_run_pre "$askq_f7")"
reason="$(_extract_reason "$out")"
if [[ "$reason" != *"ASAMA 4 ASKQ GATE"* ]]; then
  PASS=$((PASS+1)); printf '  PASS: L2.3: Faz 7 askq → L2 gate ignores (only Faz 4 caught)\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: L2.3: Faz 7 askq → L2 gate INCORRECTLY FIRED\n'
fi

# T2.4: Faz 4 askq, English label "Phase 4" → block (multilingual prefix coverage)
askq_phase4='{"tool_name":"AskUserQuestion","tool_input":{"question":"MCL 13.0.5 | Phase 4 — spec approval:","options":[]}}'
: > "$_dir/.mcl/audit.log"
out="$(_run_pre "$askq_phase4")"
_assert_contains "L2.4: 'Phase 4' EN prefix → also blocks" "$(_extract_decision "$out")" "block"

# ════════ L3: DSI loud Aşama 1 mode ════════
_dir2="$(setup_test_dir)"
mkdir -p "$_dir2/.mcl"
echo "2026-05-07T10:00:00Z | session_start | t | t1305-3" > "$_dir2/.mcl/trace.log"
: > "$_dir2/.mcl/audit.log"
out="$(MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir2/.mcl" MCL_LANG=tr \
  bash -c ". $_DSI_LIB; _mcl_dsi_render 1")"
_assert_contains "L3.1: empty audit phase=1 TR → loud '⛔ ASAMA 1 ZORUNLU'" "$out" "ASAMA 1 ZORUNLU"
_assert_contains "L3.1: empty audit phase=1 TR → 'YASAK: Spec yazma'" "$out" "YASAK: Spec yazma"

# T3.2: with Aşama 1 audit, phase=1 → normal minimal mode
echo "2026-05-07T10:00:01Z | asama-1-question-1 | model | q=test" >> "$_dir2/.mcl/audit.log"
out="$(MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir2/.mcl" MCL_LANG=tr \
  bash -c ". $_DSI_LIB; _mcl_dsi_render 1")"
if [[ "$out" != *"ASAMA 1 ZORUNLU"* ]]; then
  PASS=$((PASS+1)); printf '  PASS: L3.2: A1 audit present → loud mode OFF\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: L3.2: A1 audit present → loud mode STILL ON\n'
fi
_assert_contains "L3.2: minimal mode shows 'summary-confirm-approve'" "$out" "summary-confirm-approve"

# T3.3: empty audit phase=2 (mid-flow) → minimal mode (loud only on phase=1)
_dir3="$(setup_test_dir)"
mkdir -p "$_dir3/.mcl"
echo "2026-05-07T10:00:00Z | session_start | t | t1305-3b" > "$_dir3/.mcl/trace.log"
: > "$_dir3/.mcl/audit.log"
out="$(MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir3/.mcl" MCL_LANG=tr \
  bash -c ". $_DSI_LIB; _mcl_dsi_render 2")"
if [[ "$out" != *"ASAMA 1 ZORUNLU"* ]]; then
  PASS=$((PASS+1)); printf '  PASS: L3.3: phase=2 empty audit → loud A1 mode does NOT fire\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: L3.3: phase=2 → A1 loud mode incorrectly fired\n'
fi

# T3.4: EN loud variant
_dir4="$(setup_test_dir)"
mkdir -p "$_dir4/.mcl"
echo "2026-05-07T10:00:00Z | session_start | t | t1305-3c" > "$_dir4/.mcl/trace.log"
: > "$_dir4/.mcl/audit.log"
out="$(MCL_GATE_SPEC="$_GATE_SPEC" MCL_STATE_DIR="$_dir4/.mcl" MCL_LANG=en \
  bash -c ". $_DSI_LIB; _mcl_dsi_render 1")"
_assert_contains "L3.4: EN loud → 'ASAMA 1 MANDATORY'" "$out" "ASAMA 1 MANDATORY"
_assert_contains "L3.4: EN loud → 'FORBIDDEN: emitting a spec'" "$out" "FORBIDDEN: emitting a spec"

cleanup_test_dir "$_dir"
cleanup_test_dir "$_dir2"
cleanup_test_dir "$_dir3"
cleanup_test_dir "$_dir4"
