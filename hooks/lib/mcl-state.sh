#!/bin/bash
# MCL State — .mcl/state.json schema + atomic helpers.
#
# Sourceable library AND CLI. All reads survive corruption by falling
# back to a default Phase-1 state and logging to stderr. All writes use
# tmp-file + mv (atomic rename) so a crash mid-write cannot leave the
# state file half-serialized.
#
# State file lives at `<project>/.mcl/state.json` — one file per working
# directory. Stale-state garbage collection is NOT in v1 (YAGNI).
#
# Schema v2 (since MCL 6.2.0):
#   {
#     "schema_version":      2,
#     "current_phase":       1,           // 1..5
#     "phase_name":          "COLLECT",   // COLLECT|SPEC_REVIEW|USER_VERIFY|EXECUTE|DELIVER
#     "spec_approved":       false,
#     "spec_hash":           null,        // sha256 of approved spec body
#     "plugin_gate_active":  false,
#     "plugin_gate_missing": [],
#     "ui_flow_active":      false,       // set by Phase 1 confirm (opt-out path)
#     "ui_sub_phase":        null,        // "BUILD_UI" | "REVIEW" | "BACKEND" | null
#     "ui_build_hash":       null,        // sha256 of last frontend build output
#     "ui_reviewed":         false,       // set by Phase 4b approve intent
#     "last_update":         1713456789   // unix epoch seconds
#   }
#
# v1 files (schema_version=1) are auto-migrated to v2 on next hook run.
# v1→v2 migration adds the four UI fields with default values and
# preserves a backup at `.mcl/state.json.backup.v1`.
#
# CLI usage:
#   mcl-state.sh init                          # create default if missing
#   mcl-state.sh get <field>                   # print one field
#   mcl-state.sh set <field> <value>           # set one field, update last_update
#   mcl-state.sh dump                          # print full JSON
#   mcl-state.sh reset                         # overwrite with default
#
# Sourced usage:
#   source hooks/lib/mcl-state.sh
#   mcl_state_get current_phase
#   mcl_state_set spec_approved true

set -u

MCL_STATE_SCHEMA_VERSION=2
MCL_STATE_DIR="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}"
MCL_STATE_FILE="${MCL_STATE_FILE:-$MCL_STATE_DIR/state.json}"

_mcl_state_default() {
  local now
  now="$(date +%s)"
  cat <<JSON
{
  "schema_version": ${MCL_STATE_SCHEMA_VERSION},
  "current_phase": 1,
  "phase_name": "COLLECT",
  "spec_approved": false,
  "spec_hash": null,
  "plugin_gate_active": false,
  "plugin_gate_missing": [],
  "ui_flow_active": false,
  "ui_sub_phase": null,
  "ui_build_hash": null,
  "ui_reviewed": false,
  "scope_paths": [],
  "pattern_scan_due": false,
  "pattern_files": [],
  "rollback_sha": null,
  "rollback_notice_shown": false,
  "pattern_summary": null,
  "tdd_last_green": null,
  "last_write_ts": null,
  "last_update": ${now}
}
JSON
}

_mcl_state_auth_check() {
  # Return 0 iff the ENTRY script (what the OS executed) is one of our
  # own hook files under hooks/. `$0` in a sourced library reflects the
  # parent script, so this catches:
  #   - CLI invocations of mcl-state.sh itself → $0 = mcl-state.sh → deny
  #   - `bash -c "source .../mcl-state.sh; mcl_state_set ..."` → $0 = bash → deny
  #   - Hooks that source this lib → $0 = hook path → allow
  # Does NOT rely on env tokens (children would inherit them, unsafe).
  local entry_abs hooks_dir
  entry_abs="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
  hooks_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
  case "$entry_abs" in
    "$hooks_dir"/mcl-activate.sh)    return 0 ;;
    "$hooks_dir"/mcl-stop.sh)        return 0 ;;
    "$hooks_dir"/mcl-pre-tool.sh)    return 0 ;;
    "$hooks_dir"/mcl-post-tool.sh)   return 0 ;;
    "$hooks_dir"/mcl-user-prompt.sh) return 0 ;;
  esac
  return 1
}

