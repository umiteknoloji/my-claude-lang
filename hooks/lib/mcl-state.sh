#!/bin/bash
# MCL State — .mcl/state.json schema + atomic helpers.
#
# Sourceable library AND CLI. All reads survive corruption by falling
# back to a default Aşama-1 state and logging to stderr. All writes use
# tmp-file + mv (atomic rename) so a crash mid-write cannot leave the
# state file half-serialized.
#
# State file lives at `<project>/.mcl/state.json` — one file per working
# directory.
#
# Schema v3 (since MCL 9.0.0; valid-range widened in v10.1.20 for v11
# migration — see ~/.claude/plans/g-zel-bi-plan-yap-iridescent-star.md):
#   current_phase: 1, 4, 7, 11 (coarse buckets — Aşama 1=GATHER,
#                  4=SPEC_REVIEW, 7=EXECUTE, 11=DELIVER)
#   Schema v3 stores coarse buckets only; the v11 migration extends the
#   valid range to [1..21] so future quality-phase buckets (10..17 in
#   v11 numbering) and tail-rename buckets (18..21) can be persisted
#   without a schema_version bump. Sub-states refine within EXECUTE:
#   pattern_scan_due, ui_sub_phase, risk_review_state,
#   quality_review_state.
#
# Schema v3 is INCOMPATIBLE with prior versions. On schema mismatch the
# state file is reset to v3 default — no migration. v9.0.0 is a major
# rewrite; in-progress task state from older MCL is discarded.
#
# CLI usage:
#   mcl-state.sh init                          # create default if missing
#   mcl-state.sh get <field>                   # print one field
#   mcl-state.sh dump                          # print full JSON
#
# Sourced usage:
#   source hooks/lib/mcl-state.sh
#   mcl_state_get current_phase
#   mcl_state_set spec_approved true

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
  "phase_name": "GATHER",
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
  "pattern_summary": null,
  "pattern_level": null,
  "pattern_ask_pending": false,
  "precision_audit_done": false,
  "risk_review_state": null,
  "quality_review_state": null,
  "open_severity_count": 0,
  "tdd_compliance_score": null,
  "rollback_sha": null,
  "rollback_notice_shown": false,
  "tdd_last_green": null,
  "last_write_ts": null,
  "plan_critique_done": false,
  "restart_turn_ts": null,
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
  # Return 0 if stdin is parseable JSON with v3 schema. Older schemas
  # are rejected so mcl_state_init can reset them to v3 default — no
  # backward-compat migration in v9.0.0.
  python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    assert isinstance(obj, dict)
    assert obj.get("schema_version") == 3
    assert isinstance(obj.get("current_phase"), int)
    assert 1 <= obj["current_phase"] <= 22
except Exception:
    sys.exit(1)
' 2>/dev/null
}

mcl_state_init() {
  mkdir -p "$MCL_STATE_DIR" 2>/dev/null || true
  if [ ! -f "$MCL_STATE_FILE" ]; then
    _mcl_state_write_raw "$(_mcl_state_default)"
    return 0
  fi
  # File exists — check schema version. On mismatch, reset (no migration).
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
    cp "$MCL_STATE_FILE" "${MCL_STATE_FILE}.pre-v9-backup" 2>/dev/null || true
    _mcl_state_write_raw "$(_mcl_state_default)"
    mcl_audit_log "schema-reset-to-v3" "$(basename "${0:-unknown}")" "old_version=${current_version} backup=${MCL_STATE_FILE}.pre-v9-backup"
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
    echo "mcl-state: corrupt or wrong-schema state file, returning default (keeping copy at ${MCL_STATE_FILE}.corrupt)" >&2
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
  #
  # Timestamp format (since v10.1.13): UTC ISO 8601 (e.g.
  # `2026-05-03T13:42:30Z`) — matches `mcl_trace_append` format so
  # session_ts filtering in scanners can use direct string comparison
  # without timezone or format mismatch. Prior to v10.1.13 audit used
  # local time with space separator (`2026-05-03 13:42:30`); when
  # compared against trace's ISO format, the space (0x20) sorted
  # BEFORE 'T' (0x54), causing all audit entries to be filtered as
  # stale and recovery emits to never reach the scanner.
  local dir="${MCL_STATE_DIR}"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s | %s | %s | %s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" "$3" \
    >> "$dir/audit.log" 2>/dev/null || true
}

_mcl_is_devtime() {
  # v13.0.13 — Devtime / runtime ayrımı.
  # Devtime: CLAUDE_PROJECT_DIR yolunda 'my-claude-lang' geçiyor (MCL'in
  # kendi geliştirme repo'su) VEYA MCL_DEVTIME=1 env var manuel olarak set.
  # Runtime: kullanıcının kendi projesi.
  # Devtime'da REASON metinleri uzun + İngilizce + tam debug.
  # Runtime'da REASON metinleri kısa + Türkçe + dostça (kullanıcı korkmasın).
  [ "${MCL_DEVTIME:-0}" = "1" ] && return 0
  case "${CLAUDE_PROJECT_DIR:-$(pwd)}" in
    *my-claude-lang*) return 0 ;;
    *) return 1 ;;
  esac
}

_mcl_runtime_reason() {
  # Helper: REASON metni için devtime/runtime ayrımı.
  # Kullanım:
  #   REASON="$(_mcl_runtime_reason "long debug text" "kısa Türkçe mesaj")"
  # Devtime → 1. argüman; runtime → 2. argüman.
  if _mcl_is_devtime; then
    printf '%s' "$1"
  else
    printf '%s' "$2"
  fi
}

