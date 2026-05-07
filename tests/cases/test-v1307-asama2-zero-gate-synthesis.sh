#!/bin/bash
# v13.0.7 — Aşama 2 zero-gate synthesis.
# When current_phase=2 + summary-confirm-approve done + no precision-audit
# emit + no Faz 2 askq + no asama-2-complete → synthesize precision-audit
# (core_gates=0, stack_gates=0) and let universal loop auto-emit
# asama-2-complete + advance to phase 3.

echo "--- test-v1307-asama2-zero-gate-synthesis ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

_GATE_SPEC="$REPO_ROOT/skills/my-claude-lang/gate-spec.json"
_STOP_HOOK="$REPO_ROOT/hooks/mcl-stop.sh"

_a2_state() {
  local phase="$1"
  cat > "$_dir/.mcl/state.json" <<JSON
{"schema_version":3,"current_phase":${phase},"phase_name":"PRECISION_AUDIT","spec_approved":false,"spec_hash":null,"plugin_gate_active":false,"plugin_gate_missing":[],"ui_flow_active":false,"ui_sub_phase":null,"ui_build_hash":null,"ui_reviewed":false,"scope_paths":[],"pattern_scan_due":false,"pattern_files":[],"pattern_summary":null,"pattern_level":null}
JSON
}

_run_stop() {
  local transcript="$1"
  echo "{\"transcript_path\":\"${transcript}\",\"stop_hook_active\":false}" | \
    CLAUDE_PROJECT_DIR="$_dir" MCL_STATE_DIR="$_dir/.mcl" \
    MCL_GATE_SPEC="$_GATE_SPEC" \
    bash "$_STOP_HOOK" 2>/dev/null > /dev/null
}

_phase() {
  cat "$_dir/.mcl/state.json" | python3 -c "import json,sys;print(json.load(sys.stdin)['current_phase'])"
}

_audit_has() {
  grep -qE "$1" "$_dir/.mcl/audit.log"
}

_assert() {
  local label="$1" cond="$2"
  if [ "$cond" = "true" ]; then
    PASS=$((PASS+1)); printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$label"
  fi
}

_reset() {
  echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t1307" > "$_dir/.mcl/trace.log"
  : > "$_dir/.mcl/audit.log"
}

# ════════ T1: classic synthesis path → emit + advance to 3 ════════
_a2_state 2
_reset
echo "2026-05-07T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All dimensions silent-assume"}]}}
EOF
_run_stop "$_dir/transcript.jsonl"
_assert "T1: phase advanced 2→3" "$([ "$(_phase)" = "3" ] && echo true || echo false)"
_assert "T1: synthesized precision-audit emitted" "$(_audit_has 'precision-audit \| stop-auto.*synthesized=true' && echo true || echo false)"
_assert "T1: asama-2-complete emitted by universal loop" "$(_audit_has 'asama-2-complete \| stop-auto' && echo true || echo false)"
_assert "T1: asama-2-zero-gate-synthesis trail audit" "$(_audit_has 'asama-2-zero-gate-synthesis' && echo true || echo false)"

# ════════ T2: precision-audit ALREADY emitted by model → no synthesis ════════
_a2_state 2
_reset
echo "2026-05-07T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
echo "2026-05-07T10:00:02Z | precision-audit | model | core_gates=2 stack_gates=1 assumes=4 skipmarks=0" >> "$_dir/.mcl/audit.log"
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"emitted audit"}]}}
EOF
_run_stop "$_dir/transcript.jsonl"
_assert "T2: model emitted precision-audit (gates>0) → no synth" "$(! grep -qE 'asama-2-zero-gate-synthesis' "$_dir/.mcl/audit.log" && echo true || echo false)"

# ════════ T3: model asked Faz 2 askq this turn → no synthesis ════════
_a2_state 2
_reset
echo "2026-05-07T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","input":{"question":"MCL 13.0.7 | Faz 2 — Auth modeli:","options":[]}}]}}
EOF
_run_stop "$_dir/transcript.jsonl"
_assert "T3: Faz 2 askq this turn → no synth (model asking GATE)" "$(! grep -qE 'asama-2-zero-gate-synthesis' "$_dir/.mcl/audit.log" && echo true || echo false)"

# ════════ T4: NOT phase 2 (e.g., phase 1) → synth dormant ════════
_a2_state 1
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"phase 1"}]}}
EOF
_run_stop "$_dir/transcript.jsonl"
_assert "T4: phase=1 → synth doesn't fire" "$(! grep -qE 'asama-2-zero-gate-synthesis' "$_dir/.mcl/audit.log" && echo true || echo false)"

# ════════ T5: phase 2 but summary-confirm-approve missing → no synth ════════
_a2_state 2
_reset
# NO summary-confirm-approve seeded
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"x"}]}}
EOF
_run_stop "$_dir/transcript.jsonl"
_assert "T5: phase=2 but Aşama 1 not done → no synth" "$(! grep -qE 'asama-2-zero-gate-synthesis' "$_dir/.mcl/audit.log" && echo true || echo false)"

# ════════ T6: asama-2-complete already present → no synth (idempotent) ════════
_a2_state 2
_reset
echo "2026-05-07T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
echo "2026-05-07T10:00:02Z | asama-2-complete | model | s" >> "$_dir/.mcl/audit.log"
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"already done"}]}}
EOF
_run_stop "$_dir/transcript.jsonl"
_assert "T6: asama-2-complete already present → no synth" "$(! grep -qE 'asama-2-zero-gate-synthesis' "$_dir/.mcl/audit.log" && echo true || echo false)"

# ════════ T7: English prefix 'Phase 2' askq → no synth ════════
_a2_state 2
_reset
echo "2026-05-07T10:00:01Z | summary-confirm-approve | model | s" >> "$_dir/.mcl/audit.log"
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","input":{"question":"MCL 13.0.7 | Phase 2 — Auth model:","options":[]}}]}}
EOF
_run_stop "$_dir/transcript.jsonl"
_assert "T7: Phase 2 EN askq → no synth (multilingual prefix coverage)" "$(! grep -qE 'asama-2-zero-gate-synthesis' "$_dir/.mcl/audit.log" && echo true || echo false)"

cleanup_test_dir "$_dir"
