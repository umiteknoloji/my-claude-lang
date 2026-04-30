#!/bin/bash
# Test: state lives at MCL_STATE_DIR (the per-project location), NOT in
# CLAUDE_PROJECT_DIR/.mcl/. The mcl-claude wrapper resolves
# MCL_STATE_DIR=~/.mcl/projects/<sha1-of-cwd>/state/ and exports it.
#
# This test exercises the hook layer directly with an explicit
# MCL_STATE_DIR pointing at a temp dir, and asserts:
#   1. State file is created at $MCL_STATE_DIR/state.json
#   2. CLAUDE_PROJECT_DIR/.mcl/ is NOT touched
#   3. Audit + trace logs follow MCL_STATE_DIR

echo "--- test-state-path-isolation ---"

_si_proj="$(mktemp -d)"
_si_state="$(mktemp -d)/state"
mkdir -p "$_si_state"

# Run activate hook with explicit MCL_STATE_DIR.
_si_payload="{\"prompt\":\"build it\",\"session_id\":\"si\",\"cwd\":\"${_si_proj}\"}"
printf '%s' "$_si_payload" \
  | CLAUDE_PROJECT_DIR="$_si_proj" \
    MCL_STATE_DIR="$_si_state" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-activate.sh" >/dev/null 2>&1

# State should be at $MCL_STATE_DIR/state.json.
if [ -f "$_si_state/state.json" ]; then
  PASS=$((PASS+1))
  printf '  PASS: state.json created at MCL_STATE_DIR (%s)\n' "$_si_state"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: state.json missing at MCL_STATE_DIR\n'
  ls -la "$_si_state" 2>&1 | head -5
fi

# CLAUDE_PROJECT_DIR/.mcl/ must NOT be created.
if [ -d "$_si_proj/.mcl" ]; then
  FAIL=$((FAIL+1))
  printf '  FAIL: $CLAUDE_PROJECT_DIR/.mcl/ created (state leaked into project)\n'
  ls -la "$_si_proj/.mcl"
else
  PASS=$((PASS+1))
  printf '  PASS: $CLAUDE_PROJECT_DIR/.mcl/ not created (per-project isolation honored)\n'
fi

# Stop hook also writes to MCL_STATE_DIR.
_si_t="$_si_proj/t.jsonl"
python3 "$REPO_ROOT/tests/lib/build-transcript.py" "$_si_t" spec-correct "Test"
printf '%s' "{\"transcript_path\":\"${_si_t}\",\"session_id\":\"si\",\"cwd\":\"${_si_proj}\"}" \
  | CLAUDE_PROJECT_DIR="$_si_proj" \
    MCL_STATE_DIR="$_si_state" \
    MCL_REPO_PATH="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/mcl-stop.sh" >/dev/null 2>&1

if [ -f "$_si_state/audit.log" ]; then
  PASS=$((PASS+1))
  printf '  PASS: audit.log written to MCL_STATE_DIR\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: audit.log not at MCL_STATE_DIR\n'
fi

if [ ! -f "$_si_proj/.mcl/audit.log" ]; then
  PASS=$((PASS+1))
  printf '  PASS: audit.log not in $CLAUDE_PROJECT_DIR/.mcl/\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: audit.log leaked into $CLAUDE_PROJECT_DIR/.mcl/\n'
fi

# Cleanup.
rm -rf "$_si_proj" "$_si_state"
