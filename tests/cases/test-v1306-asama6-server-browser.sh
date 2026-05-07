#!/bin/bash
# v13.0.6 — Aşama 6 server-without-browser STRICT lens.
# Real-world failure: model runs `npm run dev` then says "Tarayıcıyı açıyorum:"
# and stops without `open <url>`. Lens forces browser-open or asama-6 audit.

echo "--- test-v1306-asama6-server-browser ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

_STOP_HOOK="$REPO_ROOT/hooks/mcl-stop.sh"

_a6_state() {
  local phase="$1" sub="$2"
  cat > "$_dir/.mcl/state.json" <<JSON
{"schema_version":3,"current_phase":${phase},"phase_name":"BUILD_UI","spec_approved":true,"spec_hash":"x","plugin_gate_active":false,"plugin_gate_missing":[],"ui_flow_active":true,"ui_sub_phase":"${sub}","ui_build_hash":"x","ui_reviewed":false,"scope_paths":[],"pattern_scan_due":false,"pattern_files":[],"pattern_summary":null,"pattern_level":null}
JSON
}

_run_stop() {
  local transcript="$1"
  echo "{\"transcript_path\":\"${transcript}\",\"stop_hook_active\":false}" | \
    CLAUDE_PROJECT_DIR="$_dir" MCL_STATE_DIR="$_dir/.mcl" \
    bash "$_STOP_HOOK" 2>/dev/null
}

_decision() {
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("decision") or "none")
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

# Reset audit + trace per test
_reset() {
  echo "2026-05-07T10:00:00Z | session_start | mcl-activate.sh | t1306" > "$_dir/.mcl/trace.log"
  : > "$_dir/.mcl/audit.log"
}

# ════════ T1: server started, no browser → block ════════
_a6_state 6 "BUILD_UI"
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"start"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"npm run dev &"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T1: npm run dev only → block" "$(_decision "$out")" "block"

# ════════ T2: server + open browser → no block ════════
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"start"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"npm run dev &"}},{"type":"tool_use","name":"Bash","input":{"command":"sleep 2 && open http://localhost:3000"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T2: npm + open → no block" "$(_decision "$out")" "none"

# ════════ T3: server in same Bash chained with open → no block ════════
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"node server.js & sleep 2 && open http://localhost:3000"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T3: chained server+open in one Bash → no block" "$(_decision "$out")" "none"

# ════════ T4: xdg-open (Linux) → no block ════════
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"flask run &"}},{"type":"tool_use","name":"Bash","input":{"command":"xdg-open http://localhost:5000"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T4: flask + xdg-open → no block" "$(_decision "$out")" "none"

# ════════ T5: asama-6-end audit emitted → bypass even if browser missing ════════
_reset
echo "2026-05-07T10:00:01Z | asama-6-end | model | server=true browser=true" >> "$_dir/.mcl/audit.log"
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"node server.js"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T5: asama-6-end audit present → no block" "$(_decision "$out")" "none"

# ════════ T6: asama-6-skipped (no UI) → bypass ════════
_reset
echo "2026-05-07T10:00:01Z | asama-6-skipped | model | reason=no-ui-flow" >> "$_dir/.mcl/audit.log"
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"npm run dev"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T6: asama-6-skipped audit → no block" "$(_decision "$out")" "none"

# ════════ T7: NOT phase 6 (e.g. phase 9 TDD) → lens dormant ════════
_a6_state 9 ""
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"npm run dev"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T7: phase=9 not Aşama 6 → lens dormant" "$(_decision "$out")" "none"

# ════════ T8: ui_sub_phase=BUILD_UI alone (legacy) → fires ════════
_a6_state 7 "BUILD_UI"
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"npm run dev &"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T8: ui_sub_phase=BUILD_UI legacy → block" "$(_decision "$out")" "block"

# ════════ T9: STRICT — repeated stops still block (no fail-open) ════════
_a6_state 6 "BUILD_UI"
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"node server.js"}}]}}
EOF
# 5 consecutive stops — must all block (strict, no loop-breaker)
_strict_pass=0
_strict_fail=0
for i in 1 2 3 4 5; do
  out="$(_run_stop "$_dir/transcript.jsonl")"
  if [ "$(_decision "$out")" = "block" ]; then
    _strict_pass=$((_strict_pass+1))
  else
    _strict_fail=$((_strict_fail+1))
  fi
done
if [ "$_strict_pass" = "5" ] && [ "$_strict_fail" = "0" ]; then
  PASS=$((PASS+1)); printf '  PASS: T9: 5 consecutive stops all block (STRICT, no loop-breaker)\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T9: strict mode — 5 stops, expected all block, got %d block %d not-block\n' "$_strict_pass" "$_strict_fail"
fi

# ════════ T10: only Bash other than server (e.g., ls) → no block ════════
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T10: ls only (no server) → no block" "$(_decision "$out")" "none"

# ════════ T11: Python flask, no browser → block ════════
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"flask run --port 5000"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T11: flask run, no browser → block" "$(_decision "$out")" "block"

# ════════ T12: pnpm dev + open chained → no block ════════
_reset
cat > "$_dir/transcript.jsonl" <<'EOF'
{"role":"user","content":"x"}
{"role":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"pnpm dev > /dev/null 2>&1 & sleep 3 && open http://localhost:5173"}}]}}
EOF
out="$(_run_stop "$_dir/transcript.jsonl")"
_assert "T12: pnpm dev + open chained → no block" "$(_decision "$out")" "none"

cleanup_test_dir "$_dir"
