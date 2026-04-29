#!/bin/bash
# MCL Stack Detect — scan a project directory for language markers.
#
# Sourceable + CLI. Prints detected language tags newline-separated to
# stdout. Empty output means "no recognizable stack" — caller treats
# this as "ask the developer" fallback.
#
# Detection is top-level only (shallow scan). Monorepos with nested
# manifests under apps/* or packages/* are out of scope for MVP.
#
# Language tags map 1:1 to entries in
# skills/my-claude-lang/plugin-suggestions.md. Keep in sync.
#
# CLI:
#   mcl-stack-detect.sh detect [dir]
# Sourced:
#   source hooks/lib/mcl-stack-detect.sh
#   mcl_stack_detect /path/to/project

set -u

mcl_stack_detect() {
  local dir="${1:-$(pwd)}"
  [ -d "$dir" ] || return 0

  local -a detected=()

  _mcl_stack_add() {
    # Index-based loop avoids the empty-array "unbound variable" bash
    # quirk under `set -u` that bites "${arr[@]}" expansion when arr=().
    local i
    for (( i=0; i<${#detected[@]}; i++ )); do
      [ "${detected[i]}" = "$1" ] && return
    done
    detected+=("$1")
  }

  # JavaScript / TypeScript — TypeScript wins when tsconfig.json or a
  # "typescript" dep is present; otherwise plain JavaScript.
  if [ -f "$dir/package.json" ]; then
    if [ -f "$dir/tsconfig.json" ] \
       || grep -q '"typescript"' "$dir/package.json" 2>/dev/null; then
      _mcl_stack_add typescript
    else
      _mcl_stack_add javascript
    fi

    # Frontend framework markers (MVP: react/vue/svelte). Tags the
    # dominant framework so Phase 4a picks the right component syntax.
    # Multiple can match (Nx monorepo, stale deps) — MCL prose reconciles.
    if grep -q '"react"' "$dir/package.json" 2>/dev/null; then
      _mcl_stack_add react-frontend
    fi
    if grep -Eq '"(vue|nuxt)"' "$dir/package.json" 2>/dev/null; then
      _mcl_stack_add vue-frontend
    fi
    if grep -Eq '"(svelte|@sveltejs/kit)"' "$dir/package.json" 2>/dev/null; then
      _mcl_stack_add svelte-frontend
    fi
  fi

  # Static HTML (no JS framework detected): top-level index.html or *.html
  # in the absence of package.json. Lets Phase 4a emit plain HTML+JS.
  if [ ! -f "$dir/package.json" ]; then
    if [ -f "$dir/index.html" ] || compgen -G "$dir/*.html" >/dev/null; then
      _mcl_stack_add html-static
    fi
  fi

  # Python
  if [ -f "$dir/pyproject.toml" ] \
     || [ -f "$dir/requirements.txt" ] \
     || [ -f "$dir/setup.py" ] \
     || [ -f "$dir/Pipfile" ]; then
    _mcl_stack_add python
  fi

  # Go
  [ -f "$dir/go.mod" ] && _mcl_stack_add go

  # Rust
  [ -f "$dir/Cargo.toml" ] && _mcl_stack_add rust

  # Kotlin beats Java when `.kts` gradle file is present.
  if [ -f "$dir/build.gradle.kts" ]; then
    _mcl_stack_add kotlin
  elif [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ]; then
    _mcl_stack_add java
  fi

  # PHP
  [ -f "$dir/composer.json" ] && _mcl_stack_add php

  # Ruby
  if [ -f "$dir/Gemfile" ] || compgen -G "$dir/*.gemspec" >/dev/null; then
    _mcl_stack_add ruby
  fi

  # Swift
  if [ -f "$dir/Package.swift" ] || compgen -G "$dir/*.xcodeproj" >/dev/null; then
    _mcl_stack_add swift
  fi

  # C / C++
  if [ -f "$dir/CMakeLists.txt" ] \
     || compgen -G "$dir/*.c" >/dev/null \
     || compgen -G "$dir/*.cpp" >/dev/null \
     || compgen -G "$dir/*.cc" >/dev/null; then
    _mcl_stack_add cpp
  fi

  # Lua
  if compgen -G "$dir/*.lua" >/dev/null; then
    _mcl_stack_add lua
  fi

  # C# — .csproj/.sln/global.json are strong signals; *.cs alone is noisy
  # and often co-appears in docs repos, so excluded from MVP detection.
  if compgen -G "$dir/*.csproj" >/dev/null \
     || compgen -G "$dir/*.sln" >/dev/null \
     || [ -f "$dir/global.json" ]; then
    _mcl_stack_add csharp
  fi

  # ---- Domain-shape tags (since 8.4.1) ----
  # These are NOT language tags — they classify the project's domain
  # shape so Phase 1.7 can pick the right stack add-on. False positives
  # are accepted (Phase 1.7 dimensions are general enough to misfire
  # without breaking the spec).

  # CLI — bin entries in language manifests, bin/ dir, or cmd/ Go convention.
  _mcl_is_cli=0
  if [ -f "$dir/package.json" ] && grep -q '"bin"\s*:' "$dir/package.json" 2>/dev/null; then
    _mcl_is_cli=1
  fi
  if [ -f "$dir/pyproject.toml" ] && grep -qE '\[(project|tool\.poetry)\.scripts\]' "$dir/pyproject.toml" 2>/dev/null; then
    _mcl_is_cli=1
  fi
  if [ -f "$dir/Cargo.toml" ] && grep -q '\[\[bin\]\]' "$dir/Cargo.toml" 2>/dev/null; then
    _mcl_is_cli=1
  fi
  if [ -f "$dir/go.mod" ] && [ -d "$dir/cmd" ]; then
    _mcl_is_cli=1
  fi
  if [ -d "$dir/bin" ] && compgen -G "$dir/bin/*" >/dev/null; then
    # bin/ dir with at least one entry — exclude empty bin/ placeholders.
    _mcl_is_cli=1
  fi
  if [ "$_mcl_is_cli" = "1" ]; then
    _mcl_stack_add cli
  fi
  unset _mcl_is_cli

  # Data pipeline — orchestrators (Airflow / dbt / Prefect / Dagster) or
  # batch/stream framework deps in Python requirements.
  _mcl_is_dp=0
  [ -f "$dir/airflow.cfg" ] && _mcl_is_dp=1
  [ -d "$dir/dags" ] && _mcl_is_dp=1
  [ -f "$dir/dbt_project.yml" ] && _mcl_is_dp=1
  [ -f "$dir/prefect.yaml" ] && _mcl_is_dp=1
  [ -f "$dir/prefect.toml" ] && _mcl_is_dp=1
  if compgen -G "$dir/requirements*.txt" >/dev/null; then
    if grep -hqE '^(apache-beam|pyspark|dagster|dask|luigi)([[:space:]]|=|<|>|~|$)' "$dir"/requirements*.txt 2>/dev/null; then
      _mcl_is_dp=1
    fi
  fi
  if [ "$_mcl_is_dp" = "1" ]; then
    _mcl_stack_add data-pipeline
  fi
  unset _mcl_is_dp

  # ML inference — model artifact files OR ML library deps OR mlflow dirs.
  _mcl_is_ml=0
  for ext in pkl onnx pt h5 safetensors pb; do
    if compgen -G "$dir/*.$ext" >/dev/null \
       || compgen -G "$dir/**/*.$ext" >/dev/null 2>&1; then
      _mcl_is_ml=1
      break
    fi
  done
  [ -d "$dir/mlflow" ] && _mcl_is_ml=1
  [ -d "$dir/mlruns" ] && _mcl_is_ml=1
  [ -f "$dir/model_card.md" ] && _mcl_is_ml=1
  [ -f "$dir/MODEL.md" ] && _mcl_is_ml=1
  if [ "$_mcl_is_ml" = "0" ] && compgen -G "$dir/requirements*.txt" >/dev/null; then
    if grep -hqE '^(torch|tensorflow|transformers|scikit-learn|xgboost|lightgbm|bentoml|mlflow)([[:space:]]|=|<|>|~|$)' "$dir"/requirements*.txt 2>/dev/null; then
      _mcl_is_ml=1
    fi
  fi
  if [ "$_mcl_is_ml" = "0" ] && [ -f "$dir/pyproject.toml" ]; then
    if grep -qE '"(torch|tensorflow|transformers|scikit-learn|xgboost|lightgbm|bentoml|mlflow)"' "$dir/pyproject.toml" 2>/dev/null; then
      _mcl_is_ml=1
    fi
  fi
  if [ "$_mcl_is_ml" = "1" ]; then
    _mcl_stack_add ml-inference
  fi
  unset _mcl_is_ml

  # ---- DB dialect tags (since 8.8.0) ----
  # Detected from: manifest deps (npm/pip/cargo/go/Gemfile/composer), Docker
  # compose service images, env example connection-string regex. False
  # positives accepted (DB rules are general enough to misfire safely).

  _mcl_has_dep() {
    # _mcl_has_dep <pattern> — grep across common manifests
    grep -qE "$1" "$dir/package.json" 2>/dev/null && return 0
    grep -qE "$1" "$dir/package-lock.json" 2>/dev/null && return 0
    grep -qE "$1" "$dir/pyproject.toml" 2>/dev/null && return 0
    grep -qE "$1" "$dir"/requirements*.txt 2>/dev/null && return 0
    grep -qE "$1" "$dir/Cargo.toml" 2>/dev/null && return 0
    grep -qE "$1" "$dir/go.mod" 2>/dev/null && return 0
    grep -qE "$1" "$dir/Gemfile" 2>/dev/null && return 0
    grep -qE "$1" "$dir/composer.json" 2>/dev/null && return 0
    return 1
  }
  _mcl_compose_image() {
    # _mcl_compose_image <pattern> — Docker compose service image regex
    grep -qE "image:\s*[\"']?$1" "$dir/docker-compose.yml" "$dir/docker-compose.yaml" "$dir/compose.yml" "$dir/compose.yaml" 2>/dev/null
  }
  _mcl_envexample_url() {
    # _mcl_envexample_url <prefix> — connection string in .env.example
    grep -qiE "(database_url|db_url|conn(ection)?_?str(ing)?)\s*=\s*$1" "$dir/.env.example" "$dir/.env.sample" 2>/dev/null
  }

  if _mcl_has_dep '"pg"|psycopg|asyncpg|sqlalchemy.*postgres|pq\b|jackc/pgx|github.com/lib/pq' || _mcl_compose_image 'postgres' || _mcl_envexample_url 'postgres'; then
    _mcl_stack_add db-postgres
  fi
  if _mcl_has_dep '"mysql2?"|pymysql|mysqlclient|go-sql-driver/mysql|mariadb' || _mcl_compose_image 'mysql|mariadb' || _mcl_envexample_url 'mysql'; then
    _mcl_stack_add db-mysql
  fi
  if _mcl_has_dep 'better-sqlite3|"sqlite3?"|sqlx.*sqlite|github.com/mattn/go-sqlite3' || [ -f "$dir"/*.db ] 2>/dev/null; then
    _mcl_stack_add db-sqlite
  fi
  if _mcl_has_dep 'mariadb' || _mcl_compose_image 'mariadb'; then
    _mcl_stack_add db-mariadb
  fi
  if _mcl_has_dep 'mongoose|mongodb|pymongo|motor|go.mongodb.org/mongo-driver' || _mcl_compose_image 'mongo'; then
    _mcl_stack_add db-mongo
  fi
  if _mcl_has_dep '"redis"|ioredis|redis-py|github.com/redis/go-redis|predis' || _mcl_compose_image 'redis'; then
    _mcl_stack_add db-redis
  fi

  # ---- Cloud DB tags (since 8.8.0; tag-only — rule packs in 8.8.x) ----
  if _mcl_has_dep '@google-cloud/bigquery|google-cloud-bigquery|cloud.google.com/go/bigquery'; then
    _mcl_stack_add db-bigquery
  fi
  if _mcl_has_dep 'snowflake-(connector|sdk)|snowflake/snowflake-connector|gosnowflake'; then
    _mcl_stack_add db-snowflake
  fi
  if _mcl_has_dep '@aws-sdk/client-dynamodb|boto3|github.com/aws/aws-sdk-go.*dynamodb'; then
    _mcl_stack_add db-dynamodb
  fi

  # ---- ORM tags (since 8.8.0) ----
  # Detected from: manifest dep + schema/model file presence + import scan.
  if [ -f "$dir/prisma/schema.prisma" ] || _mcl_has_dep '"@?prisma'; then
    _mcl_stack_add orm-prisma
  fi
  if _mcl_has_dep '\bsqlalchemy\b|SQLAlchemy'; then
    _mcl_stack_add orm-sqlalchemy
  fi
  if _mcl_has_dep '\bdjango\b|Django' || [ -f "$dir/manage.py" ]; then
    _mcl_stack_add orm-django
  fi
  if _mcl_has_dep '"rails"|activerecord' || [ -f "$dir/config/application.rb" ]; then
    _mcl_stack_add orm-activerecord
  fi
  if _mcl_has_dep '"sequelize"'; then
    _mcl_stack_add orm-sequelize
  fi
  if _mcl_has_dep '"typeorm"'; then
    _mcl_stack_add orm-typeorm
  fi
  if _mcl_has_dep 'gorm.io/gorm|jinzhu/gorm'; then
    _mcl_stack_add orm-gorm
  fi
  if _mcl_has_dep 'illuminate/database|laravel/framework'; then
    _mcl_stack_add orm-eloquent
  fi

  unset -f _mcl_has_dep _mcl_compose_image _mcl_envexample_url

  if [ "${#detected[@]}" -gt 0 ]; then
    printf '%s\n' "${detected[@]}"
  fi

  unset -f _mcl_stack_add
}

# mcl_is_ui_capable — heuristic: does this project have a UI surface?
# Returns 0 (true) / 1 (false). Called once per session by
# mcl-activate.sh to decide ui_flow_active without prompting the
# developer. Cheap checks only — existence tests and jq lookups.
#
# True when any of:
#   - package.json exists AND:
#       * templates/ dir (Symfony/Twig) present, OR
#       * scripts.dev / scripts.start / scripts.serve defined, OR
#       * src/components/, src/pages/, src/app/ dir exists, OR
#       * src/ dir exists with *.tsx / *.jsx / *.vue / *.svelte files
#   - manage.py + templates/ dir (Django)
#   - Gemfile mentions rails AND app/views/ exists (Rails)
#   - config/routes.rb exists AND app/views/ exists (Rails, alt signal)
#   - Root-level index.html (static site) — even alongside package.json
#   - composer.json exists AND templates/ dir (Symfony/Laravel/Twig)
#
# False when none of the above hold. CLI repos, pure-backend APIs,
# config-only repos, MCL itself (only hooks/ + skills/) → false.
mcl_is_ui_capable() {
  local dir="${1:-$(pwd)}"
  [ -d "$dir" ] || return 1

  # Root-level index.html — static site, any stack.
  [ -f "$dir/index.html" ] && return 0

  # Node / frontend framework land.
  if [ -f "$dir/package.json" ]; then
    # Symfony/Twig projects carry package.json (Encore) alongside templates/.
    [ -d "$dir/templates" ] && return 0

    # Component/page dirs are strong UI signals.
    [ -d "$dir/src/components" ] && return 0
    [ -d "$dir/src/pages" ] && return 0
    [ -d "$dir/src/app" ] && return 0
    [ -d "$dir/app" ] && return 0

    # jq check on scripts.dev/start/serve — cheap, no content parsing
    # beyond JSON-native.
    if command -v jq >/dev/null 2>&1; then
      local script
      script="$(jq -r '.scripts.dev // .scripts.start // .scripts.serve // empty' "$dir/package.json" 2>/dev/null)"
      [ -n "$script" ] && return 0
    else
      # jq absent — fall back to substring match.
      if grep -qE '"(dev|start|serve)"[[:space:]]*:' "$dir/package.json" 2>/dev/null; then
        return 0
      fi
    fi

    # Any frontend file extension under src/.
    if [ -d "$dir/src" ]; then
      if find "$dir/src" -maxdepth 3 -type f \
           \( -name '*.tsx' -o -name '*.jsx' -o -name '*.vue' -o -name '*.svelte' \) \
           2>/dev/null | grep -q .; then
        return 0
      fi
    fi
  fi

  # Django.
  if [ -f "$dir/manage.py" ] && [ -d "$dir/templates" ]; then
    return 0
  fi

  # Rails — app/views/ is the canonical template dir.
  if [ -d "$dir/app/views" ]; then
    return 0
  fi

  # PHP composer projects with templates/ (Symfony without package.json,
  # Laravel with resources/views).
  if [ -f "$dir/composer.json" ]; then
    [ -d "$dir/templates" ] && return 0
    [ -d "$dir/resources/views" ] && return 0
  fi

  return 1
}

# CLI dispatch — only when invoked directly, not when sourced.
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
  cmd="${1:-}"
  case "$cmd" in
    detect)
      shift
      mcl_stack_detect "${1:-}"
      ;;
    ui-capable)
      shift
      if mcl_is_ui_capable "${1:-}"; then
        echo "true"
      else
        echo "false"
      fi
      ;;
    *)
      echo "usage: $0 detect|ui-capable [dir]" >&2
      exit 2
      ;;
  esac
fi
