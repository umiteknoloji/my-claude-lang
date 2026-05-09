"""hooks/lib/state.py birim testleri.

Kapsama:
    - read/get default invariant
    - atomik write
    - format auth (current_phase aralık, spec_hash SHA256)
    - reset
    - eksik alanlar default ile doldurulur (forward-compat)
"""

from __future__ import annotations

import hashlib

import pytest

from hooks.lib import state


# ---------- read / default ----------


def test_read_default_when_missing(tmp_project):
    s = state.read()
    assert s["current_phase"] == 1
    assert s["spec_approved"] is False
    assert s["spec_hash"] is None
    assert s["schema_version"] == state.SCHEMA_VERSION


def test_get_field_with_default(tmp_project):
    assert state.get("current_phase") == 1
    assert state.get("nonexistent_field", "fallback") == "fallback"


def test_state_path_uses_project_dir(tmp_project):
    p = state.state_path()
    assert p.parent.name == ".mycl"
    assert p.name == "state.json"


# ---------- atomik write ----------


def test_set_field_persists(tmp_project):
    state.set_field("current_phase", 5)
    assert state.get("current_phase") == 5
    p = state.state_path()
    assert p.exists()


def test_update_multiple_atomic(tmp_project):
    state.update({"current_phase": 4, "spec_approved": True, "phase_name": "SPEC_APPROVED"})
    s = state.read()
    assert s["current_phase"] == 4
    assert s["spec_approved"] is True
    assert s["phase_name"] == "SPEC_APPROVED"


def test_last_update_bumps(tmp_project):
    state.set_field("current_phase", 2)
    t1 = state.get("last_update")
    state.set_field("current_phase", 3)
    t2 = state.get("last_update")
    assert t2 >= t1


# ---------- format auth ----------


def test_invalid_phase_rejected(tmp_project):
    with pytest.raises(state.StateValidationError):
        state.set_field("current_phase", 0)
    with pytest.raises(state.StateValidationError):
        state.set_field("current_phase", 23)
    with pytest.raises(state.StateValidationError):
        state.set_field("current_phase", "spec_approved")


def test_invalid_spec_hash_rejected(tmp_project):
    """v13.1.3 öğrenimi: model `mcl_state_set spec_hash backoffice-v1` ile
    sahte hash giriyordu. v1.0.0'da format auth her yazımda."""
    with pytest.raises(state.StateValidationError):
        state.set_field("spec_hash", "backoffice-v1")
    with pytest.raises(state.StateValidationError):
        state.set_field("spec_hash", "abc123")  # kısa
    with pytest.raises(state.StateValidationError):
        state.set_field("spec_hash", "Z" * 64)  # geçersiz hex


def test_valid_spec_hash_accepted(tmp_project):
    valid = hashlib.sha256(b"sample spec body").hexdigest()
    state.set_field("spec_hash", valid)
    assert state.get("spec_hash") == valid


def test_spec_hash_none_accepted(tmp_project):
    state.set_field("spec_hash", None)
    assert state.get("spec_hash") is None


def test_invalid_spec_approved_rejected(tmp_project):
    with pytest.raises(state.StateValidationError):
        state.set_field("spec_approved", "yes")
    with pytest.raises(state.StateValidationError):
        state.set_field("spec_approved", 1)


# ---------- reset ----------


def test_reset_returns_default(tmp_project):
    state.update({"current_phase": 10, "spec_approved": True})
    state.reset()
    assert state.get("current_phase") == 1
    assert state.get("spec_approved") is False
    assert state.get("spec_hash") is None


# ---------- forward compat ----------


def test_missing_fields_filled_from_default(tmp_project):
    """Eski schema state.json'unda yeni alanlar yoksa, read() default ile
    doldurur — forward-compatible upgrade."""
    p = state.state_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text('{"schema_version": 3, "current_phase": 5}', encoding="utf-8")
    s = state.read()
    assert s["current_phase"] == 5
    # Default'tan geliyor:
    assert s["spec_approved"] is False
    assert s["spec_must_list"] == []


def test_corrupt_json_returns_default(tmp_project):
    p = state.state_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("{not valid json", encoding="utf-8")
    s = state.read()
    assert s["current_phase"] == 1


# ---------- isolation ----------


def test_independent_project_dirs(tmp_path, monkeypatch):
    a = tmp_path / "proj_a"
    b = tmp_path / "proj_b"
    a.mkdir()
    b.mkdir()
    state.set_field("current_phase", 5, project_root=str(a))
    state.set_field("current_phase", 9, project_root=str(b))
    assert state.get("current_phase", project_root=str(a)) == 5
    assert state.get("current_phase", project_root=str(b)) == 9
