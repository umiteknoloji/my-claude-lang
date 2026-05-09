#!/bin/bash
# MCL Spec Save — write each approved spec body to
# `$MCL_STATE_DIR/specs/NNNN-slug.md` with YAML frontmatter, then
# regenerate `INDEX.md`. Idempotent on spec_hash (drift-reapproval of
# the same body writes once).
#
# Invoked from mcl-stop.sh at the moment an AskUserQuestion approve-family
# tool_result transitions the phase to EXECUTE — both fresh-approval
# (`approve-via-askuserquestion`) and drift-reapproval (`drift-reapproved |
# via=askuserquestion`) paths. Since 6.0.0 the legacy `✅ MCL APPROVED`
# text marker is no longer a trigger.
#
# CLI:
#   bash ~/.claude/hooks/lib/mcl-spec-save.sh <transcript_path> <spec_hash>
#
# Sourced:
#   source hooks/lib/mcl-spec-save.sh
#   mcl_spec_save <transcript_path> <spec_hash>
#
# Output: empty on success. Diagnostics on stderr. Audit log entry:
#   spec-saved       | stop | id=NNNN slug=... hash=...
#   spec-saved-noop  | stop | reason=duplicate-hash id=NNNN
#
# Exits 0 on success AND on idempotent no-op. Non-zero only on
# unrecoverable internal error (e.g., unwritable specs dir).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -z "${SCRIPT_DIR:-}" ]; then
  echo "mcl-spec-save: cannot locate own directory" >&2
  exit 1
fi

# shellcheck source=mcl-state.sh
source "$SCRIPT_DIR/mcl-state.sh"

_mcl_spec_dir() {
  printf '%s\n' "${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/specs"
}

# Extract the normalized spec body (same logic as mcl-stop.sh). Prints
# the body on stdout; empty output means no spec block was found in the
# last assistant message.
_mcl_spec_extract_body() {
  local transcript="$1"
  python3 - "$transcript" <<'PY'
import json, sys, re

path = sys.argv[1]

def extract_text(msg):
    if isinstance(msg, dict) and "message" in msg and isinstance(msg["message"], dict):
        msg = msg["message"]
    if not isinstance(msg, dict):
        return None
    if msg.get("role") != "assistant":
        return None
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                t = item.get("text")
                if isinstance(t, str):
                    parts.append(t)
        return "\n".join(parts) if parts else None
    return None

# Must stay in sync with mcl-stop.sh — finds the last assistant turn
# that CONTAINS a spec block (not just the last assistant turn).
spec_line_re = re.compile(
    r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?(?:\U0001F4CB[ \t]+)?Spec\b[^\n:]*:",
    re.MULTILINE,
)

last_text = None
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
            text = extract_text(obj)
            if text and spec_line_re.search(text):
                last_text = text
except Exception:
    sys.exit(0)

if not last_text:
    sys.exit(0)

lines = last_text.splitlines()
start = None
for i, ln in enumerate(lines):
    if spec_line_re.match(ln):
        start = i
        break
if start is None:
    sys.exit(0)

end = len(lines)
for j in range(start + 1, len(lines)):
    stripped = lines[j].lstrip()
    if re.match(r"^#+\s", stripped):
        end = j
        break

body_lines = lines[start:end]
normalized = []
prev_blank = False
for ln in body_lines:
    ln = ln.rstrip()
    is_blank = (ln == "")
    if is_blank and prev_blank:
        continue
    normalized.append(ln)
    prev_blank = is_blank
while normalized and normalized[0] == "":
    normalized.pop(0)
while normalized and normalized[-1] == "":
    normalized.pop()

sys.stdout.write("\n".join(normalized))
PY
}

