#!/usr/bin/env python3
"""MCL Codebase Scan — extracts P1-P12 patterns and writes:
  - <state-dir>/project.md       (high-confidence; merged via mcl-auto markers)
  - <state-dir>/project-scan-report.md (all findings, in user's language)

Triggered by `/codebase-scan` keyword via mcl-activate.sh. Manual only —
no automatic invocation.

Since 8.6.0.

Usage:
  python3 mcl-codebase-scan.py --state-dir <dir> --project-dir <dir> --lang <iso>

Output (stdout): markdown summary suitable for direct presentation to the
developer (already localized to --lang).
Output (stderr): progress lines `[MCL] Scanning... <done>/<total>`.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

# ---- Excludes ----
EXCLUDE_DIRS = {
    ".git", "node_modules", "dist", "build", ".next", ".nuxt",
    "target", "vendor", ".venv", "venv", "__pycache__", ".cache",
    "coverage", ".pytest_cache", ".mypy_cache", ".ruff_cache",
    "out", ".turbo", ".parcel-cache", ".svelte-kit",
}
SOURCE_EXTS = {
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs",
    ".py", ".rb", ".go", ".rs", ".java", ".kt", ".swift",
    ".cs", ".php", ".cpp", ".cc", ".c", ".h", ".hpp",
    ".lua", ".vue", ".svelte", ".scala", ".dart",
}
SKIP_FILE_PATTERNS = (".min.", ".bundle.", "-lock.", ".lock")
MAX_FILE_BYTES = 1024 * 1024  # 1 MB


@dataclass
class Finding:
    pattern_id: str
    confidence: str  # "high"|"medium"|"low"
    summary: str
    evidence: list[str] = field(default_factory=list)
    details: str | None = None


# ============================================================
# Localization
# ============================================================
LOC = {
    "en": {
        "title": "Codebase Scan Report",
        "scan_complete": "Scan complete.",
        "files_scanned": "Files scanned",
        "high_conf": "High-confidence findings (written to project.md)",
        "med_conf": "Medium-confidence findings",
        "low_conf": "Low-confidence findings",
        "no_findings": "No findings.",
        "saved_to": "Saved to",
        "evidence": "Evidence",
        "auto_section_note": "Managed by /codebase-scan. Manual edits between these markers will be overwritten.",
        "last_scan": "Last scan",
        "auto_arch": "Auto: Architecture",
        "auto_stack": "Auto: Stack & Tooling",
        "auto_conv": "Auto: Conventions",
        "auto_test": "Auto: Testing",
        "auto_other": "Auto: Other",
    },
    "tr": {
        "title": "Codebase Tarama Raporu",
        "scan_complete": "Tarama tamamlandı.",
        "files_scanned": "Taranan dosya",
        "high_conf": "Yüksek güvenilirlikteki bulgular (project.md'ye yazıldı)",
        "med_conf": "Orta güvenilirlikteki bulgular",
        "low_conf": "Düşük güvenilirlikteki bulgular",
        "no_findings": "Bulgu yok.",
        "saved_to": "Kaydedildi",
        "evidence": "Kanıt",
        "auto_section_note": "/codebase-scan tarafından yönetilir. Marker'lar arasındaki manuel değişiklikler üzerine yazılır.",
        "last_scan": "Son tarama",
        "auto_arch": "Otomatik: Mimari",
        "auto_stack": "Otomatik: Stack & Araçlar",
        "auto_conv": "Otomatik: Konvansiyonlar",
        "auto_test": "Otomatik: Test",
        "auto_other": "Otomatik: Diğer",
    },
}


def L(lang: str, key: str) -> str:
    return LOC.get(lang, LOC["en"]).get(key, LOC["en"][key])


# ============================================================
# File enumeration
# ============================================================
def enumerate_files(root: Path) -> tuple[list[Path], list[Path]]:
    """Returns (source_files, manifest_files) — both relative to root."""
    sources: list[Path] = []
    manifests: list[Path] = []
    manifest_names = {
        "package.json", "pyproject.toml", "Cargo.toml", "go.mod", "Gemfile",
        "pom.xml", "build.gradle", "build.gradle.kts", "composer.json",
        "Package.swift", "mix.exs", "deno.json", "deno.jsonc",
    }
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS and not d.startswith(".") or d in {".github"}]
        for fn in filenames:
            if any(p in fn for p in SKIP_FILE_PATTERNS):
                continue
            p = Path(dirpath) / fn
            try:
                if p.stat().st_size > MAX_FILE_BYTES:
                    continue
            except OSError:
                continue
            if fn in manifest_names or fn.endswith(".csproj"):
                manifests.append(p)
            ext = p.suffix.lower()
            if ext in SOURCE_EXTS:
                sources.append(p)
    sources.sort()
    manifests.sort()
    return sources, manifests


def read_text(path: Path, max_lines: int | None = None) -> str:
    try:
        if max_lines is None:
            return path.read_text(encoding="utf-8", errors="replace")
        with path.open(encoding="utf-8", errors="replace") as f:
            lines = []
            for i, line in enumerate(f):
                if i >= max_lines:
                    break
                lines.append(line)
            return "".join(lines)
    except OSError:
        return ""


# ============================================================
# Pattern extractors P1-P12
# ============================================================
def p1_stack(root: Path) -> list[Finding]:
    """Run mcl-stack-detect.sh and return as findings."""
    try:
        script = Path(__file__).parent / "mcl-stack-detect.sh"
        out = subprocess.run(
            ["bash", "-c", f'source "{script}" && mcl_stack_detect "{root}"'],
            capture_output=True, text=True, timeout=15,
        )
        tags = [t for t in out.stdout.split() if t]
        if not tags:
            return []
        return [Finding(
            pattern_id="P1-stack",
            confidence="high",
            summary=f"Detected stack tags: {', '.join(tags)}",
            evidence=["(mcl-stack-detect.sh)"],
        )]
    except Exception:
        return []


def p2_architecture(root: Path) -> list[Finding]:
    findings = []
    top_dirs = {p.name for p in root.iterdir() if p.is_dir() and p.name not in EXCLUDE_DIRS}
    # Monorepo
    if (root / "pnpm-workspace.yaml").exists():
        findings.append(Finding("P2-arch", "high", "Monorepo: pnpm workspaces", ["pnpm-workspace.yaml"]))
    elif (root / "lerna.json").exists():
        findings.append(Finding("P2-arch", "high", "Monorepo: Lerna", ["lerna.json"]))
    elif (root / "nx.json").exists():
        findings.append(Finding("P2-arch", "high", "Monorepo: Nx", ["nx.json"]))
    elif (root / "turbo.json").exists():
        findings.append(Finding("P2-arch", "high", "Monorepo: Turborepo", ["turbo.json"]))
    elif top_dirs & {"packages", "apps"} and (root / "package.json").exists():
        findings.append(Finding("P2-arch", "medium", f"Possible monorepo (top dirs: {top_dirs & {'packages', 'apps'}})", []))

    # Clean architecture markers
    clean_arch_dirs = {"domain", "application", "infrastructure", "presentation"}
    if len(top_dirs & clean_arch_dirs) >= 2 or (root / "src").is_dir() and len({p.name for p in (root / "src").iterdir() if p.is_dir()} & clean_arch_dirs) >= 2:
        findings.append(Finding("P2-arch", "high", "Clean / hexagonal architecture (domain / application / infrastructure layers)", []))

    # MVC markers
    mvc_dirs = {"models", "views", "controllers"}
    if len(top_dirs & mvc_dirs) >= 2:
        findings.append(Finding("P2-arch", "medium", f"MVC-style layout (top dirs: {sorted(top_dirs & mvc_dirs)})", []))

    return findings


def p3_naming(sources: list[Path], root: Path) -> list[Finding]:
    if not sources:
        return []
    sample = sources[: min(500, len(sources))]
    camel = snake = pascal = kebab = 0
    for p in sample:
        name = p.stem
        if "-" in name:
            kebab += 1
        elif "_" in name:
            snake += 1
        elif name and name[0].isupper():
            pascal += 1
        else:
            camel += 1
    total = camel + snake + pascal + kebab
    if total == 0:
        return []
    pcts = {"camelCase": camel, "snake_case": snake, "PascalCase": pascal, "kebab-case": kebab}
    dominant, count = max(pcts.items(), key=lambda x: x[1])
    pct = count / total
    if pct >= 0.8:
        conf = "high"
    elif pct >= 0.6:
        conf = "medium"
    else:
        conf = "low"
    summary = f"File naming: {dominant} ({pct:.0%} of {total} source files)"
    return [Finding("P3-naming", conf, summary, [str(sample[0].relative_to(root))])]


def p4_error_handling(sources: list[Path], root: Path) -> list[Finding]:
    if not sources:
        return []
    counts = {"try-catch": 0, "Result-type": 0, "raise": 0, "panic!": 0, "throw new": 0}
    sample = sources[: min(200, len(sources))]
    for p in sample:
        text = read_text(p, max_lines=500)
        counts["try-catch"] += len(re.findall(r"\btry\s*[{(]", text))
        counts["Result-type"] += len(re.findall(r"\bResult<[^>]+>", text))
        counts["raise"] += len(re.findall(r"\braise\s+\w+", text))
        counts["panic!"] += len(re.findall(r"\bpanic!\(", text))
        counts["throw new"] += len(re.findall(r"\bthrow\s+new\s+", text))
    total = sum(counts.values())
    if total == 0:
        return []
    dominant, count = max(counts.items(), key=lambda x: x[1])
    pct = count / total
    conf = "high" if pct >= 0.7 else "medium" if pct >= 0.4 else "low"
    summary = f"Error handling: {dominant} dominant ({count}/{total} occurrences in {len(sample)} files)"
    return [Finding("P4-error", conf, summary, [], details=str(counts))]


def p5_tests(root: Path, manifests: list[Path]) -> list[Finding]:
    findings = []
    deps = collect_deps(manifests)
    test_frameworks = {
        "vitest": "Vitest", "jest": "Jest", "mocha": "Mocha",
        "pytest": "pytest", "unittest": "unittest",
        "rspec": "RSpec", "minitest": "Minitest",
        "junit": "JUnit", "testng": "TestNG",
        "xunit": "xUnit", "nunit": "NUnit",
        "go test": "go test (stdlib)",
    }
    for dep, name in test_frameworks.items():
        if dep in deps:
            findings.append(Finding("P5-test", "high", f"Test framework: {name}", [dep + " in manifest"]))
            break

    test_dirs = []
    for d in ("test", "tests", "spec", "__tests__"):
        if (root / d).is_dir():
            test_dirs.append(d)
    if test_dirs:
        findings.append(Finding("P5-test", "high", f"Test directories: {', '.join(test_dirs)}", test_dirs))
    return findings


def p6_api_style(manifests: list[Path]) -> list[Finding]:
    deps = collect_deps(manifests)
    findings = []
    api_libs = {
        "express": "REST (Express)",
        "fastify": "REST (Fastify)",
        "koa": "REST (Koa)",
        "fastapi": "REST (FastAPI)",
        "django": "REST/MVT (Django)",
        "flask": "REST (Flask)",
        "graphql": "GraphQL",
        "apollo-server": "GraphQL (Apollo)",
        "@trpc/server": "tRPC",
        "actix-web": "REST (Actix)",
        "axum": "REST (Axum)",
        "gin-gonic/gin": "REST (Gin)",
    }
    for dep, label in api_libs.items():
        if dep in deps:
            findings.append(Finding("P6-api", "high", f"API style: {label}", [dep]))
    return findings


def p7_state_mgmt(manifests: list[Path]) -> list[Finding]:
    deps = collect_deps(manifests)
    findings = []
    state_libs = {
        "redux": "Redux", "@reduxjs/toolkit": "Redux Toolkit",
        "zustand": "Zustand", "jotai": "Jotai",
        "recoil": "Recoil", "mobx": "MobX",
        "pinia": "Pinia (Vue)",
        "@tanstack/react-query": "React Query",
        "swr": "SWR",
    }
    for dep, label in state_libs.items():
        if dep in deps:
            findings.append(Finding("P7-state", "high", f"State management: {label}", [dep]))
    return findings


def p8_db(root: Path, manifests: list[Path]) -> list[Finding]:
    findings = []
    deps = collect_deps(manifests)
    if (root / "prisma" / "schema.prisma").exists():
        findings.append(Finding("P8-db", "high", "ORM: Prisma", ["prisma/schema.prisma"]))
    if any((root / d).is_dir() for d in ("db/migrate", "migrations", "alembic", "prisma/migrations")):
        findings.append(Finding("P8-db", "high", "Database migrations directory present", []))
    db_libs = {
        "sqlalchemy": "SQLAlchemy", "django": "Django ORM",
        "typeorm": "TypeORM", "drizzle-orm": "Drizzle ORM",
        "mongoose": "Mongoose", "sequelize": "Sequelize",
        "diesel": "Diesel (Rust)", "gorm": "GORM (Go)",
    }
    for dep, label in db_libs.items():
        if dep in deps:
            findings.append(Finding("P8-db", "high", f"ORM: {label}", [dep]))
    return findings


def p9_logging(sources: list[Path], manifests: list[Path]) -> list[Finding]:
    deps = collect_deps(manifests)
    findings = []
    structured = {
        "winston": "Winston", "pino": "Pino", "bunyan": "Bunyan",
        "loguru": "Loguru", "structlog": "structlog",
        "log4j": "Log4j", "serilog": "Serilog",
    }
    used = [name for dep, name in structured.items() if dep in deps]
    if used:
        findings.append(Finding("P9-log", "high", f"Structured logger: {', '.join(used)}", []))
    else:
        # Heuristic: scan a sample for console.log / print(...)
        sample = sources[: min(80, len(sources))]
        console_count = 0
        for p in sample:
            text = read_text(p, max_lines=300)
            console_count += len(re.findall(r"\bconsole\.(log|info|warn|error)\(", text))
            console_count += len(re.findall(r"^\s*print\(", text, flags=re.MULTILINE))
        if console_count > 5:
            findings.append(Finding("P9-log", "medium", f"Ad-hoc logging via console/print ({console_count} calls in {len(sample)} files); no structured logger detected", []))
    return findings


def p10_lint(root: Path, manifests: list[Path]) -> list[Finding]:
    findings = []
    # tsconfig strict
    tsconfig = root / "tsconfig.json"
    if tsconfig.exists():
        text = read_text(tsconfig)
        if re.search(r'"strict"\s*:\s*true', text):
            findings.append(Finding("P10-lint", "high", "TypeScript strict mode: ON", ["tsconfig.json"]))
        else:
            findings.append(Finding("P10-lint", "medium", "TypeScript strict mode: OFF or unspecified", ["tsconfig.json"]))
    # ESLint config
    for cfg in (".eslintrc", ".eslintrc.json", ".eslintrc.js", "eslint.config.js", "eslint.config.mjs"):
        if (root / cfg).exists():
            findings.append(Finding("P10-lint", "high", f"ESLint configured ({cfg})", [cfg]))
            break
    # Prettier
    for cfg in (".prettierrc", ".prettierrc.json", ".prettierrc.js", "prettier.config.js"):
        if (root / cfg).exists():
            findings.append(Finding("P10-lint", "high", f"Prettier configured ({cfg})", [cfg]))
            break
    # Ruff / mypy
    if (root / "ruff.toml").exists() or "ruff" in read_text(root / "pyproject.toml"):
        findings.append(Finding("P10-lint", "high", "Ruff configured", ["ruff.toml or pyproject.toml"]))
    if (root / "mypy.ini").exists() or (root / ".mypy.ini").exists():
        findings.append(Finding("P10-lint", "high", "mypy configured", []))
    return findings


def p11_build_deploy(root: Path) -> list[Finding]:
    findings = []
    if (root / "Dockerfile").exists():
        findings.append(Finding("P11-build", "high", "Dockerized (Dockerfile present)", ["Dockerfile"]))
    if (root / "docker-compose.yml").exists() or (root / "docker-compose.yaml").exists():
        findings.append(Finding("P11-build", "high", "docker-compose present", []))
    workflows_dir = root / ".github" / "workflows"
    if workflows_dir.is_dir():
        wf_files = list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml"))
        if wf_files:
            findings.append(Finding("P11-build", "high", f"GitHub Actions ({len(wf_files)} workflow file(s))", [str(p.relative_to(root)) for p in wf_files[:3]]))
    if (root / "vercel.json").exists():
        findings.append(Finding("P11-build", "high", "Vercel deployment", ["vercel.json"]))
    if (root / "netlify.toml").exists():
        findings.append(Finding("P11-build", "high", "Netlify deployment", ["netlify.toml"]))
    if (root / "fly.toml").exists():
        findings.append(Finding("P11-build", "high", "Fly.io deployment", ["fly.toml"]))
    return findings


def p12_readme(root: Path) -> list[Finding]:
    for name in ("README.md", "README.rst", "README.txt", "README"):
        p = root / name
        if p.exists():
            text = read_text(p, max_lines=40)
            # First non-heading paragraph
            paras = [s.strip() for s in re.split(r"\n\s*\n", text) if s.strip() and not s.strip().startswith("#")]
            if paras:
                first = paras[0].split("\n")[0]
                if len(first) > 200:
                    first = first[:197] + "..."
                return [Finding("P12-readme", "medium", f"README intent: {first}", [name])]
    return []


# ============================================================
# Manifest dependency collection
# ============================================================
def collect_deps(manifests: list[Path]) -> set[str]:
    deps: set[str] = set()
    for m in manifests:
        text = read_text(m)
        if m.name == "package.json":
            try:
                data = json.loads(text)
                for section in ("dependencies", "devDependencies", "peerDependencies"):
                    deps.update((data.get(section) or {}).keys())
            except json.JSONDecodeError:
                pass
        elif m.name == "pyproject.toml":
            for line in text.splitlines():
                m2 = re.match(r'^\s*"?([a-zA-Z0-9_\-\.]+)"?\s*=', line)
                if m2:
                    deps.add(m2.group(1).lower())
            deps.update(re.findall(r'"([a-zA-Z0-9_\-\.]+)\s*[<>=]', text))
        elif m.name in ("Cargo.toml", "go.mod", "Gemfile", "composer.json"):
            deps.update(re.findall(r'["\']([a-zA-Z0-9_\-/]+)["\']', text))
    return deps


# ============================================================
# project.md merge (M3 marker strategy)
# ============================================================
MARKER_START = "<!-- mcl-auto:start -->"
MARKER_END = "<!-- mcl-auto:end -->"


def render_auto_section(findings: list[Finding], lang: str) -> str:
    high = [f for f in findings if f.confidence == "high"]
    if not high:
        body = f"<!-- {L(lang, 'auto_section_note')} -->\n<!-- {L(lang, 'last_scan')}: {datetime.now(timezone.utc).strftime('%Y-%m-%d')} -->\n\n_{L(lang, 'no_findings')}_\n"
        return f"{MARKER_START}\n{body}\n{MARKER_END}"

    by_pattern: dict[str, list[Finding]] = {}
    for f in high:
        by_pattern.setdefault(f.pattern_id, []).append(f)

    section_map = {
        "P1-stack": "auto_stack", "P10-lint": "auto_stack", "P11-build": "auto_stack",
        "P2-arch": "auto_arch",
        "P3-naming": "auto_conv", "P4-error": "auto_conv", "P9-log": "auto_conv",
        "P5-test": "auto_test",
        "P6-api": "auto_other", "P7-state": "auto_other", "P8-db": "auto_other", "P12-readme": "auto_other",
    }
    grouped: dict[str, list[Finding]] = {}
    for pid, items in by_pattern.items():
        section = section_map.get(pid, "auto_other")
        grouped.setdefault(section, []).extend(items)

    parts = [
        MARKER_START,
        f"<!-- {L(lang, 'auto_section_note')} -->",
        f"<!-- {L(lang, 'last_scan')}: {datetime.now(timezone.utc).strftime('%Y-%m-%d')} -->",
        "",
    ]
    for section_key in ("auto_arch", "auto_stack", "auto_conv", "auto_test", "auto_other"):
        items = grouped.get(section_key)
        if not items:
            continue
        parts.append(f"## {L(lang, section_key)}")
        for f in items:
            parts.append(f"- {f.summary}")
        parts.append("")
    parts.append(MARKER_END)
    return "\n".join(parts)


def merge_project_md(state_dir: Path, auto_section: str, project_dir: Path) -> Path:
    project_md = state_dir / "project.md"
    if not project_md.exists():
        # Create fresh template
        title = project_dir.name
        new = f"# {title}\n\n{auto_section}\n\n## Mimari\n\n## Teknik Borç\n\n## Bilinen Sorunlar\n"
        project_md.write_text(new, encoding="utf-8")
        return project_md

    existing = project_md.read_text(encoding="utf-8")
    pattern = re.compile(
        re.escape(MARKER_START) + r".*?" + re.escape(MARKER_END),
        flags=re.DOTALL,
    )
    if pattern.search(existing):
        merged = pattern.sub(auto_section, existing)
    else:
        # Insert auto section after the metadata block (between title and first ## heading).
        lines = existing.split("\n")
        insert_at = 0
        for i, line in enumerate(lines):
            if line.startswith("## "):
                insert_at = i
                break
            insert_at = i + 1
        lines = lines[:insert_at] + [auto_section, ""] + lines[insert_at:]
        merged = "\n".join(lines)
    project_md.write_text(merged, encoding="utf-8")
    return project_md


def write_full_report(state_dir: Path, findings: list[Finding], lang: str, file_count: int) -> Path:
    report = state_dir / "project-scan-report.md"
    parts = [
        f"# {L(lang, 'title')}",
        "",
        f"**{L(lang, 'last_scan')}:** {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        f"**{L(lang, 'files_scanned')}:** {file_count}",
        "",
    ]
    for conf_key in ("high", "medium", "low"):
        items = [f for f in findings if f.confidence == conf_key]
        if not items:
            continue
        header = {"high": "high_conf", "medium": "med_conf", "low": "low_conf"}[conf_key]
        parts.append(f"## {L(lang, header)}")
        parts.append("")
        for f in items:
            parts.append(f"- **[{f.pattern_id}]** {f.summary}")
            if f.evidence:
                parts.append(f"  - {L(lang, 'evidence')}: {', '.join(f.evidence[:5])}")
            if f.details:
                parts.append(f"  - {f.details}")
        parts.append("")
    report.write_text("\n".join(parts), encoding="utf-8")
    return report


# ============================================================
# Main
# ============================================================
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--state-dir", required=True, type=Path)
    ap.add_argument("--project-dir", required=True, type=Path)
    ap.add_argument("--lang", default="en")
    args = ap.parse_args()

    state_dir: Path = args.state_dir
    project_dir: Path = args.project_dir.resolve()
    lang: str = args.lang if args.lang in LOC else "en"
    state_dir.mkdir(parents=True, exist_ok=True)

    print(f"[MCL] Scanning {project_dir} ...", file=sys.stderr)
    sources, manifests = enumerate_files(project_dir)
    total = len(sources) + len(manifests)
    print(f"[MCL] Enumerated {total} files ({len(sources)} source, {len(manifests)} manifest)", file=sys.stderr)

    findings: list[Finding] = []
    extractors = [
        ("P1", lambda: p1_stack(project_dir)),
        ("P2", lambda: p2_architecture(project_dir)),
        ("P3", lambda: p3_naming(sources, project_dir)),
        ("P4", lambda: p4_error_handling(sources, project_dir)),
        ("P5", lambda: p5_tests(project_dir, manifests)),
        ("P6", lambda: p6_api_style(manifests)),
        ("P7", lambda: p7_state_mgmt(manifests)),
        ("P8", lambda: p8_db(project_dir, manifests)),
        ("P9", lambda: p9_logging(sources, manifests)),
        ("P10", lambda: p10_lint(project_dir, manifests)),
        ("P11", lambda: p11_build_deploy(project_dir)),
        ("P12", lambda: p12_readme(project_dir)),
    ]
    for i, (pid, fn) in enumerate(extractors, 1):
        print(f"[MCL] Scanning... {pid} ({i}/{len(extractors)})", file=sys.stderr)
        try:
            findings.extend(fn())
        except Exception as e:
            print(f"[MCL] Pattern {pid} failed: {e}", file=sys.stderr)

    auto_section = render_auto_section(findings, lang)
    project_md_path = merge_project_md(state_dir, auto_section, project_dir)
    report_path = write_full_report(state_dir, findings, lang, total)

    # Stdout summary (already localized)
    print(f"# {L(lang, 'title')}\n")
    print(f"_{L(lang, 'scan_complete')} {L(lang, 'files_scanned')}: {total}_\n")
    high = [f for f in findings if f.confidence == "high"]
    med = [f for f in findings if f.confidence == "medium"]
    low = [f for f in findings if f.confidence == "low"]
    if high:
        print(f"## {L(lang, 'high_conf')} ({len(high)})\n")
        for f in high:
            print(f"- {f.summary}")
        print()
    if med:
        print(f"## {L(lang, 'med_conf')} ({len(med)})\n")
        for f in med:
            print(f"- {f.summary}")
        print()
    if low:
        print(f"## {L(lang, 'low_conf')} ({len(low)})\n")
        for f in low:
            print(f"- {f.summary}")
        print()
    print(f"\n**{L(lang, 'saved_to')}:**")
    print(f"- `{project_md_path}`")
    print(f"- `{report_path}`")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as _e:
        import traceback as _tb
        print(json.dumps({"error": str(_e)[:500], "traceback": _tb.format_exc()[-1500:]}))
        sys.exit(3)
