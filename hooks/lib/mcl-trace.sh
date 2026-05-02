#!/bin/bash
# MCL Trace — append one line per significant MCL action to `.mcl/trace.log`.
#
# Line format:
#   <ISO-8601 UTC> | <event_key> | <comma-separated args>
#
# Example:
#   2026-04-23T14:32:01Z | session_start | 6.3.0
#   2026-04-23T14:35:10Z | summary_confirmed
#   2026-04-23T14:37:44Z | spec_approved
#   2026-04-23T14:40:12Z | plugin_dispatched | code-reviewer
#   2026-04-23T14:55:08Z | verification_emitted
#
# The log is consumed by Aşama 11 (Verification Report) which reads the
# file and renders a localized "Process Trace" section. Lines are stored
# in a stable machine-readable format; localization happens at render time
# in the skill file — not here. This keeps the hook surface small and the
# log portable across languages.
#
# Never blocks the caller. All errors go to stderr and return 0.
#
# Sourced usage:
#   source hooks/lib/mcl-trace.sh
#   mcl_trace_append session_start 6.3.0
#   mcl_trace_append plugin_dispatched code-reviewer
#
# CLI usage:
#   bash hooks/lib/mcl-trace.sh emit <event_key> [args...]

set -u

MCL_STATE_DIR="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}"
MCL_TRACE_FILE="${MCL_TRACE_FILE:-$MCL_STATE_DIR/trace.log}"
MCL_TRACE_MAX_BYTES="${MCL_TRACE_MAX_BYTES:-10485760}"  # 10 MB soft threshold

mcl_trace_append() {
  local event="${1:-}"
  [ -z "$event" ] && return 0
  shift 2>/dev/null || true

  mkdir -p "$MCL_STATE_DIR" 2>/dev/null || true

  # Soft size warning — single stderr line, no rotation, no block.
  if [ -f "$MCL_TRACE_FILE" ]; then
    local sz
    sz="$(wc -c < "$MCL_TRACE_FILE" 2>/dev/null | tr -d ' ')"
    if [ -n "$sz" ] && [ "$sz" -ge "$MCL_TRACE_MAX_BYTES" ] 2>/dev/null; then
      echo "mcl-trace: trace log exceeds ${MCL_TRACE_MAX_BYTES} bytes — consider archiving $MCL_TRACE_FILE" >&2
    fi
  fi

  local ts args
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || ts="-"
  # Join positional args with commas. Empty args are preserved as blanks.
  if [ "$#" -gt 0 ]; then
    local IFS=','
    args="$*"
  else
    args=""
  fi

  # Strip pipe characters from args to keep the log's pipe-delimited
  # format parseable. Pipes inside arg values are rare but defensive.
  args="$(printf '%s' "$args" | tr '|' '/')"

  printf '%s | %s | %s\n' "$ts" "$event" "$args" >> "$MCL_TRACE_FILE" 2>/dev/null || {
    echo "mcl-trace: append failed for event=${event}" >&2
    return 0
  }
  return 0
}

# CLI dispatch — only when invoked directly, not when sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cmd="${1:-}"
  case "$cmd" in
    emit)
      shift 2>/dev/null || true
      mcl_trace_append "$@"
      ;;
    *)
      echo "usage: $0 emit <event_key> [args...]" >&2
      exit 2
      ;;
  esac
fi
