#!/bin/bash
# MCL Dispatch Audit — verifies required plugins were dispatched during Phase 4.5.
#
# Phase 4.5 mandatory dispatches:
#   (a) Code-review sub-agent: any plugin_dispatched event whose subagent_type
#       starts with "pr-review-toolkit", "code-review", or equals
#       "superpowers:code-reviewer" — must appear AFTER the last
#       phase_review_pending event in trace.log (i.e., after Phase 4 code
#       was written and Phase 4.5 started).
#   (b) Semgrep scan: a semgrep_ran event in trace.log after phase_review_pending,
#       unless semgrep is known to be unavailable (skip flag).
#
# Usage (sourced):
#   source hooks/lib/mcl-dispatch-audit.sh
#   MISSED=$(mcl_check_phase45_dispatches "$TRACE_LOG" "$SEMGREP_SKIP")
#   # MISSED: space-separated list of missed plugin labels, or empty string.
#
# Never blocks the caller. All errors go to stderr and return 0.

set -u

mcl_check_phase45_dispatches() {
  local trace_log="${1:-}"
  local semgrep_skip="${2:-false}"   # "true" if semgrep binary missing or stack unsupported

  [ -f "$trace_log" ] || { echo ""; return 0; }

  python3 - "$trace_log" "$semgrep_skip" 2>/dev/null <<'PYEOF'
import sys, json

trace_log  = sys.argv[1]
skip_sgrep = sys.argv[2].lower() == "true"

# Read all lines, find the last phase_review_pending event index,
# then scan for dispatches after that index.
lines = []
try:
    with open(trace_log, "r", encoding="utf-8", errors="replace") as f:
        lines = [l.rstrip("\n") for l in f if l.strip()]
except Exception:
    print("")
    sys.exit(0)

# Find the last phase_review_pending line (anchor for Phase 4.5 start).
last_pending_idx = -1
for i, line in enumerate(lines):
    parts = line.split(" | ", 2)
    if len(parts) >= 2 and parts[1].strip() == "phase_review_pending":
        last_pending_idx = i

# If no pending event, Phase 4.5 hasn't started yet — nothing to audit.
if last_pending_idx == -1:
    print("")
    sys.exit(0)

# Scan events AFTER the pending anchor.
code_review_found = False
semgrep_found     = False

code_review_prefixes = ("pr-review-toolkit", "code-review", "superpowers:code-reviewer")

for line in lines[last_pending_idx + 1:]:
    parts = line.split(" | ", 2)
    if len(parts) < 2:
        continue
    event = parts[1].strip()
    args  = parts[2].strip() if len(parts) > 2 else ""

    if event == "plugin_dispatched":
        if any(args.startswith(p) for p in code_review_prefixes):
            code_review_found = True

    elif event == "semgrep_ran":
        semgrep_found = True

missed = []
if not code_review_found:
    missed.append("code-review")
if not skip_sgrep and not semgrep_found:
    missed.append("semgrep")

print(" ".join(missed))
PYEOF
}

# CLI dispatch — only when invoked directly, not when sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cmd="${1:-}"
  case "$cmd" in
    check)
      shift 2>/dev/null || true
      mcl_check_phase45_dispatches "$@"
      ;;
    *)
      echo "usage: $0 check <trace_log_path> [semgrep_skip=false]" >&2
      exit 2
      ;;
  esac
fi
