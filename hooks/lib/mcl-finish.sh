#!/bin/bash
# MCL Finish — aggregate Phase 4.6 impacts accumulated since the last
# checkpoint and emit conventions the `mcl-finish` slash-command uses.
#
# Design: this helper owns filesystem conventions only. The actual
# aggregation, report composition, and Semgrep rescan are driven by
# Claude via the `mcl-finish` intercept in mcl-activate.sh. Keeping the
# shell surface small means future iterations (re-check, re-run) can
# extend the helper without touching the prompt layer.
#
# Directory layout (per MCL project):
#   .mcl/impact/NNNN.md        — one file per Phase 4.6 impact
#   .mcl/finish/NNNN-YYYY-MM-DD.md — one file per mcl-finish checkpoint
#
# CLI:
#   bash mcl-finish.sh list-since-last-checkpoint
#     → prints newline-separated impact file paths modified after the
#       most recent checkpoint's mtime; prints ALL impact paths when
#       no checkpoint exists yet.
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
# exist once Phase 4.6 or mcl-finish has written into them.

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
  *)
    echo "mcl-finish: unknown subcommand '${1:-}'" >&2
    echo "usage: mcl-finish.sh {impact-dir|finish-dir|last-checkpoint|next-checkpoint-id|list-since-last-checkpoint}" >&2
    exit 2
    ;;
esac
