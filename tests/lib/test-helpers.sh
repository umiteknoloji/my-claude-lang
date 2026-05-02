#!/bin/bash
# Shared test helpers for MCL hook-level tests.

setup_test_dir() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.mcl"
  echo "$tmp"
}

cleanup_test_dir() {
  rm -rf "$1"
}

assert_json_valid() {
  local label="$1"
  local output="$2"
  if printf '%s' "$output" | python3 -m json.tool >/dev/null 2>&1; then
    PASS=$((PASS+1))
    printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: %s — output is not valid JSON\n' "$label"
    printf '        output: %s\n' "$output"
  fi
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle" 2>/dev/null; then
    PASS=$((PASS+1))
    printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: %s\n' "$label"
    printf '        expected to find: %s\n' "$needle"
  fi
}

assert_equals() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS+1))
    printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: %s\n' "$label"
    printf '        expected: %s\n' "$expected"
    printf '        actual:   %s\n' "$actual"
  fi
}

skip_test() {
  local label="$1"
  local reason="$2"
  SKIP=$((SKIP+1))
  printf '  SKIP: %s — %s\n' "$label" "$reason"
}

# Run mcl-activate.sh with a given prompt, using an isolated project dir.
# Env vars: CLAUDE_PROJECT_DIR=project_dir, MCL_REPO_PATH=REPO_ROOT.
# pwd is changed to project_dir via subshell so hook code that reads $(pwd)
# (e.g., stack-detect, ui-capable) sees the project dir rather than the
# directory the tests were invoked from.
run_activate_hook() {
  local project_dir="$1"
  local prompt_text="$2"
  local session="${3:-mcl-test-session}"
  local encoded_prompt
  encoded_prompt="$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$prompt_text" 2>/dev/null)"
  local payload="{\"prompt\":${encoded_prompt},\"session_id\":\"${session}\",\"cwd\":\"${project_dir}\"}"
  (
    cd "$project_dir" 2>/dev/null || return 1
    printf '%s' "$payload" \
      | CLAUDE_PROJECT_DIR="$project_dir" \
        MCL_REPO_PATH="$REPO_ROOT" \
        bash "$REPO_ROOT/hooks/mcl-activate.sh" 2>/dev/null
  )
}
