"""pytest yapılandırması — repo köküne sys.path eklenir.

Tests `from hooks.lib import state` şeklinde import eder.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


import pytest


@pytest.fixture
def tmp_project(tmp_path, monkeypatch):
    """Geçici proje kökü; CLAUDE_PROJECT_DIR ona bağlanır."""
    monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))
    return tmp_path
