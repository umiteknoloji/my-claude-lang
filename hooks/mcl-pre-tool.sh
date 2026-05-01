#!/bin/bash
# MCL PreToolUse Hook — mechanical gate that blocks mutating tools
# according to the 10.0.0 phase model.
#
# Block list (mutating tools): Write, Edit, MultiEdit, NotebookEdit
#
# Allow matrix (current_phase, is_ui_project, design_approved):
#   phase=1                                       → BLOCK (all paths)
#   phase=2 + is_ui_project=true                  → frontend paths only
#                                                   (backend / api / db
#                                                   denied with
#                                                   DESIGN_REVIEW LOCK
#                                                   reason; frontend
#                                                   pages/components/
#                                                   styles allowed)
#   phase>=3                                      → unlocked (all paths)
#
# Phase 2 → 3 transition fires when the developer approves the design
# askq ("Tasarımı onaylıyor musun?" / "Approve this design?"), setting
# design_approved=true and current_phase=3. For non-UI projects the
# Phase 1 summary-confirm askq advances directly 1→3.
#
# Additional guards on Phase 3+:
#   - Pattern scan (one-turn read of sibling files before first writes)
#   - Scope guard (block out-of-scope writes when scope_paths is set)
#   - Intent violation (HIGH severity blocks for "no backend" / "no DB"
#     / "no auth" intent + matching path)
#   - Severity scans (security / db / ui — HIGH blocks Write)
#

# Everything else (Read, Glob, Grep, WebFetch, WebSearch, TodoWrite,
# Bash, Task, ...) passes through unchanged. Bash and Task are handled
# by the prose layer in v1.

set -u

# Self-project guard: MCL must not process its own repo (recursive friction).
_MCL_REPO_PATH_SG="${MCL_REPO_PATH:-$HOME/my-claude-lang}"
_MCL_CWD_SG="$(cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null && pwd || true)"
_MCL_REPO_SG="$(cd "$_MCL_REPO_PATH_SG" 2>/dev/null && pwd || true)"
if [ -n "$_MCL_REPO_SG" ] && [ "$_MCL_CWD_SG" = "$_MCL_REPO_SG" ]; then
  cat >/dev/null 2>&1 || true
  exit 0
fi

# Hook health timestamp (since 8.2.7) — writes hook_last_run_ts to
# .mcl/hook-health.json so `mcl check-up` can detect an unregistered or
# silently broken hook (no recent timestamp = WARN).
_HH_FILE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/hook-health.json"
mkdir -p "$(dirname "$_HH_FILE")" 2>/dev/null || true
python3 - "$_HH_FILE" "pre_tool" "$(date +%s)" 2>/dev/null <<'PYEOF' || true
import json, os, sys
path, hook, ts = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = {}
try:
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            data = {}
except Exception:
    data = {}
data[hook] = ts
tmp = path + ".tmp"
try:
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp, path)
except Exception:
    pass
PYEOF

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mcl-state.sh
source "$SCRIPT_DIR/lib/mcl-state.sh"
# shellcheck source=lib/mcl-trace.sh
[ -f "$SCRIPT_DIR/lib/mcl-trace.sh" ] && source "$SCRIPT_DIR/lib/mcl-trace.sh"
# shellcheck source=lib/mcl-pause.sh
[ -f "$SCRIPT_DIR/lib/mcl-pause.sh" ] && source "$SCRIPT_DIR/lib/mcl-pause.sh"

# 8.10.0 sticky pause check — short-circuit any tool while paused.
if command -v mcl_pause_check >/dev/null 2>&1 && [ "$(mcl_pause_check)" = "true" ]; then
  mcl_audit_log "pause-sticky-block" "mcl-pre-tool" "tool=${TOOL_NAME:-unknown}"
  _PAUSE_REASON="$(mcl_pause_block_reason 2>/dev/null)"
  python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": sys.argv[1]
    }
}))
' "$_PAUSE_REASON" 2>/dev/null
  exit 0
fi

RAW_INPUT="$(cat 2>/dev/null || true)"

TOOL_NAME="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("tool_name", "") or "")
except Exception:
    pass
' 2>/dev/null)"

TRANSCRIPT_PATH="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("transcript_path", "") or "")
except Exception:
    pass
' 2>/dev/null)"

# Trace: Task tool dispatch records which subagent MCL invoked.
if [ "$TOOL_NAME" = "Task" ] && command -v mcl_trace_append >/dev/null 2>&1; then
  SUBAGENT_TYPE="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("subagent_type","") or "")
except Exception:
    pass
' 2>/dev/null)"
  [ -n "$SUBAGENT_TYPE" ] && mcl_trace_append plugin_dispatched "$SUBAGENT_TYPE"
fi

# -------- Branch: plugin gate (hard gate, overrides phase logic) --------
# When `plugin_gate_active=true` in state, mutating tools AND writer-Bash
# commands are denied regardless of phase/approval. Read-only tools still
# pass through. The gate is set by mcl-activate.sh on the first message of
# a session when curated / LSP plugins or their binaries are missing.
PLUGIN_GATE_ACTIVE="$(mcl_state_get plugin_gate_active 2>/dev/null)"
if [ "$PLUGIN_GATE_ACTIVE" = "true" ]; then
  GATE_DENY=0
  case "$TOOL_NAME" in
    Write|Edit|MultiEdit|NotebookEdit)
      GATE_DENY=1
      ;;
    Bash)
      BASH_CMD="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("command","") or "")
except Exception:
    pass
' 2>/dev/null)"
      if [ -n "$BASH_CMD" ]; then
        IS_WRITER="$(printf '%s' "$BASH_CMD" | python3 -c '
import re, sys
cmd = sys.stdin.read()
# Shell-redirection writers: `> file`, `>> file`, `>|`, `|& tee`.
if re.search(r"(^|[^<>&0-9])>>?\s*[^&\s]", cmd) or re.search(r"\btee\b(?!\s*--help)", cmd):
    print("1"); sys.exit(0)
# Mutating commands at token boundary.
token_re = r"(?:^|[\s|;&`(])"
patterns = [
    token_re + r"(rm|mv|cp|touch|mkdir|rmdir|chmod|chown|chgrp|ln|truncate|dd|patch|install|unlink)\b",
    token_re + r"sed\b[^|;&`]*?\s-i\b",
    token_re + r"git\s+(commit|push|add|rm|mv|reset|checkout|restore|switch|rebase|merge|pull|fetch|init|clone|stash|tag|branch|clean|cherry-pick|revert|apply|am|worktree)\b",
    token_re + r"(npm|yarn|pnpm|bun|pip|pip3|poetry|uv|gem|bundle|cargo|go|brew|apt|apt-get|dnf|yum|pacman|zypper)\s+(install|i|ci|add|remove|uninstall|update|upgrade|mod)\b",
    # NOTE: we deliberately do NOT block `bash foo.sh` / `python3 foo.py`.
    # Read-only helper scripts (our own `mcl-plugin-gate.sh check`, lint
    # dry-runs, stat collectors) would otherwise be false-positived. Real
    # mutating scripts still hit the other patterns when they reach a
    # mutating shell command inside.
    token_re + r"(docker|docker-compose|kubectl|terraform|ansible|helm|systemctl|launchctl)\s+\w+",
    token_re + r"(curl|wget)\s+[^|;&`]*(-o|--output|-O|--download)\b",
]
for p in patterns:
    if re.search(p, cmd):
        print("1"); sys.exit(0)
print("0")
' 2>/dev/null)"
        [ "$IS_WRITER" = "1" ] && GATE_DENY=1
      fi
      ;;
    *)
      # Read-only tools (Read, Glob, Grep, TodoWrite, WebFetch, WebSearch, Task, AskUserQuestion, ...).
      ;;
  esac
  if [ "$GATE_DENY" = "1" ]; then
    MISSING_SUMMARY="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        obj = json.load(f)
    arr = obj.get("plugin_gate_missing") or []
    bits = []
    for item in arr:
        k = item.get("kind")
        if k == "plugin":
            bits.append("plugin:" + item.get("name",""))
        elif k == "binary":
            bits.append("binary:" + item.get("plugin","") + "/" + item.get("name",""))
    print(" ".join(bits))
except Exception:
    print("")
