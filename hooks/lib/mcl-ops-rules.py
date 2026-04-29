#!/usr/bin/env python3
"""MCL Ops Rules (8.13.0) — 4 categories, ~20 rules.

Categories: ops-deployment | ops-monitoring | ops-testing | ops-docs
8.7-8.9 ile çakışmazlık: 8.7.0 G09 console-only (security gizleme), 8.13.0
MON yapısal logger eksikliği (observability); 8.6.0 P12 README intent,
8.13.0 DOC structural sections; Phase 5 per-MUST/SHOULD test, 8.13.0 TST
aggregate threshold. category=ops-* field ayrım.
"""
from __future__ import annotations
import json
import re
from dataclasses import dataclass, asdict
from pathlib import Path


@dataclass
class Finding:
    severity: str
    source: str         # generic | delegate
    rule_id: str
    file: str
    line: int
    message: str
    category: str = ""  # ops-deployment | ops-monitoring | ops-testing | ops-docs
    autofix: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)


_RULES_DEP: list = []
_RULES_MON: list = []
_RULES_TST: list = []
_RULES_DOC: list = []


def _reg(bucket):
    def deco(fn):
        bucket.append(fn)
        return fn
    return deco


# ============================================================
# Trigger detection
# ============================================================

def has_deployment_intent(project_dir: Path) -> bool:
    if (project_dir / "Dockerfile").exists():
        return True
    if (project_dir / ".github" / "workflows").is_dir():
        return any((project_dir / ".github" / "workflows").glob("*.yml")) or \
               any((project_dir / ".github" / "workflows").glob("*.yaml"))
    if (project_dir / ".gitlab-ci.yml").exists():
        return True
    for f in ("Procfile", "fly.toml", "vercel.json", "netlify.toml", "app.yaml", "Jenkinsfile"):
        if (project_dir / f).exists():
            return True
    return False


def has_backend_stack(stack_tags: set[str]) -> bool:
    backend_only = {"python", "java", "csharp", "ruby", "php", "go", "rust"}
    fe_only = {"react-frontend", "vue-frontend", "svelte-frontend", "html-static"}
    has_be = bool(stack_tags & backend_only)
    # node backend = javascript without FE-only tag
    if "javascript" in stack_tags and not (stack_tags & fe_only):
        has_be = True
    return has_be


def has_test_framework(project_dir: Path, stack_tags: set[str]) -> tuple[bool, str | None]:
    pkg = project_dir / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text(encoding="utf-8"))
            deps = {**(data.get("dependencies") or {}), **(data.get("devDependencies") or {})}
            for tool in ("vitest", "jest", "mocha"):
                if tool in deps:
                    return True, tool
        except Exception:
            pass
    if (project_dir / "pytest.ini").exists() or (project_dir / "pyproject.toml").exists():
        if "pytest" in (project_dir / "pyproject.toml").read_text(encoding="utf-8", errors="ignore") if (project_dir / "pyproject.toml").exists() else False:
            return True, "pytest"
        if (project_dir / "pytest.ini").exists():
            return True, "pytest"
    if (project_dir / "Gemfile").exists():
        gf = (project_dir / "Gemfile").read_text(encoding="utf-8", errors="ignore")
        if "rspec" in gf:
            return True, "rspec"
    if (project_dir / "go.mod").exists() and "go" in stack_tags:
        return True, "go-test"
    if (project_dir / "Cargo.toml").exists():
        return True, "cargo"
    return False, None


# ============================================================
# Deployment rules (8 rules)
# ============================================================