_mcl_pre_spec_audit_chain_status() {
  # v13.0.18 — Spec-approve advance prerequisitlerini kontrol eder.
  # Aşama 4 spec onayı askq'si onaylandığında, Aşama 1, 2, 3'ün gerçekten
  # tamamlandığını kanıtlayan audit'ler audit.log'da bulunmalı. Eksikse
  # spec-approve advance hakkı kazanılmamış demektir (atlama tespit).
  #
  # Kontrol edilen audit'ler (canonical sıra):
  #   * summary-confirm-approve   → Aşama 1 onayı
  #   * asama-2-complete          → Aşama 2 closing askq onayı
  #   * asama-3-complete          → Aşama 3 engineering brief tamamlandı
  #
  # Stdout: ya "ok" ya da virgülle ayrılmış eksik audit isimleri listesi.
  # (Boş çıktı = uygunsuz girdi / hata, defansif olarak "ok" kabul edilir.)
  command -v python3 >/dev/null 2>&1 || { echo "ok"; return 0; }
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  python3 - "$audit_file" "$trace_file" 2>/dev/null <<'PYEOF' || echo "ok"
import os, sys
audit_path, trace_path = sys.argv[1], sys.argv[2]
session_ts = ""
try:
    if os.path.isfile(trace_path):
        for line in open(trace_path, "r", encoding="utf-8", errors="replace"):
            if "| session_start |" in line:
                session_ts = line.split("|", 1)[0].strip()
except Exception:
    pass

required = ["summary-confirm-approve", "asama-2-complete", "asama-3-complete"]
seen = set()
try:
    if os.path.isfile(audit_path):
        for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
            ts = line.split("|", 1)[0].strip()
            if session_ts and ts < session_ts:
                continue
            for req in required:
                if f"| {req} |" in line:
                    seen.add(req)
except Exception:
    print("ok"); sys.exit(0)

missing = [r for r in required if r not in seen]
print("ok" if not missing else ",".join(missing))
PYEOF
}

_mcl_audit_emitted_in_session() {
  # Returns 1 if `event_name` audit fired in current session, else 0.
  # Optional `idem_marker` (arg 2): if that marker is also present in
  # the session, returns 0 (already-handled). Used by phase-progression
  # scanners and by v10.1.8 skip enforcement gate.
  #
  # Timestamp normalization (since v10.1.13): trace.log uses UTC ISO
  # 8601 (`YYYY-MM-DDTHH:MM:SSZ`), audit.log was using local-tz space-
  # separator format until v10.1.13 fixed it to ISO UTC. To handle
  # both old and new audit formats AND tolerate timezone mismatch,
  # parse both timestamps to epoch seconds via _norm() before
  # comparison. String compare alone failed because space (0x20) <
  # 'T' (0x54) caused all space-format audits to be filtered as stale.
  local event_name="$1"
  local idem_marker="${2:-}"
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo 0; return; fi
  python3 - "$audit_file" "$trace_file" "$event_name" "$idem_marker" 2>/dev/null <<'PYEOF' || echo 0
import datetime, os, sys
audit_path, trace_path, event_name, idem = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def _norm(ts):
    """Parse 'YYYY-MM-DDTHH:MM:SSZ' (UTC ISO) OR 'YYYY-MM-DD HH:MM:SS'
    (local) into epoch seconds. Returns 0.0 on parse failure."""
    if not ts:
        return 0.0
    try:
        if "T" in ts:
            return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
        return datetime.datetime.strptime(ts, "%Y-%m-%d %H:%M:%S").timestamp()
    except Exception:
        return 0.0

session_epoch = 0.0
try:
    if os.path.isfile(trace_path):
        for line in open(trace_path, "r", encoding="utf-8", errors="replace"):
            if "| session_start |" in line:
                session_epoch = _norm(line.split("|", 1)[0].strip())
except Exception:
    pass
emitted = False
already = False
try:
    needle_emit = f"| {event_name} |"
    needle_idem = f"| {idem} |" if idem else None
    for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
        ts_epoch = _norm(line.split("|", 1)[0].strip())
        if session_epoch and ts_epoch and ts_epoch < session_epoch:
            continue
        if needle_emit in line:
            emitted = True
        if needle_idem and needle_idem in line:
            already = True
except Exception:
    pass
print(1 if (emitted and not already) else 0)
PYEOF
}

_mcl_loop_breaker_count() {
  # Counts how many times a given audit event fired in the current
  # session. Used by hard-enforcement blocks to fail-open after 3
  # consecutive same-cause blocks so a stuck model cannot trap the
  # developer in an infinite loop. Session boundary = most recent
  # `session_start` event in trace.log.
  #
  # Timestamp normalization (since v10.1.13): see comment on
  # _mcl_audit_emitted_in_session for the format-mismatch backstory.
  local event="$1"
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo 0; return; fi
  python3 - "$audit_file" "$trace_file" "$event" 2>/dev/null <<'PYEOF' || echo 0
import datetime, os, sys
audit_path, trace_path, event = sys.argv[1], sys.argv[2], sys.argv[3]

def _norm(ts):
    if not ts:
        return 0.0
    try:
        if "T" in ts:
            return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
        return datetime.datetime.strptime(ts, "%Y-%m-%d %H:%M:%S").timestamp()
    except Exception:
        return 0.0

session_epoch = 0.0
try:
    if os.path.isfile(trace_path):
        with open(trace_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                if "| session_start |" in line:
                    session_epoch = _norm(line.split("|", 1)[0].strip())
except Exception:
    pass
count = 0
needle = f"| {event} |"
try:
    with open(audit_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if needle not in line:
                continue
            ts_epoch = _norm(line.split("|", 1)[0].strip())
            if not session_epoch or not ts_epoch or ts_epoch >= session_epoch:
                count += 1
except Exception:
    pass
print(count)
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