' "$MCL_STATE_FILE" 2>/dev/null)"
    GATE_REASON="MCL PLUGIN GATE — required plugins or binaries are missing (${MISSING_SUMMARY}). Mutating tools and writer-Bash commands are blocked for this project until every missing item is installed and MCL reloads in a new session. Read-only tools (Read / Grep / Glob / read-only Bash) still work. Tell the developer which items are missing and the /plugin install commands; do NOT retry the blocked tool."
    mcl_audit_log "plugin-gate-block" "pre-tool" "tool=${TOOL_NAME} missing=${MISSING_SUMMARY}"
    mcl_debug_log "pre-tool" "plugin-gate-block" "tool=${TOOL_NAME}"
    python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason
    }
}))
' "$GATE_REASON"
    exit 0
  fi
fi

# -------- Project isolation pattern definition (since 9.1.3) --------
# The actual isolation BRANCH lives further down in this file, after
# the Phase 1-3 hook-debug branches (Bash + Read/Grep/Glob). Order
# matters: hook-debug fires first to deny `~/.mcl/lib/...` reads in
# Phase 1-3 with the "trust the pipeline" reason; isolation fires
# after with the broader "outside CLAUDE_PROJECT_DIR" reason. If
# isolation went first, its `~/.mcl` whitelist would mask hook-debug.
# Defining the helper here keeps the long Python heredoc out of the
# branch site below.
_iso_check_python='
import json, os, re, sys

_proj = sys.argv[1].rstrip("/")
_tool = sys.argv[2]

try:
    obj = json.loads(sys.stdin.read())
    ti = obj.get("tool_input") or {}
except Exception:
    print(""); sys.exit(0)

home = os.path.expanduser("~")

# Whitelist: prefixes any project may legitimately reach.
ALLOW = [
    _proj,
    "/tmp", "/private/tmp", "/var/tmp", "/var/folders",
    home + "/.npm", home + "/.cache",
    home + "/.yarn", home + "/.pnpm-store",
    home + "/.cargo", home + "/.rustup",
    home + "/.gradle", home + "/.m2",
    home + "/.bun",
    home + "/.claude/skills/my-claude-lang",
    home + "/.claude/skills/my-claude-lang.md",
    home + "/.claude/hooks/lib/mcl-stack-detect.sh",
    home + "/.mcl",
    "/usr",
]
def _norm(p):
    p = os.path.expanduser(p)
    if not os.path.isabs(p):
        # Relative paths interpret against project (CWD == project for
        # MCL hook subprocess); reject obvious lexical escape.
        if p.startswith("../") or p == ".." or "/../" in p or p.endswith("/.."):
            return None
        return os.path.normpath(os.path.join(_proj, p))
    return os.path.normpath(p)

def _allowed(abs_p):
    if abs_p is None:
        return False
    for a in ALLOW:
        a_norm = os.path.normpath(os.path.expanduser(a))
        if abs_p == a_norm or abs_p.startswith(a_norm + "/"):
            return True
    return False

if _tool == "Bash":
    cmd = ti.get("command", "") or ""
    # Pattern 1: dangerous cd/pushd targets — lexical escape.
    # Pattern 1b: any `../` argv token in any command (cat ../x,
    # node ../bin/cli.js, mv ../a ./b, etc.). Anchored with a
    # whitespace / shell-separator left context so `1..10` brace
    # expansion does not false-positive.
    escapes = [
        r"(?:^|[;&|\s])cd\s+\.\.(?:[/\s;&|]|$)",
        r"(?:^|[;&|\s])pushd\s+\.\.(?:[/\s;&|]|$)",
        r"(?:^|[;&|\s])cd\s+~(?:/[^;&|\s]*)?(?:[;&|\s]|$)",
        r"(?:^|[;&|\s])cd\s+\$HOME(?:/[^;&|\s]*)?(?:[;&|\s]|$)",
        r"(?:^|[;&|=\s])\.\./",
    ]
    for p in escapes:
        if re.search(p, cmd):
            print("block:cd-escape:" + cmd[:80].replace("\n"," "))
            sys.exit(0)
    # Pattern 2: absolute / tilde-prefixed path tokens that escape the
    # project + whitelist. Token-scan; reject the first non-allowed.
    # Negative lookbehind includes `.` so relative paths like `./bin`
    # or `../sibling` will not get their `/foo/bar` suffix captured
    # as a standalone absolute path. Lexical-escape (`../`) is still
    # caught by the cd/pushd patterns above; relative `./x` is
    # project-local.
    abs_re = re.compile(
        r"(?<![\w/=:.])(/[A-Za-z0-9._\-/]+|~/[A-Za-z0-9._\-/]+)"
    )
    for m in abs_re.finditer(cmd):
        tok = m.group(0)
        # Pure root "/" tokens etc. — skip; only longer paths are signal.
        if len(tok) < 2:
            continue
        # Drop trailing punctuation that may have been captured.
        tok = tok.rstrip(".,;:)\"’”")
        norm = _norm(tok)
        if norm and not _allowed(norm):
            print("block:abs:" + tok[:80])
            sys.exit(0)
elif _tool in ("Read", "Write", "Edit", "MultiEdit", "Glob", "Grep", "NotebookEdit"):
    # Collect every input field that carries a path-like value.
    candidates = []
    for k in ("file_path", "path", "notebook_path"):
        v = ti.get(k)
        if isinstance(v, str) and v:
            candidates.append(v)
    pat = ti.get("pattern")
    if isinstance(pat, str) and pat:
        # Only treat pattern as a path if it looks absolute/tilde or
        # has an escape segment — pure globs like "src/**/*.ts" are
        # project-relative and fine.
        if pat.startswith("/") or pat.startswith("~/") or \
           pat.startswith("../") or "/../" in pat:
            candidates.append(pat)
    for c in candidates:
        norm = _norm(c)
        if norm is None:
            print("block:relpath-escape:" + c[:80]); sys.exit(0)
        if not _allowed(norm):
            print("block:abs:" + c[:80]); sys.exit(0)
print("")
'

# 8.19.2: superpowers:brainstorming hook block REMOVED.
# Root-cause cut: install-claude-plugins.sh no longer installs the
# superpowers plugin (8.19.2), so its `using-superpowers` SKILL.md
# never auto-loads, and the "ABSOLUTELY MUST invoke brainstorming"
# instruction that triggered the call site never reaches the model.
# All Skill calls now pass through this hook.

# -------- Branch: block TodoWrite in Phase 1-3 --------
# TodoWrite in Phase 1-3 duplicates / conflicts with MCL phase state.
# MCL manages phase state via state.json, not todo checklists.
# Phase 4+ TodoWrite is allowed (legitimate task tracking during code execution).
if [ "$TOOL_NAME" = "TodoWrite" ] && command -v python3 >/dev/null 2>&1; then
  _TW_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
  # Default: block if phase unknown (no state yet = new session = Phase 1).
  # Allow only when phase is explicitly >= 4.
  _TW_ALLOW=0
  [ -n "$_TW_PHASE" ] && [ "$_TW_PHASE" -ge 4 ] 2>/dev/null && _TW_ALLOW=1
  if [ "$_TW_ALLOW" = "0" ]; then
    mcl_audit_log "block-todowrite" "pre-tool" "phase=${_TW_PHASE}"
    # 8.19.1: modern permission-decision schema (see brainstorming branch
    # above for rationale).
    python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL ACTIVE (Phase 1-3) — TodoWrite is blocked. MCL manages phase state via state.json; Phase 1-3 todo checklists duplicate that and pull the model into a parallel workflow. Proceed directly with MCL Phase 1 parameter gathering."
    }
}))
' 2>/dev/null
    exit 0
  fi
fi
# TodoWrite in Phase 4+ passes through — allow.
if [ "$TOOL_NAME" = "TodoWrite" ]; then
  exit 0
fi

# -------- Branch: block hook/lib debugging Bash in Phase 1-3 (since 8.19.3) --------
# Real-session telemetry: when a Phase 1.7 precision-audit block fires,
# the model often interprets the technical reason (`transition-rewind`,
# `partial_spec`, etc.) as a bug to investigate — and starts cat-ing /
# greping `~/.mcl/lib/`, `~/.claude/hooks/`, `~/.mcl/projects/<key>/state/`.
# 50+ Bash calls per session in the worst case, none of which advance
# the pipeline. The skill's spec-approval-discipline section already
# forbids this ("NO HOOK FILE DEBUGGING") but enforcement was missing.
# Phase 4+ legitimate reasons exist (e.g., reading hook libs from
# Phase 4 code), so the block scopes to Phase 1-3 only.
if [ "$TOOL_NAME" = "Bash" ] && command -v python3 >/dev/null 2>&1; then
  _HD_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
  # Only fire when phase is explicitly 1, 2, or 3. Default-block on
  # unknown is too aggressive (early activation race with state init).
  case "$_HD_PHASE" in
    1|2|3)
      _HD_HIT="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, re, sys
