#!/usr/bin/env python3
"""Find existing pattern reference files for Aşama 5.

Cascade search — returns the first level that yields results:
  Level 1 (sibling): files in the same directory as scope_paths
  Level 2 (project): project-wide files with matching extension,
           most-recently-modified, up to MAX_TOTAL
  Level 3 (ecosystem): returns empty list + sets exit code 3 to
           signal "use ecosystem default"

Exit codes:
  0 — files found (Level 1 or 2), JSON array on stdout
  3 — no project files found, caller should use ecosystem defaults

Usage:
  echo '["src/auth/login.ts"]' | python3 mcl-pattern-scan.py /project/root
  # → ["src/auth/register.ts"] and exit 0
  # → [] and exit 3  (no siblings, no project files found)
"""

import json, os, sys

MAX_REFS_PER_DIR = 3
MAX_TOTAL        = 10
RECENT_COUNT     = 8   # Level 2: most-recently-modified files to return


def _ext(filename: str) -> str:
    if '.' in filename:
        return filename.rsplit('.', 1)[-1].lower()
    return ''


# ── Level 1: sibling files ────────────────────────────────────────────────────

def _sibling_refs(target_pat: str, project_root: str, max_refs: int) -> list[str]:
    """Find existing files in the same directory as target_pat."""
    pat = target_pat.lstrip('./')

    if '/' in pat:
        dir_rel, basename = pat.rsplit('/', 1)
    else:
        dir_rel, basename = '.', pat

    if '*' in dir_rel:
        dir_rel = dir_rel.split('*')[0].rstrip('/')

    target_ext = _ext(basename.replace('*', ''))

    abs_dir = os.path.normpath(os.path.join(project_root, dir_rel))
    if not os.path.isdir(abs_dir):
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
        if target_ext and _ext(entry) != target_ext:
            continue
        if entry.startswith('.'):
            continue
        try:
            rel = os.path.relpath(full, project_root)
        except ValueError:
            rel = full
        refs.append(rel)
        if len(refs) >= max_refs:
            break

    return refs


def level1(scope_paths: list[str], project_root: str) -> list[str]:
    all_refs: list[str] = []
    seen_dirs: set[str] = set()

    for pat in scope_paths:
        p = pat.lstrip('./')
        dir_key = p.rsplit('/', 1)[0] if '/' in p else '.'
        if '*' in dir_key:
            dir_key = dir_key.split('*')[0].rstrip('/')
        if dir_key in seen_dirs:
            continue
        seen_dirs.add(dir_key)

        for ref in _sibling_refs(pat, project_root, MAX_REFS_PER_DIR):
            rel = ref.replace('\\', '/')
            if rel not in all_refs:
                all_refs.append(rel)

        if len(all_refs) >= MAX_TOTAL:
            break

    return all_refs[:MAX_TOTAL]


# ── Level 2: project-wide, most-recently-modified ────────────────────────────

_SKIP_DIRS = {'.git', 'node_modules', '__pycache__', '.venv', 'venv',
              'dist', 'build', '.next', 'target', 'vendor', '.cache'}

_CODE_EXTS = {
    'ts', 'tsx', 'js', 'jsx', 'mjs', 'cjs',
    'py', 'go', 'rs', 'java', 'kt', 'swift',
    'rb', 'php', 'cs', 'cpp', 'c', 'h',
}


def level2(scope_paths: list[str], project_root: str) -> list[str]:
    """Walk project, collect code files matching scope extensions, return
    the RECENT_COUNT most recently modified."""
    # Determine target extensions from scope_paths
    target_exts: set[str] = set()
    for pat in scope_paths:
        e = _ext(pat.split('/')[-1].replace('*', ''))
        if e:
            target_exts.add(e)
    # Fall back to all known code extensions
    if not target_exts:
        target_exts = _CODE_EXTS

    # Collect scope_paths as set for exclusion (avoid self-reference)
    scope_set = {p.lstrip('./').replace('\\', '/') for p in scope_paths}

    candidates: list[tuple[float, str]] = []  # (mtime, relpath)

    for dirpath, dirnames, filenames in os.walk(project_root):
        # Prune skip dirs in-place
        dirnames[:] = [d for d in dirnames if d not in _SKIP_DIRS and not d.startswith('.')]

        for fname in filenames:
            if fname.startswith('.'):
                continue
            if _ext(fname) not in target_exts:
                continue
            full = os.path.join(dirpath, fname)
            try:
                rel = os.path.relpath(full, project_root).replace('\\', '/')
            except ValueError:
                continue
            if rel in scope_set:
                continue
            try:
                mtime = os.path.getmtime(full)
            except OSError:
                continue
            candidates.append((mtime, rel))

    # Sort by most-recently-modified, newest first
    candidates.sort(key=lambda x: x[0], reverse=True)
    return [rel for _, rel in candidates[:RECENT_COUNT]]


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == '__main__':
    project_root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()

    try:
        scope_paths = json.loads(sys.stdin.read())
    except Exception:
        print('[]')
        sys.exit(0)

    if not isinstance(scope_paths, list) or not scope_paths:
        print('[]')
        sys.exit(0)

    # Level 1 — siblings
    refs = level1(scope_paths, project_root)
    if refs:
        print(json.dumps(refs))
        sys.exit(0)

    # Level 2 — project-wide recent files
    refs = level2(scope_paths, project_root)
    if refs:
        print(json.dumps(refs))
        sys.exit(0)

    # Level 3 — no project files found; signal caller to use ecosystem defaults
    print('[]')
    sys.exit(3)
