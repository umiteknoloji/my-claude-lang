#!/bin/bash
# MCL Plugin Gate — compute required plugins+binaries for a project and
# check what's missing.
#
# Sourceable library AND CLI. All output is advisory (exit 0) so the
# caller (mcl-activate.sh) decides whether to gate.
#
# Required set = curated tier-A orchestration plugins (always required)
# plus one LSP plugin per stack tag returned by mcl-stack-detect.sh.
# Stack-tag → LSP plugin + binary mapping is the canonical table in
# skills/my-claude-lang/plugin-suggestions.md, mirrored here as a pure-
# bash lookup so the gate has zero runtime dependency on the skill file.
#
# "Installed" means a key matching `<plugin>@*` exists under `.plugins`
# in `~/.claude/plugins/installed_plugins.json`. A binary is "present"
# when `command -v <bin>` resolves under the user's login shell.
#
# CLI:
#   mcl-plugin-gate.sh required-plugins [dir]
#   mcl-plugin-gate.sh required-binaries <plugin>
#   mcl-plugin-gate.sh check [dir]
#
# Sourced:
#   source hooks/lib/mcl-plugin-gate.sh
#   mcl_plugin_gate_check "$PWD"

set -u

MCL_PLUGIN_GATE_INSTALLED_FILE="${MCL_PLUGIN_GATE_INSTALLED_FILE:-$HOME/.claude/plugins/installed_plugins.json}"

_mcl_plugin_gate_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
[ -f "$_mcl_plugin_gate_dir/mcl-stack-detect.sh" ] && \
  source "$_mcl_plugin_gate_dir/mcl-stack-detect.sh"

# Stack tag → LSP plugin name. Mirrors plugin-suggestions.md.
_mcl_plugin_gate_lsp_for_tag() {
  case "$1" in
    typescript|javascript) echo "typescript-lsp" ;;
    python)                echo "pyright-lsp" ;;
    go)                    echo "gopls-lsp" ;;
    rust)                  echo "rust-analyzer-lsp" ;;
    java)                  echo "jdtls-lsp" ;;
    kotlin)                echo "kotlin-lsp" ;;
    csharp)                echo "csharp-lsp" ;;
    php)                   echo "php-lsp" ;;
    ruby)                  echo "ruby-lsp" ;;
    swift)                 echo "swift-lsp" ;;
    cpp)                   echo "clangd-lsp" ;;
    lua)                   echo "lua-lsp" ;;
    *) return 1 ;;
  esac
}

# Plugin name → required binary (one per plugin, empty if bundled).
mcl_plugin_gate_required_binaries() {
  case "$1" in
    typescript-lsp)    echo "typescript-language-server" ;;
    pyright-lsp)       echo "pyright-langserver" ;;
    gopls-lsp)         echo "gopls" ;;
    rust-analyzer-lsp) echo "rust-analyzer" ;;
    jdtls-lsp)         echo "jdtls" ;;
    kotlin-lsp)        echo "kotlin-language-server" ;;
    csharp-lsp)        echo "csharp-ls" ;;
    php-lsp)           echo "intelephense" ;;
    swift-lsp)         echo "sourcekit-lsp" ;;
    clangd-lsp)        echo "clangd" ;;
    lua-lsp)           echo "lua-language-server" ;;
    # ruby-lsp bundles its binary; curated tier-A plugins have none.
    *) : ;;
  esac
}

_mcl_plugin_gate_has_any_source_files() {
  # Return 0 if the project directory contains at least one recognizable
  # source file. Bootstrap / empty projects return 1 so LSP plugin
  # suggestions are suppressed until the developer has committed to a stack.
  local dir="${1:-$(pwd)}"
  local exts="js ts jsx tsx py go rb java kt php cpp cc cxx c cs rs swift lua vue svelte"
  local ext f
  for ext in $exts; do
    f="$(find "$dir" -maxdepth 6 -name "*.${ext}" -not -path '*/.git/*' \
         -not -path '*/node_modules/*' -not -path '*/__pycache__/*' \
         -not -path '*/vendor/*' 2>/dev/null | head -1)"
    [ -n "$f" ] && return 0
  done
  return 1
}

mcl_plugin_gate_required_plugins() {
  # Curated tier-A always required, regardless of stack.
  # 8.19.2: superpowers dropped — MCL has no code-path dependency on
  # it (see CHANGELOG); the plugin's auto-loaded using-superpowers
  # skill triggers conflicting brainstorming attempts MCL Phase 1-3
  # already cover.
  echo "security-guidance"

  local dir="${1:-$(pwd)}"
  # LSP plugins are only relevant when source files already exist.
  # An empty/bootstrap project has no stack yet — skip LSP suggestions.
  _mcl_plugin_gate_has_any_source_files "$dir" 2>/dev/null || return 0

  local tag
  # Stack detect is advisory — unknown stacks simply add no LSP rows.
  while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    _mcl_plugin_gate_lsp_for_tag "$tag" 2>/dev/null || true
  done < <(mcl_stack_detect "$dir" 2>/dev/null || true)
}

_mcl_plugin_gate_plugin_installed() {
  # Returns 0 iff `<name>@*` is a key under `.plugins` in the installed
  # file. Missing file → nothing installed → return 1 for every check.
  local name="$1"
  [ -f "$MCL_PLUGIN_GATE_INSTALLED_FILE" ] || return 1
  python3 - "$MCL_PLUGIN_GATE_INSTALLED_FILE" "$name" <<'PY' 2>/dev/null
import json, sys
path, name = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        obj = json.load(f)
    plugins = obj.get("plugins", {}) if isinstance(obj, dict) else {}
    for key in plugins.keys():
        head = key.split("@", 1)[0]
        if head == name:
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PY
}

_mcl_plugin_gate_binary_present() {
  # Use login shell so PATH matches what the developer sees in their
  # terminal (nvm, pyenv, asdf, rbenv shims usually live there).
  bash -lc 'command -v "$0" >/dev/null 2>&1' "$1"
}

mcl_plugin_gate_check() {
  # Emit one JSON line per missing item to stdout. Always exit 0.
  #   {"kind":"plugin","name":"<n>"}
  #   {"kind":"binary","plugin":"<p>","name":"<b>"}
  local dir="${1:-$(pwd)}"
  local plugin bin
  while IFS= read -r plugin; do
    [ -z "$plugin" ] && continue
    if ! _mcl_plugin_gate_plugin_installed "$plugin"; then
      printf '{"kind":"plugin","name":"%s"}\n' "$plugin"
      continue
    fi
    bin="$(mcl_plugin_gate_required_binaries "$plugin")"
    [ -z "$bin" ] && continue
    if ! _mcl_plugin_gate_binary_present "$bin"; then
      printf '{"kind":"binary","plugin":"%s","name":"%s"}\n' "$plugin" "$bin"
    fi
  done < <(mcl_plugin_gate_required_plugins "$dir")
  return 0
}

# CLI dispatch — only when invoked directly, not when sourced.
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
  cmd="${1:-}"
  case "$cmd" in
    required-plugins)
      shift
      mcl_plugin_gate_required_plugins "${1:-}"
      ;;
    required-binaries)
      shift
      mcl_plugin_gate_required_binaries "${1:-}"
      ;;
    check)
      shift
      mcl_plugin_gate_check "${1:-}"
      ;;
    *)
      echo "usage: $0 {required-plugins [dir]|required-binaries <plugin>|check [dir]}" >&2
      exit 2
      ;;
  esac
fi