try:
    obj = json.loads(sys.stdin.read())
    cmd = (obj.get("tool_input") or {}).get("command", "") or ""
except Exception:
    cmd = ""
# Patterns that indicate the model is reading MCL internals to debug.
# All target known MCL paths; edits here are intentional, not generic.
patterns = [
    r"~/\.mcl(/|\b)",
    r"\$HOME/\.mcl(/|\b)",
    r"/\.mcl/lib/",
    r"~/\.claude/hooks(/|\b)",
    r"\$HOME/\.claude/hooks(/|\b)",
    r"/\.claude/hooks/",
    r"~/\.mcl/projects/[^ ]*/state(/|\b)",
    r"/\.mcl/projects/[^/]+/(state|audit|trace)",
    r"mcl-state\.sh\b",
    r"mcl-stop\.sh\b",
    r"mcl-pre-tool\.sh\b",
    r"mcl-activate\.sh\b",
    r"mcl-phase6\.py\b",
    r"mcl-phase-detect\.py\b",
]
for p in patterns:
    if re.search(p, cmd):
        # Whitelist: skill-prose Bash invocations source mcl-state.sh
        # legitimately (token-path writes). Detect via the shebang-style
        # `source` + `mcl_state_set` / `mcl_audit_log` companion.
        if re.search(r"\bsource\b.*mcl-state\.sh", cmd) and \
           re.search(r"\b(mcl_state_set|mcl_audit_log|_mcl_validate_stack_tags)\b", cmd):
            break
        # Whitelist: stack detection invocation from Phase 1.7 prose.
        if re.search(r"\bmcl-stack-detect\.sh\s+detect\b", cmd):
            break
        print("block:" + cmd[:120])
        sys.exit(0)
print("")
' 2>/dev/null)"
      if printf '%s' "$_HD_HIT" | grep -q "^block:"; then
        _HD_CMD="${_HD_HIT#block:}"
        mcl_audit_log "block-hook-debug" "pre-tool" "tool=Bash phase=${_HD_PHASE} cmd=${_HD_CMD}"
        python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL ACTIVE (Phase 1-3) — reading MCL hook/lib/state files is blocked. The pipeline is healthy and self-managing; if a block fired (precision-audit / partial-spec / etc.), the only required action is to follow the block reason in your CURRENT response — not to debug the hook system. Allowed legitimate Phase 1.7 helpers: `bash ~/.claude/hooks/lib/mcl-stack-detect.sh detect $(pwd)`, and skill-prose `bash -c \"source ... mcl-state.sh; mcl_state_set ...\"`. Everything else under ~/.mcl/ or ~/.claude/hooks/ is off-limits until Phase 4. Trust the pipeline or type /mcl-restart."
    }
}))
' 2>/dev/null
        exit 0
      fi
      ;;
  esac
fi

# -------- Branch: block hook/lib debugging via Read/Grep/Glob in Phase 1-3 (9.0.0) --------
# Bash branch (above) catches `cat / grep / find` invocations. Real-session
# telemetry shows the model also reaches for the dedicated Read/Grep/Glob
# tools when looping. There is no legitimate Phase 1-3 reason to inspect
# `~/.mcl/lib/`, `~/.claude/hooks/`, or `~/.mcl/projects/<key>/state/`
# through these tools, so no whitelist is needed.
if { [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Grep" ] || [ "$TOOL_NAME" = "Glob" ]; } \
   && command -v python3 >/dev/null 2>&1; then
  _HDR_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
  case "$_HDR_PHASE" in
    1|2|3)
      _HDR_HIT="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, re, sys
try:
    obj = json.loads(sys.stdin.read())
    tool = obj.get("tool_name", "")
    ti = obj.get("tool_input") or {}
except Exception:
    print(""); sys.exit(0)

# Concatenate every input field that could carry a path: Read.file_path,
# Grep.path + .pattern, Glob.path + .pattern. Pattern is included because
# `Glob "**/mcl-state.sh"` is just as much a hook-debug attempt as a
# direct path.
candidates = []
for k in ("file_path", "path", "pattern"):
    v = ti.get(k)
    if isinstance(v, str):
        candidates.append(v)
blob = "\n".join(candidates)

patterns = [
    r"~/\.mcl(/|$|\b)",
    r"\$HOME/\.mcl(/|$|\b)",
    r"^/[^\n]*/\.mcl/(lib|projects)/",
    r"~/\.claude/hooks(/|$|\b)",
    r"\$HOME/\.claude/hooks(/|$|\b)",
    r"/\.claude/hooks/",
    r"\bmcl-state\.sh\b",
    r"\bmcl-stop\.sh\b",
    r"\bmcl-pre-tool\.sh\b",
    r"\bmcl-activate\.sh\b",
    r"\bmcl-phase6\.py\b",
    r"\bmcl-phase-detect\.py\b",
    r"\bmcl-test-coverage\.py\b",
]
for p in patterns:
    if re.search(p, blob):
        print("block:" + tool + ":" + blob[:120].replace("\n", " | "))
        sys.exit(0)
print("")
' 2>/dev/null)"
      if printf '%s' "$_HDR_HIT" | grep -q "^block:"; then
        _HDR_DETAIL="${_HDR_HIT#block:}"
        mcl_audit_log "block-hook-debug" "pre-tool" "tool=${TOOL_NAME} phase=${_HDR_PHASE} input=${_HDR_DETAIL}"
        python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL ACTIVE (Phase 1-3) — Read / Grep / Glob on MCL hook/lib/state paths is blocked. There is no legitimate Phase 1-3 reason to inspect `~/.mcl/lib/`, `~/.claude/hooks/`, or `~/.mcl/projects/<key>/state/`. If a block fired (precision-audit / partial-spec / etc.), follow the block reason in your CURRENT response. Trust the pipeline or type /mcl-restart."
    }
}))
' 2>/dev/null
        exit 0
      fi
      ;;
  esac
fi

# -------- Branch: project isolation (since 9.1.3, all phases) --------
# Vaad #1: per-project state + per-project hook scope = "this MCL only
# knows this project". Real-session bug: model ran `cd /Users/umit &&
# npx create-next-app …` then Read /Users/umit/sibling-project/file.
# That violated the isolation contract.
#
# Order note: this branch fires AFTER the Phase 1-3 hook-debug
# branches above. Hook-debug denies `~/.mcl/lib/...` etc. with the
# narrow "trust the pipeline" reason; isolation here covers any
# cross-project boundary in any phase. The `~/.mcl` whitelist below
# would otherwise mask the hook-debug deny if isolation came first.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && command -v python3 >/dev/null 2>&1 \
   && [ -n "${TOOL_NAME:-}" ]; then
  case "$TOOL_NAME" in
    Bash|Read|Write|Edit|MultiEdit|Glob|Grep|NotebookEdit)
      _ISO_PROJ_REAL="$(cd "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd -P || printf '%s' "$CLAUDE_PROJECT_DIR")"
      _ISO_HIT="$(printf '%s' "$RAW_INPUT" \
        | python3 -c "$_iso_check_python" "$_ISO_PROJ_REAL" "$TOOL_NAME" 2>/dev/null)"
      if printf '%s' "$_ISO_HIT" | grep -q "^block:"; then
        _ISO_DETAIL="${_ISO_HIT#block:}"
        mcl_audit_log "block-isolation" "pre-tool" "tool=${TOOL_NAME} detail=${_ISO_DETAIL}"
        python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL ISOLATION — operations outside project directory ($CLAUDE_PROJECT_DIR) are blocked. Stay in the current project. Allowed system paths: build scratch (/tmp, /var/folders), package caches (~/.npm, ~/.cache, ~/.yarn, ~/.pnpm-store, ~/.cargo, ~/.gradle, ~/.m2, ~/.bun), MCL skill files (~/.claude/skills/my-claude-lang), Phase 1.7 stack-detect (~/.claude/hooks/lib/mcl-stack-detect.sh), MCL state (~/.mcl), system bins (/usr). For sibling project access, exit and re-enter MCL inside that project."
    }
}))
' 2>/dev/null
        exit 0
      fi
      ;;
  esac
fi

# 9.3.0: askq-incomplete-spec block REMOVED. Spec format is advisory
# only; the model can call AskUserQuestion at any time, and spec format
# violations no longer gate any tool call. Phase 1 summary-confirm askq
# is the only state-driving askq.

