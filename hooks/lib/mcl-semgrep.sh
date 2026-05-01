#!/bin/bash
# MCL Semgrep — local SAST bridge for Phase 4.
#
# Three responsibilities:
#   1. Preflight — verify `semgrep` binary presence + project-stack
#      support + cache freshness. Called from `mcl-activate.sh` at
#      session start.
#   2. Scan — run semgrep on a given file list (delta scope), emit
#      findings as JSON on stdout classified by severity (HIGH /
#      MEDIUM / LOW). Called from Phase 4 branch of `mcl-stop.sh`.
#   3. Refresh cache — fetch latest rule pack from
#      registry.semgrep.dev via `--config=auto`, cache under
#      `~/.mcl/semgrep-cache/`, stamp a version marker. Called on
#      first-run and whenever the cache is > 7 days old.
#
# Privacy invariant: project source code never leaves the machine.
# The only permitted network endpoint is registry.semgrep.dev
# (rule-pack fetches during cache refresh).
#
# Sourceable + CLI:
#   source hooks/lib/mcl-semgrep.sh
#   mcl_semgrep_preflight               # echoes status line; exit 0/1/2
#   mcl_semgrep_scan file1 file2 ...    # emits findings JSON
#   mcl_semgrep_refresh_cache           # one-shot cache rebuild
#
#   bash hooks/lib/mcl-semgrep.sh preflight
#   bash hooks/lib/mcl-semgrep.sh scan <file>...
#   bash hooks/lib/mcl-semgrep.sh refresh-cache

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -z "${SCRIPT_DIR:-}" ]; then
  echo "mcl-semgrep: cannot locate own directory" >&2
  exit 1
fi

# shellcheck source=mcl-state.sh
source "$SCRIPT_DIR/mcl-state.sh"
# shellcheck source=mcl-stack-detect.sh
source "$SCRIPT_DIR/mcl-stack-detect.sh"
# shellcheck source=mcl-trace.sh
[ -f "$SCRIPT_DIR/mcl-trace.sh" ] && source "$SCRIPT_DIR/mcl-trace.sh"

MCL_SEMGREP_CACHE_DIR="${MCL_SEMGREP_CACHE_DIR:-$HOME/.mcl/semgrep-cache}"
MCL_SEMGREP_CACHE_TTL_DAYS=7
MCL_SEMGREP_REFRESH_TIMEOUT=10

# Stack tags the Semgrep CLI can usefully lint. Kept in sync with
# Semgrep's supported-languages matrix; tags match mcl-stack-detect.sh
# outputs. Lua/Swift are excluded: Semgrep's OSS ruleset for them is
# thin enough that we treat them as unsupported to avoid false-confidence.
_MCL_SEMGREP_SUPPORTED_TAGS="typescript javascript python go ruby java kotlin php cpp csharp rust"

mcl_semgrep_supported() {
  # mcl_semgrep_supported <tag> — return 0 if tag is in the supported list.
  local tag="$1" t
  for t in $_MCL_SEMGREP_SUPPORTED_TAGS; do
    [ "$t" = "$tag" ] && return 0
  done
  return 1
}

_mcl_semgrep_binary_present() {
  command -v semgrep >/dev/null 2>&1
}

_mcl_semgrep_install_hint() {
  case "$(uname -s)" in
    Darwin) echo "brew install semgrep" ;;
    Linux)  echo "pip install semgrep" ;;
    *)      echo "pip install semgrep" ;;
  esac
}

_mcl_semgrep_cache_marker() {
  printf '%s\n' "$MCL_SEMGREP_CACHE_DIR/.version"
}

_mcl_semgrep_cache_fresh() {
  # Return 0 if cache marker exists AND is within TTL.
  local marker
  marker="$(_mcl_semgrep_cache_marker)"
  [ -f "$marker" ] || return 1
  local mtime now age_days
  mtime="$(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null)"
  [ -n "$mtime" ] || return 1
  now="$(date +%s)"
  age_days=$(( (now - mtime) / 86400 ))
  [ "$age_days" -lt "$MCL_SEMGREP_CACHE_TTL_DAYS" ]
}

_mcl_semgrep_has_any_code_files() {
  # Return 0 if the project directory contains at least one file with a
  # recognizable source extension. Bootstrap / empty projects return 1 so
  # the preflight can emit rc=3 (silent) rather than rc=1 (unsupported-
  # stack warning that fires before the developer has stated their language).
  local dir="${1:-$(pwd)}"
  local exts="js ts jsx tsx py go rb java kt php cpp cc cxx c cs rs swift lua vue svelte"
  local ext f
  for ext in $exts; do
    # find is the right tool here — glob depth-first across the tree.
    f="$(find "$dir" -maxdepth 6 -name "*.${ext}" -not -path '*/.git/*' \
         -not -path '*/node_modules/*' -not -path '*/__pycache__/*' \
         -not -path '*/vendor/*' 2>/dev/null | head -1)"
    [ -n "$f" ] && return 0
  done
  return 1
}

