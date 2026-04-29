#!/usr/bin/env bash
# MCL global installer.
#
# Clones (or updates) the MCL library into ~/.mcl/lib and links the
# mcl-claude wrapper into ~/.local/bin (override with MCL_BIN).
#
# Idempotent — safe to re-run for upgrades.
#
# Usage:
#   bash install.sh
#   curl -sSL https://raw.githubusercontent.com/YZ-LLM/my-claude-lang/main/install.sh | bash
#
# Env overrides:
#   MCL_HOME  (default: ~/.mcl)
#   MCL_BIN   (default: ~/.local/bin)
#   MCL_REPO  (default: https://github.com/YZ-LLM/my-claude-lang)

set -euo pipefail

MCL_HOME="${MCL_HOME:-$HOME/.mcl}"
LIB="$MCL_HOME/lib"
BIN="${MCL_BIN:-$HOME/.local/bin}"
REPO="${MCL_REPO:-https://github.com/YZ-LLM/my-claude-lang}"

mkdir -p "$MCL_HOME/projects"
mkdir -p "$BIN"

if [ -d "$LIB/.git" ]; then
  echo "Updating MCL at $LIB ..."
  git -C "$LIB" pull --ff-only
else
  if [ -e "$LIB" ]; then
    echo "install.sh: $LIB exists but is not a git repo. Aborting to avoid clobbering." >&2
    exit 1
  fi
  echo "Cloning MCL into $LIB ..."
  git clone "$REPO" "$LIB"
fi

chmod +x "$LIB/bin/mcl-claude"
ln -sf "$LIB/bin/mcl-claude" "$BIN/mcl-claude"

version="$(cat "$LIB/VERSION" 2>/dev/null || echo unknown)"
echo
echo "✓ MCL $version installed → $BIN/mcl-claude"
echo "✓ Library: $LIB"
echo "✓ Per-project state: $MCL_HOME/projects/<key>/"
echo
echo "Usage:  cd <your-project> && mcl-claude"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *)
    echo
    echo "⚠  $BIN is not in your PATH."
    echo "   Add this to your shell rc (~/.bashrc, ~/.zshrc):"
    echo "     export PATH=\"$BIN:\$PATH\""
    ;;
esac
