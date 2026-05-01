#!/bin/bash
# MCL session log helper — append one timestamped line to the active log.
#
# Sourceable library. Usage:
#   source hooks/lib/mcl-log-append.sh
#   mcl_log_append "Sentence in developer's language."
#
# The active log file path is stored in .mcl/log-current (written by
# mcl-activate.sh on session start). Silent no-op if missing.

mcl_log_append() {
  local msg="$1"
  local state_dir="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}"
  local LOG_CURRENT="$state_dir/log-current"
  local LOG_FILE
  LOG_FILE="$(cat "$LOG_CURRENT" 2>/dev/null | tr -d '[:space:]')"
  [ -z "$LOG_FILE" ] && return 0
  [ -f "$LOG_FILE" ] || return 0
  printf -- '- **%s** — %s\n' "$(date '+%H:%M:%S')" "$msg" >> "$LOG_FILE" 2>/dev/null || true
}