# -------- Branch: block Task dispatch of Phase 4/5 as sub-agent --------
# sub-agent-phase-discipline: Phase 4 (Risk Review), 4.6 (Impact Review),
# and Phase 5 (Verification Report) MUST run in the main MCL session as
# interactive AskUserQuestion dialogs. Sub-agents cannot substitute them.
if [ "$TOOL_NAME" = "Task" ] && command -v python3 >/dev/null 2>&1; then
  _TASK_DESC="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys, re
try:
    obj = json.loads(sys.stdin.read())
    tin = obj.get("tool_input") or {}
    desc = (tin.get("description") or tin.get("prompt") or "").lower()
    # Check for Phase 4/5 keywords indicating sub-agent substitution
    patterns = [
        r"phase\s*4\.5", r"phase\s*4\.6", r"phase\s*5",
        r"risk\s+review", r"impact\s+review", r"verification\s+report",
        r"phase\s+review", r"spec.compliance.review",
    ]
    for pat in patterns:
        if re.search(pat, desc):
            print("block:" + desc[:80])
            sys.exit(0)
except Exception:
    pass
print("")
' 2>/dev/null)"
  if printf '%s' "$_TASK_DESC" | grep -q "^block:"; then
    _MATCHED="${_TASK_DESC#block:}"
    mcl_audit_log "block-task-phase-dispatch" "pre-tool" "desc=${_MATCHED}"
    # 8.19.1: modern permission-decision schema.
    python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL SUB-AGENT DISCIPLINE — Phase 4 (Risk Review), Phase 4 (impact lens) (Impact Review), and Phase 5 (Verification Report) cannot be dispatched to sub-agents. These phases require the main MCL session to run the interactive AskUserQuestion dialog directly with the developer. Run them in this session after all code sub-agents complete."
    }
}))
' 2>/dev/null
    exit 0
  fi
fi
# -------- Branch: plan critique substance gate (Gap 3 + 8.3.3) --------
# Task with subagent_type containing "general-purpose" AND model containing
# "sonnet" is the plan-critique shape. 8.2.10 set plan_critique_done=true on
# this shape alone — bypassable via Task(prompt="say hi"). 8.3.3 adds an
# intent-validation step: pre-tool scans the transcript for a recent
# `Task(subagent_type=*mcl-intent-validator*)` call and reads its JSON
# verdict. Recursion-safe — the validator subagent has its own subagent_type
# so its own Task call passes through this gate without re-entry.
if [ "$TOOL_NAME" = "Task" ] && command -v python3 >/dev/null 2>&1; then
  _PCD_TASK_INFO="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    tin = obj.get("tool_input") or {}
    sub = (tin.get("subagent_type") or "").lower()
    mdl = (tin.get("model") or "").lower()
    if "general-purpose" in sub and "sonnet" in mdl:
        print(sub + "|" + mdl)
except Exception:
    pass
' 2>/dev/null)"
  if [ -n "$_PCD_TASK_INFO" ]; then
    _PCD_SUB="${_PCD_TASK_INFO%%|*}"
    _PCD_MDL="${_PCD_TASK_INFO#*|}"

    # 8.3.3: scan transcript for the most recent mcl-intent-validator Task
    # call + tool_result, parse the JSON verdict, branch accordingly.
    _PCD_VALIDATION="missing|"
    if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
      _PCD_VALIDATION="$(python3 - "$TRANSCRIPT_PATH" 2>/dev/null <<'PYEOF'
import json, sys

path = sys.argv[1]

tool_uses, tool_results, order = {}, {}, []

try:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            msg = obj.get("message") or obj
            if not isinstance(msg, dict):
                continue
            role = msg.get("role")
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for item in content:
                if not isinstance(item, dict):
                    continue
                t = item.get("type")
                if role == "assistant" and t == "tool_use" and item.get("name") == "Task":
                    inp = item.get("input") or {}
                    sub = (inp.get("subagent_type") or "").lower()
                    if "mcl-intent-validator" in sub:
                        tid = item.get("id") or ""
                        if tid:
                            tool_uses[tid] = inp
                            order.append(tid)
                elif role == "user" and t == "tool_result":
                    tid = item.get("tool_use_id") or ""
                    if tid in tool_uses:
                        raw = item.get("content")
                        text_val = ""
                        if isinstance(raw, str):
                            text_val = raw
                        elif isinstance(raw, list):
                            parts = [b.get("text", "") for b in raw
                                     if isinstance(b, dict) and b.get("type") == "text"]
                            text_val = "\n".join(parts)
                        tool_results[tid] = text_val
except Exception:
    pass

# Walk in reverse to find LATEST validator with a result.
for tid in reversed(order):
    res = tool_results.get(tid)
    if not res:
        continue
    # Try to extract the JSON object from the response. Validator is
    # instructed to return a single-line JSON; tolerate leading/trailing
    # whitespace and stray text — find the first {...} block.
    s = res.strip()
    parsed = None
    try:
        parsed = json.loads(s)
    except Exception:
        # Fallback: scan for a JSON object substring.
        depth = 0
        start = -1
        for i, ch in enumerate(s):
            if ch == "{":
                if depth == 0:
                    start = i
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0 and start >= 0:
                    try:
                        parsed = json.loads(s[start:i + 1])
                        break
                    except Exception:
                        pass
                    start = -1
    if not isinstance(parsed, dict):
        print("parse-error|invalid-json")
        sys.exit(0)
    verdict = (parsed.get("verdict") or "").strip().lower()
    reason = (parsed.get("reason") or "").strip()
    if verdict in ("yes", "no"):
        # Sanitize reason for audit log: strip pipes and newlines.
        reason = reason.replace("|", "/").replace("\n", " ").replace("\r", " ")
        if len(reason) > 120:
            reason = reason[:120] + "…"
        print(f"{verdict}|{reason}")
        sys.exit(0)
    print("parse-error|verdict-missing-or-invalid")
    sys.exit(0)

# No validator call found in transcript at all.
print("missing|")
PYEOF
)"
    fi
    _PCD_VVERDICT="${_PCD_VALIDATION%%|*}"
    _PCD_VREASON="${_PCD_VALIDATION#*|}"

    case "$_PCD_VVERDICT" in
      yes)
        mcl_state_set plan_critique_done true >/dev/null 2>&1 || true
        mcl_audit_log "plan-critique-done" "pre-tool" "subagent=${_PCD_SUB} model=${_PCD_MDL} intent_validated reason=${_PCD_VREASON}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_done "${_PCD_MDL}"
        ;;
      no)
        mcl_audit_log "plan-critique-substance-fail" "pre-tool" "intent=no reason=${_PCD_VREASON}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_substance_fail "intent=no"
        # 8.19.1: modern permission-decision schema.
        python3 -c '
import json, sys
reason_text = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL PLAN CRITIQUE SUBSTANCE GATE — Intent validator rejected the prompt. Reason: " + reason_text + ". Refine the Task prompt so it clearly carries plan critique intent (concrete plan reference + analytical scope), or skip the critique step if not needed."
    }
}))
' "$_PCD_VREASON" 2>/dev/null
        exit 0
        ;;
      missing)
        mcl_audit_log "plan-critique-substance-fail" "pre-tool" "validator=not-called"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_substance_fail "validator=not-called"
        # 8.19.1: modern permission-decision schema.
        python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL PLAN CRITIQUE SUBSTANCE GATE — Plan critique requires intent validation since 8.3.3. Before this Task(subagent_type=general-purpose, model=*sonnet*), dispatch Task(subagent_type=\"mcl-intent-validator\", prompt=<the same prompt>) FIRST. Wait for its JSON verdict; if {\"verdict\":\"yes\"} re-issue this Task; if {\"verdict\":\"no\"} refine the prompt or skip."
    }
}))
' 2>/dev/null
        exit 0
        ;;
      parse-error|*)
        # Fail-open: validator runtime issue (malformed output, transient
        # error). Don't lock the user out — proceed but record a warn so
        # patterns are visible via audit / mcl check-up.
        mcl_state_set plan_critique_done true >/dev/null 2>&1 || true
        mcl_audit_log "intent-validator-parse-error" "pre-tool" "fail-open detail=${_PCD_VREASON}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append intent_validator_parse_error
        ;;
    esac
  fi
fi

# Non-phase-dispatch Task calls pass through — allow.
if [ "$TOOL_NAME" = "Task" ]; then
  exit 0
fi

