#!/bin/bash
# MCL Finish — aggregate Aşama 10 impacts accumulated since the last
# checkpoint and emit conventions the `mcl-finish` slash-command uses.
#
# Design: this helper owns filesystem conventions only. The actual
# aggregation, report composition, and Semgrep rescan are driven by
# Claude via the `mcl-finish` intercept in mcl-activate.sh. Keeping the
# shell surface small means future iterations (re-check, re-run) can
# extend the helper without touching the prompt layer.
#
# Directory layout (per MCL project):
#   .mcl/impact/NNNN.md        — one file per Aşama 10 impact
#   .mcl/finish/NNNN-YYYY-MM-DD.md — one file per mcl-finish checkpoint
#
# CLI:
#   bash mcl-finish.sh list-since-last-checkpoint
#     → prints newline-separated impact file paths modified after the
#       most recent checkpoint's mtime; prints ALL impact paths when
#       no checkpoint exists yet.
#   bash mcl-finish.sh reconcile <project_dir>
#     → reads impact file paths from stdin (one per line); for each,
#       outputs: path|STATUS|detail|days_old
#       STATUS values: RESOLVED / FILE_DELETED / FILE_CHANGED / STALE / OPEN / ERROR
#       Typical usage: list-since-last-checkpoint | reconcile "$(pwd)"
#   bash mcl-finish.sh next-checkpoint-id
#     → prints the next 4-digit id.
#   bash mcl-finish.sh last-checkpoint
#     → prints the filename of the most recent checkpoint, or empty.
#   bash mcl-finish.sh impact-dir
#     → prints the absolute path of the impact dir.
#   bash mcl-finish.sh finish-dir
#     → prints the absolute path of the finish dir.
#
# Exits 0 on success, non-zero only on unrecoverable internal error.
# Missing dirs are treated as "no entries", not an error — they only
# exist once Aşama 10 or mcl-finish has written into them.

set -u

_mcl_finish_root() {
  printf '%s\n' "${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}"
}

_mcl_finish_impact_dir() {
  printf '%s\n' "$(_mcl_finish_root)/impact"
}

_mcl_finish_checkpoint_dir() {
  printf '%s\n' "$(_mcl_finish_root)/finish"
}

_mcl_finish_last_checkpoint() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  python3 - "$dir" <<'PY'
import os, sys, re
d = sys.argv[1]
if not os.path.isdir(d):
    sys.exit(0)
entries = []
for name in os.listdir(d):
    m = re.match(r"^(\d{4})-.+\.md$", name)
    if m:
        entries.append((int(m.group(1)), name))
if not entries:
    sys.exit(0)
entries.sort(key=lambda x: x[0])
sys.stdout.write(entries[-1][1])
PY
}

_mcl_finish_next_id() {
  local dir="$1"
  python3 - "$dir" <<'PY'
import os, sys, re
d = sys.argv[1]
max_id = 0
if os.path.isdir(d):
    for name in os.listdir(d):
        m = re.match(r"^(\d{4})-.+\.md$", name)
        if m:
            n = int(m.group(1))
            if n > max_id:
                max_id = n
print(f"{max_id + 1:04d}")
PY
}

_mcl_finish_list_since() {
  local impact_dir="$1"
  local checkpoint_path="$2"
  [ -d "$impact_dir" ] || return 0
  python3 - "$impact_dir" "$checkpoint_path" <<'PY'
import os, sys, re
impact_dir = sys.argv[1]
cp_path = sys.argv[2]

if not os.path.isdir(impact_dir):
    sys.exit(0)

cutoff = 0.0
if cp_path and os.path.isfile(cp_path):
    try:
        cutoff = os.path.getmtime(cp_path)
    except Exception:
        cutoff = 0.0

entries = []
for name in sorted(os.listdir(impact_dir)):
    if not re.match(r"^\d{4}\.md$", name):
        continue
    path = os.path.join(impact_dir, name)
    try:
        mtime = os.path.getmtime(path)
    except Exception:
        continue
    if mtime > cutoff:
        entries.append(path)

for p in entries:
    sys.stdout.write(p + "\n")
PY
}

