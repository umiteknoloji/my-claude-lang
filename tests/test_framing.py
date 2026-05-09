"""hooks/lib/framing.py birim testleri."""

from __future__ import annotations

from hooks.lib import framing


def test_load_manifesto_from_real_file(tmp_path):
    p = tmp_path / "manifesto.txt"
    p.write_text("Test manifesto", encoding="utf-8")
    text = framing.load_manifesto(p)
    assert text == "Test manifesto"


def test_load_manifesto_missing_returns_empty(tmp_path):
    text = framing.load_manifesto(tmp_path / "no.txt")
    assert text == ""


def test_load_manifesto_caches(tmp_path):
    """path=None ile cache; ikinci çağrı aynı."""
    framing.reset_cache()
    a = framing.load_manifesto()
    b = framing.load_manifesto()
    assert a == b


def test_real_repo_manifesto_loads():
    """Repo data/manifesto.txt yüklenir."""
    framing.reset_cache()
    text = framing.load_manifesto()
    # Production manifesto'da co-author pattern var
    assert len(text) > 0
    assert "MyCL" in text


def test_real_repo_manifesto_has_tr_section():
    framing.reset_cache()
    text = framing.load_manifesto()
    # Manifesto.txt format: [Türkçe ...] / [English ...]
    assert "[Türkçe" in text
    assert "[English" in text


def test_real_repo_manifesto_has_concrete_story():
    """Disiplin #15: somut maliyet hikayesi (47 dakika)."""
    framing.reset_cache()
    text = framing.load_manifesto()
    assert "47" in text  # 47 dakika kayıp
    assert "Aşama 2" in text or "Phase 2" in text


def test_for_context_returns_full_text():
    framing.reset_cache()
    a = framing.for_context()
    b = framing.load_manifesto()
    assert a == b


def test_reset_cache_works(tmp_path):
    framing.reset_cache()
    text1 = framing.load_manifesto()
    framing.reset_cache()
    text2 = framing.load_manifesto()
    assert text1 == text2  # aynı içerik