# Derive slug from spec body. Looks for "Objective" marker in common
# spec layouts (bold/heading/plain). Returns kebab-case slug (<=40
# chars) or empty if nothing usable found — caller then falls back to
# `spec-NNNN`.
#
# Body passed as argv[1] (not stdin) because the python heredoc itself
# consumes stdin — piping body in would land in the heredoc, not the
# script. Argv handles multi-line safely under POSIX ARG_MAX limits.
_mcl_spec_slug_from_body() {
  python3 - "$1" <<'PY'
import sys, re
body = sys.argv[1] if len(sys.argv) > 1 else ""
if not body:
    sys.exit(0)

objective_text = ""
lines = body.splitlines()
patterns = [
    # Same-line forms: "Objective: <text>", "**Objective:** <text>",
    # "## Objective: <text>", "- Objective: <text>"
    re.compile(r"^\s*(?:[-*]\s+)?(?:#+\s+)?(?:\*{1,2})?Objective(?:\*{1,2})?\s*:\s*(.+)$", re.IGNORECASE),
]
next_line_patterns = [
    # Header-only forms: "## Objective" then body on next line
    re.compile(r"^\s*#+\s+(?:\*{1,2})?Objective(?:\*{1,2})?\s*$", re.IGNORECASE),
]

for i, ln in enumerate(lines):
    # Same-line match wins
    for pat in patterns:
        m = pat.match(ln)
        if m:
            cand = m.group(1).strip()
            if cand:
                objective_text = cand
                break
    if objective_text:
        break
    # Header-only → grab next non-blank line
    for pat in next_line_patterns:
        if pat.match(ln):
            for j in range(i + 1, len(lines)):
                nxt = lines[j].strip()
                if nxt:
                    objective_text = nxt
                    break
            break
    if objective_text:
        break

# Strip markdown inline formatting characters that don't belong in a slug.
objective_text = re.sub(r"[`*_~\[\]()]+", " ", objective_text)

slug = objective_text.lower()
slug = re.sub(r"[^a-z0-9]+", "-", slug)
slug = slug.strip("-")
slug = slug[:40].rstrip("-")

if slug:
    sys.stdout.write(slug)
PY
}

# Return the next spec_id (monotonic 4-digit). Scans existing
# NNNN-*.md files in the specs dir. Returns "0001" for an empty dir.
_mcl_spec_next_id() {
  local dir="$1"
  python3 - "$dir" <<'PY'
import os, sys, re
dir_ = sys.argv[1]
max_id = 0
if os.path.isdir(dir_):
    for name in os.listdir(dir_):
        m = re.match(r"^(\d{4})-.*\.md$", name)
        if m:
            n = int(m.group(1))
            if n > max_id:
                max_id = n
print(f"{max_id + 1:04d}")
PY
}

# Read spec_hash from the frontmatter of the last (highest NNNN)
# spec file in the dir. Empty when dir is empty or last file has no
# spec_hash. Used for idempotency on drift-reapproval.
_mcl_spec_last_hash() {
  local dir="$1"
  python3 - "$dir" <<'PY'
import os, sys, re
dir_ = sys.argv[1]
if not os.path.isdir(dir_):
    sys.exit(0)
entries = []
for name in os.listdir(dir_):
    m = re.match(r"^(\d{4})-.*\.md$", name)
    if m:
        entries.append((int(m.group(1)), name))
if not entries:
    sys.exit(0)
entries.sort(key=lambda x: x[0])
last_name = entries[-1][1]
try:
    with open(os.path.join(dir_, last_name), "r", encoding="utf-8") as f:
        content = f.read()
except Exception:
    sys.exit(0)
# Frontmatter: first line must be --- ; read until next ---
lines = content.splitlines()
if not lines or lines[0].strip() != "---":
    sys.exit(0)
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        break
    m = re.match(r"^spec_hash:\s*(.+)$", lines[i].strip())
    if m:
        sys.stdout.write(m.group(1).strip())
        sys.exit(0)
PY
}

