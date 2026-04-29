#!/usr/bin/env bash
# MCL Perf Bundle delegate (8.14.0).
# Walks build output dirs (dist/build/.next/out) and aggregates gzipped JS
# size. Does NOT invoke the build — assumes user already built.
# Usage: bash mcl-perf-bundle.sh <project-dir>
# Stdout: JSON {found, output_dir, total_gzip_bytes, files: [...], checked_dirs}

set -uo pipefail
PROJECT_DIR="${1:-$PWD}"
cd "$PROJECT_DIR" || { printf '{"found":false}\n'; exit 0; }

CHECK_DIRS="dist build .next/static/chunks out"
FOUND_DIR=""
for d in $CHECK_DIRS; do
  if [ -d "$d" ]; then
    FOUND_DIR="$d"
    break
  fi
done

if [ -z "$FOUND_DIR" ]; then
  printf '{"found":false,"checked_dirs":"%s"}\n' "$CHECK_DIRS"
  exit 0
fi

# Walk *.js (skip *.map, *.d.ts), gzip-size each, aggregate.
python3 -c '
import gzip, json, os, sys
root = sys.argv[1]
files = []
total = 0
for dp, dns, fns in os.walk(root):
    for fn in fns:
        if not fn.endswith(".js") or fn.endswith(".min.js.map") or fn.endswith(".map"):
            continue
        p = os.path.join(dp, fn)
        try:
            with open(p, "rb") as f:
                data = f.read()
            gz = gzip.compress(data, compresslevel=6)
            sz = len(gz)
        except Exception:
            continue
        rel = os.path.relpath(p, root)
        files.append({"path": rel, "gzip_size": sz, "raw_size": len(data)})
        total += sz
print(json.dumps({
    "found": True,
    "output_dir": root,
    "total_gzip_bytes": total,
    "files": sorted(files, key=lambda x: -x["gzip_size"])[:20],
    "file_count": len(files),
}))
' "$FOUND_DIR"