# -------- Branch: ExitPlanMode gate (Gap 3, since 8.2.10) --------
# Block ExitPlanMode when plan_critique_done is false. Critique subagent
# (Sonnet 4.6) must run before plan approval to avoid bias-aligned plans.
if [ "$TOOL_NAME" = "ExitPlanMode" ]; then
  _PLAN_CRITIQUE_DONE="$(mcl_state_get plan_critique_done 2>/dev/null)"
  if [ "$_PLAN_CRITIQUE_DONE" != "true" ]; then
    mcl_audit_log "plan-critique-block" "pre-tool" "tool=ExitPlanMode plan_critique_done=false"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_block
    # 8.19.1: modern permission-decision schema.
    python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL PLAN CRITIQUE GATE — Plan critique subagent (Sonnet 4.6) must run before plan approval. Call Agent (Task) with subagent_type containing \"general-purpose\" AND model containing \"sonnet\" to critique the plan, then re-attempt ExitPlanMode."
    }
}))
' 2>/dev/null
    exit 0
  fi
fi

# -------- Branch: protect .mcl/state.json from direct Bash writes --------
# MCL's state machine is owned exclusively by the hook system (mcl-state.sh).
# Direct writes to .mcl/state.json via Bash (cat >, echo >, tee, etc.) bypass
# phase transitions — e.g. manually setting current_phase=4 skips Phase 4a/4b.
if [ "$TOOL_NAME" = "Bash" ] && command -v python3 >/dev/null 2>&1; then
  _STATE_WRITE="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, re, sys
try:
    obj = json.loads(sys.stdin.read())
    cmd = (obj.get("tool_input") or {}).get("command","") or ""
    # Detect writes where the state file is the DIRECT target of >> or tee.
    # A >/dev/null or >> elsewhere in the command must NOT trigger.
    hits = re.findall(r">>?\s*([^\s;|&]+)", cmd)
    direct_write = any("state.json" in h for h in hits)
    tee_write = bool(re.search(r"\btee\b", cmd) and "state.json" in cmd
                     and not re.search(r"tee.*[|;&].*state\.json", cmd))
    if direct_write or tee_write:
        print("block")
    else:
        print("")
except Exception:
    pass
' 2>/dev/null)"
  if [ "$_STATE_WRITE" = "block" ]; then
    mcl_audit_log "block-state-write" "pre-tool" "cmd=direct-write-to-state-json"
    python3 -c '
import json, sys
print(json.dumps({
    "decision": "block",
    "reason": "MCL: Direct state.json writes forbidden. Transitions are hook-owned. To advance phase, emit a format-valid 📋 Spec: block — auto-approve fires on next Stop."
}))
' 2>/dev/null
    exit 0
  fi
fi

# Fast-path: non-mutating tool → allow.
# Skill, TodoWrite, and Task MCL-specific blocks run BEFORE this fast-path.
case "$TOOL_NAME" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

# -------- Security: secret / credential scan (all phases) --------
# Runs before the phase gate so credentials are blocked even in Phase 1-3.
# Never blocks on scanner error (fallback = safe).
_SECRET_SCAN_LIB="$SCRIPT_DIR/lib/mcl-secret-scan.py"
if [ -f "$_SECRET_SCAN_LIB" ] && command -v python3 >/dev/null 2>&1; then
  _SEC_RESULT="$(printf '%s' "$RAW_INPUT" | python3 "$_SECRET_SCAN_LIB" 2>/dev/null || echo safe)"
  if [ "${_SEC_RESULT%%|*}" = "block" ]; then
    _SEC_REASON="${_SEC_RESULT#block|}"
    mcl_audit_log "secret-scan-block" "pre-tool" "tool=${TOOL_NAME}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append secret_scan_block
    python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL SECURITY — " + reason
    }
}))
' "$_SEC_REASON" 2>/dev/null
    exit 0
  fi
fi

# Mutating tool attempted — consult state.
CURRENT_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
DESIGN_APPROVED="$(mcl_state_get design_approved 2>/dev/null)"
IS_UI_PROJECT="$(mcl_state_get is_ui_project 2>/dev/null)"
PHASE_NAME="$(mcl_state_get phase_name 2>/dev/null)"

# Default everything if state missing.
CURRENT_PHASE="${CURRENT_PHASE:-1}"
DESIGN_APPROVED="${DESIGN_APPROVED:-false}"
IS_UI_PROJECT="${IS_UI_PROJECT:-false}"
PHASE_NAME="${PHASE_NAME:-INTENT}"

# -------- Branch: Phase 4 incremental security scan (since 8.7.1) --------
# Edit/Write/MultiEdit to source files trigger HIGH-only quick scan.
# Cache-keyed (file SHA1 + rules version), MEDIUM/LOW silent audit only.
_SEC_SCAN_LIB="$SCRIPT_DIR/lib/mcl-security-scan.py"
if { [ "$CURRENT_PHASE" = "3" ] || [ "$CURRENT_PHASE" = "4" ]; } \
   && [ -f "$_SEC_SCAN_LIB" ] \
   && command -v python3 >/dev/null 2>&1 \
   && [ -n "${MCL_STATE_DIR:-}" ]; then
  case "$TOOL_NAME" in
    Edit|Write|MultiEdit)
      _SEC_TARGET_PATH="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("file_path") or "")
except Exception:
    pass' 2>/dev/null)"
      _SEC_EXT="${_SEC_TARGET_PATH##*.}"
      case "$_SEC_EXT" in
        ts|tsx|js|jsx|mjs|cjs|py|rb|go|rs|java|kt|swift|cs|php|cpp|cc|c|h|hpp|lua|vue|svelte|scala|dart)
          # Build hypothetical post-edit content into a temp file with same ext.
          _SEC_TMP="$(mktemp -t mcl-sec-pre.XXXXXX)" || _SEC_TMP=""
          if [ -n "$_SEC_TMP" ]; then
            _SEC_TMP_EXT="${_SEC_TMP}.${_SEC_EXT}"
            mv "$_SEC_TMP" "$_SEC_TMP_EXT" 2>/dev/null && _SEC_TMP="$_SEC_TMP_EXT"
            printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
from pathlib import Path
data = json.loads(sys.stdin.read())
tool = data.get("tool_name", "")
ti = data.get("tool_input", {}) or {}
target_real = ti.get("file_path") or ""
out = sys.argv[1]
content = ""
if tool == "Write":
    content = ti.get("content") or ""
else:
    try:
        content = Path(target_real).read_text(encoding="utf-8", errors="replace")
    except Exception:
        content = ""
    if tool == "Edit":
        old, new = ti.get("old_string", ""), ti.get("new_string", "")
        if old and old in content:
            content = content.replace(old, new, 1)
    elif tool == "MultiEdit":
        for ed in (ti.get("edits") or []):
            old, new = ed.get("old_string", ""), ed.get("new_string", "")
            if old and old in content:
                content = content.replace(old, new, 1)
Path(out).write_text(content, encoding="utf-8")
' "$_SEC_TMP" 2>/dev/null
            _SEC_RESULT_JSON="$(python3 "$_SEC_SCAN_LIB" \
              --mode=incremental \
              --state-dir "$MCL_STATE_DIR" \
              --project-dir "${CLAUDE_PROJECT_DIR:-$PWD}" \
              --target "$_SEC_TMP" \
              --lang "${MCL_USER_LANG:-tr}" 2>/dev/null || echo '{}')"
            if command -v mcl_pause_on_scan_error >/dev/null 2>&1 \
               && mcl_pause_on_scan_error "mcl-security-scan.py" "$_SEC_RESULT_JSON"; then
              rm -f "$_SEC_TMP" 2>/dev/null
              exit 0
            fi
            _SEC_BLOCK="$(printf '%s' "$_SEC_RESULT_JSON" | python3 -c '
import json, sys
try:
    r = json.loads(sys.stdin.read() or "{}")
except Exception:
    sys.exit(0)
high = [f for f in r.get("findings", []) if f.get("severity") == "HIGH"]
if not high:
    sys.exit(0)
top = high[0]
real = sys.argv[1] if len(sys.argv) > 1 else top.get("file", "")
rule = top.get("rule_id", "?")
owasp = top.get("owasp") or ""
line = top.get("line", 0)
msg = top.get("message", "")
suffix = " (OWASP " + owasp + ")" if owasp else ""
print(rule + suffix + " at " + real + ":" + str(line) + " — " + msg)
' "$_SEC_TARGET_PATH" 2>/dev/null)"
            rm -f "$_SEC_TMP" 2>/dev/null
            if [ -n "$_SEC_BLOCK" ]; then
              # Audit + block.
              _SEC_RULE="$(printf '%s' "$_SEC_BLOCK" | awk '{print $1}')"
              mcl_audit_log "security-scan-block" "mcl-pre-tool" "rule=${_SEC_RULE} tool=${TOOL_NAME} file=${_SEC_TARGET_PATH} severity=HIGH"
              python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL SECURITY — " + reason + ". Fix the issue and retry."
    }
}))
' "$_SEC_BLOCK" 2>/dev/null
              exit 0
            fi
          fi
          ;;
      esac
      ;;
  esac
