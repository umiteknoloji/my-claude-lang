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

  if [ "${#detected[@]}" -gt 0 ]; then
    printf '%s\n' "${detected[@]}"
  fi

  unset -f _mcl_stack_add
}

# CLI dispatch — only when invoked directly, not when sourced.
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
  cmd="${1:-}"
  case "$cmd" in
    detect)
      shift
      mcl_stack_detect "${1:-}"
      ;;
    *)
      echo "usage: $0 detect [dir]" >&2
      exit 2
      ;;
  esac
fi
