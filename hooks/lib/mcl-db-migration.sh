#!/usr/bin/env bash
# MCL DB Migration delegate — invokes external migration linters and emits
# normalized findings JSON array.
#
# Usage: bash mcl-db-migration.sh <project-dir> <stack-tags-csv>
# Stdout: JSON array of findings (severity, source=migration, rule_id, file, line, message, ...)
# Stderr: progress / warnings / binary-missing notices
# Exit: 0 always (errors yield empty array)
#
# Tools delegated (each binary-missing is graceful):
#   squawk         — Postgres migration linter (lock impact, data-loss, type narrow)
#   alembic        — `alembic check` offline migration sanity (Python alembic)
#
# Since 8.8.0.

set -uo pipefail

PROJECT_DIR="${1:-$PWD}"
STACK_TAGS_CSV="${2:-}"
cd "$PROJECT_DIR" || { printf '[]\n'; exit 0; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

_has_tag() {
  case ",$STACK_TAGS_CSV," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

# ---- squawk on Postgres migration files ----
if _has_tag "db-postgres" && command -v squawk >/dev/null 2>&1; then
  # Heuristic migration dir candidates.
  MIG_FILES=()
  for d in migrations db/migrate prisma/migrations alembic/versions sql/migrations; do
    if [ -d "$PROJECT_DIR/$d" ]; then
      while IFS= read -r f; do
        MIG_FILES+=("$f")
      done < <(find "$PROJECT_DIR/$d" -maxdepth 3 -type f \( -name "*.sql" -o -name "*.py" \) 2>/dev/null | head -50)
    fi
  done
  if [ "${#MIG_FILES[@]}" -gt 0 ]; then
    SQK_OUT="$(squawk --reporter json "${MIG_FILES[@]}" 2>/dev/null || true)"
    if [ -n "$SQK_OUT" ]; then
      python3 -c '
import json, sys
data = sys.stdin.read()
# squawk outputs one JSON per file; concatenate with newlines or as array.
out = []
try:
    arr = json.loads(data)
    if not isinstance(arr, list):
        arr = [arr]
except json.JSONDecodeError:
    arr = []
    for line in data.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            arr.append(json.loads(line))
        except Exception:
            pass
for entry in arr:
    sev_map = {"high":"HIGH","medium":"MEDIUM","low":"LOW","warning":"MEDIUM","error":"HIGH"}
    for v in (entry.get("violations") or []):
        sev = sev_map.get((v.get("level") or "").lower(), "MEDIUM")
        rule = v.get("rule_name", "squawk-unknown")
        out.append({
          "severity": sev, "source": "migration",
          "rule_id": f"squawk-{rule}",
          "file": entry.get("file", "?"),
          "line": v.get("span", {}).get("start", {}).get("line", 0),
          "message": (v.get("message") or "")[:200],
          "category": "db-migration",
          "dialect": "postgres",
          "autofix": None,
        })
print(json.dumps(out))
' <<< "$SQK_OUT" > "$TMP" 2>/dev/null
    fi
  fi
elif _has_tag "db-postgres"; then
  echo "[MCL/DB] squawk not installed; Postgres migration safety skipped" >&2
fi

# ---- alembic check (Python) ----
if _has_tag "orm-sqlalchemy" && command -v alembic >/dev/null 2>&1 && [ -f "alembic.ini" ]; then
  AL_OUT="$(alembic check 2>&1 || true)"
  if echo "$AL_OUT" | grep -q "FAILED\|error\|conflict"; then
    python3 -c '
import json, sys
print(json.dumps([{
  "severity": "MEDIUM", "source": "migration",
  "rule_id": "alembic-check-failed",
  "file": "alembic.ini", "line": 0,
  "message": ("alembic check reported issues: " + sys.argv[1])[:200],
  "category": "db-migration", "dialect": "", "autofix": None,
}]))
' "$AL_OUT" >> "$TMP"
  fi
elif _has_tag "orm-sqlalchemy" && [ -f "alembic.ini" ]; then
  echo "[MCL/DB] alembic CLI not installed; alembic check skipped" >&2
fi

# Combine all JSON outputs into single array.
if [ -s "$TMP" ]; then
  python3 -c '
import json, sys
out = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        arr = json.loads(line)
        if isinstance(arr, list):
            out.extend(arr)
        else:
            out.append(arr)
    except Exception:
        pass
print(json.dumps(out))
' < "$TMP"
else
  printf '[]\n'
fi