fi
# -------- end of Phase 4 incremental security scan --------

# -------- Branch: Phase 4 incremental DB scan (since 8.8.0) --------
# Edit/Write/MultiEdit to schema/migration/model/source files trigger
# HIGH-only DB scan. Cache-keyed via mcl-db-scan.py. Skipped if no
# db-* stack tag detected.
_DB_SCAN_LIB="$SCRIPT_DIR/lib/mcl-db-scan.py"
if { [ "$CURRENT_PHASE" = "3" ] || [ "$CURRENT_PHASE" = "4" ]; } \
   && [ -f "$_DB_SCAN_LIB" ] \
   && command -v python3 >/dev/null 2>&1 \
   && [ -n "${MCL_STATE_DIR:-}" ]; then
  case "$TOOL_NAME" in
    Edit|Write|MultiEdit)
      _DB_TARGET_PATH="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("file_path") or "")
except Exception:
    pass' 2>/dev/null)"
      _DB_EXT="${_DB_TARGET_PATH##*.}"
      case "$_DB_EXT" in
        ts|tsx|js|jsx|mjs|cjs|py|rb|go|rs|java|kt|swift|cs|php|cpp|cc|c|h|hpp|lua|vue|svelte|scala|dart|sql|prisma)
          _DB_TMP="$(mktemp -t mcl-db-pre.XXXXXX)" || _DB_TMP=""
          if [ -n "$_DB_TMP" ]; then
            _DB_TMP_EXT="${_DB_TMP}.${_DB_EXT}"
            mv "$_DB_TMP" "$_DB_TMP_EXT" 2>/dev/null && _DB_TMP="$_DB_TMP_EXT"
            printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
from pathlib import Path
data = json.loads(sys.stdin.read())
tool = data.get("tool_name", "")
ti = data.get("tool_input", {}) or {}
target_real = ti.get("file_path") or ""
out = sys.argv[1]
content = ""
if tool == "Write":
    content = ti.get("content") or ""
else:
    try:
        content = Path(target_real).read_text(encoding="utf-8", errors="replace")
    except Exception:
        content = ""
    if tool == "Edit":
        old, new = ti.get("old_string", ""), ti.get("new_string", "")
        if old and old in content:
            content = content.replace(old, new, 1)
    elif tool == "MultiEdit":
        for ed in (ti.get("edits") or []):
            old, new = ed.get("old_string", ""), ed.get("new_string", "")
            if old and old in content:
                content = content.replace(old, new, 1)
Path(out).write_text(content, encoding="utf-8")
' "$_DB_TMP" 2>/dev/null
            _DB_RESULT_JSON="$(python3 "$_DB_SCAN_LIB" \
              --mode=incremental \
              --state-dir "$MCL_STATE_DIR" \
              --project-dir "${CLAUDE_PROJECT_DIR:-$PWD}" \
              --target "$_DB_TMP" \
              --lang "${MCL_USER_LANG:-tr}" 2>/dev/null || echo '{}')"
            if command -v mcl_pause_on_scan_error >/dev/null 2>&1 \
               && mcl_pause_on_scan_error "mcl-db-scan.py" "$_DB_RESULT_JSON"; then
              rm -f "$_DB_TMP" 2>/dev/null
              exit 0
            fi
            _DB_BLOCK="$(printf '%s' "$_DB_RESULT_JSON" | python3 -c '
import json, sys
try:
    r = json.loads(sys.stdin.read() or "{}")
except Exception:
    sys.exit(0)
if r.get("no_db_stack"):
    sys.exit(0)
high = [f for f in r.get("findings", []) if f.get("severity") == "HIGH"]
if not high:
    sys.exit(0)
top = high[0]
real = sys.argv[1] if len(sys.argv) > 1 else top.get("file", "")
rule = top.get("rule_id", "?")
cat = top.get("category", "")
line = top.get("line", 0)
msg = top.get("message", "")
suffix = " [" + cat + "]" if cat else ""
print(rule + suffix + " at " + real + ":" + str(line) + " — " + msg)
' "$_DB_TARGET_PATH" 2>/dev/null)"
            rm -f "$_DB_TMP" 2>/dev/null
            if [ -n "$_DB_BLOCK" ]; then
              _DB_RULE="$(printf '%s' "$_DB_BLOCK" | awk '{print $1}')"
              mcl_audit_log "db-scan-block" "mcl-pre-tool" "rule=${_DB_RULE} tool=${TOOL_NAME} file=${_DB_TARGET_PATH} severity=HIGH"
              python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL DB DESIGN — " + reason + ". Fix the design issue and retry."
    }
}))
' "$_DB_BLOCK" 2>/dev/null
              exit 0
            fi
          fi
          ;;
      esac
      ;;
  esac
fi
# -------- end of Phase 4 incremental DB scan --------

# -------- Branch: Phase 4 incremental UI scan (since 8.9.0) --------
# Edit/Write/MultiEdit to UI files trigger HIGH-only a11y-critical scan.
# Cache-keyed via mcl-ui-scan.py. Skipped if no fe stack tag.
_UI_SCAN_LIB="$SCRIPT_DIR/lib/mcl-ui-scan.py"
if { [ "$CURRENT_PHASE" = "3" ] || [ "$CURRENT_PHASE" = "4" ]; } \
   && [ -f "$_UI_SCAN_LIB" ] \
   && command -v python3 >/dev/null 2>&1 \
   && [ -n "${MCL_STATE_DIR:-}" ]; then
  case "$TOOL_NAME" in
    Edit|Write|MultiEdit)
      _UI_TARGET_PATH="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("file_path") or "")
except Exception:
    pass' 2>/dev/null)"
      _UI_EXT="${_UI_TARGET_PATH##*.}"
      case "$_UI_EXT" in
        tsx|jsx|ts|js|vue|svelte|html|css|scss)
          _UI_TMP="$(mktemp -t mcl-ui-pre.XXXXXX)" || _UI_TMP=""
          if [ -n "$_UI_TMP" ]; then
            _UI_TMP_EXT="${_UI_TMP}.${_UI_EXT}"
            mv "$_UI_TMP" "$_UI_TMP_EXT" 2>/dev/null && _UI_TMP="$_UI_TMP_EXT"
            printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
from pathlib import Path
data = json.loads(sys.stdin.read())
tool = data.get("tool_name", "")
ti = data.get("tool_input", {}) or {}
target_real = ti.get("file_path") or ""
out = sys.argv[1]
content = ""
if tool == "Write":
    content = ti.get("content") or ""
else:
    try:
        content = Path(target_real).read_text(encoding="utf-8", errors="replace")
    except Exception:
        content = ""
    if tool == "Edit":
        old, new = ti.get("old_string", ""), ti.get("new_string", "")
        if old and old in content:
            content = content.replace(old, new, 1)
    elif tool == "MultiEdit":
        for ed in (ti.get("edits") or []):
            old, new = ed.get("old_string", ""), ed.get("new_string", "")
            if old and old in content:
                content = content.replace(old, new, 1)
Path(out).write_text(content, encoding="utf-8")
' "$_UI_TMP" 2>/dev/null
            _UI_RESULT_JSON="$(python3 "$_UI_SCAN_LIB" \
              --mode=incremental \
              --state-dir "$MCL_STATE_DIR" \
              --project-dir "${CLAUDE_PROJECT_DIR:-$PWD}" \
              --target "$_UI_TMP" \
              --lang "${MCL_USER_LANG:-tr}" 2>/dev/null || echo '{}')"
            if command -v mcl_pause_on_scan_error >/dev/null 2>&1 \
               && mcl_pause_on_scan_error "mcl-ui-scan.py" "$_UI_RESULT_JSON"; then
              rm -f "$_UI_TMP" 2>/dev/null
              exit 0
            fi
            _UI_BLOCK="$(printf '%s' "$_UI_RESULT_JSON" | python3 -c '
import json, sys
try:
    r = json.loads(sys.stdin.read() or "{}")
except Exception:
    sys.exit(0)
if r.get("no_fe_stack"):
    sys.exit(0)
