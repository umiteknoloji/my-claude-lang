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
# Schema v3 (since MCL 10.0.0):
#   {
#     "schema_version":      3,
#     "current_phase":       1,           // 1..6 (no decimals)
#     "phase_name":          "INTENT",    // INTENT|DESIGN_REVIEW|IMPLEMENTATION|RISK_GATE|VERIFICATION|FINAL_REVIEW
#     "is_ui_project":       false,       // detected once in Phase 1 brief parse, immutable
#     "design_approved":     false,       // set true on Phase 2 design askq approve (UI only)
#     "spec_hash":           null,        // sha256 of last emitted Phase 3 spec body (advisory)
#     "plugin_gate_active":  false,
#     "plugin_gate_missing": [],
#     "ui_flow_active":      false,       // (legacy alias — deprecated; use is_ui_project)
#     "ui_sub_phase":        null,        // (legacy — deprecated)
#     "ui_build_hash":       null,
#     "ui_reviewed":         false,       // (legacy alias for design_approved)
#     "last_update":         1713456789
#   }
#
# Removed in v3 (10.0.0):
#   - spec_approved (Phase 1 summary-confirm IS the approval gate)
#   - precision_audit_block_count, precision_audit_skipped (helper flags)
#   - phase_review_state (old SPEC_REVIEW field)
#
# v1/v2 files are auto-migrated to v3 on next hook run.
# Migration: current_phase∈{2,3}→3, current_phase=4→3, current_phase=4.5→4;
# spec_approved=true → design_approved=true; is_ui_project defaults to true
# (safe non-trigger), design_approved=true so old projects don't re-prompt.
#
# CLI usage:
#   mcl-state.sh get <field>                   # print one field
#   mcl-state.sh dump                          # print full JSON
#
# Sourced usage:
#   source hooks/lib/mcl-state.sh
#   mcl_state_get current_phase
#   mcl_state_set design_approved true

set -u

MCL_STATE_SCHEMA_VERSION=3
MCL_STATE_DIR="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}"
MCL_STATE_FILE="${MCL_STATE_FILE:-$MCL_STATE_DIR/state.json}"

_mcl_state_default() {
  local now
  now="$(date +%s)"
  cat <<JSON
{
  "schema_version": ${MCL_STATE_SCHEMA_VERSION},
  "current_phase": 1,
  "phase_name": "INTENT",
  "is_ui_project": false,
  "design_approved": false,
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
  "pattern_level": null,
  "pattern_ask_pending": false,
  "plan_critique_done": false,
  "restart_turn_ts": null,
  "phase4_security_scan_done": false,
  "phase4_db_scan_done": false,
  "phase4_ui_scan_done": false,
  "phase4_high_baseline": {"security": 0, "db": 0, "ui": 0, "ops": 0, "perf": 0},
  "phase4_ops_scan_done": false,
  "phase4_perf_scan_done": false,
  "phase1_ops": {"deployment_target": null, "observability_tier": null, "test_policy": null, "doc_level": null},
  "phase1_perf": {"budget_tier": null},
  "phase6_double_check_done": false,
  "phase4_batch_decision": null,
  "phase1_turn_count": 0,
  "summary_askq_skipped": false,
  "phase1_intent": null,
  "phase1_constraints": null,
  "paused_on_error": {"active": false},
  "dev_server": {"active": false},
  "spec_format_warn_count": 0,
  "last_update": ${now}
}
JSON
}

_mcl_state_auth_check() {
  # Return 0 iff EITHER:
  #   (a) the ENTRY script (`$0`) is one of our hook files under hooks/, OR
  #   (b) [since 8.17.0] MCL_SKILL_TOKEN env var matches the contents of
  #       `$MCL_STATE_DIR/skill-token` (project-scoped, rotated each
  #       UserPromptSubmit by mcl-activate.sh). Path (b) authorizes skill
  #       prose Bash invocations of the form
  #         `bash -c 'export MCL_SKILL_TOKEN=$(cat .../skill-token); ...'`
  #       without giving CLI bypass — the token file is mode 0600 inside
  #       the project state dir and rotated every prompt.
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
  # (b) skill-token path — only valid when both env var and file present.
  if [ -n "${MCL_SKILL_TOKEN:-}" ] && [ -f "$MCL_STATE_DIR/skill-token" ]; then
    local stored
    stored="$(cat "$MCL_STATE_DIR/skill-token" 2>/dev/null)"
    if [ -n "$stored" ] && [ "$MCL_SKILL_TOKEN" = "$stored" ]; then
      MCL_AUTH_CALLER="skill-prose"
      return 0
    fi
  fi
  return 1
}

