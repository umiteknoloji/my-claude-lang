#!/bin/bash
# Test: single-session-per-project lock in mcl-claude wrapper.
#
# Wrapper exits early before reaching `claude` if a live MCL session
# already holds the project's lock. Stale locks (owning PID gone) are
# silently reclaimed.
#
# This test stubs `claude` with a sleeper so the wrapper has a real
# child to wait on. We exercise four paths:
#   1. First start — lock written with our PID
#   2. Concurrent start — rejected with exit 1, helpful message
#   3. Trap cleanup — lock removed when wrapper exits
#   4. Stale-lock recovery — dead-PID lock auto-cleaned on next start
#
# Driven directly via the test runner (test-helpers.sh sourced by
# tests/run-tests.sh). Runs in a temp HOME so it cannot pollute the
# user's real ~/.mcl/projects/.

echo "--- test-session-lock ---"

_sl_tmphome="$(mktemp -d)"
_sl_proj="$(mktemp -d)"
_sl_stub_bin="$(mktemp -d)"
_sl_lib="$_sl_tmphome/.mcl/lib"

# Mirror the real repo as MCL_LIB so the wrapper finds `bin/mcl-claude`,
# `VERSION`, hooks, and skills. Symlink rather than copy — we are not
# mutating any of these.
mkdir -p "$_sl_tmphome/.mcl/projects"
ln -s "$REPO_ROOT" "$_sl_lib"

# Stub `claude` — sleeps long enough that we can race a second wrapper
# against the running first one, then exits 0. Lives at the front of PATH.
cat > "$_sl_stub_bin/claude" <<'STUB'
#!/usr/bin/env bash
# Test stub. Honors --settings / --plugin-dir without touching them.
sleep "${MCL_TEST_CLAUDE_SLEEP:-3}"
exit 0
STUB
chmod +x "$_sl_stub_bin/claude"

# Helper: project key matching the wrapper's own SHA1 logic.
_sl_proj_real="$(cd "$_sl_proj" && pwd -P)"
_sl_key="$(printf '%s' "$_sl_proj_real" | shasum -a 1 | awk '{print $1}')"
_sl_state="$_sl_tmphome/.mcl/projects/$_sl_key/state"
_sl_lock="$_sl_state/session.lock"

# Common env all wrapper invocations need.
_sl_env() {
  HOME="$_sl_tmphome" \
  MCL_HOME="$_sl_tmphome/.mcl" \
  PATH="$_sl_stub_bin:$PATH" \
  "$@"
}

# ---- Test 1: first start — lock written with PID, claude reached ----

# Run the wrapper in the background; it should write the lock and then
# block on the stubbed claude (sleep 3).
(cd "$_sl_proj" && _sl_env bash "$REPO_ROOT/bin/mcl-claude") &
_sl_first_pid=$!

# Poll up to 2s for the lock to appear (wrapper does init + write).
for _i in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$_sl_lock" ] && break
  sleep 0.2
done

if [ -f "$_sl_lock" ]; then
  PASS=$((PASS+1))
  printf '  PASS: first start → session.lock created\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: first start did NOT create session.lock at %s\n' "$_sl_lock"
fi

# Lock content must be a numeric PID matching our background pipeline's
# bash subprocess. The pipeline pid is its own bash; the lock holds the
# wrapper's `$$`. They are equal when no extra subshells intervene.
_sl_lock_pid="$(cat "$_sl_lock" 2>/dev/null | tr -d '[:space:]')"
if [ -n "$_sl_lock_pid" ] && [ "$_sl_lock_pid" -eq "$_sl_lock_pid" ] 2>/dev/null; then
  PASS=$((PASS+1))
  printf '  PASS: lock content is a numeric PID (%s)\n' "$_sl_lock_pid"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: lock content is not a numeric PID — got: %s\n' "$_sl_lock_pid"
fi

# Lock must be 0600 — token-adjacent secret hygiene.
_sl_perm="$(stat -f '%Lp' "$_sl_lock" 2>/dev/null || stat -c '%a' "$_sl_lock" 2>/dev/null)"
if [ "$_sl_perm" = "600" ]; then
  PASS=$((PASS+1))
  printf '  PASS: lock file mode is 0600\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: lock file mode is %s, expected 600\n' "$_sl_perm"
fi

# ---- Test 2: concurrent start — must reject with exit 1 ----

_sl_second_out="$(mktemp)"
_sl_second_err="$(mktemp)"
# Wrap in `|| rc=$?` so the runner's `set -e` doesn't abort on the
# expected non-zero exit (the whole point of this assertion).
_sl_second_rc=0
(cd "$_sl_proj" && _sl_env bash "$REPO_ROOT/bin/mcl-claude") \
  >"$_sl_second_out" 2>"$_sl_second_err" || _sl_second_rc=$?

if [ "$_sl_second_rc" -eq 1 ]; then
  PASS=$((PASS+1))
  printf '  PASS: concurrent start → exit 1\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: concurrent start exit code=%d, expected 1\n' "$_sl_second_rc"
fi

if grep -q "session already active" "$_sl_second_err"; then
  PASS=$((PASS+1))
  printf '  PASS: concurrent start → helpful "session already active" message\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: concurrent start did not surface the expected message\n'
  printf '        stderr: %s\n' "$(head -c 200 "$_sl_second_err")"
fi

# ---- Test 3: trap cleanup on normal exit ----

# Wait for the first wrapper to finish (claude stub sleeps then exits).
wait "$_sl_first_pid" 2>/dev/null || true

if [ ! -f "$_sl_lock" ]; then
  PASS=$((PASS+1))
  printf '  PASS: lock removed by EXIT trap when wrapper finished\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: lock still present at %s after wrapper exit\n' "$_sl_lock"
fi

# ---- Test 4: stale-lock recovery ----

# Plant a lock owned by an impossibly-large PID that is not running.
mkdir -p "$_sl_state"
printf '%s' "999999" > "$_sl_lock"
chmod 600 "$_sl_lock" 2>/dev/null || true

# Run the wrapper with a very short claude sleep so we don't wait long.
_sl_stale_rc=0
(cd "$_sl_proj" && _sl_env env MCL_TEST_CLAUDE_SLEEP=0 \
   bash "$REPO_ROOT/bin/mcl-claude") || _sl_stale_rc=$?

if [ "$_sl_stale_rc" -eq 0 ]; then
  PASS=$((PASS+1))
  printf '  PASS: stale-lock recovery → wrapper proceeded (exit 0)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: stale-lock recovery did not proceed (exit %d)\n' "$_sl_stale_rc"
fi

# After recovery + completion, lock should be cleared.
if [ ! -f "$_sl_lock" ]; then
  PASS=$((PASS+1))
  printf '  PASS: stale-lock cleared and own lock cleaned on exit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: lock survived stale recovery + clean exit\n'
fi

# ---- Cleanup ----
rm -rf "$_sl_tmphome" "$_sl_proj" "$_sl_stub_bin"
rm -f "$_sl_second_out" "$_sl_second_err"
