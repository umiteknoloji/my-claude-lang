#!/bin/bash
# MCL Test Runner — opt-in Phase 5 test-runner orchestration.
#
# Claude invokes this via the Bash tool during Phase 5 when the
# developer has declared a `test_command` in .mcl/config.json.
# The runner executes the command with a portable timeout, captures
# merged stdout+stderr, truncates to 2KB preserving the tail, and
# prints a formatted block that Claude pastes verbatim at the top
# of the Verification Report.
#
# Exits 0 for GREEN / RED / TIMEOUT / no-op. Non-zero only on
# internal errors (mktemp failure, unreadable lib dir, etc.).
#
# Output format (stdout):
#   line 1: one of
#     ✅ Tests: GREEN (exit 0, 2.1s)
#     ❌ Tests: RED (exit 1, 0.8s)
#     ⏱ Tests: TIMEOUT after 5.0s (limit 5s)
#   line 2: empty
#   lines 3+: fenced block ```text ... ```
#     — omitted entirely when GREEN and output is empty
#
# Audit log entry (every invocation that reaches exec):
#   test-run | runner | result=<type> exit=<code> duration_ms=<n> output_bytes=<n>
#
# CLI:
#   bash ~/.claude/hooks/lib/mcl-test-runner.sh
#
# Sourced:
#   source hooks/lib/mcl-test-runner.sh
#   mcl_test_run

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -z "${SCRIPT_DIR:-}" ]; then
  echo "mcl-test-runner: cannot locate own directory" >&2
  exit 1
fi

# shellcheck source=mcl-state.sh
source "$SCRIPT_DIR/mcl-state.sh"
# shellcheck source=mcl-config.sh
source "$SCRIPT_DIR/mcl-config.sh"

MCL_RUNNER_DEFAULT_TIMEOUT=120
MCL_RUNNER_MAX_OUTPUT=2048

_mcl_runner_resolve_timeout() {
  # Read test_command_timeout_seconds; must be a positive integer.
  # Anything else (absent, 0, negative, float, string) → fall back to
  # default with a stderr warning.
  local raw
  raw="$(mcl_config_get test_command_timeout_seconds)"
  if [ -z "$raw" ]; then
    printf '%s\n' "$MCL_RUNNER_DEFAULT_TIMEOUT"
    return 0
  fi
  if ! printf '%s' "$raw" | grep -qE '^[1-9][0-9]*$'; then
    echo "mcl-test-runner: invalid test_command_timeout_seconds='${raw}' (must be positive integer), using default ${MCL_RUNNER_DEFAULT_TIMEOUT}s" >&2
    printf '%s\n' "$MCL_RUNNER_DEFAULT_TIMEOUT"
    return 0
  fi
  printf '%s\n' "$raw"
}

_mcl_runner_now_ms() {
  python3 -c 'import time; print(int(time.time()*1000))'
}

_mcl_runner_format_duration() {
  # $1 = duration_ms → "2.1s"
  python3 -c "print(f'{$1/1000:.1f}s')" 2>/dev/null
}

_mcl_runner_emit_output() {
  # Emit file contents, tail-preserving truncation at $2 bytes.
  # Truncation prepends `... (truncated, original N bytes)` marker.
  local file="$1" max="$2"
  python3 - "$file" "$max" <<'PY'
import sys
path, max_b = sys.argv[1], int(sys.argv[2])
try:
    data = open(path, "rb").read()
except Exception:
    data = b""
if len(data) > max_b:
    tail = data[-max_b:]
    marker = ("... (truncated, original " + str(len(data)) + " bytes)\n").encode("utf-8")
    sys.stdout.buffer.write(marker + tail)
else:
    sys.stdout.buffer.write(data)
PY
}

