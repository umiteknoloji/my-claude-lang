"""hooks/lib/tdd.py birim testleri.

TDD compliance score invariantları (pseudocode §5):
    - test before prod = compliant
    - prod before test = non-compliant
    - score = compliant_prod / total_prod * 100
    - 0 prod write → None (anlamsız)
"""

from __future__ import annotations

from hooks.lib import audit, state, tdd


# ---------- is_test_path ----------


def test_is_test_path_python_prefix():
    assert tdd.is_test_path("tests/test_foo.py") is True
    assert tdd.is_test_path("src/test_module.py") is True


def test_is_test_path_python_suffix():
    assert tdd.is_test_path("foo_test.py") is True
    assert tdd.is_test_path("src/utils_test.py") is True


def test_is_test_path_tests_dir():
    assert tdd.is_test_path("tests/foo.py") is True
    assert tdd.is_test_path("project/test/foo.py") is True
    assert tdd.is_test_path("a/b/tests/c/d.py") is True


def test_is_test_path_jest_dot_test():
    assert tdd.is_test_path("src/Login.test.tsx") is True
    assert tdd.is_test_path("utils.test.js") is True


def test_is_test_path_spec_extension():
    assert tdd.is_test_path("foo.spec.ts") is True
    assert tdd.is_test_path("user.spec.rb") is True


def test_is_test_path_dunder_tests_dir():
    """Jest __tests__ convention."""
    assert tdd.is_test_path("src/__tests__/Login.tsx") is True


def test_is_test_path_spec_dir():
    """Ruby/Rails spec/."""
    assert tdd.is_test_path("spec/models/user_spec.rb") is True


def test_is_test_path_go_test_suffix():
    assert tdd.is_test_path("handler_test.go") is True
    assert tdd.is_test_path("pkg/foo_test.go") is True


def test_is_test_path_java_maven():
    assert tdd.is_test_path("project/src/test/java/UserTest.java") is True


def test_is_test_path_ruby_spec():
    assert tdd.is_test_path("models/user_spec.rb") is True


def test_is_test_path_windows_backslash():
    """Windows path separator normalize edilir."""
    assert tdd.is_test_path("tests\\test_foo.py") is True


def test_is_test_path_false_for_prod():
    assert tdd.is_test_path("src/main.py") is False
    assert tdd.is_test_path("src/index.ts") is False
    assert tdd.is_test_path("README.md") is False


def test_is_test_path_empty():
    assert tdd.is_test_path("") is False
    assert tdd.is_test_path(None) is False  # type: ignore[arg-type]


# ---------- is_prod_path ----------


def test_is_prod_path_python_module():
    assert tdd.is_prod_path("src/main.py") is True
    assert tdd.is_prod_path("foo.py") is True


def test_is_prod_path_typescript():
    assert tdd.is_prod_path("src/index.ts") is True
    assert tdd.is_prod_path("components/Login.tsx") is True


def test_is_prod_path_go():
    assert tdd.is_prod_path("handler.go") is True


def test_is_prod_path_rust():
    assert tdd.is_prod_path("src/main.rs") is True


def test_is_prod_path_excludes_test_files():
    """Test path olan dosya prod değil."""
    assert tdd.is_prod_path("tests/test_foo.py") is False
    assert tdd.is_prod_path("foo.test.ts") is False
    assert tdd.is_prod_path("user_test.go") is False


def test_is_prod_path_excludes_config_files():
    """Yapılandırma dosyaları TDD takibi dışı."""
    assert tdd.is_prod_path("README.md") is False
    assert tdd.is_prod_path("package.json") is False
    assert tdd.is_prod_path("docker-compose.yml") is False
    assert tdd.is_prod_path(".gitignore") is False


def test_is_prod_path_empty():
    assert tdd.is_prod_path("") is False
    assert tdd.is_prod_path(None) is False  # type: ignore[arg-type]


# ---------- record_write ----------


def test_record_write_test_path(tmp_project):
    result = tdd.record_write("tests/test_foo.py")
    assert result == "test"
    ev = audit.latest("tdd-test-write")
    assert ev is not None
    assert "tests/test_foo.py" in ev["detail"]


def test_record_write_prod_path(tmp_project):
    result = tdd.record_write("src/main.py")
    assert result == "prod"
    ev = audit.latest("tdd-prod-write")
    assert ev is not None
    assert "src/main.py" in ev["detail"]


def test_record_write_other_path(tmp_project):
    """Yapılandırma dosyaları audit'e gitmiyor."""
    result = tdd.record_write("README.md")
    assert result == "other"
    assert audit.latest("tdd-test-write") is None
    assert audit.latest("tdd-prod-write") is None


def test_record_write_empty_path(tmp_project):
    assert tdd.record_write("") == "other"
    assert tdd.record_write(None) == "other"  # type: ignore[arg-type]