# Only block on HIGH a11y-critical findings.
high_a11y = [f for f in r.get("findings", []) if f.get("severity") == "HIGH" and f.get("category") == "ui-a11y"]
if not high_a11y:
    sys.exit(0)
top = high_a11y[0]
real = sys.argv[1] if len(sys.argv) > 1 else top.get("file", "")
rule = top.get("rule_id", "?")
line = top.get("line", 0)
msg = top.get("message", "")
print(rule + " at " + real + ":" + str(line) + " — " + msg)
' "$_UI_TARGET_PATH" 2>/dev/null)"
            rm -f "$_UI_TMP" 2>/dev/null
            if [ -n "$_UI_BLOCK" ]; then
              _UI_RULE="$(printf '%s' "$_UI_BLOCK" | awk '{print $1}')"
              mcl_audit_log "ui-scan-block" "mcl-pre-tool" "rule=${_UI_RULE} tool=${TOOL_NAME} file=${_UI_TARGET_PATH} severity=HIGH category=ui-a11y"
              python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "MCL UI A11Y — " + reason + ". Fix the accessibility issue and retry."
    }
}))
' "$_UI_BLOCK" 2>/dev/null
              exit 0
            fi
          fi
          ;;
      esac
      ;;
  esac
fi
# -------- end of Phase 4 incremental UI scan --------

# --- Just-in-time askq advance (since 6.5.6) ---
# Stop hook only fires at end-of-turn. When the model chains
# summary-askq → spec → approve-askq → Write in a single turn, Stop has
# not run yet and state is still phase=1. We rescan the transcript for
# an already-approved MCL askq and advance state before evaluating the
# phase gate, so a spec approved mid-turn doesn't force the developer
# to pay for a second turn (or pay tokens for a re-emitted spec).
_mcl_pre_is_approve_option() {
  # 10.0.1: TR + EN only (the two languages MCL officially supports).
  local raw="$1"
  [ -z "$raw" ] && return 1
  local norm
  norm="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$norm" in
    *onayla*|*onaylıyorum*|*evet*|*kabul*|*tamam*) return 0 ;;
    *approve*|*yes*|*confirm*|*ok*|*proceed*|*accept*) return 0 ;;
  esac
  return 1
}

# 10.0.0: Phase guard — current_phase semantics:
#   1 INTENT          → all Write/Edit BLOCKED (locked)
#   2 DESIGN_REVIEW   → frontend paths only (UI projects); backend BLOCKED
#   3 IMPLEMENTATION  → all unlocked
#   4 RISK_GATE       → all unlocked (severity scans run)
#   5 VERIFICATION    → all unlocked
#   6 FINAL_REVIEW    → all unlocked
REASON=""
if [ "$CURRENT_PHASE" -lt 2 ] 2>/dev/null; then
  REASON="MCL: ${TOOL_NAME} blocked. phase=${CURRENT_PHASE} (Phase 1 INTENT). Phase 1 summary-confirm askq must be approved first; on approval phase advances to 2 (UI projects) or 3 (non-UI), mutating tools unlock."
fi

# -------- Branch: Phase 2 DESIGN_REVIEW path-exception --------
# When current_phase=2 (DESIGN_REVIEW), only frontend paths + .mcl/ internals
# are writeable. Backend paths stay locked until the developer approves the
# design askq and MCL advances to Phase 3 (IMPLEMENTATION). This prevents
# "Claude wrote the backend before I saw the UI" regressions.
if [ -z "$REASON" ] && [ "$CURRENT_PHASE" = "2" ]; then
  UI_FLOW_ACTIVE="$(mcl_state_get ui_flow_active 2>/dev/null)"
  UI_SUB_PHASE="$(mcl_state_get ui_sub_phase 2>/dev/null)"
  # Phase 2 always treats writes as BUILD_UI-equivalent (frontend-only).
  if true; then
    UI_PATH_VERDICT="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, re, sys
try:
    obj = json.loads(sys.stdin.read())
except Exception:
    print("allow|"); sys.exit(0)
tin = obj.get("tool_input") or {}
# Write/Edit/MultiEdit use file_path; NotebookEdit uses notebook_path.
p = tin.get("file_path") or tin.get("notebook_path") or ""
if not p:
    print("allow|"); sys.exit(0)

# Normalize relative-style path for matching (strip leading ./, leave
# absolute paths alone — classifier uses substring search anchored by
# path separators).
norm = p.replace("\\\\", "/")

# Backend path globs — checked FIRST so `pages/api/**` wins over the
# broader `pages/**` frontend allow. If any backend pattern matches,
# deny.
backend_patterns = [
    r"(^|/)src/api(/|$)",
    r"(^|/)src/server(/|$)",
    r"(^|/)src/services(/|$)",
    r"(^|/)src/lib/db(/|$)",
    r"(^|/)src/db(/|$)",
    r"(^|/)src/backend(/|$)",
    r"(^|/)pages/api(/|$)",          # Next.js pages router
    r"(^|/)app/api(/|$)",            # Next.js app router
    r"(^|/)prisma(/|$)",
    r"(^|/)drizzle(/|$)",
    r"(^|/)supabase/migrations(/|$)",
    r"(^|/)migrations(/|$)",
    r"(^|/)\.env(\.|$)",             # .env, .env.local, .env.production
    r"(^|/)vercel\.json$",
    r"(^|/)netlify\.toml$",
    r"(^|/)server\.(js|ts|mjs)$",
    r"(^|/)index\.server\.",
    r"(^|/)server(/|$)",             # standalone server/ directory (Express, Fastify, etc.)
    r"(^|/)backend(/|$)",
    r"(^|/)api(/|$)",                # standalone api/ directory
    r"(^|/)routes(/|$)",
]
for pat in backend_patterns:
    if re.search(pat, norm):
        print(f"deny|{p}"); sys.exit(0)
print("allow|")
' 2>/dev/null)"
    if [ "${UI_PATH_VERDICT%%|*}" = "deny" ]; then
      DENIED_PATH="${UI_PATH_VERDICT#deny|}"
      REASON="MCL DESIGN-REVIEW LOCK — Phase 2 (DESIGN_REVIEW). Backend path \`${DENIED_PATH}\` is blocked until the developer approves the design (AskUserQuestion 'Tasarımı onaylıyor musun?' / 'Approve this design?') and MCL advances to Phase 3. Frontend code (components, pages, styles, fixtures), \`public/\`, \`.mcl/\` temp files, and framework-neutral files (README, package.json) are allowed. Build the UI skeleton with mock/fixture data only; integrate backend in Phase 3."
    fi
  fi
fi

# -------- Branch: Pattern Matching guard (Phase 3 entry pattern scan) --------
# When pattern_scan_due=true, Claude must read existing sibling files before
# writing anything. One-turn grace: after the first Phase 3 turn the stop
# hook clears the flag and writes are unblocked.
if [ -z "$REASON" ] && [ "$CURRENT_PHASE" = "3" ]; then
  _PS_DUE_PT="$(mcl_state_get pattern_scan_due 2>/dev/null)"
  if [ "$_PS_DUE_PT" = "true" ]; then
    _PAT_FILES_PT="$(mcl_state_get pattern_files 2>/dev/null)"
    REASON="MCL PATTERN SCAN — Pattern scan pending. Before writing any Phase 3 code, read the existing sibling files listed in the PATTERN_MATCHING_NOTICE to extract naming, error handling, import style, and test structure patterns. Write nothing this turn — use Read tool on each listed file, note the patterns, then end the turn. Writes will unblock automatically on the next turn."
    mcl_audit_log "pattern-scan-block" "pre-tool" "tool=${TOOL_NAME}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append pattern_scan_block
  fi
fi

# -------- Branch: Intent Violation Check (Phase 3+) --------
# Phase 4 RISK_GATE feature: scan phase1_intent for negation phrases
# ("no backend", "frontend only", "no DB", "no auth", etc.); if a Write
# attempt targets a path that violates the declared intent, deny with
# HIGH severity. Stack-agnostic — patterns match any framework's
# backend/api/db conventions.
if [ -z "$REASON" ] && [ "$CURRENT_PHASE" -ge 3 ] 2>/dev/null \
   && command -v python3 >/dev/null 2>&1; then
  _IV_VERDICT="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, os, re, sys

try:
    obj = json.loads(sys.stdin.read())
except Exception:
    print("allow"); sys.exit(0)
tin = obj.get("tool_input") or {}
fp = tin.get("file_path") or tin.get("notebook_path") or ""
if not fp:
    print("allow"); sys.exit(0)

