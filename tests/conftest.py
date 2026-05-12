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


@pytest.fixture(autouse=True)
def _mycl_test_force_active(monkeypatch):
    """1.0.5: opt-in `/mycl` aktivasyonu test'lerde bypass edilir.

    Üretimde hook'lar `/mycl` trigger gelene kadar pasif kalır; ama
    mevcut test takımı bu davranışı bilmiyor (hook'u doğrudan çağırıp
    deny/audit/state-mutation kontrolü yapıyor). Tüm subprocess
    hook'larının `MYCL_TEST_FORCE_ACTIVE=1` env'ini görmesi için bu
    fixture'ı autouse olarak ekledik. Yeni opt-in test'leri bu env'i
    monkeypatch.delenv ile kapatıp gerçek davranışı doğrular.
    """
    monkeypatch.setenv("MYCL_TEST_FORCE_ACTIVE", "1")