def test_record_write_caller_recorded(tmp_project):
    tdd.record_write("src/foo.py", caller="post_tool")
    ev = audit.latest("tdd-prod-write")
    assert ev is not None
    assert ev["caller"] == "post_tool"


# ---------- compute_score: senaryolar ----------


def test_compute_score_no_audits_returns_none(tmp_project):
    assert tdd.compute_score() is None


def test_compute_score_only_tests_returns_none(tmp_project):
    """Henüz prod write yok → skor anlamsız."""
    audit.log_event("tdd-test-write", "post_tool", "path=test_a.py")
    audit.log_event("tdd-test-write", "post_tool", "path=test_b.py")
    assert tdd.compute_score() is None


def test_compute_score_perfect_tdd_100(tmp_project):
    """Test → Prod sırası: 100."""
    audit.log_event("tdd-test-write", "post_tool", "path=test_a.py")
    audit.log_event("tdd-prod-write", "post_tool", "path=a.py")
    audit.log_event("tdd-test-write", "post_tool", "path=test_b.py")
    audit.log_event("tdd-prod-write", "post_tool", "path=b.py")
    assert tdd.compute_score() == 100


def test_compute_score_no_test_first_zero(tmp_project):
    """Hiç test yazılmadan prod yazıldı → 0."""
    audit.log_event("tdd-prod-write", "post_tool", "path=a.py")
    audit.log_event("tdd-prod-write", "post_tool", "path=b.py")
    assert tdd.compute_score() == 0


def test_compute_score_test_after_prod_partial(tmp_project):
    """Önce 1 prod, sonra test, sonra prod: 1/2 = 50."""
    audit.log_event("tdd-prod-write", "post_tool", "path=a.py")
    audit.log_event("tdd-test-write", "post_tool", "path=test_a.py")
    audit.log_event("tdd-prod-write", "post_tool", "path=b.py")
    assert tdd.compute_score() == 50


def test_compute_score_one_test_then_many_prod(tmp_project):
    """Bir test yazıldıktan sonra hepsi compliant."""
    audit.log_event("tdd-test-write", "post_tool", "path=test_a.py")
    audit.log_event("tdd-prod-write", "post_tool", "path=a.py")
    audit.log_event("tdd-prod-write", "post_tool", "path=b.py")
    audit.log_event("tdd-prod-write", "post_tool", "path=c.py")
    assert tdd.compute_score() == 100


def test_compute_score_ignores_other_audits(tmp_project):
    """Sadece tdd-test-write + tdd-prod-write sayılır."""
    audit.log_event("phase-advance", "gate", "from=4 to=5")
    audit.log_event("tdd-test-write", "post_tool", "path=test_a.py")
    audit.log_event("asama-9-ac-1-red", "stop", "")
    audit.log_event("tdd-prod-write", "post_tool", "path=a.py")
    assert tdd.compute_score() == 100


# ---------- update_compliance_score ----------


def test_update_compliance_score_writes_state(tmp_project):
    audit.log_event("tdd-test-write", "post_tool", "path=t.py")
    audit.log_event("tdd-prod-write", "post_tool", "path=a.py")
    score = tdd.update_compliance_score()
    assert score == 100
    assert state.get("tdd_compliance_score") == 100


def test_update_compliance_score_none_keeps_state(tmp_project):
    """compute_score None ise state'e yazma."""
    state.set_field("tdd_compliance_score", 50)
    # Hiç audit yok → score None
    result = tdd.update_compliance_score()
    assert result is None
    # State değişmedi
    assert state.get("tdd_compliance_score") == 50


def test_update_compliance_score_multiple_calls(tmp_project):
    """Yeniden hesap eskisini overwrite eder."""
    audit.log_event("tdd-prod-write", "post_tool", "path=a.py")
    tdd.update_compliance_score()
    assert state.get("tdd_compliance_score") == 0
    audit.log_event("tdd-test-write", "post_tool", "path=t.py")
    audit.log_event("tdd-prod-write", "post_tool", "path=b.py")
    tdd.update_compliance_score()
    # 1 compliant / 2 total = 50
    assert state.get("tdd_compliance_score") == 50


# ---------- isolation ----------


def test_score_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "proj_a"
    b = tmp_path / "proj_b"
    a.mkdir()
    b.mkdir()
    audit.log_event("tdd-test-write", "post_tool", "p=t.py", project_root=str(a))
    audit.log_event("tdd-prod-write", "post_tool", "p=a.py", project_root=str(a))
    audit.log_event("tdd-prod-write", "post_tool", "p=b.py", project_root=str(b))
    assert tdd.compute_score(project_root=str(a)) == 100
    assert tdd.compute_score(project_root=str(b)) == 0
