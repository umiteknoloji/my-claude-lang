"""hooks/lib/bilingual.py birim testleri."""

from __future__ import annotations

import json

from hooks.lib import bilingual


def _test_messages() -> dict:
    return {
        "messages": {
            "phase_done": {
                "tr": "✅ Aşama {phase} tamamlandı.",
                "en": "✅ Phase {phase} complete.",
            },
            "spec_block": {
                "tr": "Spec onayı yok, `{tool}` engellendi.",
                "en": "No spec approval, `{tool}` blocked.",
            },
            "no_placeholder": {
                "tr": "Sade Türkçe.",
                "en": "Plain English.",
            },
            "tr_only": {"tr": "Sadece Türkçe.", "en": ""},
            "en_only": {"tr": "", "en": "English only."},
        }
    }


# ---------- render ----------


def test_render_double_block_format():
    result = bilingual.render("phase_done", messages=_test_messages(), phase=4)
    assert result == "✅ Aşama 4 tamamlandı.\n\n✅ Phase 4 complete."


def test_render_no_placeholder():
    result = bilingual.render("no_placeholder", messages=_test_messages())
    assert result == "Sade Türkçe.\n\nPlain English."


def test_render_substitutes_kwargs():
    result = bilingual.render(
        "spec_block", messages=_test_messages(), tool="Write"
    )
    assert "`Write` engellendi" in result
    assert "`Write` blocked" in result


def test_render_blank_line_separator():
    result = bilingual.render("phase_done", messages=_test_messages(), phase=1)
    assert "\n\n" in result
    parts = result.split("\n\n")
    assert len(parts) == 2


def test_render_no_tr_en_label():
    """CLAUDE.md kuralı: etiket (TR:/EN:) yok."""
    result = bilingual.render("phase_done", messages=_test_messages(), phase=2)
    assert "TR:" not in result
    assert "EN:" not in result


# ---------- eksik key fail-safe ----------


def test_render_unknown_key_returns_marker():
    result = bilingual.render("unknown_key", messages=_test_messages())
    assert result == "[unknown_key]"


def test_render_missing_placeholder_keeps_template():
    """Eksik placeholder hata vermez — orijinal template döner."""
    # phase_done {phase} placeholder bekliyor; geçilmez
    result = bilingual.render("phase_done", messages=_test_messages())
    # Format hata atmamalı; raw template korunur
    assert "Aşama" in result
    assert "Phase" in result


# ---------- tek dil eksik ----------


def test_render_tr_only_when_en_empty():
    result = bilingual.render("tr_only", messages=_test_messages())
    assert result == "Sadece Türkçe."


def test_render_en_only_when_tr_empty():
    result = bilingual.render("en_only", messages=_test_messages())
    assert result == "English only."


# ---------- render_tr / render_en ----------


def test_render_tr_only():
    assert (
        bilingual.render_tr("phase_done", messages=_test_messages(), phase=5)
        == "✅ Aşama 5 tamamlandı."
    )


def test_render_en_only():
    assert (
        bilingual.render_en("phase_done", messages=_test_messages(), phase=5)
        == "✅ Phase 5 complete."
    )


def test_render_tr_unknown_key():
    assert bilingual.render_tr("nope", messages=_test_messages()) == "[nope]"


# ---------- has_key ----------


def test_has_key_true():
    assert bilingual.has_key("phase_done", messages=_test_messages()) is True


def test_has_key_false():
    assert bilingual.has_key("nope", messages=_test_messages()) is False


# ---------- load_messages ----------


def test_load_messages_from_real_file(tmp_path):
    p = tmp_path / "bilingual_messages.json"
    p.write_text(
        json.dumps({
            "messages": {
                "test_key": {"tr": "Türkçe", "en": "English"}
            }
        }),
        encoding="utf-8",
    )
    msgs = bilingual.load_messages(p)
    assert "test_key" in msgs["messages"]


def test_load_messages_missing_file(tmp_path):
    msgs = bilingual.load_messages(tmp_path / "no.json")
    assert msgs["messages"] == {}


def test_load_messages_corrupt_json(tmp_path):
    p = tmp_path / "bad.json"
    p.write_text("{not valid", encoding="utf-8")
    msgs = bilingual.load_messages(p)
    assert msgs["messages"] == {}


def test_load_messages_invalid_structure(tmp_path):
    p = tmp_path / "wrong.json"
    p.write_text(json.dumps([1, 2, 3]), encoding="utf-8")
    msgs = bilingual.load_messages(p)
    assert msgs["messages"] == {}


def test_real_repo_messages_load():
    """Repo data/bilingual_messages.json gerçekten yükleniyor mu?"""
    bilingual.reset_cache()
    msgs = bilingual.load_messages()
    assert "phase_done_notification" in msgs["messages"]


def test_real_repo_phase_done_renders():
    """Production mesajı render kontrol."""
    bilingual.reset_cache()
    result = bilingual.render(
        "phase_done_notification",
        phase=4, phase_name="Spec", next_phase=5,
    )
    assert "Aşama 4" in result
    assert "Phase 4" in result
    assert "\n\n" in result


def test_reset_cache_works():
    bilingual.reset_cache()
    m1 = bilingual.load_messages()
    bilingual.reset_cache()
    m2 = bilingual.load_messages()
    assert m1 == m2