_mcl_finish_reconcile() {
  local project_dir="${1:-$(pwd)}"
  # Write Python script to a temp file so stdin stays available for
  # reading impact paths from the caller's pipeline.
  local _tmp
  _tmp="$(mktemp -t mcl_reconcile_XXXXXX.py 2>/dev/null || mktemp)"
  cat > "$_tmp" << 'PY_RECONCILE'
import os, sys, re, subprocess
from datetime import datetime, timezone
from pathlib import Path

project_dir = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()

FILE_EXT_RE = re.compile(
    r'(?:^|[`\s\(\[,])([a-zA-Z0-9_./\-]+\.'
    r'(?:ts|tsx|js|jsx|mjs|cjs|py|go|rb|java|kt|swift|rs|sh|sql|md|json|yaml|yml|toml|css|scss|html|tf|prisma|vue|svelte))'
    r'(?:[`\s\),\]:]|$)',
    re.MULTILINE
)
STALE_DAYS = 30

def parse_fm(text):
    lines, fm, body, dashes = text.split('\n'), {}, [], 0
    for line in lines:
        if line.strip() == '---':
            dashes += 1
            continue
        if dashes == 1:
            m = re.match(r'^(\w+):\s*(.*)', line)
            if m:
                fm[m.group(1)] = m.group(2).strip()
        elif dashes >= 2:
            body.append(line)
    return fm, '\n'.join(body)

def days_since(iso_str):
    if not iso_str:
        return 0
    try:
        dt = datetime.fromisoformat(iso_str.replace('Z', '+00:00'))
        now = datetime.now(timezone.utc)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return max(0, (now - dt).days)
    except Exception:
        return 0

def git_changed_since(rel_path, since_iso, cwd):
    if not since_iso:
        return ''
    try:
        r = subprocess.run(
            ['git', 'log', '--oneline', '-1', f'--after={since_iso}', '--', rel_path],
            capture_output=True, text=True, cwd=cwd, timeout=5
        )
        return r.stdout.strip()
    except Exception:
        return ''

for raw in sys.stdin:
    path = raw.strip()
    if not path or not os.path.isfile(path):
        continue
    try:
        text = Path(path).read_text(encoding='utf-8')
    except Exception:
        sys.stdout.write(f'{path}|ERROR|cannot read|0\n')
        continue

    fm, body = parse_fm(text)
    resolution = fm.get('resolution', 'open').strip()
    presented_at = fm.get('presented_at', '').strip()
    days_old = days_since(presented_at)

    if resolution in ('fix-applied', 'rule-captured'):
        sys.stdout.write(f'{path}|RESOLVED|{resolution}|{days_old}\n')
        continue

    # Extract first plausible file path from impact body
    candidates = list(dict.fromkeys(
        f.strip('`').strip()
        for f in FILE_EXT_RE.findall(body)
        if f.strip() and ('/' in f or re.search(r'\.\w{2,6}$', f.strip()))
    ))

    if candidates:
        rel = candidates[0].strip()
        abs_path = os.path.join(project_dir, rel)
        exists = os.path.isfile(abs_path) or os.path.isfile(rel)
        if not exists:
            sys.stdout.write(f'{path}|FILE_DELETED|{rel}|{days_old}\n')
        else:
            changed = git_changed_since(rel, presented_at, project_dir)
            if changed:
                detail = (rel + ' — ' + changed)[:80]
                sys.stdout.write(f'{path}|FILE_CHANGED|{detail}|{days_old}\n')
            else:
                sys.stdout.write(f'{path}|OPEN|{rel}|{days_old}\n')
    else:
        if days_old >= STALE_DAYS:
            sys.stdout.write(f'{path}|STALE|no file ref {days_old}d|{days_old}\n')
        else:
            sys.stdout.write(f'{path}|OPEN|no file ref|{days_old}\n')
PY_RECONCILE
  python3 "$_tmp" "$project_dir"
  local _rc=$?
  rm -f "$_tmp" 2>/dev/null || true
  return $_rc
}

case "${1:-}" in
  impact-dir)
    _mcl_finish_impact_dir
    ;;
  finish-dir)
    _mcl_finish_checkpoint_dir
    ;;
  last-checkpoint)
    cp_dir="$(_mcl_finish_checkpoint_dir)"
    last="$(_mcl_finish_last_checkpoint "$cp_dir")"
    [ -n "$last" ] && printf '%s\n' "$cp_dir/$last" || true
    ;;
  next-checkpoint-id)
    _mcl_finish_next_id "$(_mcl_finish_checkpoint_dir)"
    ;;
  list-since-last-checkpoint)
    cp_dir="$(_mcl_finish_checkpoint_dir)"
    impact_dir="$(_mcl_finish_impact_dir)"
    last="$(_mcl_finish_last_checkpoint "$cp_dir")"
    cp_path=""
    [ -n "$last" ] && cp_path="$cp_dir/$last"
    _mcl_finish_list_since "$impact_dir" "$cp_path"
    ;;
  reconcile)
    _mcl_finish_reconcile "${2:-$(pwd)}"
    ;;
  *)
    echo "mcl-finish: unknown subcommand '${1:-}'" >&2
    echo "usage: mcl-finish.sh {impact-dir|finish-dir|last-checkpoint|next-checkpoint-id|list-since-last-checkpoint|reconcile <project_dir>}" >&2
    exit 2
    ;;
esac