_mcl_state_valid() {
  # Return 0 if stdin is parseable JSON with schema_version 1 or 2.
  # v1 files are accepted so mcl_state_init can migrate them in-place
  # instead of corrupt-copying + replacing with default.
  # Uses `python3 -c` (not heredoc) so the piped body isn't shadowed.
  python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    assert isinstance(obj, dict)
    assert obj.get("schema_version") in (1, 2)
    assert isinstance(obj.get("current_phase"), int)
    assert 1 <= obj["current_phase"] <= 5
except Exception:
    sys.exit(1)
' 2>/dev/null
}

_mcl_state_migrate_v1_to_v2() {
  # Read the current file, add missing v2 fields with defaults, rewrite
  # atomically. Backup the v1 body at `.mcl/state.json.backup.v1` so the
  # migration is reversible by hand if anything goes wrong. Emits an
  # audit event so the migration is always visible after the fact.
  [ -f "$MCL_STATE_FILE" ] || return 0
  local body migrated
  body="$(cat "$MCL_STATE_FILE" 2>/dev/null)" || return 1
  cp "$MCL_STATE_FILE" "${MCL_STATE_FILE}.backup.v1" 2>/dev/null || true
  migrated="$(printf '%s' "$body" | python3 -c '
import json, sys, time
obj = json.loads(sys.stdin.read())
obj["schema_version"] = 2
obj.setdefault("plugin_gate_active", False)
obj.setdefault("plugin_gate_missing", [])
obj.setdefault("ui_flow_active", False)
obj.setdefault("ui_sub_phase", None)
obj.setdefault("ui_build_hash", None)
obj.setdefault("ui_reviewed", False)
obj["last_update"] = int(time.time())
print(json.dumps(obj, indent=2))
' 2>/dev/null)"
  [ -n "$migrated" ] || return 1
  _mcl_state_write_raw "$migrated" || return 1
  mcl_audit_log "migrate-v1-to-v2" "$(basename "${0:-unknown}")" "backup=${MCL_STATE_FILE}.backup.v1"
}

mcl_state_init() {
  mkdir -p "$MCL_STATE_DIR" 2>/dev/null || true
  if [ ! -f "$MCL_STATE_FILE" ]; then
    _mcl_state_write_raw "$(_mcl_state_default)"
    return 0
  fi
  # File exists — check if it needs v1→v2 migration.
  local current_version
  current_version="$(python3 -c '
import json, sys
try:
    obj = json.load(open(sys.argv[1]))
    print(obj.get("schema_version", 0))
except Exception:
    print(0)
' "$MCL_STATE_FILE" 2>/dev/null)"
  if [ "$current_version" = "1" ]; then
    _mcl_state_migrate_v1_to_v2
  fi
}

mcl_state_read() {
  # Echo the current state JSON. On any failure, echo the default and
  # log the reason to stderr — NEVER block the caller.
  if [ ! -f "$MCL_STATE_FILE" ]; then
    _mcl_state_default
    return 0
  fi
  local body
  body="$(cat "$MCL_STATE_FILE" 2>/dev/null)"
  if [ -z "$body" ]; then
    echo "mcl-state: empty state file, returning default" >&2
    _mcl_state_default
    return 0
  fi
  if ! printf '%s' "$body" | _mcl_state_valid; then
    echo "mcl-state: corrupt state file, returning default (keeping corrupt copy at ${MCL_STATE_FILE}.corrupt)" >&2
    cp "$MCL_STATE_FILE" "${MCL_STATE_FILE}.corrupt" 2>/dev/null || true
    _mcl_state_default
    return 0
  fi
  printf '%s\n' "$body"
}

