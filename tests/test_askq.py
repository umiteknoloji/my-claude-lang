"""hooks/lib/askq.py birim testleri."""

from __future__ import annotations

import json

from hooks.lib import askq


# ---------- Test fixture cues ----------


def _test_cues() -> dict:
    """Test'lerde explicit cues — global cache'i bypass."""
    return {
        "approve": {
            "tr": ["onayla", "onaylıyorum", "onayladım", "evet", "kabul", "tamam"],
            "en": ["approve", "yes", "ok", "confirm", "proceed"],
        },
        "revise": {
            "tr": ["revize", "düzelt", "değiştir", "değişiklik"],
            "en": ["revise", "change", "fix", "wrong"],
        },
        "cancel": {
            "tr": ["iptal", "vazgeç", "dur", "durdur"],
            "en": ["cancel", "abort", "stop", "quit"],
        },
    }


# ---------- classify: Türkçe ----------


def test_classify_tr_approve_simple():
    assert askq.classify("Onayla", cues=_test_cues()) == askq.INTENT_APPROVE


def test_classify_tr_approve_morphology():
    """approve_cues.json'da 'onayladım' explicit listede."""
    assert askq.classify("Onayladım, başla", cues=_test_cues()) == askq.INTENT_APPROVE


def test_classify_tr_approve_phrase():
    assert askq.classify("Evet kabul", cues=_test_cues()) == askq.INTENT_APPROVE


def test_classify_tr_revise():
    assert askq.classify("Revize gerek", cues=_test_cues()) == askq.INTENT_REVISE
    assert askq.classify("Düzelt şunu", cues=_test_cues()) == askq.INTENT_REVISE


def test_classify_tr_cancel():
    assert askq.classify("İptal", cues=_test_cues()) == askq.INTENT_CANCEL
    assert askq.classify("Vazgeç", cues=_test_cues()) == askq.INTENT_CANCEL


# ---------- classify: İngilizce ----------


def test_classify_en_approve():
    assert askq.classify("Yes proceed", cues=_test_cues()) == askq.INTENT_APPROVE
    assert askq.classify("approve", cues=_test_cues()) == askq.INTENT_APPROVE


def test_classify_en_revise():
    assert askq.classify("please change this", cues=_test_cues()) == askq.INTENT_REVISE


def test_classify_en_cancel():
    assert askq.classify("cancel everything", cues=_test_cues()) == askq.INTENT_CANCEL
    assert askq.classify("abort", cues=_test_cues()) == askq.INTENT_CANCEL


# ---------- Sıralama (cancel > revise > approve) ----------


def test_cancel_wins_over_approve():
    """Aşama 7 pseudocode kuralı: cancel en güçlü."""
    assert askq.classify("İptal et, evet", cues=_test_cues()) == askq.INTENT_CANCEL


def test_revise_wins_over_approve():
    """'güzel ama büyüt' örneği: approve + revise → revise kazanır."""
    assert askq.classify("evet ama düzelt", cues=_test_cues()) == askq.INTENT_REVISE
    assert askq.classify("approved but fix it", cues=_test_cues()) == askq.INTENT_REVISE


def test_cancel_wins_over_revise():
    assert askq.classify("revize gerekmez, iptal", cues=_test_cues()) == askq.INTENT_CANCEL


# ---------- Word-boundary (false positive koruması) ----------


def test_word_boundary_prevents_false_positive():
    """'değiştirme yok' cümlesi 'değiştir' substring'ini içerir
    ama \\b sayesinde match etmez (kelime sonu 'm' = word char).
    Niyet aslında approve değil, 'değiştirme' ile reddediliyor —
    classify ambiguous döner (yanlış-revise yerine)."""
    result = askq.classify("değiştirme yok", cues=_test_cues())
    assert result != askq.INTENT_REVISE


def test_word_boundary_morphology_explicit_only():
    """Listede olmayan ek varsa match etmez. 'Tamamladım' listede yok
    (sadece 'tamam' var). Tamam tek kelime ile match → approve."""
    assert askq.classify("Tamam", cues=_test_cues()) == askq.INTENT_APPROVE
    # 'Tamamladım' listede yok ve 'tamam' kök word-boundary ile match etmez
    result = askq.classify("Tamamladım", cues=_test_cues())
    assert result != askq.INTENT_APPROVE  # listede explicit yok


# ---------- Ambiguous ----------


