#!/usr/bin/env bash
# setup.sh — MyCL 1.0.0 kurulumu / installer
#
# Yapılan iş:
#   1. Python 3.8+ kontrolü
#   2. ~/.claude/mycl/ — repo'nun bir kopyası (hooks/ import path'leri
#      `from hooks.lib import` formatında; tek dizin altında klonlanırsa
#      dev = prod simetrisi korunur)
#   3. ~/.claude/skills/mycl.md + ~/.claude/skills/mycl/ — Claude Code
#      skill loader buraya bakar
#   4. ~/.claude/data/ — gate.py + askq.py + bilingual.py JSON'ları
#      buradan da arar
#   5. ~/.claude/settings.json — 4 hook event MERGE (mevcut hook'lar
#      korunur; aynı command varsa atlanır)
#   6. Smoke test (py_compile + lib import)
#
# Kullanım:
#   bash setup.sh           # standart
#   bash setup.sh --dry-run # sadece göster
#   bash setup.sh --force   # var olan dosyaları üzerine yaz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MYCL_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION" 2>/dev/null || echo '?')"
DRY_RUN=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    -h|--help)
      cat <<'EOF'
setup.sh — MyCL 1.0.0 kurulumu / installer

Kullanım:
  bash setup.sh           # standart
  bash setup.sh --dry-run # sadece göster, kopyalama yapma
  bash setup.sh --force   # var olan dosyaları üzerine yaz

Çıktı:
  ~/.claude/mycl/         (hooks/, skills/, data/, lib/ — repo kopyası)
  ~/.claude/skills/mycl.md  + skills/mycl/  (Claude Code skill loader)
  ~/.claude/data/         (gate_spec, phase_meta, ...)
  ~/.claude/settings.json (4 hook event merged)
EOF
      exit 0
      ;;
    *) echo "Bilinmeyen argüman: $arg" >&2; exit 1 ;;
  esac
done

run() {
  if [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# 1. Python 3.8+ kontrolü
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ python3 bulunamadı. MyCL pure Python 3.8+ gerektirir." >&2
  echo "❌ python3 not found. MyCL requires pure Python 3.8+." >&2
  exit 1
fi

PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PY_MAJOR="$(python3 -c 'import sys; print(sys.version_info.major)')"
PY_MINOR="$(python3 -c 'import sys; print(sys.version_info.minor)')"

if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 8 ]; }; then
  echo "❌ Python $PY_VER tespit edildi; MyCL 3.8+ gerektirir." >&2
  echo "❌ Python $PY_VER detected; MyCL requires 3.8+." >&2
  exit 1
fi

echo "✓ Python $PY_VER"

# 2. ~/.claude/ alt dizinler
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
MYCL_DIR="$CLAUDE_DIR/mycl"
SKILLS_DIR="$CLAUDE_DIR/skills"
DATA_DIR="$CLAUDE_DIR/data"
AGENTS_DIR="$CLAUDE_DIR/agents"
SETTINGS="$CLAUDE_DIR/settings.json"

run mkdir -p "$MYCL_DIR" "$SKILLS_DIR/mycl/ortak" "$DATA_DIR" "$AGENTS_DIR"

# 3. ~/.claude/mycl/ — repo kopyası (hooks + skills + data + lib)
echo "→ ~/.claude/mycl/ — repo klonlanıyor"

copy_tree() {
  # $1=src dir, $2=dst dir; (--force yoksa) var olanı atlar
  local src="$1" dst="$2"
  if [ "$DRY_RUN" = 1 ]; then
    echo "  [dry-run] cp -R $src → $dst"
    return
  fi
  mkdir -p "$dst"
  # POSIX-uyumlu kopyalama: find + cp (rsync varsayma)
  while IFS= read -r f; do
    rel="${f#$src/}"
    dst_file="$dst/$rel"
    if [ -d "$f" ]; then
      mkdir -p "$dst_file"
    else
      mkdir -p "$(dirname "$dst_file")"
      if [ -f "$dst_file" ] && [ "$FORCE" = 0 ]; then
        echo "  ↷ skip (exists): $dst_file"
        continue
      fi
      cp "$f" "$dst_file"
    fi
  done < <(find "$src" -mindepth 1)
}

copy_tree "$SCRIPT_DIR/hooks" "$MYCL_DIR/hooks"
copy_tree "$SCRIPT_DIR/skills" "$MYCL_DIR/skills"
copy_tree "$SCRIPT_DIR/data" "$MYCL_DIR/data"

# VERSION dosyası — activate.py _REPO_ROOT/VERSION okur; eksikse '0.0.0' (H-4 fix)
# copy_file henüz tanımlı değil; doğrudan cp kullanılır
if [ "$DRY_RUN" = 1 ]; then
  echo "  [dry-run] cp $SCRIPT_DIR/VERSION → $MYCL_DIR/VERSION"
elif [ -f "$SCRIPT_DIR/VERSION" ]; then
  if [ -f "$MYCL_DIR/VERSION" ] && [ "$FORCE" = 0 ]; then
    echo "  ↷ skip (exists): $MYCL_DIR/VERSION"
  else
    cp "$SCRIPT_DIR/VERSION" "$MYCL_DIR/VERSION"
    echo "  ✓ $MYCL_DIR/VERSION"
  fi
fi

