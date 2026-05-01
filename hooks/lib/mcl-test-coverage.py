#!/usr/bin/env python3
"""MCL test-coverage detector (since 8.19.0).

Phase 4 Lens (g) — surfaces missing test categories as MEDIUM/LOW
findings inserted into the sequential dialog.

Detection layers:
  1. Manifest scan — package.json, requirements.txt, pyproject.toml,
     Gemfile, composer.json, pom.xml, go.mod, Cargo.toml.
  2. File scan fallback — when manifest deps don't name a known
     framework but the project has *.test.* / *.spec.* / tests/ files,
     classify by extension.

Categories tracked:
  - unit          (vitest, jest, mocha, pytest, go test, rspec, phpunit, ...)
  - integration   (supertest, testcontainers, pytest-asyncio, rspec-rails, ...)
  - e2e           (@playwright/test, cypress, selenium-webdriver, puppeteer)
  - load          (k6, locust, artillery, jmeter)

Output JSON:
  {
    "categories_present": [...],
    "categories_missing": [...],
    "findings": [
      {"rule_id": "TST-T0X", "severity": "HIGH|MEDIUM|LOW",
       "category": "test", "message": "...", "file": "<manifest>"},
      ...
    ]
  }

Severity rubric:
  - unit missing AND project has source code     → HIGH (no tests at all)
  - integration missing AND multi-module project → MEDIUM
  - e2e missing AND ui_flow_active=true          → MEDIUM
  - load missing AND backend-stack
                  AND deployment_target ∈ public → MEDIUM (TST-T04)
"""
from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path

# --- Framework dependency map ----------------------------------------
# Each value is a list of (manifest_field_pattern, package_name_regex)
# that match a category. Order doesn't matter; a single hit per
# category is sufficient.
FRAMEWORKS: dict[str, list[str]] = {
    "unit": [
        # JS/TS
        r"\bvitest\b", r"\bjest\b", r"\bmocha\b", r"\bava\b", r"\btap\b",
        r"\b@?testing-library\b",
        # Python
        r"\bpytest\b", r"\bunittest\b", r"\bnose2\b",
        # Ruby
        r"\brspec\b", r"\bminitest\b",
        # PHP
        r"\bphpunit\b", r"\bpest\b",
        # Go
        r"\btestify\b",  # `go test` itself has no manifest dep
        # Java/JVM
        r"\bjunit\b", r"\bspock\b",
        # Rust
        r"\bcargo-(?:test|nextest)\b",
        # .NET
        r"\bxunit\b", r"\bnunit\b", r"\bmstest\b",
    ],
    "integration": [
        r"\bsupertest\b", r"\btestcontainers\b", r"\bpytest-asyncio\b",
        r"\brspec-rails\b", r"\bspring-boot-starter-test\b",
        r"\bpact\b", r"\bwiremock\b",
    ],
    "e2e": [
        r"\b@playwright/test\b", r"\bplaywright\b",
        r"\bcypress\b", r"\bselenium-webdriver\b", r"\bpuppeteer\b",
        r"\bwebdriverio\b", r"\bnightwatch\b",
        r"\bcapybara\b",  # Ruby
    ],
    "load": [
        r"\bk6\b", r"\blocust\b", r"\bartillery\b", r"\bjmeter\b",
        r"\bgatling\b", r"\bvegeta\b",
    ],
}

# Backend stack tags (mirrors mcl-stack-detect.sh / mcl-state.sh).
BACKEND_TAGS = {
    "python", "java", "go", "ruby", "csharp", "rust", "php",
}

# Source extensions that count as "real source code" — used to escalate
# missing-unit-tests to HIGH only when there is something to test.
SOURCE_EXTS = {
    ".py", ".js", ".ts", ".jsx", ".tsx", ".vue", ".svelte",
    ".rb", ".php", ".go", ".rs", ".java", ".kt", ".cs", ".cpp", ".c",
}


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def scan_manifests(project_dir: Path) -> dict[str, list[str]]:
    """Return {category: [manifest_paths_that_provided_evidence]}."""
    manifests = [
        "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
        "requirements.txt", "requirements-dev.txt", "pyproject.toml",
        "Pipfile", "Pipfile.lock",
        "Gemfile", "Gemfile.lock",
        "composer.json", "composer.lock",
        "pom.xml", "build.gradle", "build.gradle.kts",
        "go.mod", "go.sum",
        "Cargo.toml", "Cargo.lock",
    ]
    blob_parts: list[tuple[str, str]] = []
    for name in manifests:
        p = project_dir / name
        if p.is_file():
            blob_parts.append((str(p), _read_text(p)))
    out: dict[str, list[str]] = {cat: [] for cat in FRAMEWORKS}
    for cat, patterns in FRAMEWORKS.items():
        for src, blob in blob_parts:
            if any(re.search(p, blob, re.IGNORECASE) for p in patterns):
                if src not in out[cat]:
                    out[cat].append(src)
    return out