# Read phase1_intent + phase1_constraints from state.json. Honor
# MCL_STATE_DIR / CLAUDE_PROJECT_DIR env vars (set by hook entrypoint).
_state_dir = os.environ.get("MCL_STATE_DIR")
if not _state_dir:
    _proj = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    _state_dir = os.path.join(_proj, ".mcl")
state_file = os.path.join(_state_dir, "state.json")
try:
    with open(state_file, encoding="utf-8") as sf:
        state = json.load(sf)
except Exception:
    print("allow"); sys.exit(0)
intent = (state.get("phase1_intent") or "").lower()
constraints = (state.get("phase1_constraints") or "").lower()
combined = intent + " || " + constraints
if not combined.strip(" |"):
    print("allow"); sys.exit(0)

# Negation rule packs: each is (intent_regex, path_regex, label, severity).
NEGATIONS = [
    # frontend-only / no-backend
    (re.compile(r"frontend only|no backend|no api|sadece frontend|sadece ön ?yüz|backend yok|api yok"),
     re.compile(r"(^|/)(?:app|pages|src)/api(/|$)|(^|/)(?:server|backend|api|routes)(/|$)|(^|/)src/server(/|$)|(^|/)src/services(/|$)|(^|/)src/backend(/|$)|server\.(?:js|ts|mjs)$"),
     "no-backend", "HIGH"),
    # no-db
    (re.compile(r"no ?db|no database|no datastore|veritabanı yok|db yok|veritabanı kullanma"),
     re.compile(r"(^|/)(?:prisma|drizzle|migrations|supabase)(/|$)|schema\.prisma$|sequelize|mongoose|typeorm|knex"),
     "no-db", "MEDIUM"),
    # no-auth
    (re.compile(r"no auth|no authentication|kimlik doğrulama yok|auth yok"),
     re.compile(r"next-auth|passport|clerk|auth0|@auth/|/auth/|(^|/)auth(/|$)"),
     "no-auth", "MEDIUM"),
]

norm = fp.replace("\\\\", "/")
for intent_re, path_re, label, sev in NEGATIONS:
    if intent_re.search(combined) and path_re.search(norm):
        print(f"deny|{label}|{sev}|{fp}")
        sys.exit(0)
print("allow")
' 2>/dev/null || echo "allow")"
  if [ "${_IV_VERDICT%%|*}" = "deny" ]; then
    _IV_REST="${_IV_VERDICT#deny|}"
    _IV_LABEL="${_IV_REST%%|*}"
    _IV_REST2="${_IV_REST#*|}"
    _IV_SEV="${_IV_REST2%%|*}"
    _IV_PATH="${_IV_REST2#*|}"
    REASON="MCL INTENT VIOLATION (severity=${_IV_SEV}, rule=${_IV_LABEL}) — \`${_IV_PATH}\` contradicts the declared phase1_intent. The Phase 1 brief explicitly excluded this layer; writing here is an intent-violation. Options: (A) revise Phase 1 intent if the scope genuinely changed (use AskUserQuestion to confirm with developer); (B) keep the work within declared scope. Do NOT silently expand scope."
    mcl_audit_log "intent-violation-block" "pre-tool" "rule=${_IV_LABEL} severity=${_IV_SEV} path=${_IV_PATH} tool=${TOOL_NAME}"
    command -v mcl_trace_append >/dev/null 2>&1 && \
      mcl_trace_append intent_violation_block "${_IV_LABEL}|${_IV_SEV}"
  fi
fi

# -------- Branch: Scope Guard (Phase 3) --------
# When scope_paths is non-empty (spec listed explicit file paths / globs),
# block writes to paths that don't match any declared pattern.
# Empty scope_paths = spec had no explicit paths = no restriction.
if [ -z "$REASON" ] && [ "$CURRENT_PHASE" = "3" ] && command -v python3 >/dev/null 2>&1; then
  _SCOPE_VERDICT="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, fnmatch, os, sys

try:
    obj = json.loads(sys.stdin.read())
except Exception:
    print("allow"); sys.exit(0)

tin = obj.get("tool_input") or {}
# Write/Edit use file_path; MultiEdit uses file_path[]; NotebookEdit uses notebook_path
paths_to_check = []
fp = tin.get("file_path") or tin.get("notebook_path")
if fp:
    paths_to_check.append(str(fp))
# MultiEdit: edits is a list of {file_path: ...}
edits = tin.get("edits")
if isinstance(edits, list):
    for e in edits:
        if isinstance(e, dict) and e.get("file_path"):
            paths_to_check.append(str(e["file_path"]))

if not paths_to_check:
    print("allow"); sys.exit(0)

# Read scope_paths from state.json directly
import os
state_file = os.path.join(os.getcwd(), ".mcl", "state.json")
try:
    with open(state_file, encoding="utf-8") as sf:
        state = json.load(sf)
    scope_paths = state.get("scope_paths") or []
    if not isinstance(scope_paths, list):
        scope_paths = []
except Exception:
    scope_paths = []

if not scope_paths:
    print("allow"); sys.exit(0)  # No declared paths — no restriction

def matches(file_abs, patterns):
    """True if file_abs matches any pattern (relative glob or absolute)."""
    file_abs = os.path.normpath(file_abs)
    for pat in patterns:
        pat = pat.lstrip("./")
        if not pat:
            continue
        # Absolute match
        if fnmatch.fnmatch(file_abs, pat):
            return True
        # Suffix match: pattern relative to any parent dir
        if fnmatch.fnmatch(file_abs, "*/" + pat):
            return True
        # Exact suffix without glob
        if file_abs.endswith("/" + pat) or file_abs == pat:
            return True
    return False

# Check all paths; report the first out-of-scope path
for p in paths_to_check:
    if not matches(p, scope_paths):
        # Skip .mcl/ internals and temp files — always allowed
        norm = p.replace("\\\\", "/")
        if "/.mcl/" in norm or norm.endswith("/.mcl") or "/tmp/" in norm:
            continue
        print("deny|" + p)
        sys.exit(0)

print("allow")
' 2>/dev/null || echo "allow")"
  if [ "${_SCOPE_VERDICT%%|*}" = "deny" ]; then
    _SCOPE_DENIED_PATH="${_SCOPE_VERDICT#deny|}"
    REASON="MCL SCOPE GUARD (Rule 2 — File Scope) — \`${_SCOPE_DENIED_PATH}\` is not in the spec's declared file scope. This also likely violates Rule 1 (Spec-Only): if this file needs changes, it should have been in the spec. Options: (A) surface as a Phase 4 risk and request scope extension; (B) if genuinely required now, ask the developer via AskUserQuestion BEFORE writing — never silently touch out-of-scope files."
    mcl_audit_log "scope-guard-block" "pre-tool" "path=${_SCOPE_DENIED_PATH} tool=${TOOL_NAME}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append scope_guard_block "${_SCOPE_DENIED_PATH}"
  fi
fi

if [ -n "$REASON" ]; then
  mcl_audit_log "deny-tool" "pre-tool" "tool=${TOOL_NAME} phase=${CURRENT_PHASE} design_approved=${DESIGN_APPROVED}"
  mcl_debug_log "pre-tool" "deny" "tool=${TOOL_NAME} phase=${CURRENT_PHASE} design_approved=${DESIGN_APPROVED}"
  python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason
    }
}))
' "$REASON"
  exit 0
fi

# -------- Plan critique reset on plan-file modification (Gap 3, since 8.2.10) --------
# When Write/Edit/MultiEdit targets a `.claude/plans/*.md` file, the plan
# content is changing — a fresh critique is required for the new plan.
# Runs after all gating decisions so we only reset on tool calls that the
# pre-tool hook is actually allowing through.
case "$TOOL_NAME" in
  Write|Edit|MultiEdit)
    _PCR_PATH="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("file_path","") or "")
except Exception:
    pass
' 2>/dev/null)"
    case "$_PCR_PATH" in
      */.claude/plans/*.md|.claude/plans/*.md)
        _PCR_NOW="$(mcl_state_get plan_critique_done 2>/dev/null)"
        if [ "$_PCR_NOW" = "true" ]; then
          mcl_state_set plan_critique_done false >/dev/null 2>&1 || true
          mcl_audit_log "plan-critique-reset" "pre-tool" "path=${_PCR_PATH}"
          command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_reset "${_PCR_PATH}"
        fi
        ;;
    esac
    ;;
esac

mcl_debug_log "pre-tool" "allow" "tool=${TOOL_NAME} phase=${CURRENT_PHASE}"
exit 0
