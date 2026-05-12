"""hooks/lib/activation.py birim testleri (1.0.5 opt-in `/mycl`).

Üç sözleşme:
    - extract_trigger: prompt başında `/mycl` prefix tespit + sıyır
    - activate_session: session_id'yi `.mycl/active_session.txt`'e yaz
    - is_session_active: session_id eşleşmesi (oturum-geçici semantik)
"""

from __future__ import annotations

from hooks.lib import activation


# ---------- extract_trigger ----------


def test_extract_trigger_bare(monkeypatch):
    has, stripped = activation.extract_trigger("/mycl")
    assert has is True
    assert stripped == ""


def test_extract_trigger_with_prompt():
    has, stripped = activation.extract_trigger("/mycl todo uygulaması yap")
    assert has is True
    assert stripped == "todo uygulaması yap"


def test_extract_trigger_case_insensitive():
    has, stripped = activation.extract_trigger("/MyCL deploy")
    assert has is True
    assert stripped == "deploy"


def test_extract_trigger_leading_whitespace():
    has, stripped = activation.extract_trigger("   /mycl  start")
    assert has is True
    assert stripped == "start"


def test_extract_trigger_no_match():
    has, stripped = activation.extract_trigger("normal prompt")
    assert has is False
    assert stripped == "normal prompt"


def test_extract_trigger_mid_line_does_not_match():
    """`/mycl` sadece prompt başında — orta satırda olursa eşleşmez."""
    has, stripped = activation.extract_trigger("see /mycl docs")
    assert has is False
    assert stripped == "see /mycl docs"


def test_extract_trigger_partial_word_no_match():
    """`/myclient` `/mycl`'in eşleşmesine yol açmamalı (\\b ankarı)."""
    has, _ = activation.extract_trigger("/myclient action")
    assert has is False


def test_extract_trigger_empty_input():
    has, stripped = activation.extract_trigger("")
    assert has is False
    assert stripped == ""


def test_extract_trigger_none_input():
    has, stripped = activation.extract_trigger(None)
    assert has is False
    assert stripped == ""


# ---------- activate_session + is_session_active ----------


def test_activation_roundtrip(tmp_project, monkeypatch):
    """Aktive et → aynı session_id is_session_active True döner."""
    # Test bypass env'i kapat → gerçek davranış
    monkeypatch.delenv("MYCL_TEST_FORCE_ACTIVE", raising=False)
    sid = "abc-123"
    assert activation.is_session_active(sid, project_root=str(tmp_project)) is False
    ok = activation.activate_session(sid, project_root=str(tmp_project))
    assert ok is True
    assert activation.is_session_active(sid, project_root=str(tmp_project)) is True


def test_activation_per_session(tmp_project, monkeypatch):
    """Farklı session_id pasif kalır — oturum-geçici semantik."""
    monkeypatch.delenv("MYCL_TEST_FORCE_ACTIVE", raising=False)
    activation.activate_session("first-session", project_root=str(tmp_project))
    assert activation.is_session_active(
        "second-session", project_root=str(tmp_project)
    ) is False


def test_activation_empty_session_id(tmp_project, monkeypatch):
    monkeypatch.delenv("MYCL_TEST_FORCE_ACTIVE", raising=False)
    assert activation.activate_session("", project_root=str(tmp_project)) is False
    assert activation.is_session_active("", project_root=str(tmp_project)) is False


def test_activation_force_active_env_bypass(tmp_project, monkeypatch):
    """`MYCL_TEST_FORCE_ACTIVE=1` → session_id boş veya yanlış olsa
    bile True döner (test ortamı için)."""
    monkeypatch.setenv("MYCL_TEST_FORCE_ACTIVE", "1")
    assert activation.is_session_active(
        "any-session", project_root=str(tmp_project)
    ) is True
    assert activation.is_session_active(
        None, project_root=str(tmp_project)
    ) is True


def test_deactivate(tmp_project, monkeypatch):
    monkeypatch.delenv("MYCL_TEST_FORCE_ACTIVE", raising=False)
    activation.activate_session("sid-x", project_root=str(tmp_project))
    activation.deactivate(project_root=str(tmp_project))
    assert activation.is_session_active(
        "sid-x", project_root=str(tmp_project)
    ) is False
