#!/usr/bin/env python3
"""Find existing sibling files that serve as pattern references for Phase 3.5.

Given a JSON array of scope_paths (relative paths/globs, via stdin),
for each path finds existing files in the same directory with the same
extension. Returns a JSON array of relative file paths (max 10 total).

Usage:
  echo '["src/auth/login.ts","src/models/user.ts"]' | python3 mcl-pattern-scan.py /project/root
  # → ["src/auth/register.ts","src/auth/logout.ts","src/models/post.ts"]
"""

import json, os, sys

MAX_REFS_PER_DIR = 3   # similar files suggested per unique directory
MAX_TOTAL        = 10  # hard cap on total references returned


def _ext(filename: str) -> str:
    """Return lowercased extension without dot, or '' if none."""
    if '.' in filename:
        return filename.rsplit('.', 1)[-1].lower()
    return ''


def _sibling_refs(target_pat: str, project_root: str, max_refs: int) -> list[str]:
    """Find existing files in the same directory as target_pat."""
    pat = target_pat.lstrip('./')

    # Determine directory and extension from the pattern
    if '/' in pat:
        dir_rel, basename = pat.rsplit('/', 1)
    else:
        dir_rel, basename = '.', pat

    # For glob patterns, walk up to the last non-glob segment
    if '*' in dir_rel:
        dir_rel = dir_rel.split('*')[0].rstrip('/')

    target_ext = _ext(basename.replace('*', ''))

    abs_dir = os.path.normpath(os.path.join(project_root, dir_rel))
    if not os.path.isdir(abs_dir):
        # Try parent directory
        abs_dir = os.path.dirname(abs_dir)
    if not os.path.isdir(abs_dir):
        return []

    refs: list[str] = []
    try:
        entries = sorted(os.listdir(abs_dir))
    except OSError:
        return []

    for entry in entries:
        full = os.path.join(abs_dir, entry)
        if not os.path.isfile(full):
            continue
        # Skip if extension doesn't match (when a target extension is known)
        if target_ext and _ext(entry) != target_ext:
            continue
        # Skip hidden files and test files as pattern sources
        if entry.startswith('.'):
            continue
        # Compute path relative to project root
        try:
            rel = os.path.relpath(full, project_root)
        except ValueError:
            rel = full
        refs.append(rel)
        if len(refs) >= max_refs:
            break

    return refs


if __name__ == '__main__':
    project_root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()

    try:
        scope_paths = json.loads(sys.stdin.read())
    except Exception:
        print('[]')
        sys.exit(0)

    if not isinstance(scope_paths, list):
        print('[]')
        sys.exit(0)

    all_refs: list[str] = []
    seen_dirs: set[str] = set()

    for pat in scope_paths:
        # Derive canonical dir key for deduplication
        p = pat.lstrip('./')
        dir_key = p.rsplit('/', 1)[0] if '/' in p else '.'
        if '*' in dir_key:
            dir_key = dir_key.split('*')[0].rstrip('/')
        if dir_key in seen_dirs:
            continue
        seen_dirs.add(dir_key)

        for ref in _sibling_refs(pat, project_root, MAX_REFS_PER_DIR):
            # Don't include files that are themselves scope targets
            rel = ref.replace('\\', '/')
            if rel not in all_refs:
                all_refs.append(rel)

        if len(all_refs) >= MAX_TOTAL:
            break

    print(json.dumps(all_refs[:MAX_TOTAL]))
