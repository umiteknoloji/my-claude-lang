#!/usr/bin/env python3
"""MCL Phase 4 architectural drift + intent violation scanner (9.3.0).

Compares Phase 4 code writes against:
  (a) state.scope_paths — file paths declared in spec's Technical Approach.
      Writes outside this set → drift advisory.
  (b) state.phase1_intent + state.phase1_constraints — Phase 1 declared
      direction. Writes that import libraries / create files contradicting
      this → intent-violation advisory.

Both findings are ADVISORY in 9.3.0 — the hook emits audit entries but
does not block. They feed Phase 6 audit-trail completeness and the
/mcl-finish report.

Usage:
  python3 mcl-drift-scan.py --state-dir <dir> --project-dir <dir>
  python3 mcl-drift-scan.py --state-dir <dir> --project-dir <dir> --transcript <jsonl>

Output: JSON with `drift_findings: [...]`, `intent_violations: [...]`.
Each finding: {severity, rule_id, file, message, source}.
"""

from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path


# Heuristic patterns for intent-violation detection. Each entry:
#   (intent_keyword, anti_pattern, message)
# An anti_pattern matches a file path or content that contradicts the intent.
INTENT_VIOLATIONS = [
    # "no auth" / "frontend only" / "static" → no auth libraries
    {
        "intent_keywords": [r"no\s+auth", r"auth\s+yok", r"static", r"frontend\s+only",
                            r"sadece\s+frontend", r"no\s+backend", r"backend\s+yok"],
        "anti_path_patterns": [
            r"(?:^|/)(?:src/api|src/server|src/services|src/lib/db|prisma|drizzle|migrations)(?:/|$)",
            r"(?:^|/)(?:server|index)\.(?:server|api)\.",
            r"(?:^|/)pages/api(?:/|$)",
            r"(?:^|/)app/api(?:/|$)",
        ],
        "anti_import_patterns": [
            r"\bnext-auth\b", r"\bpassport\b", r"\bauth0\b", r"@clerk/",
            r"\bbcrypt\b", r"\bjsonwebtoken\b", r"@supabase/auth",
            r"\bprisma\b", r"@prisma/", r"\bdrizzle-orm\b", r"\bsequelize\b",
            r"\bmongoose\b", r"\bbetter-sqlite3\b", r"\bpg\b\s*\)",
        ],
        "category": "no-auth-or-backend",
    },
    # "no DB" / "in-memory" → no DB libraries
    {
        "intent_keywords": [r"no\s+db", r"db\s+yok", r"in.?memory", r"memory.?only",
                            r"file.?based", r"json\s+only"],
        "anti_path_patterns": [
            r"(?:^|/)(?:prisma|drizzle|migrations|supabase/migrations)(?:/|$)",
            r"\.sql$", r"schema\.prisma$",
        ],
        "anti_import_patterns": [
            r"\bprisma\b", r"@prisma/", r"\bdrizzle-orm\b", r"\bsequelize\b",
            r"\bmongoose\b", r"\bpg\b", r"\bbetter-sqlite3\b",
        ],
        "category": "no-db",
    },
    # "no external API" / "offline" → no fetch/axios to external URLs
    {
        "intent_keywords": [r"offline", r"no\s+external", r"external\s+yok",
                            r"local\s+only", r"no\s+network"],
        "anti_import_patterns": [
            r"\baxios\b", r"\bnode-fetch\b", r"\bgot\b\s*[\"']",
        ],
        "category": "offline-only",
    },
]