mcl_state_skill_token_rotate() {
  # Generate a fresh 32-hex token, write to <state>/skill-token (0600).
  # Called by mcl-activate.sh on each UserPromptSubmit so the previous
  # turn's token cannot be replayed by an unrelated subprocess.
  # Stdout: the new token (so the caller can also surface it via
  # additionalContext if needed for diagnostics).
  local dir="${MCL_STATE_DIR}"
  mkdir -p "$dir" 2>/dev/null || true
  local tok
  tok="$(openssl rand -hex 16 2>/dev/null \
    || head -c 16 /dev/urandom 2>/dev/null | od -An -vtx1 | tr -d ' \n')"
  if [ -z "$tok" ]; then
    return 1
  fi
  printf '%s' "$tok" > "$dir/skill-token"
  chmod 600 "$dir/skill-token" 2>/dev/null || true
  printf '%s\n' "$tok"
}

_mcl_state_valid() {
  # Return 0 if stdin is parseable JSON with schema_version 1, 2, or 3.
  # Older files are accepted so mcl_state_init can migrate them in-place.
  # Uses `python3 -c` (not heredoc) so the piped body isn't shadowed.
  python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    assert isinstance(obj, dict)
    assert obj.get("schema_version") in (1, 2, 3)
    assert isinstance(obj.get("current_phase"), (int, float))
    assert 1 <= obj["current_phase"] <= 6
except Exception:
    sys.exit(1)
' 2>/dev/null
}

_mcl_state_migrate_to_v3() {
  # Read the current file, migrate to v3 schema (10.0.0), rewrite atomically.
  # Migration rules (10.0.0):
  #   - schema_version → 3
  #   - current_phase ∈ {2, 3} → 3 (treat past-spec-review as IMPLEMENTATION)
  #   - current_phase = 4 → 3 (old EXECUTE → new IMPLEMENTATION)
  #   - current_phase = 4.5 / 4.6 → 4 (RISK_GATE)
  #   - current_phase ∈ {5, 6} unchanged
  #   - spec_approved=true → design_approved=true (default false otherwise)
  #   - is_ui_project default true (safe non-trigger; old projects don't reprompt)
  #   - design_approved default true (don't retrigger old project's UI review)
  #   - drop spec_approved, precision_audit_block_count,
  #     precision_audit_skipped, phase_review_state
  #   - rename phase4_*_scan_done → phase4_*_scan_done; phase4_high_baseline
  #     → phase4_high_baseline; phase4_batch_decision → phase4_batch_decision
  [ -f "$MCL_STATE_FILE" ] || return 0
  local body migrated
  body="$(cat "$MCL_STATE_FILE" 2>/dev/null)" || return 1
  cp "$MCL_STATE_FILE" "${MCL_STATE_FILE}.backup.pre-v3" 2>/dev/null || true
  migrated="$(printf '%s' "$body" | python3 -c '
import json, sys, time
obj = json.loads(sys.stdin.read())
old_phase = obj.get("current_phase", 1)
old_pname = (obj.get("phase_name") or "").upper()
spec_approved = bool(obj.get("spec_approved"))
ui_active    = bool(obj.get("ui_flow_active"))

# Phase renumbering
try:
    cp = float(old_phase)
except Exception:
    cp = 1.0
if cp in (2.0, 3.0):
    new_phase = 3
elif cp == 4.0:
    new_phase = 3
elif cp in (4.5, 4.6):
    new_phase = 4
elif cp == 5.0:
    new_phase = 5
elif cp >= 6.0:
    new_phase = 6
else:
    new_phase = 1

phase_name_map = {
    1: "INTENT",
    2: "DESIGN_REVIEW",
    3: "IMPLEMENTATION",
    4: "RISK_GATE",
    5: "VERIFICATION",
    6: "FINAL_REVIEW",
}
obj["schema_version"]    = 3
obj["current_phase"]     = new_phase
obj["phase_name"]        = phase_name_map.get(new_phase, "INTENT")

# is_ui_project: default true for old projects (avoids requiring re-detect),
# but if ui_flow_active was set it was definitely a UI project.
obj["is_ui_project"]     = obj.get("is_ui_project", ui_active or True)
# design_approved: true if old project already had spec_approved=true
# (so post-migration the project does not retrigger UI review askq).
obj["design_approved"]   = obj.get("design_approved", spec_approved or True)

# 10.0.0 deletes spec_approved, phase_review_state, precision_audit_*.
# Test contract (test-state-migration-v3.sh) requires all four absent
# after migration. Phase 1.7 skip + Phase 4 dialog will treat absent
# fields as default (count=0 / state=null) — same effective behavior.
for f in ("spec_approved", "phase_review_state",
          "precision_audit_block_count", "precision_audit_skipped"):
    obj.pop(f, None)

# Rename phase4_5_* → phase4_*
rename_map = {
    "phase4_5_security_scan_done": "phase4_security_scan_done",
    "phase4_5_db_scan_done":       "phase4_db_scan_done",
    "phase4_5_ui_scan_done":       "phase4_ui_scan_done",
    "phase4_5_ops_scan_done":      "phase4_ops_scan_done",
    "phase4_5_perf_scan_done":     "phase4_perf_scan_done",
    "phase4_5_high_baseline":      "phase4_high_baseline",
    "phase4_5_batch_decision":     "phase4_batch_decision",
}
for old_k, new_k in rename_map.items():
    if old_k in obj and new_k not in obj:
        obj[new_k] = obj.pop(old_k)
    else:
        obj.pop(old_k, None)

obj.setdefault("spec_format_warn_count", 0)
obj["last_update"] = int(time.time())
print(json.dumps(obj, indent=2))
' 2>/dev/null)"
  [ -n "$migrated" ] || return 1
  _mcl_state_write_raw "$migrated" || return 1
  mcl_audit_log "state-migrated-10.0.0" "$(basename "${0:-unknown}")" "backup=${MCL_STATE_FILE}.backup.pre-v3"
}