@_reg(_RULES_DEP)
def r_dep_g01_no_ci(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    if not has_deployment_intent(project_dir):
        return []
    has_ci = ((project_dir / ".github" / "workflows").is_dir()
              or (project_dir / ".gitlab-ci.yml").exists()
              or (project_dir / "Jenkinsfile").exists()
              or (project_dir / ".circleci").is_dir())
    if has_ci:
        return []
    sev = "HIGH" if (project_dir / "Dockerfile").exists() and (project_dir / ".env.example").exists() else "MEDIUM"
    return [Finding(severity=sev, source="generic", rule_id="DEP-G01-no-ci-config",
                    file=str(project_dir), line=0, category="ops-deployment",
                    message="No CI/CD configuration found despite deployment intent. Add GitHub Actions / GitLab CI / Jenkins / CircleCI workflow.")]


@_reg(_RULES_DEP)
def r_dep_g02_workflow_yaml_error(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    wf_dir = project_dir / ".github" / "workflows"
    if not wf_dir.is_dir():
        return []
    out = []
    for wf in list(wf_dir.glob("*.yml")) + list(wf_dir.glob("*.yaml")):
        try:
            txt = wf.read_text(encoding="utf-8", errors="replace")
            # Lightweight: just check structural markers; full YAML parse via python yaml optional.
            if not re.search(r"^\s*(on|jobs)\s*:", txt, re.MULTILINE):
                out.append(Finding(severity="HIGH", source="generic", rule_id="DEP-G02-workflow-yaml-error",
                                   file=str(wf), line=1, category="ops-deployment",
                                   message=f"Workflow {wf.name!r} missing 'on:' or 'jobs:' top-level keys."))
        except OSError:
            continue
    return out


@_reg(_RULES_DEP)
def r_dep_g03_dockerfile_no_healthcheck(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    df = project_dir / "Dockerfile"
    if not df.exists():
        return []
    txt = df.read_text(encoding="utf-8", errors="replace")
    if re.search(r"^\s*HEALTHCHECK\b", txt, re.MULTILINE | re.IGNORECASE):
        return []
    return [Finding(severity="MEDIUM", source="generic", rule_id="DEP-G03-dockerfile-no-healthcheck",
                    file=str(df), line=1, category="ops-deployment",
                    message="Dockerfile has no HEALTHCHECK instruction. Orchestrators cannot detect unhealthy containers.")]


@_reg(_RULES_DEP)
def r_dep_g04_dockerfile_root(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    df = project_dir / "Dockerfile"
    if not df.exists():
        return []
    txt = df.read_text(encoding="utf-8", errors="replace")
    if re.search(r"^\s*USER\s+\S+", txt, re.MULTILINE):
        return []
    return [Finding(severity="HIGH", source="generic", rule_id="DEP-G04-dockerfile-root-user",
                    file=str(df), line=1, category="ops-deployment",
                    message="Dockerfile runs as root (no USER directive). Add `USER nonroot` for least-privilege.")]


@_reg(_RULES_DEP)
def r_dep_g05_dockerfile_latest(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    df = project_dir / "Dockerfile"
    if not df.exists():
        return []
    out = []
    for i, line in enumerate(df.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        m = re.match(r"^\s*FROM\s+[\w./-]+:latest\b", line, re.IGNORECASE)
        if m:
            out.append(Finding(severity="MEDIUM", source="generic", rule_id="DEP-G05-dockerfile-latest-tag",
                               file=str(df), line=i, category="ops-deployment",
                               message="FROM image:latest — not reproducible. Pin to a specific version tag."))
    return out


@_reg(_RULES_DEP)
def r_dep_g06_no_env_example(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    if (project_dir / ".env.example").exists() or (project_dir / ".env.sample").exists():
        return []
    # Trigger: code references env vars OR Dockerfile has ENV instructions
    refs = files.get("env_var_refs", 0)
    has_dockerfile = (project_dir / "Dockerfile").exists()
    if refs < 3 and not has_dockerfile:
        return []
    return [Finding(severity="MEDIUM", source="generic", rule_id="DEP-G06-env-example-missing",
                    file=str(project_dir), line=0, category="ops-deployment",
                    message=f"Code references env vars ({refs} occurrences) / Dockerfile present, but no .env.example. Add template for new contributors.")]


@_reg(_RULES_DEP)
def r_dep_g07_env_drift(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    ex = project_dir / ".env.example"
    if not ex.exists():
        return []
    example_keys = set()
    for line in ex.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^\s*([A-Z][A-Z0-9_]+)\s*=", line)
        if m:
            example_keys.add(m.group(1))
    code_keys = files.get("env_var_keys", set())
    missing = code_keys - example_keys
    if not missing:
        return []
    sample = sorted(missing)[:5]
    return [Finding(severity="LOW", source="generic", rule_id="DEP-G07-env-example-stale",
                    file=str(ex), line=0, category="ops-deployment",
                    message=f"Code references env keys not in .env.example: {', '.join(sample)}{' ...' if len(missing) > 5 else ''}")]


@_reg(_RULES_DEP)
def r_dep_g08_secrets_no_doc(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    ex = project_dir / ".env.example"
    if not ex.exists():
        return []
    text = ex.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    keys_total = sum(1 for ln in lines if re.match(r"^\s*[A-Z][A-Z0-9_]+\s*=", ln))
    keys_documented = sum(1 for i, ln in enumerate(lines)
                          if re.match(r"^\s*[A-Z][A-Z0-9_]+\s*=", ln)
                          and (i > 0 and lines[i-1].lstrip().startswith("#")))
    if keys_total == 0 or keys_documented / keys_total >= 0.5:
        return []
    return [Finding(severity="LOW", source="generic", rule_id="DEP-G08-secrets-no-doc",
                    file=str(ex), line=0, category="ops-deployment",
                    message=f".env.example has {keys_total} keys but only {keys_documented} documented (above-line comment). Add comments explaining each var.")]


# ============================================================
# Monitoring rules (4)
# ============================================================

LOGGER_DEPS = {"winston", "pino", "bunyan", "loguru", "structlog", "log4j", "serilog",
               "log4net", "logrus", "zap", "monolog"}


@_reg(_RULES_MON)
def r_mon_g01_no_logger(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    if not has_backend_stack(stack_tags):
        return []
    deps = files.get("manifest_deps", set())
    if deps & LOGGER_DEPS:
        return []
    adhoc = files.get("adhoc_logging_count", 0)
    loc = files.get("loc_total", 0)
    if adhoc > 10 and loc > 500:
        return [Finding(severity="MEDIUM", source="generic", rule_id="MON-G01-no-structured-logger",
                        file=str(project_dir), line=0, category="ops-monitoring",
                        message=f"Backend project with {adhoc} ad-hoc log/print calls in {loc} LOC, no structured logger dependency. Add winston/pino/loguru/structlog.")]
    return []


@_reg(_RULES_MON)
def r_mon_g02_no_metrics(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    if not has_backend_stack(stack_tags):
        return []
    deps = files.get("manifest_deps", set())
    metrics_libs = {"prom-client", "prometheus_client", "micrometer-core", "promhttp"}
    if deps & metrics_libs:
        return []
    return [Finding(severity="LOW", source="generic", rule_id="MON-G02-no-metrics-endpoint",
                    file=str(project_dir), line=0, category="ops-monitoring",
                    message="Backend without metrics library (prom-client / prometheus_client / micrometer). Consider /metrics endpoint for SRE.")]


@_reg(_RULES_MON)
def r_mon_g03_no_error_tracking(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    if not has_backend_stack(stack_tags):
        return []
    if not has_deployment_intent(project_dir):
        return []
    deps = files.get("manifest_deps", set())
    err_libs = {"@sentry/node", "@sentry/python", "sentry-sdk", "bugsnag", "rollbar",
                "honeybadger", "raven"}
    if any(d in deps for d in err_libs):
        return []
    return [Finding(severity="LOW", source="generic", rule_id="MON-G03-no-error-tracking",
                    file=str(project_dir), line=0, category="ops-monitoring",
                    message="Production-bound backend without error tracking (Sentry/Bugsnag/Rollbar/Honeybadger). Errors lost in stdout.")]


@_reg(_RULES_MON)
def r_mon_g04_log_no_level(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    if not has_backend_stack(stack_tags):
        return []
    no_level = files.get("logger_no_level_count", 0)
    if no_level < 5:
        return []
    return [Finding(severity="LOW", source="generic", rule_id="MON-G04-log-no-level",
                    file=str(project_dir), line=0, category="ops-monitoring",
                    message=f"{no_level} logger calls without explicit level (logger(...) instead of logger.info/.warn/.error). Use level methods.")]


# ============================================================
# Testing rules (3 + delegate)
# ============================================================

@_reg(_RULES_TST)
def r_tst_t01_coverage_threshold(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    cov = files.get("coverage_total")
    if cov is None:
        return []
    high_cut = files.get("coverage_threshold_high", 50)
    med_cut = files.get("coverage_threshold_medium", 70)
    if cov < high_cut:
        return [Finding(severity="HIGH", source="delegate", rule_id="TST-T01-coverage-below-threshold",
                        file=str(project_dir), line=0, category="ops-testing",
                        message=f"Test coverage {cov:.1f}% below HIGH threshold ({high_cut}%). Add tests before shipping.")]
    elif cov < med_cut:
        return [Finding(severity="MEDIUM", source="delegate", rule_id="TST-T01-coverage-below-threshold",
                        file=str(project_dir), line=0, category="ops-testing",
                        message=f"Test coverage {cov:.1f}% below MEDIUM threshold ({med_cut}%). Improve coverage on changed files.")]
    return []


@_reg(_RULES_TST)
def r_tst_t02_no_test_framework(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    has, _ = has_test_framework(project_dir, stack_tags)
    if has:
        return []
    if not (has_backend_stack(stack_tags) or stack_tags & {"react-frontend", "vue-frontend", "svelte-frontend"}):
        return []
    return [Finding(severity="LOW", source="generic", rule_id="TST-T02-no-test-framework",
                    file=str(project_dir), line=0, category="ops-testing",
                    message="No test framework manifest detected. Add vitest/jest/pytest/rspec for the project's stack.")]


@_reg(_RULES_TST)
def r_tst_t03_changed_no_test(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    untested = files.get("changed_files_no_test", [])
    if not untested:
        return []
    return [Finding(severity="MEDIUM", source="generic", rule_id="TST-T03-changed-file-no-test",
                    file=untested[0], line=0, category="ops-testing",
                    message=f"{len(untested)} changed file(s) without corresponding test: {', '.join(untested[:3])}{' ...' if len(untested) > 3 else ''}")]


# ============================================================
# Documentation rules (5)
# ============================================================

def _readme_path(project_dir: Path) -> Path | None:
    for n in ("README.md", "README.rst", "README.txt", "README"):
        if (project_dir / n).exists():
            return project_dir / n
    return None


@_reg(_RULES_DOC)
def r_doc_g01_no_readme(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    if _readme_path(project_dir):
        return []
    sev = "HIGH" if has_deployment_intent(project_dir) else "MEDIUM"
    return [Finding(severity=sev, source="generic", rule_id="DOC-G01-no-readme",
                    file=str(project_dir), line=0, category="ops-docs",
                    message="No README found. Add README.md with what / why / how to install / how to run.")]


@_reg(_RULES_DOC)
def r_doc_g02_readme_no_install(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    rp = _readme_path(project_dir)
    if not rp:
        return []
    txt = rp.read_text(encoding="utf-8", errors="replace")
    if len(txt) < 200:
        return [Finding(severity="MEDIUM", source="generic", rule_id="DOC-G02-readme-too-short",
                        file=str(rp), line=0, category="ops-docs",
                        message=f"README is {len(txt)} chars — too thin to be useful.")]
    if not re.search(r"^#{1,3}\s+(Install|Setup|Quick\s*Start|Getting\s*Started|Kurulum)\b", txt, re.MULTILINE | re.IGNORECASE):
        return [Finding(severity="MEDIUM", source="generic", rule_id="DOC-G02-readme-no-install",
                        file=str(rp), line=0, category="ops-docs",
                        message="README has no Install / Setup / Quick Start section. Document install steps.")]
    return []


@_reg(_RULES_DOC)
def r_doc_g03_readme_no_usage(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    rp = _readme_path(project_dir)
    if not rp:
        return []
    txt = rp.read_text(encoding="utf-8", errors="replace")
    if not re.search(r"^#{1,3}\s+(Usage|Example|Getting\s*Started|How\s+to|Kullanım)\b", txt, re.MULTILINE | re.IGNORECASE):
        return [Finding(severity="MEDIUM", source="generic", rule_id="DOC-G03-readme-no-usage",
                        file=str(rp), line=0, category="ops-docs",
                        message="README has no Usage / Example / How-to section. Show at least one usage example.")]
    return []


@_reg(_RULES_DOC)
def r_doc_g04_api_no_docs(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    has_api = files.get("api_routes_count", 0) > 0
    if not has_api:
        return []
    has_doc = ((project_dir / "openapi.yaml").exists() or (project_dir / "openapi.json").exists()
               or (project_dir / "swagger.yaml").exists() or (project_dir / "swagger.json").exists()
               or (project_dir / "docs" / "api").is_dir() or (project_dir / "api-docs").is_dir())
    if has_doc:
        return []
    sev = "MEDIUM" if has_deployment_intent(project_dir) else "LOW"
    return [Finding(severity=sev, source="generic", rule_id="DOC-G04-api-no-docs",
                    file=str(project_dir), line=0, category="ops-docs",
                    message=f"{files['api_routes_count']} API routes detected but no OpenAPI / Swagger / api-docs. Generate or hand-write API docs.")]


@_reg(_RULES_DOC)
def r_doc_g05_docstring_low(project_dir: Path, files: dict, stack_tags: set[str]) -> list[Finding]:
    fn_total = files.get("function_count", 0)
    fn_doc = files.get("function_doc_count", 0)
    if fn_total < 10:
        return []
    pct = fn_doc / fn_total * 100
    if pct >= 30:
        return []
    return [Finding(severity="LOW", source="generic", rule_id="DOC-G05-function-docstring-low",
                    file=str(project_dir), line=0, category="ops-docs",
                    message=f"Function-level docstring coverage: {pct:.1f}% ({fn_doc}/{fn_total}). Add docstrings on public functions.")]


# ============================================================
# Public API
# ============================================================

def scan_project(project_dir: Path, stack_tags: set[str], aggregate: dict) -> list[Finding]:
    """Run all 4 rule packs against pre-aggregated file metrics."""
    findings: list[Finding] = []
    for fn in _RULES_DEP + _RULES_MON + _RULES_TST + _RULES_DOC:
        try:
            findings.extend(fn(project_dir, aggregate, stack_tags))
        except Exception:
            pass
    return findings


def all_rule_ids() -> list[str]:
    out = []
    for bucket in (_RULES_DEP, _RULES_MON, _RULES_TST, _RULES_DOC):
        out.extend(getattr(fn, "__name__", "?") for fn in bucket)
    return sorted(out)


def rules_version_seed() -> str:
    src = Path(__file__).read_text(encoding="utf-8")
    return "|".join(all_rule_ids()) + "\n---\n" + src