def _read_state(state_dir: Path) -> dict:
    p = state_dir / "state.json"
    if not p.is_file():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _read_transcript_writes(transcript_path: Path) -> list[dict]:
    """Return list of {file_path, content} for Write/Edit/MultiEdit tool calls."""
    if not transcript_path.is_file():
        return []
    out: list[dict] = []
    try:
        with transcript_path.open("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                msg = obj.get("message")
                if not isinstance(msg, dict):
                    continue
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for item in content:
                    if not isinstance(item, dict):
                        continue
                    if item.get("type") != "tool_use":
                        continue
                    name = item.get("name", "")
                    if name not in ("Write", "Edit", "MultiEdit"):
                        continue
                    inp = item.get("input") or {}
                    fp = inp.get("file_path") or inp.get("notebook_path") or ""
                    body = inp.get("content") or inp.get("new_string") or ""
                    if not fp:
                        continue
                    out.append({"file_path": fp, "content": body})
    except Exception:
        pass
    return out


def _normalize_scope(scope_paths: list[str], project_dir: Path) -> set[str]:
    """Return a set of normalized scope path prefixes (relative)."""
    out: set[str] = set()
    proj = str(project_dir.resolve()).rstrip("/")
    for p in scope_paths or []:
        if not isinstance(p, str) or not p:
            continue
        rel = p
        if rel.startswith(proj + "/"):
            rel = rel[len(proj) + 1:]
        if rel.startswith("./"):
            rel = rel[2:]
        # Reduce wildcards to base prefix.
        rel = rel.split("**", 1)[0].rstrip("/*")
        if rel:
            out.add(rel)
    return out


def detect_drift(scope_set: set[str], writes: list[dict],
                 project_dir: Path) -> list[dict]:
    """Files written outside declared scope → drift findings."""
    if not scope_set:
        return []  # no scope declared → nothing to drift from
    proj = str(project_dir.resolve()).rstrip("/")
    findings: list[dict] = []
    seen_paths: set[str] = set()
    for w in writes:
        fp = w["file_path"]
        rel = fp
        if rel.startswith(proj + "/"):
            rel = rel[len(proj) + 1:]
        rel = rel.lstrip("./")
        if rel in seen_paths:
            continue
        seen_paths.add(rel)
        # Match against any scope prefix.
        in_scope = any(rel == s or rel.startswith(s.rstrip("/") + "/") for s in scope_set)
        if in_scope:
            continue
        # Allow common non-scope writes (docs, configs, .mcl/, etc.).
        if re.search(
            r"^(?:README|CHANGELOG|LICENSE|\.mcl/|\.git/|\.env|tsconfig|"
            r"package(?:-lock)?\.json|yarn\.lock|pnpm-lock\.yaml|"
            r"vite\.config|next\.config|nuxt\.config|tailwind\.config|"
            r"postcss\.config|public/|docs/)",
            rel,
        ):
            continue
        findings.append({
            "severity": "MEDIUM",
            "source": "drift",
            "rule_id": "DR-01-out-of-scope-write",
            "file": rel,
            "message": (
                f"Write outside declared scope_paths. Scope: "
                f"{sorted(scope_set)[:3]} ; this write: {rel}. "
                f"Either expand the spec's Technical Approach paths or move the file."
            ),
            "category": "phase4-drift",
        })
    return findings


def detect_intent_violations(intent_text: str, constraints_text: str,
                             writes: list[dict]) -> list[dict]:
    """Detect anti-patterns that contradict declared intent."""
    findings: list[dict] = []
    haystack = (intent_text or "") + " | " + (constraints_text or "")
    haystack_lower = haystack.lower()
    if not haystack_lower.strip(" |"):
        return findings  # no intent declared → nothing to check
    for rule in INTENT_VIOLATIONS:
        intent_match = any(
            re.search(kw, haystack_lower, re.IGNORECASE)
            for kw in rule.get("intent_keywords", [])
        )
        if not intent_match:
            continue
        # Intent triggered. Scan writes for anti-patterns.
        for w in writes:
            fp = w["file_path"]
            body = w.get("content", "") or ""
            anti_path_hit = None
            for pat in rule.get("anti_path_patterns", []):
                if re.search(pat, fp):
                    anti_path_hit = pat
                    break
            anti_import_hit = None
            for pat in rule.get("anti_import_patterns", []):
                if re.search(pat, body):
                    anti_import_hit = pat
                    break
            if anti_path_hit or anti_import_hit:
                findings.append({
                    "severity": "MEDIUM",
                    "source": "intent",
                    "rule_id": f"IV-{rule['category']}",
                    "file": fp,
                    "message": (
                        f"Phase 1 intent contradicts this write. "
                        f"Intent keyword matched: '{rule['category']}'. "
                        f"Anti-pattern: {anti_path_hit or anti_import_hit}. "
                        f"Reconcile: either revise Phase 1 declaration or "
                        f"remove this dependency."
                    ),
                    "category": "phase4-intent-violation",
                })
    return findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("--project-dir", required=True)
    ap.add_argument("--transcript", default=None)
    ap.add_argument("--lang", default="en")
    args = ap.parse_args()

    state_dir = Path(args.state_dir)
    project_dir = Path(args.project_dir)
    state = _read_state(state_dir)

    intent = state.get("phase1_intent") or ""
    constraints_raw = state.get("phase1_constraints") or ""
    constraints = constraints_raw if isinstance(constraints_raw, str) else json.dumps(constraints_raw)
    scope_paths = state.get("scope_paths") or []

    transcript = Path(args.transcript) if args.transcript else None
    writes: list[dict] = []
    if transcript and transcript.is_file():
        writes = _read_transcript_writes(transcript)

    scope_set = _normalize_scope(scope_paths, project_dir) if isinstance(scope_paths, list) else set()
    drift = detect_drift(scope_set, writes, project_dir)
    iv = detect_intent_violations(intent, constraints, writes)

    print(json.dumps({
        "drift_findings": drift,
        "intent_violations": iv,
        "scope_count": len(scope_set),
        "writes_seen": len(writes),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
