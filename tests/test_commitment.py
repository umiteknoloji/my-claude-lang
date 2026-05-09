"""hooks/lib/commitment.py birim testleri."""

from __future__ import annotations

import json

from hooks.lib import audit, commitment


def _test_template() -> dict:
    return {
        "pre_commitment": {
            "tr": "Pre-commitment: Aşama {phase} ({phase_name})?",
            "en": "Pre-commitment: Phase {phase} ({phase_name})?",
        },
        "public_commitment_list_open": {
            "tr": "Aşama {phase} ({phase_name}) başlıyor:",
            "en": "Phase {phase} ({phase_name}) starting:",
        },
        "public_commitment_list_close": {
            "tr": "Aşama {phase} {count} maddeden:",
            "en": "Phase {phase} of {count} items:",
        },
        "phase_specific_templates": {
            "1": {
                "tr_items": ["Tek soru sor", "Onay al"],
                "en_items": ["Ask one question", "Confirm"],
            },
            "4": {
                "tr_items": ["📋 Spec yaz", "MUST etiketle", "Onay al"],
                "en_items": ["Write 📋 Spec", "Tag MUST", "Confirm"],
            },
        },
    }


# ---------- pre_commitment_prompt ----------


def test_pre_commitment_prompt_double_block():
    result = commitment.pre_commitment_prompt(
        4, phase_name="Spec", template=_test_template()
    )
    assert "Aşama 4 (Spec)" in result
    assert "Phase 4 (Spec)" in result
    assert "\n\n" in result


def test_pre_commitment_prompt_missing_template():
    """Boş template → boş string."""
    result = commitment.pre_commitment_prompt(1, template={})
    assert result == ""


# ---------- public_commitment_open ----------


def test_public_commitment_open():
    result = commitment.public_commitment_open(
        9, phase_name="TDD", template=_test_template()
    )
    assert "Aşama 9" in result
    assert "Phase 9" in result


# ---------- public_commitment_close ----------


def test_public_commitment_close_with_count():
    result = commitment.public_commitment_close(
        4, count=5, phase_name="Spec", template=_test_template()
    )
    assert "5 maddeden" in result
    assert "5 items" in result


# ---------- phase_specific_items ----------


def test_phase_specific_items_returns_lists():
    items = commitment.phase_specific_items(4, template=_test_template())
    assert items is not None
    assert items["tr_items"] == ["📋 Spec yaz", "MUST etiketle", "Onay al"]
    assert items["en_items"] == ["Write 📋 Spec", "Tag MUST", "Confirm"]


def test_phase_specific_items_missing_phase():
    """Faza özel template yoksa None."""
    items = commitment.phase_specific_items(99, template=_test_template())
    assert items is None


def test_phase_specific_items_phase_1():
    items = commitment.phase_specific_items(1, template=_test_template())
    assert items is not None
    assert len(items["tr_items"]) == 2


# ---------- record_pre_commitment ----------


def test_record_pre_commitment_writes_audit(tmp_project):
    commitment.record_pre_commitment(
        "Bu turda Aşama 4'ü tamamlayacağım.", phase=4
    )
    ev = audit.latest("pre-commitment-stated")
    assert ev is not None
    assert "phase=4" in ev["detail"]
    assert "tamamlayacağım" in ev["detail"]


def test_record_pre_commitment_truncates_long(tmp_project):
    long_text = "x" * 500
    commitment.record_pre_commitment(long_text, phase=4)
    ev = audit.latest("pre-commitment-stated")
    assert ev is not None
    assert "..." in ev["detail"]
    # 200 char + 'phase=N text="..."' wrapper
    assert len(ev["detail"]) < 300


def test_record_pre_commitment_replaces_pipe_in_text(tmp_project):
    """Audit detail'de ' | ' yasak — text içeriği temizlenmeli."""
    commitment.record_pre_commitment(
        "Aşama 4 | spec yaz | onay al", phase=4
    )
    ev = audit.latest("pre-commitment-stated")
    assert ev is not None
    assert " | " not in ev["detail"].split("text=", 1)[1]


def test_record_pre_commitment_empty_skipped(tmp_project):
    commitment.record_pre_commitment("", phase=4)
    assert audit.latest("pre-commitment-stated") is None


def test_record_pre_commitment_strips_newlines(tmp_project):
    commitment.record_pre_commitment(
        "Birinci satır\nİkinci satır", phase=4
    )
    ev = audit.latest("pre-commitment-stated")
    assert ev is not None
    assert "\n" not in ev["detail"]


# ---------- record_commitment_kept ----------


def test_record_commitment_kept_true(tmp_project):
    commitment.record_commitment_kept(phase=4, kept=True)
    ev = audit.latest("commitment-tracked")
    assert ev is not None
    assert "phase=4" in ev["detail"]
    assert "kept=true" in ev["detail"]


def test_record_commitment_kept_false(tmp_project):
    commitment.record_commitment_kept(phase=9, kept=False)
    ev = audit.latest("commitment-tracked")
    assert ev is not None
    assert "kept=false" in ev["detail"]


# ---------- latest_pre_commitment ----------


def test_latest_pre_commitment_returns_text(tmp_project):
    commitment.record_pre_commitment("İlk söz", phase=4)
    commitment.record_pre_commitment("İkinci söz", phase=4)
    result = commitment.latest_pre_commitment(phase=4)
    assert result is not None
    assert "İkinci söz" in result


def test_latest_pre_commitment_filtered_by_phase(tmp_project):
    """Aşama 4 sözü Aşama 9 isteğine dönmemeli."""
    commitment.record_pre_commitment("Aşama 4 sözü", phase=4)
    assert commitment.latest_pre_commitment(phase=9) is None


def test_latest_pre_commitment_none_when_absent(tmp_project):
    assert commitment.latest_pre_commitment(phase=1) is None


# ---------- load_template ----------


def test_load_template_from_real_file(tmp_path):
    p = tmp_path / "commitment_template.json"
    p.write_text(
        json.dumps({"pre_commitment": {"tr": "Test", "en": "Test EN"}}),
        encoding="utf-8",
    )
    tpl = commitment.load_template(p)
    assert tpl["pre_commitment"]["tr"] == "Test"


def test_load_template_missing_file(tmp_path):
    tpl = commitment.load_template(tmp_path / "no.json")
    assert tpl == commitment._DEFAULT_EMPTY


def test_real_repo_template_loads():
    commitment.reset_cache()
    tpl = commitment.load_template()
    assert "pre_commitment" in tpl
    assert "phase_specific_templates" in tpl


def test_real_repo_phase_4_items_exist():
    """Production template Aşama 4 için item içeriyor."""
    commitment.reset_cache()
    items = commitment.phase_specific_items(4)
    assert items is not None
    assert len(items["tr_items"]) > 0
    assert len(items["en_items"]) > 0


# ---------- isolation ----------


def test_record_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    commitment.record_pre_commitment("a sözü", phase=1, project_root=str(a))
    commitment.record_pre_commitment("b sözü", phase=1, project_root=str(b))
    assert "a sözü" in (commitment.latest_pre_commitment(1, project_root=str(a)) or "")
    assert "b sözü" in (commitment.latest_pre_commitment(1, project_root=str(b)) or "")