_mcl_state_write_raw() {
  # Atomic write: tmp file in same dir, then mv. Same-dir mv is atomic
  # on POSIX filesystems. Gated by auth check so no unauthorized caller
  # can reach the filesystem write path — even if they know the helper
  # name.
  local caller="${0:-unknown}"
  if ! _mcl_state_auth_check; then
    echo "mcl-state: write denied — unauthorized caller: $caller" >&2
    mcl_audit_log "deny-write" "$caller" "unauthorized"
    return 2
  fi
  mkdir -p "$MCL_STATE_DIR" 2>/dev/null || true
  local tmp
  tmp="${MCL_STATE_FILE}.tmp.$$"
  if printf '%s\n' "$1" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$MCL_STATE_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
}

mcl_state_get() {
  # mcl_state_get <field> — prints scalar value (bool/int as literals,
  # null as empty string, string without quotes).
  local field="$1"
  mcl_state_read | python3 -c '
import json, sys
field = sys.argv[1]
try:
    obj = json.loads(sys.stdin.read())
    val = obj.get(field)
    if val is None:
        print("")
    elif isinstance(val, bool):
        print("true" if val else "false")
    else:
        print(val)
except Exception:
    sys.exit(1)
' "$field" 2>/dev/null
}

mcl_state_set() {
  # mcl_state_set <field> <value> — value is interpreted as JSON if it
  # parses, otherwise as a string. Always bumps last_update.
  local field="$1" value="$2"
  local current
  current="$(mcl_state_read)"
  local updated
  updated="$(printf '%s' "$current" | python3 -c '
import json, sys, time
field, raw = sys.argv[1], sys.argv[2]
obj = json.loads(sys.stdin.read())
try:
    val = json.loads(raw)
except Exception:
    val = raw
obj[field] = val
obj["last_update"] = int(time.time())
print(json.dumps(obj, indent=2))
' "$field" "$value" 2>/dev/null)"
  if [ -z "$updated" ]; then
    echo "mcl-state: set failed for field=$field" >&2
    return 1
  fi
  if _mcl_state_write_raw "$updated"; then
    mcl_audit_log "set" "$(basename "${0:-unknown}")" "field=${field} value=${value}"
    return 0
  fi
  return 1
}

mcl_state_dump() {
  mcl_state_read
}

mcl_state_reset() {
  _mcl_state_write_raw "$(_mcl_state_default)"
}

mcl_debug_log() {
  # Append one forensic line to `.mcl/debug.log` when MCL_DEBUG=1.
  # Fields: timestamp | hook | event | detail. No rotation, no levels.
  [ "${MCL_DEBUG:-0}" = "1" ] || return 0
  local dir="${MCL_STATE_DIR}"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s | %s | %s | %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$3" \
    >> "$dir/debug.log" 2>/dev/null || true
}

mcl_audit_log() {
  # Security-relevant audit trail — ALWAYS ON regardless of MCL_DEBUG.
  # Every state write attempt (allow or deny) lands here so Claude-
  # driven bypass attempts are visible to the developer after the fact.
  # Fields: timestamp | event | caller | detail.
  local dir="${MCL_STATE_DIR}"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s | %s | %s | %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$3" \
    >> "$dir/audit.log" 2>/dev/null || true
}

# CLI dispatch — only when invoked directly, not when sourced.
# READ-ONLY from CLI. All write operations (set/init/reset) are gated by
# `_mcl_state_auth_check` and will be denied from this entry point —
# $0 would be mcl-state.sh, not an MCL hook. Write ops live inside the
# hooks only. To hard-reset state, delete `.mcl/state.json` directly.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cmd="${1:-dump}"
  case "$cmd" in
    get)    shift; mcl_state_get "$@" ;;
    dump)   mcl_state_dump ;;
    *)      echo "usage: $0 {get <field>|dump}  (read-only — writes live in hooks)" >&2; exit 2 ;;
  esac
fi