_mcl_semgrep_any_supported_stack() {
  # Check project's detected stacks against the Semgrep-supported list.
  # Return 0 if at least one detected tag is supported; 1 otherwise.
  # Empty output (no recognizable stack) is treated as unsupported.
  local dir="${1:-$(pwd)}" tag
  local detected
  detected="$(mcl_stack_detect "$dir")"
  [ -n "$detected" ] || return 1
  while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    if mcl_semgrep_supported "$tag"; then
      return 0
    fi
  done <<< "$detected"
  return 1
}

mcl_semgrep_preflight() {
  # Emits a one-line status on stdout and exits:
  #   0 = OK, SAST will run
  #   1 = soft skip (unsupported stack — caller emits one-time warning)
  #   2 = hard block (binary missing — caller refuses session)
  #   3 = empty project — no source files yet; silent skip, no warning
  if ! _mcl_semgrep_binary_present; then
    local hint
    hint="$(_mcl_semgrep_install_hint)"
    printf 'semgrep-missing|install=%s\n' "$hint"
    mcl_audit_log "semgrep-preflight" "mcl-activate" "missing-binary"
    return 2
  fi
  # Empty project — no source files yet. Bootstrap sessions have not written
  # any code yet; the stack is unknown and the "unsupported" notice would be
  # premature. Return 3 so the caller skips silently without a developer notice.
  if ! _mcl_semgrep_has_any_code_files "${1:-$(pwd)}"; then
    printf 'semgrep-empty-project\n'
    mcl_audit_log "semgrep-preflight" "mcl-activate" "empty-project"
    return 3
  fi
  if ! _mcl_semgrep_any_supported_stack "${1:-$(pwd)}"; then
    printf 'semgrep-unsupported-stack\n'
    mcl_audit_log "semgrep-preflight" "mcl-activate" "unsupported-stack"
    return 1
  fi
  if ! _mcl_semgrep_cache_fresh; then
    printf 'semgrep-cache-stale\n'
    mcl_audit_log "semgrep-preflight" "mcl-activate" "cache-stale"
    return 0
  fi
  printf 'semgrep-ready\n'
  mcl_audit_log "semgrep-preflight" "mcl-activate" "ready"
  return 0
}

mcl_semgrep_refresh_cache() {
  # `semgrep --config=auto` is the only Semgrep invocation that touches
  # registry.semgrep.dev. We redirect its output to /dev/null here — we
  # do not care about findings during cache warm-up, only that the rule
  # packs get materialized under ~/.cache/semgrep. We then stamp the
  # marker so subsequent scans know the cache is fresh.
  #
  # Semgrep caches rules under $HOME/.cache/semgrep by default; we do
  # not relocate that. Our own marker under MCL_SEMGREP_CACHE_DIR is
  # what we read for TTL — Semgrep's internal cache is the actual
  # ruleset storage and persists across invocations.
  mkdir -p "$MCL_SEMGREP_CACHE_DIR" 2>/dev/null || {
    echo "mcl-semgrep: cannot create cache dir $MCL_SEMGREP_CACHE_DIR" >&2
    mcl_audit_log "semgrep-refresh" "mcl-semgrep" "cache-dir-unwritable"
    return 1
  }
  if ! _mcl_semgrep_binary_present; then
    mcl_audit_log "semgrep-refresh" "mcl-semgrep" "missing-binary"
    return 2
  fi
  local tmpdir
  tmpdir="$(mktemp -d 2>/dev/null)" || return 1
  local marker version rc
  marker="$(_mcl_semgrep_cache_marker)"
  # Warm the Semgrep OSS rule cache. Touch an empty file so --config=auto
  # has something to target; we do not care about findings here, only
  # rule download. Timeout guards against hung DNS / flaky networks.
  printf '' > "$tmpdir/.mcl-warm"
  if command -v timeout >/dev/null 2>&1; then
    timeout "$MCL_SEMGREP_REFRESH_TIMEOUT" \
      semgrep --config=auto --quiet --error --no-git-ignore \
      "$tmpdir" >/dev/null 2>&1
    rc=$?
  else
    semgrep --config=auto --quiet --error --no-git-ignore \
      "$tmpdir" >/dev/null 2>&1
    rc=$?
  fi
  rm -rf "$tmpdir" 2>/dev/null
  # Semgrep returns 0 (no findings) or 1 (findings present) on a successful
  # rule run; both mean the rule pack was fetched. 124 = timeout.
  if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
    version="$(semgrep --version 2>/dev/null | head -1)"
    printf '%s\n' "${version:-unknown} $(date +%s)" > "$marker"
    mcl_audit_log "semgrep-refresh" "mcl-semgrep" "ok rc=$rc"
    return 0
  fi
  mcl_audit_log "semgrep-refresh" "mcl-semgrep" "fail rc=$rc (fail-open)"
  return 1
}