def test_classify_empty():
    assert askq.classify("", cues=_test_cues()) == askq.INTENT_AMBIGUOUS
    assert askq.classify(None, cues=_test_cues()) == askq.INTENT_AMBIGUOUS


def test_classify_unrelated():
    assert askq.classify("merhaba dünya", cues=_test_cues()) == askq.INTENT_AMBIGUOUS
    assert askq.classify("👍", cues=_test_cues()) == askq.INTENT_AMBIGUOUS


# ---------- predicate helpers ----------


def test_is_approve_helper():
    assert askq.is_approve("Onayla", cues=_test_cues()) is True
    assert askq.is_approve("İptal", cues=_test_cues()) is False


def test_is_revise_helper():
    assert askq.is_revise("Revize", cues=_test_cues()) is True


def test_is_cancel_helper():
    assert askq.is_cancel("Vazgeç", cues=_test_cues()) is True


# ---------- tool_result extract ----------


def test_extract_result_text_string_content():
    r = {"tool_use_id": "x", "content": "Onayla"}
    assert askq.extract_result_text(r) == "Onayla"


def test_extract_result_text_list_content():
    r = {
        "tool_use_id": "x",
        "content": [{"type": "text", "text": "User selected: Onayla"}],
    }
    assert askq.extract_result_text(r) == "User selected: Onayla"


def test_extract_result_text_multi_blocks():
    r = {
        "content": [
            {"type": "text", "text": "Birinci."},
            {"type": "text", "text": "İkinci."},
        ]
    }
    assert askq.extract_result_text(r) == "Birinci.\nİkinci."


def test_extract_result_text_nested_content():
    """Bazı sürümler nested content (item.content) kullanır."""
    r = {"content": [{"content": "fallback metni"}]}
    assert askq.extract_result_text(r) == "fallback metni"


def test_extract_result_text_answer_fallback():
    """Eski sürüm: 'answer' alanı."""
    r = {"answer": "Onayla"}
    assert askq.extract_result_text(r) == "Onayla"


def test_extract_result_text_empty_or_invalid():
    assert askq.extract_result_text(None) == ""
    assert askq.extract_result_text({}) == ""
    assert askq.extract_result_text("not a dict") == ""  # type: ignore[arg-type]


def test_classify_tool_result_full():
    r = {"tool_use_id": "x", "content": "Onayla"}
    assert askq.classify_tool_result(r, cues=_test_cues()) == askq.INTENT_APPROVE


def test_classify_tool_result_empty():
    assert askq.classify_tool_result(None, cues=_test_cues()) == askq.INTENT_AMBIGUOUS


# ---------- load_cues + cache ----------


def test_load_cues_from_real_file(tmp_path):
    """tmp dizinde sahte JSON yaz, oradan yükle."""
    p = tmp_path / "approve_cues.json"
    p.write_text(
        json.dumps({
            "approve": {"tr": ["evet"], "en": ["yes"]},
            "revise": {"tr": ["düzelt"], "en": ["fix"]},
            "cancel": {"tr": ["iptal"], "en": ["cancel"]},
        }),
        encoding="utf-8",
    )
    cues = askq.load_cues(p)
    assert "evet" in cues["approve"]["tr"]
    assert "fix" in cues["revise"]["en"]


def test_load_cues_missing_file_returns_empty(tmp_path):
    cues = askq.load_cues(tmp_path / "no.json")
    # boş cue: her şey ambiguous olur
    assert askq.classify("Onayla", cues=cues) == askq.INTENT_AMBIGUOUS


def test_load_cues_corrupt_json_returns_empty(tmp_path):
    p = tmp_path / "bad.json"
    p.write_text("{not valid json", encoding="utf-8")
    cues = askq.load_cues(p)
    assert askq.classify("Onayla", cues=cues) == askq.INTENT_AMBIGUOUS


def test_real_repo_cues_load():
    """Repo data/approve_cues.json gerçekten yükleniyor mu?"""
    askq.reset_cache()
    cues = askq.load_cues()
    # En azından bazı approve sözcükleri olmalı
    assert "onayla" in cues["approve"]["tr"]
    assert "approve" in cues["approve"]["en"]


def test_reset_cache_works():
    """reset_cache çağrısı sonrası tekrar yükleme yapılır."""
    askq.reset_cache()
    cues1 = askq.load_cues()
    askq.reset_cache()
    cues2 = askq.load_cues()
    assert cues1 == cues2  # aynı içerik
