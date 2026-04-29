#!/usr/bin/env python3
"""MCL Dev Server Detection (8.12.0).

Detect frontend dev server stack from project manifests.

Output JSON: {"stack": "...", "default_port": N, "start_cmd": "...", "args": [...]}
or {"stack": null, "reason": "..."} if not detected.

Stacks: vite | next | cra | vue-cli | sveltekit | rails | django | flask |
        expo | static
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path


def _read(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _pkg_json(project_dir: Path) -> dict | None:
    f = project_dir / "package.json"
    if not f.exists():
        return None
    try:
        return json.loads(_read(f))
    except json.JSONDecodeError:
        return None


def detect(project_dir: Path) -> dict:
    pkg = _pkg_json(project_dir)
    scripts = (pkg or {}).get("scripts", {}) or {}
    deps_raw = (pkg or {}).get("dependencies", {}) or {}
    devdeps_raw = (pkg or {}).get("devDependencies", {}) or {}
    deps = {**deps_raw, **devdeps_raw}

    # Vite
    if any("vite" in (scripts.get(k, "") or "") for k in ("dev", "start")):
        return {"stack": "vite", "default_port": 5173,
                "start_cmd": "npm", "args": ["run", "dev"]}

    # Next.js
    if any(re.search(r"\bnext\b\s*(dev|start)?", scripts.get(k, "") or "") for k in ("dev", "start")):
        return {"stack": "next", "default_port": 3000,
                "start_cmd": "npm", "args": ["run", "dev"]}

    # SvelteKit (vite-based but distinct dep)
    if "@sveltejs/kit" in deps:
        return {"stack": "sveltekit", "default_port": 5173,
                "start_cmd": "npm", "args": ["run", "dev"]}

    # Vue CLI
    if "vue-cli-service" in (scripts.get("serve", "") or ""):
        return {"stack": "vue-cli", "default_port": 8080,
                "start_cmd": "npm", "args": ["run", "serve"]}

    # CRA
    if "react-scripts" in (scripts.get("start", "") or ""):
        return {"stack": "cra", "default_port": 3000,
                "start_cmd": "npm", "args": ["start"]}

    # Expo (mobile)
    if "expo" in deps or (project_dir / "app.json").exists() and "expo" in _read(project_dir / "app.json"):
        return {"stack": "expo", "default_port": 19000,
                "start_cmd": "npx", "args": ["expo", "start"]}

    # Rails
    if (project_dir / "bin" / "rails").exists() or "rails" in _read(project_dir / "Gemfile").lower():
        return {"stack": "rails", "default_port": 3000,
                "start_cmd": str(project_dir / "bin" / "rails"), "args": ["server"]}

    # Django
    if (project_dir / "manage.py").exists():
        return {"stack": "django", "default_port": 8000,
                "start_cmd": "python", "args": ["manage.py", "runserver"]}

    # Flask
    req_text = ""
    for r in ("requirements.txt", "requirements-dev.txt"):
        if (project_dir / r).exists():
            req_text += _read(project_dir / r).lower()
    if "flask" in req_text and ((project_dir / "app.py").exists() or (project_dir / "wsgi.py").exists()):
        return {"stack": "flask", "default_port": 5000,
                "start_cmd": "flask", "args": ["run"], "env": {"FLASK_APP": "app.py"}}

    # Static HTML
    if (project_dir / "index.html").exists() and not pkg:
        return {"stack": "static", "default_port": 8000,
                "start_cmd": "python3", "args": ["-m", "http.server", "8000"]}

    return {"stack": None, "reason": "no recognized frontend dev stack"}


def main() -> int:
    project_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    print(json.dumps(detect(project_dir.resolve())))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as _e:
        import traceback as _tb
        print(json.dumps({"error": str(_e)[:500], "traceback": _tb.format_exc()[-1500:]}))
        sys.exit(3)