mcl_state_init() {
  mkdir -p "$MCL_STATE_DIR" 2>/dev/null || true
  if [ ! -f "$MCL_STATE_FILE" ]; then
    _mcl_state_write_raw "$(_mcl_state_default)"
    return 0
  fi
  # File exists — check if it needs migration to v3.
  local current_version
  current_version="$(python3 -c '
import json, sys
try:
    obj = json.load(open(sys.argv[1]))
    print(obj.get("schema_version", 0))
except Exception:
    print(0)
' "$MCL_STATE_FILE" 2>/dev/null)"
  if [ "$current_version" != "3" ]; then
    _mcl_state_migrate_to_v3
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
    # 8.10.0: corrupt-state recovery is non-blocking (CHANGELOG-documented
    # exception to silent-fallback rule — recovery safety > silent-pause).
    # Audit makes it visible.
    mcl_audit_log "state-corrupt-recovered" "$(basename "${0:-mcl-state.sh}")" \
      "path=${MCL_STATE_FILE}.corrupt" 2>/dev/null || true
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
    # Caller field reflects the auth path: hook entry → basename of $0;
    # skill-token path → "skill-prose" (set by _mcl_state_auth_check).
    local _caller
    _caller="${MCL_AUTH_CALLER:-$(basename "${0:-unknown}")}"
    mcl_audit_log "set" "$_caller" "field=${field} value=${value}"
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

# Known stack tags — kept in sync with hooks/lib/mcl-stack-detect.sh.
# Used by _mcl_validate_stack_tags to validate phase1_stack_declared.
_MCL_KNOWN_STACK_TAGS="typescript javascript react-frontend vue-frontend svelte-frontend html-static python java csharp ruby php go rust db-postgres db-mysql db-sqlite db-mariadb db-mongo db-redis db-bigquery db-snowflake db-dynamodb orm-prisma orm-sqlalchemy orm-django orm-activerecord orm-sequelize orm-typeorm orm-gorm orm-eloquent cli data-pipeline ml-inference"

_mcl_validate_stack_tags() {
  # Validate a comma-separated stack-tag CSV against the known-tag set.
  # Prints a WARN line per unknown tag to stderr. Returns 0 if all known,
  # 1 if any unknown. Empty/whitespace tokens are ignored.
  local csv="${1:-}"
  [ -z "$csv" ] && return 0
  local bad=() t
  local IFS=','
  for t in $csv; do
    t="$(echo "$t" | tr -d '[:space:]')"
    [ -z "$t" ] && continue
    case " $_MCL_KNOWN_STACK_TAGS " in
      *" $t "*) ;;
      *) bad+=("$t") ;;
    esac
  done
  if [ ${#bad[@]} -gt 0 ]; then
    echo "[mcl] WARN: unknown stack tag(s): ${bad[*]}" >&2
    echo "[mcl] known tags: $_MCL_KNOWN_STACK_TAGS" >&2
    mcl_audit_log "stack-tag-unknown" "$(basename "${0:-unknown}")" "tags=${bad[*]}"
    return 1
  fi
  return 0
}

mcl_get_active_phase() {
  # Returns a single effective phase string from current_phase + UI signals.
  #
  # Effective phase values (10.0.0):
  #   "1"   Phase 1 — INTENT (questions, precision audit)
  #   "2"   Phase 2 — DESIGN_REVIEW (UI skeleton + design askq, UI projects only)
  #   "3"   Phase 3 — IMPLEMENTATION (📋 Spec emit + code)
  #   "4"   Phase 4 — RISK_GATE (security/db/ui/ops/perf scans)
  #   "5"   Phase 5 — VERIFICATION (test/lint/build/smoke report)
  #   "6"   Phase 6 — FINAL_REVIEW (double-check / forensic audit)
  #   "?"   indeterminate (state inconsistent or unreadable)
  #
  # Optional arg: path to state.json (default: $MCL_STATE_FILE)
  local state_file="${1:-${MCL_STATE_FILE}}"
  [ -f "$state_file" ] || { echo "1"; return 0; }

  python3 - "$state_file" 2>/dev/null <<'PYEOF'
import json, sys

try:
    obj = json.loads(open(sys.argv[1]).read())
except Exception:
    print("?"); sys.exit(0)

phase = obj.get("current_phase") or 1
try:
    p = int(phase)
except Exception:
    p = 1
if p < 1 or p > 6:
    p = 1
print(str(p))
PYEOF
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