# Hook'lara executable izin
if [ "$DRY_RUN" = 0 ]; then
  chmod +x "$MYCL_DIR"/hooks/*.py 2>/dev/null || true
fi

echo "  ✓ $MYCL_DIR populated"

# 4. ~/.claude/skills/mycl.md + skills/mycl/ — Claude Code skill loader
echo "→ ~/.claude/skills/ — skill loader"

copy_file() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && [ "$FORCE" = 0 ]; then
    echo "  ↷ skip (exists): $dst"
    return
  fi
  if [ "$DRY_RUN" = 1 ]; then
    echo "  [dry-run] cp $src → $dst"
  else
    cp "$src" "$dst"
    echo "  ✓ $dst"
  fi
}

copy_file "$SCRIPT_DIR/skills/mycl.md" "$SKILLS_DIR/mycl.md"
for f in "$SCRIPT_DIR"/skills/mycl/*.md; do
  [ -f "$f" ] || continue
  copy_file "$f" "$SKILLS_DIR/mycl/$(basename "$f")"
done
for f in "$SCRIPT_DIR"/skills/mycl/ortak/*.md; do
  [ -f "$f" ] || continue
  copy_file "$f" "$SKILLS_DIR/mycl/ortak/$(basename "$f")"
done

# 5. ~/.claude/data/ — gate/askq/bilingual JSON'ları
echo "→ ~/.claude/data/"
for f in "$SCRIPT_DIR"/data/*; do
  [ -f "$f" ] || continue
  copy_file "$f" "$DATA_DIR/$(basename "$f")"
done

# 5.5. ~/.claude/agents/ — agent definitions (Claude Code agent loader)
echo "→ ~/.claude/agents/ — agent definitions"
for f in "$SCRIPT_DIR"/agents/*.md; do
  [ -f "$f" ] || continue
  copy_file "$f" "$AGENTS_DIR/$(basename "$f")"
done

# 6. settings.json hook merge (Python — JSON merge atomik)
echo "→ settings.json hook merge"
if [ "$DRY_RUN" = 1 ]; then
  echo "  [dry-run] python3 merge $SETTINGS"
else
  python3 - <<PYEOF
import json
import os
import sys
from pathlib import Path

settings_path = Path("$SETTINGS")
hooks_root = Path("$MYCL_DIR") / "hooks"

mycl_hooks = {
    "UserPromptSubmit": str(hooks_root / "activate.py"),
    "PreToolUse":       str(hooks_root / "pre_tool.py"),
    "PostToolUse":      str(hooks_root / "post_tool.py"),
    "Stop":             str(hooks_root / "stop.py"),
    "PreCompact":       str(hooks_root / "pre_compact.py"),
}

# Mevcut settings'i oku (yoksa boş dict)
if settings_path.exists():
    try:
        data = json.loads(settings_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        backup = settings_path.with_suffix(".json.backup")
        print(f"  ⚠️ {settings_path} bozuk JSON; {backup}'a alındı", file=sys.stderr)
        settings_path.rename(backup)
        data = {}
else:
    data = {}

if not isinstance(data, dict):
    data = {}

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    hooks = {}
    data["hooks"] = hooks

added = 0
skipped = 0
for event, command in mycl_hooks.items():
    entries = hooks.setdefault(event, [])
    if not isinstance(entries, list):
        entries = []
        hooks[event] = entries

    new_command = f"python3 {command}"
    already_present = False
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        for h in entry.get("hooks", []):
            if isinstance(h, dict) and h.get("command") == new_command:
                already_present = True
                break
        if already_present:
            break

    if already_present:
        skipped += 1
        continue

    entries.append({
        "matcher": "*",
        "hooks": [{"type": "command", "command": new_command}],
    })
    added += 1

# Atomik write
tmp = settings_path.with_suffix(".json.tmp")
tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
os.replace(tmp, settings_path)

print(f"  ✓ {added} hook eklendi / added, {skipped} zaten var / already present")
PYEOF
fi

# 7. Smoke test
echo "→ smoke test"
if [ "$DRY_RUN" = 1 ]; then
  echo "  [dry-run] py_compile + import"
else
  if python3 -m py_compile "$MYCL_DIR"/hooks/*.py "$MYCL_DIR"/hooks/lib/*.py 2>/dev/null; then
    echo "  ✓ py_compile OK"
  else
    echo "  ❌ py_compile başarısız" >&2
    exit 1
  fi

  if PYTHONPATH="$MYCL_DIR" python3 -c "from hooks.lib import audit, gate, state, askq, spec_detect, transcript, bilingual" 2>/dev/null; then
    echo "  ✓ lib import OK"
  else
    echo "  ⚠️ lib import warning — hook'lar çalışırken sys.path ekleyecek"
  fi
fi

# 8. Tamamlandı (TR + EN)
echo
echo "✅ MyCL $MYCL_VERSION kurulumu tamamlandı."
echo
echo "Sonraki adımlar:"
echo "  1. Yeni bir Claude Code oturumu başlat"
echo "  2. Bir proje dizinine git: cd ~/projects/yeni-app"
echo "  3. \"todo app yap\" gibi bir niyet yaz — MyCL Aşama 1'i tetikleyecek"
echo
echo "✅ MyCL $MYCL_VERSION installation complete."
echo
echo "Next steps:"
echo "  1. Start a new Claude Code session"
echo "  2. cd into a project: cd ~/projects/new-app"
echo "  3. Type an intent like \"build a todo app\" — MyCL will trigger Phase 1"
echo
echo "Devre dışı bırakma / Disable:"
echo "  ~/.claude/settings.json'dan 'mycl' içeren hook girişlerini sil."
