#!/usr/bin/env bash
# MCL DB Explain — opt-in EXPLAIN runner.
#
# Usage: bash mcl-db-explain.sh <project-dir> [lang]
# Reads MCL_DB_URL env. If unset, prints localized advisory and exits.
# If set, dispatches to dialect-specific CLI (psql / mysql / sqlite3) and
# prints EXPLAIN output for any *.sql files it finds in <project-dir>/queries/
# or *.sql under common slow-query log locations.
#
# MVP: generic CLI EXPLAIN only (no ANALYZE — production safety).
# ORM-specific query introspection deferred to 8.8.x.
#
# Since 8.8.0.

set -uo pipefail

PROJECT_DIR="${1:-$PWD}"
LANG_CODE="${2:-en}"

if [ -z "${MCL_DB_URL:-}" ]; then
  if [ "$LANG_CODE" = "tr" ]; then
    cat <<'TR'
# Veritabanı EXPLAIN

`MCL_DB_URL` çevre değişkeni ayarlı değil. Bu komut canlı veritabanına
bağlanıp `EXPLAIN` çalıştırır; bağlantı dizesi olmadan çalışamaz.

Etkinleştirmek için:
```
export MCL_DB_URL="postgres://user:pass@localhost:5432/mydb"
mcl-claude
```

Sonra `/mcl-db-explain` yazdığında kayıtlı sorgular EXPLAIN'e gönderilir.

Güvenlik notu: Production veritabanı bağlantısı kullanmaktan kaçın —
`EXPLAIN` salt okunur olsa da yan etki üreten sorgular için riskli.
Yalnızca staging/dev kullan, tercihen read-replica.
TR
  else
    cat <<'EN'
# Database EXPLAIN

`MCL_DB_URL` env var is not set. This command connects to a live database
and runs `EXPLAIN`; without a connection string it cannot run.

To enable:
```
export MCL_DB_URL="postgres://user:pass@localhost:5432/mydb"
mcl-claude
```

Then typing `/mcl-db-explain` will run EXPLAIN against saved queries.

Safety: avoid pointing this at production. `EXPLAIN` is read-only but
mutating queries are still risky to plan-print. Use staging/dev or a
read-replica.
EN
  fi
  exit 0
fi

# Detect dialect from connection string.
URL="$MCL_DB_URL"
DIALECT=""
case "$URL" in
  postgres*|postgresql*) DIALECT="postgres" ;;
  mysql*|mariadb*) DIALECT="mysql" ;;
  sqlite*) DIALECT="sqlite" ;;
  *) DIALECT="unknown" ;;
esac

if [ "$LANG_CODE" = "tr" ]; then
  echo "# Veritabanı EXPLAIN ($DIALECT)"
else
  echo "# Database EXPLAIN ($DIALECT)"
fi
echo

# Find candidate query files.
QUERY_FILES=()
for d in "queries" "db/queries" "sql" "src/queries"; do
  if [ -d "$PROJECT_DIR/$d" ]; then
    while IFS= read -r f; do
      QUERY_FILES+=("$f")
    done < <(find "$PROJECT_DIR/$d" -maxdepth 3 -type f -name "*.sql" 2>/dev/null | head -10)
  fi
done

if [ "${#QUERY_FILES[@]}" -eq 0 ]; then
  if [ "$LANG_CODE" = "tr" ]; then
    echo "_Tarayacak sorgu dosyası bulunamadı (queries/, db/queries/, sql/ aradım)._"
  else
    echo "_No query files found (looked in queries/, db/queries/, sql/)._"
  fi
  exit 0
fi

run_explain() {
  local sql="$1"
  case "$DIALECT" in
    postgres)
      psql "$URL" -c "EXPLAIN $sql" 2>&1 || true ;;
    mysql)
      # Strip mysql:// prefix and parse.
      mysql --execute="EXPLAIN $sql" 2>&1 || true ;;
    sqlite)
      sqlite3 "${URL#sqlite://}" "EXPLAIN QUERY PLAN $sql" 2>&1 || true ;;
    *)
      echo "(unsupported dialect: $DIALECT)" ;;
  esac
}

for f in "${QUERY_FILES[@]}"; do
  echo "## \`$(basename "$f")\`"
  echo '```sql'
  cat "$f"
  echo '```'
  echo
  if [ "$LANG_CODE" = "tr" ]; then
    echo "**Plan:**"
  else
    echo "**Plan:**"
  fi
  echo '```'
  # Read SQL, send to dialect-specific CLI; first non-comment query only.
  SQL="$(grep -v '^--' "$f" | tr -d ';' | head -c 2000)"
  run_explain "$SQL"
  echo '```'
  echo
done
