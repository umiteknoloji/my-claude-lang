#!/usr/bin/env python3
"""
MCL Skill Build Script

Reads phase-mapping.md (canonical source) + processes templates in
skills/my-claude-lang/_templates/ → emits skill files in skills/my-claude-lang/.

Placeholder format:
  {{phase_no:slug}}    → phase number (e.g., 9)
  {{phase_name:slug}}  → canonical name (e.g., "TDD Yürütme")
  {{phase_audit:slug}} → output audit pattern
  {{phase_file:slug}}  → skill filename

Slug must match the "Slug" column in phase-mapping.md.

Usage:
  python3 scripts/build-skills.py
  python3 scripts/build-skills.py --check  # verify only, no write
"""
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
MAPPING_FILE = REPO_ROOT / "skills" / "my-claude-lang" / "phase-mapping.md"
TEMPLATE_DIR = REPO_ROOT / "skills" / "my-claude-lang" / "_templates"
OUTPUT_DIR = REPO_ROOT / "skills" / "my-claude-lang"


def parse_mapping(mapping_file):
    """Parse phase-mapping.md table → dict keyed by slug."""
    if not mapping_file.exists():
        sys.exit(f"ERROR: mapping file not found: {mapping_file}")

    text = mapping_file.read_text(encoding="utf-8")
    table_re = re.compile(
        r"^\|\s*(\d+)\s*\|\s*([\w-]+)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|$",
        re.MULTILINE,
    )
    phases = {}
    for m in table_re.finditer(text):
        no, slug, name, audit, filename = m.groups()
        phases[slug.strip()] = {
            "no": int(no),
            "name": name.strip(),
            "audit": audit.strip(),
            "file": filename.strip(),
        }

    if len(phases) != 22:
        sys.exit(f"ERROR: expected 22 phases in mapping, got {len(phases)}")
    return phases


def process_template(template_text, phases):
    """Replace {{key:slug}} placeholders with values from phases dict."""
    placeholder_re = re.compile(r"\{\{(phase_no|phase_name|phase_audit|phase_file):([\w-]+)\}\}")
    missing = set()

    def repl(match):
        key, slug = match.group(1), match.group(2)
        if slug not in phases:
            missing.add(slug)
            return match.group(0)
        # phase_no → "no", phase_name → "name", etc.
        attr = key.replace("phase_", "")
        value = phases[slug][attr]
        return str(value)

    output = placeholder_re.sub(repl, template_text)
    if missing:
        sys.exit(f"ERROR: unknown slug(s) referenced in template: {sorted(missing)}")
    return output


def build(check_only=False):
    phases = parse_mapping(MAPPING_FILE)
    print(f"Mapping loaded: {len(phases)} phases")

    if not TEMPLATE_DIR.exists():
        print(f"NOTE: template dir empty/missing — no templates to build: {TEMPLATE_DIR}")
        return 0

    templates = sorted(TEMPLATE_DIR.glob("*.md.tmpl"))
    if not templates:
        print(f"NOTE: no .md.tmpl files in {TEMPLATE_DIR}")
        return 0

    changed = 0
    for tmpl in templates:
        out_name = tmpl.name.removesuffix(".tmpl")
        out_path = OUTPUT_DIR / out_name
        text = tmpl.read_text(encoding="utf-8")
        rendered = process_template(text, phases)

        if check_only:
            existing = out_path.read_text(encoding="utf-8") if out_path.exists() else None
            if existing != rendered:
                print(f"  [drift]  {out_name} — needs rebuild")
                changed += 1
            else:
                print(f"  [ok]     {out_name}")
        else:
            existing = out_path.read_text(encoding="utf-8") if out_path.exists() else None
            if existing == rendered:
                print(f"  [skip]   {out_name} (unchanged)")
            else:
                out_path.write_text(rendered, encoding="utf-8")
                print(f"  [build]  {out_name}")
                changed += 1

    print(f"Done. {changed} file(s) {'would change' if check_only else 'changed'}.")
    return 1 if (check_only and changed > 0) else 0


def main():
    check = "--check" in sys.argv
    return build(check_only=check)


if __name__ == "__main__":
    sys.exit(main())