mcl_semgrep_scan() {
  # mcl_semgrep_scan <file1> <file2> ... — emits JSON on stdout:
  #   {
  #     "findings": [
  #       { "severity": "HIGH|MEDIUM|LOW",
  #         "rule_id": "...",
  #         "file": "...", "line": N,
  #         "message": "...",
  #         "autofix": "..." | null }
  #     ],
  #     "scanned_files": N,
  #     "errors": [ ... ]
  #   }
  # LOW findings are included in the JSON (caller filters for Phase 4
  # presentation). Returns 0 on scan completion (even with findings),
  # non-zero only on helper-level failure.
  if [ "$#" -eq 0 ]; then
    printf '{"findings":[],"scanned_files":0,"errors":[]}\n'
    return 0
  fi
  if ! _mcl_semgrep_binary_present; then
    mcl_audit_log "semgrep-scan" "mcl-semgrep" "missing-binary"
    printf '{"findings":[],"scanned_files":0,"errors":["semgrep-missing"]}\n'
    return 2
  fi
  local raw rc
  raw="$(semgrep --config=auto --json --quiet --no-git-ignore \
    --timeout 30 "$@" 2>/dev/null)"
  rc=$?
  if [ -z "$raw" ]; then
    mcl_audit_log "semgrep-scan" "mcl-semgrep" "empty-output rc=$rc"
    printf '{"findings":[],"scanned_files":0,"errors":["empty-output"]}\n'
    return 1
  fi
  # Normalize Semgrep's JSON into our MCL schema. Severity mapping:
  #   ERROR   -> HIGH
  #   WARNING -> MEDIUM
  #   INFO    -> LOW
  local normalized
  normalized="$(printf '%s' "$raw" | python3 -c '
import json, sys

SEV_MAP = {"ERROR": "HIGH", "WARNING": "MEDIUM", "INFO": "LOW"}

try:
    doc = json.loads(sys.stdin.read())
except Exception as e:
    print(json.dumps({"findings":[], "scanned_files":0, "errors":[f"parse-fail: {e}"]}))
    sys.exit(0)

findings = []
for r in doc.get("results", []):
    extra = r.get("extra", {}) or {}
    sev_raw = (extra.get("severity") or "").upper()
    findings.append({
        "severity": SEV_MAP.get(sev_raw, "LOW"),
        "rule_id": r.get("check_id", ""),
        "file": r.get("path", ""),
        "line": (r.get("start") or {}).get("line"),
        "message": extra.get("message", ""),
        "autofix": extra.get("fix"),
    })

errors = []
for e in doc.get("errors", []) or []:
    if isinstance(e, dict):
        errors.append(e.get("message") or e.get("type") or "unknown")
    else:
        errors.append(str(e))

paths = doc.get("paths", {}) or {}
scanned = len(paths.get("scanned", []) or [])

print(json.dumps({
    "findings": findings,
    "scanned_files": scanned,
    "errors": errors,
}))
')"
  if [ -z "$normalized" ]; then
    printf '{"findings":[],"scanned_files":0,"errors":["normalize-fail"]}\n'
    return 1
  fi
  mcl_audit_log "semgrep-scan" "mcl-semgrep" "ok files=$#"
  command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append semgrep_ran "$#"
  printf '%s\n' "$normalized"
  return 0
}

# CLI dispatch — only when invoked directly, not when sourced.
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
  cmd="${1:-}"
  case "$cmd" in
    preflight)
      shift
      mcl_semgrep_preflight "${1:-}"
      ;;
    scan)
      shift
      mcl_semgrep_scan "$@"
      ;;
    refresh-cache)
      mcl_semgrep_refresh_cache
      ;;
    supported)
      shift
      mcl_semgrep_supported "${1:-}" && echo yes || echo no
      ;;
    *)
      echo "usage: $0 {preflight [dir]|scan <file>...|refresh-cache|supported <tag>}" >&2
      exit 2
      ;;
  esac
fi