mcl_test_run() {
  # Read config. No-op (exit 0, empty stdout) when test_command is
  # absent, empty, or only whitespace — this is the opt-in path.
  local cmd
  cmd="$(mcl_config_get test_command)"
  if [ -z "${cmd// /}" ]; then
    return 0
  fi
  local timeout_s
  timeout_s="$(_mcl_runner_resolve_timeout)"

  # Subshell scopes trap + tempfiles + background PIDs so cleanup
  # fires deterministically regardless of source vs exec entry, and
  # killing the outer hook can't leave orphan children running.
  (
    outfile="$(mktemp -t mcl-runner-out.XXXXXX)" || { echo "mcl-test-runner: mktemp failed" >&2; exit 1; }
    sentinel="${outfile}.timeout"
    WATCHER_PID=""
    CMD_PID=""

    _mcl_runner_cleanup() {
      [ -n "${WATCHER_PID:-}" ] && kill "$WATCHER_PID" 2>/dev/null
      [ -n "${CMD_PID:-}" ] && kill -TERM "$CMD_PID" 2>/dev/null
      rm -f "$outfile" "$sentinel" 2>/dev/null
    }
    trap _mcl_runner_cleanup EXIT TERM INT

    start_ms="$(_mcl_runner_now_ms)"

    # Foreground command gets stdout+stderr merged into outfile to
    # avoid pipe-buffer hangs on large output. `bash -c` so the
    # developer's command inherits normal shell parsing semantics.
    bash -c "$cmd" > "$outfile" 2>&1 &
    CMD_PID=$!

    # Watcher: sleeps for timeout_s, then if child still alive writes
    # sentinel file and SIGTERMs → SIGKILLs. Sentinel existence is how
    # the parent distinguishes TIMEOUT from a normal non-zero exit.
    (
      sleep "$timeout_s"
      if kill -0 "$CMD_PID" 2>/dev/null; then
        : > "$sentinel"
        kill -TERM "$CMD_PID" 2>/dev/null
        sleep 1
        kill -KILL "$CMD_PID" 2>/dev/null
      fi
    ) &
    WATCHER_PID=$!

    wait "$CMD_PID" 2>/dev/null
    CMD_EXIT=$?

    # Command completed — cancel watcher if it's still sleeping.
    kill "$WATCHER_PID" 2>/dev/null
    wait "$WATCHER_PID" 2>/dev/null || true

    end_ms="$(_mcl_runner_now_ms)"
    duration_ms=$((end_ms - start_ms))
    duration_display="$(_mcl_runner_format_duration "$duration_ms")"

    if [ -f "$sentinel" ]; then
      result="TIMEOUT"
      exit_display=""
      result_line="⏱ Tests: TIMEOUT after ${duration_display} (limit ${timeout_s}s)"
    elif [ "$CMD_EXIT" = "0" ]; then
      result="GREEN"
      exit_display="0"
      result_line="✅ Tests: GREEN (exit 0, ${duration_display})"
    else
      result="RED"
      exit_display="$CMD_EXIT"
      result_line="❌ Tests: RED (exit ${CMD_EXIT}, ${duration_display})"
    fi

    output_bytes="$(wc -c < "$outfile" 2>/dev/null | tr -d ' ')"
    [ -n "$output_bytes" ] || output_bytes=0

    printf '%s\n' "$result_line"

    # Fenced block omitted only when GREEN + empty output. For RED
    # and TIMEOUT the block is always emitted so failure diagnostics
    # are visible (even an empty fenced block signals "no output").
    if [ "$result" = "GREEN" ] && [ "$output_bytes" = "0" ]; then
      :
    else
      printf '\n'
      printf '```text\n'
      _mcl_runner_emit_output "$outfile" "$MCL_RUNNER_MAX_OUTPUT"
      printf '\n```\n'
    fi

    mcl_audit_log "test-run" "runner" "result=${result} exit=${exit_display} duration_ms=${duration_ms} output_bytes=${output_bytes}"
  )
}

# CLI dispatch — only when invoked directly, not when sourced.
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
  mcl_test_run
fi