# Regenerate INDEX.md from all NNNN-*.md files in the dir. Table sorted
# newest first. Best-effort — missing frontmatter fields render as "-".
_mcl_spec_regen_index() {
  local dir="$1"
  python3 - "$dir" <<'PY'
import os, sys, re
dir_ = sys.argv[1]
if not os.path.isdir(dir_):
    sys.exit(0)

def parse_frontmatter(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except Exception:
        return {}
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fm = {}
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            break
        m = re.match(r"^(\w+):\s*(.*)$", lines[i])
        if m:
            fm[m.group(1)] = m.group(2).strip()
    return fm

entries = []
for name in os.listdir(dir_):
    m = re.match(r"^(\d{4})-.*\.md$", name)
    if not m:
        continue
    fm = parse_frontmatter(os.path.join(dir_, name))
    spec_id = fm.get("spec_id", m.group(1))
    slug = name[5:-3]  # strip NNNN- and .md
    approved = fm.get("approved_at", "-")[:16].replace("T", " ")
    branch = fm.get("branch", "-") or "-"
    commit = fm.get("completion_commit", "-") or "-"
    if commit == "null":
        commit = "-"
    status = fm.get("status", "-") or "-"
    entries.append((int(m.group(1)), spec_id, slug, approved, branch, commit, status))

entries.sort(key=lambda x: x[0], reverse=True)

out = [
    "# MCL Spec Index",
    "",
    "| ID   | Slug                                     | Approved         | Branch                         | Commit   | Status      |",
    "| ---- | ---------------------------------------- | ---------------- | ------------------------------ | -------- | ----------- |",
]
for _, spec_id, slug, approved, branch, commit, status in entries:
    out.append(f"| {spec_id:<4} | {slug:<40.40} | {approved:<16.16} | {branch:<30.30} | {commit:<8.8} | {status:<11.11} |")

index_path = os.path.join(dir_, "INDEX.md")
tmp = index_path + f".tmp.{os.getpid()}"
with open(tmp, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
os.replace(tmp, index_path)
PY
}

mcl_spec_save() {
  local transcript="${1:-}"
  local spec_hash="${2:-}"

  if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
    echo "mcl-spec-save: missing or unreadable transcript path" >&2
    return 1
  fi
  if [ -z "$spec_hash" ]; then
    echo "mcl-spec-save: missing spec_hash" >&2
    return 1
  fi

  local specs_dir body slug next_id last_hash
  specs_dir="$(_mcl_spec_dir)"
  mkdir -p "$specs_dir" 2>/dev/null || {
    echo "mcl-spec-save: cannot create $specs_dir" >&2
    return 1
  }

  # Idempotency: same hash as last saved spec → no-op.
  last_hash="$(_mcl_spec_last_hash "$specs_dir")"
  if [ -n "$last_hash" ] && [ "$last_hash" = "$spec_hash" ]; then
    mcl_audit_log "spec-saved-noop" "stop" "reason=duplicate-hash hash=${spec_hash:0:12}"
    return 0
  fi

  body="$(_mcl_spec_extract_body "$transcript")"
  if [ -z "$body" ]; then
    echo "mcl-spec-save: no spec block found in transcript — skipping save" >&2
    return 0
  fi

  slug="$(_mcl_spec_slug_from_body "$body")"
  next_id="$(_mcl_spec_next_id "$specs_dir")"
  if [ -z "$slug" ]; then
    slug="spec-${next_id}"
  fi

  local approved_at branch head_sha
  approved_at="$(date '+%Y-%m-%dT%H:%M:%S%z' | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ -z "$branch" ] || [ "$branch" = "HEAD" ] && branch=""
  head_sha="$(git rev-parse --short HEAD 2>/dev/null || true)"

  local file="$specs_dir/${next_id}-${slug}.md"
  local tmp="${file}.tmp.$$"

  {
    printf -- '---\n'
    printf 'spec_id: %s\n' "$next_id"
    printf 'approved_at: %s\n' "$approved_at"
    printf 'spec_hash: %s\n' "$spec_hash"
    if [ -n "$branch" ]; then
      printf 'branch: %s\n' "$branch"
    else
      printf 'branch: null\n'
    fi
    if [ -n "$head_sha" ]; then
      printf 'head_at_approval: %s\n' "$head_sha"
    else
      printf 'head_at_approval: null\n'
    fi
    printf 'completion_commit: null\n'
    printf 'status: active\n'
    printf -- '---\n\n'
    printf '%s\n' "$body"
  } > "$tmp" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null
    echo "mcl-spec-save: write failed for $file" >&2
    return 1
  }
  mv "$tmp" "$file" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null
    echo "mcl-spec-save: atomic rename failed for $file" >&2
    return 1
  }

  _mcl_spec_regen_index "$specs_dir"

  mcl_audit_log "spec-saved" "stop" "id=${next_id} slug=${slug} hash=${spec_hash:0:12}"
  return 0
}

# CLI dispatch — only when invoked directly, not when sourced.
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
  mcl_spec_save "${1:-}" "${2:-}"
fi
