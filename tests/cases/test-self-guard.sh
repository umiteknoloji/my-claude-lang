#!/bin/bash
# Test: when CLAUDE_PROJECT_DIR points to the MCL repo, hook exits with
# empty additionalContext (MCL does not wrap its own source tree).

echo "--- test-self-guard ---"

_sg_payload="{\"prompt\":\"Build something\",\"session_id\":\"test-guard\",\"cwd\":\"${REPO_ROOT}\"}"

_out="$(
  printf '%s' "$_sg_payload" \
    | CLAUDE_PROJECT_DIR="$REPO_ROOT" \
      MCL_REPO_PATH="$REPO_ROOT" \
      bash "$REPO_ROOT/hooks/mcl-activate.sh" 2>/dev/null
)"

assert_json_valid "self-guard → valid JSON"              "$_out"
assert_contains   "self-guard → empty additionalContext" "$_out" '"additionalContext":""'