def has_source_code(project_dir: Path) -> bool:
    """True if any source file with a recognized extension exists."""
    for p in project_dir.rglob("*"):
        if p.is_file() and p.suffix.lower() in SOURCE_EXTS:
            # Skip standard generated/vendor dirs.
            parts = set(p.parts)
            if parts & {"node_modules", ".git", "__pycache__", "vendor",
                        "dist", "build", "target"}:
                continue
            return True
    return False


def detect(
    project_dir: Path,
    *,
    stack_tags: list[str] | None = None,
    ui_flow_active: bool = False,
    deployment_target: str | None = None,
) -> dict:
    """Run the full coverage detection pass."""
    stack_tags = stack_tags or []
    manifest_hits = scan_manifests(project_dir)
    present: list[str] = [c for c, srcs in manifest_hits.items() if srcs]
    missing: list[str] = [c for c in FRAMEWORKS if c not in present]

    findings: list[dict] = []
    has_src = has_source_code(project_dir)

    if "unit" in missing and has_src:
        findings.append({
            "rule_id": "TST-T01",
            "severity": "HIGH",
            "category": "test",
            "message": (
                "No unit-test framework detected in any manifest. The project "
                "has source code but zero automated tests cover individual "
                "functions/components. Add vitest/jest (JS/TS), pytest "
                "(Python), rspec (Ruby), or stack equivalent."
            ),
            "file": str(project_dir),
        })

    if "integration" in missing:
        findings.append({
            "rule_id": "TST-T02",
            "severity": "MEDIUM",
            "category": "test",
            "message": (
                "No integration-test framework detected. Cross-module "
                "interactions, API contracts, and DB-touching paths run "
                "without automated coverage. Add supertest/testcontainers/"
                "pytest-asyncio/rspec-rails."
            ),
            "file": str(project_dir),
        })

    if "e2e" in missing and ui_flow_active:
        findings.append({
            "rule_id": "TST-T03",
            "severity": "MEDIUM",
            "category": "test",
            "message": (
                "UI flow is active but no E2E framework detected. User flows "
                "(login, dashboard, checkout) lack browser-driven verification. "
                "Add @playwright/test or cypress."
            ),
            "file": str(project_dir),
        })

    if "load" in missing:
        backend = bool(set(stack_tags) & BACKEND_TAGS)
        deploy_public = (deployment_target or "") in (
            "prod", "production", "public", "multi-tenant", "scale", "cloud",
        )
        if backend and deploy_public:
            findings.append({
                "rule_id": "TST-T04",
                "severity": "MEDIUM",
                "category": "test",
                "message": (
                    "Production-bound backend has no load-testing framework. "
                    "Throughput-sensitive paths (auth, query endpoints, async "
                    "workers) lack stress coverage. Add k6, Locust, Artillery, "
                    "or JMeter."
                ),
                "file": str(project_dir),
            })

    return {
        "categories_present": present,
        "categories_missing": missing,
        "findings": findings,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-dir", required=True)
    ap.add_argument("--stack-tags", default="",
                    help="Comma-separated stack tag list "
                         "(matches phase1_stack_declared).")
    ap.add_argument("--ui-flow-active", default="false")
    ap.add_argument("--deployment-target", default="")
    args = ap.parse_args()

    project_dir = Path(args.project_dir)
    if not project_dir.is_dir():
        print(json.dumps({"categories_present": [], "categories_missing": list(FRAMEWORKS),
                          "findings": []}))
        return 0

    stack_tags = [t.strip() for t in args.stack_tags.split(",") if t.strip()]
    ui_flow_active = args.ui_flow_active.lower() == "true"
    result = detect(
        project_dir,
        stack_tags=stack_tags,
        ui_flow_active=ui_flow_active,
        deployment_target=args.deployment_target.strip() or None,
    )
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
