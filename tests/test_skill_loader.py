"""hooks/lib/skill_loader.py birim testleri."""

from __future__ import annotations

from pathlib import Path

from hooks.lib import skill_loader


# ---------- next_phases_window ----------


def test_window_basic():
    assert skill_loader.next_phases_window(5, window=2) == [5, 6, 7]


def test_window_zero_returns_just_current():
    assert skill_loader.next_phases_window(5, window=0) == [5]


def test_window_caps_at_22():
    assert skill_loader.next_phases_window(21, window=5) == [21, 22]
    assert skill_loader.next_phases_window(22, window=2) == [22]


def test_window_clamps_low():
    """Aktif faz < 1 ise 1'e clamp."""
    assert skill_loader.next_phases_window(0, window=2) == [1, 2, 3]


def test_window_clamps_high():
    """Aktif faz > 22 ise 22'ye clamp."""
    assert skill_loader.next_phases_window(50, window=2) == [22]


# ---------- skills_for_phases ----------


def _make_skill(dir: Path, name: str, content: str = "skill content") -> Path:
    f = dir / name
    f.write_text(content, encoding="utf-8")
    return f


def test_skills_for_phases_filters(tmp_path, monkeypatch):
    skills_dir = tmp_path / "skills" / "mycl"
    skills_dir.mkdir(parents=True)
    _make_skill(skills_dir, "asama01-intent.md")
    _make_skill(skills_dir, "asama04-spec.md")
    _make_skill(skills_dir, "asama09-tdd.md")
    monkeypatch.setattr(skill_loader, "skills_dir", lambda: skills_dir)
    result = skill_loader.skills_for_phases([1, 4])
    names = [p.name for p in result]
    assert "asama01-intent.md" in names
    assert "asama04-spec.md" in names
    assert "asama09-tdd.md" not in names


def test_skills_for_phases_empty_list(tmp_path, monkeypatch):
    monkeypatch.setattr(skill_loader, "skills_dir", lambda: tmp_path)
    assert skill_loader.skills_for_phases([]) == []


def test_skills_for_phases_no_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(skill_loader, "skills_dir", lambda: None)
    assert skill_loader.skills_for_phases([1, 2]) == []


def test_skills_for_phases_ignores_non_skill_files(tmp_path, monkeypatch):
    skills_dir = tmp_path / "skills" / "mycl"
    skills_dir.mkdir(parents=True)
    _make_skill(skills_dir, "asama01-intent.md")
    _make_skill(skills_dir, "README.md")  # ignored
    _make_skill(skills_dir, "ortak-rules.md")  # ignored (no asamaNN prefix)
    monkeypatch.setattr(skill_loader, "skills_dir", lambda: skills_dir)
    result = skill_loader.skills_for_phases([1])
    names = [p.name for p in result]
    assert names == ["asama01-intent.md"]


# ---------- relevant_for ----------


def test_relevant_for_no_stack_returns_window(tmp_path, monkeypatch):
    skills_dir = tmp_path / "skills" / "mycl"
    skills_dir.mkdir(parents=True)
    _make_skill(skills_dir, "asama04-spec.md")
    _make_skill(skills_dir, "asama05-pattern.md")
    _make_skill(skills_dir, "asama06-ui.md")
    _make_skill(skills_dir, "asama09-tdd.md")
    monkeypatch.setattr(skill_loader, "skills_dir", lambda: skills_dir)
    result = skill_loader.relevant_for(current_phase=4, window=2)
    names = [p.name for p in result]
    assert "asama04-spec.md" in names
    assert "asama05-pattern.md" in names
    assert "asama06-ui.md" in names
    assert "asama09-tdd.md" not in names  # window dışı


def test_relevant_for_python_stack_filters_react(tmp_path, monkeypatch):
    skills_dir = tmp_path / "skills" / "mycl"
    skills_dir.mkdir(parents=True)
    _make_skill(skills_dir, "asama09-tdd-python.md")
    _make_skill(skills_dir, "asama09-tdd-react.md")
    _make_skill(skills_dir, "asama09-tdd-common.md")
    monkeypatch.setattr(skill_loader, "skills_dir", lambda: skills_dir)
    result = skill_loader.relevant_for(current_phase=9, window=0, stack="python")
    names = [p.name for p in result]
    assert "asama09-tdd-python.md" in names
    assert "asama09-tdd-common.md" in names  # ortak (stack ipucusuz)
    assert "asama09-tdd-react.md" not in names  # other stack elenir


def test_relevant_for_no_stack_keeps_all_in_window(tmp_path, monkeypatch):
    skills_dir = tmp_path / "skills" / "mycl"
    skills_dir.mkdir(parents=True)
    _make_skill(skills_dir, "asama09-tdd-python.md")
    _make_skill(skills_dir, "asama09-tdd-react.md")
    monkeypatch.setattr(skill_loader, "skills_dir", lambda: skills_dir)
    result = skill_loader.relevant_for(current_phase=9, window=0, stack=None)
    names = [p.name for p in result]
    assert "asama09-tdd-python.md" in names
    assert "asama09-tdd-react.md" in names


# ---------- load_content ----------


def test_load_content_reads_text(tmp_path):
    f = tmp_path / "skill.md"
    f.write_text("Skill içeriği", encoding="utf-8")
    assert skill_loader.load_content(f) == "Skill içeriği"


def test_load_content_missing_returns_empty(tmp_path):
    assert skill_loader.load_content(tmp_path / "nope.md") == ""


def test_load_content_directory_returns_empty(tmp_path):
    assert skill_loader.load_content(tmp_path) == ""


# ---------- list_all_skills ----------


def test_list_all_skills_sorted(tmp_path, monkeypatch):
    skills_dir = tmp_path / "skills" / "mycl"
    skills_dir.mkdir(parents=True)
    _make_skill(skills_dir, "asama09-tdd.md")
    _make_skill(skills_dir, "asama01-intent.md")
    _make_skill(skills_dir, "asama04-spec.md")
    monkeypatch.setattr(skill_loader, "skills_dir", lambda: skills_dir)
    result = skill_loader.list_all_skills()
    names = [p.name for p in result]
    assert names == ["asama01-intent.md", "asama04-spec.md", "asama09-tdd.md"]


def test_list_all_skills_empty_when_no_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(skill_loader, "skills_dir", lambda: None)
    assert skill_loader.list_all_skills() == []
