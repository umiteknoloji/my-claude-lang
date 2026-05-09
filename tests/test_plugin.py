"""hooks/lib/plugin.py birim testleri.

Kural A/B/C invariantları:
    - Kural A: git_init_consent kalıcı, tek-kez-sor-asla-tekrar-sorma
    - Kural B: curated plugin sabit liste
    - Kural C: .mcp.json içeren plugin elenir
"""

from __future__ import annotations

import pytest

from hooks.lib import plugin


# ---------- config.json read/write ----------


def test_read_config_default_when_missing(tmp_project):
    cfg = plugin.read_config()
    assert cfg["git_init_consent"] is None
    assert cfg["plugin_choices"] == {}


def test_set_config_field_persists(tmp_project):
    plugin.set_config_field("git_init_consent", "approved")
    cfg = plugin.read_config()
    assert cfg["git_init_consent"] == "approved"
    assert plugin.config_path().exists()


def test_config_atomic_write(tmp_project):
    """İki ayrı set_config_field çağrısı atomik sırayla persist."""
    plugin.set_config_field("git_init_consent", "approved")
    plugin.set_config_field("plugin_choices", {"feature-dev": "enabled"})
    cfg = plugin.read_config()
    assert cfg["git_init_consent"] == "approved"
    assert cfg["plugin_choices"] == {"feature-dev": "enabled"}


def test_config_corrupt_returns_default(tmp_project):
    p = plugin.config_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("{not valid", encoding="utf-8")
    cfg = plugin.read_config()
    assert cfg["git_init_consent"] is None


def test_config_path_uses_project_dir(tmp_project):
    p = plugin.config_path()
    assert p.parent.name == ".mycl"
    assert p.name == "config.json"


# ---------- Kural A: git_init_consent ----------


def test_is_git_repo_false_when_no_dot_git(tmp_project):
    assert plugin.is_git_repo() is False


def test_is_git_repo_true_when_dot_git_exists(tmp_project):
    (tmp_project / ".git").mkdir()
    assert plugin.is_git_repo() is True


def test_git_init_consent_default_none(tmp_project):
    assert plugin.git_init_consent() is None


def test_set_git_init_consent_approved(tmp_project):
    plugin.set_git_init_consent("approved")
    assert plugin.git_init_consent() == "approved"


def test_set_git_init_consent_declined(tmp_project):
    plugin.set_git_init_consent("declined")
    assert plugin.git_init_consent() == "declined"


def test_set_git_init_consent_invalid_rejected(tmp_project):
    with pytest.raises(ValueError):
        plugin.set_git_init_consent("yes")
    with pytest.raises(ValueError):
        plugin.set_git_init_consent("")
    with pytest.raises(ValueError):
        plugin.set_git_init_consent(None)  # type: ignore[arg-type]


def test_should_ask_no_git_no_consent(tmp_project):
    """Git yok + consent null → askq sor."""
    assert plugin.should_ask_git_init_consent() is True


def test_should_ask_git_exists_skip(tmp_project):
    """Git zaten varsa → sorma."""
    (tmp_project / ".git").mkdir()
    assert plugin.should_ask_git_init_consent() is False


def test_should_ask_consent_already_recorded(tmp_project):
    """Consent zaten kayıtlı → sorma (Kural A 'asla tekrar sorma')."""
    plugin.set_git_init_consent("approved")
    assert plugin.should_ask_git_init_consent() is False
    plugin.set_git_init_consent("declined")
    assert plugin.should_ask_git_init_consent() is False


# ---------- Kural B: curated plugins ----------


def test_curated_plugins_includes_core_set():
    plugins = plugin.curated_plugins()
    assert "feature-dev" in plugins
    assert "code-review" in plugins
    assert "pr-review-toolkit" in plugins
    assert "security-guidance" in plugins


def test_curated_plugins_returns_copy():
    """Modifiable list — ama internal CONST etkilenmez."""
    a = plugin.curated_plugins()
    b = plugin.curated_plugins()
    a.append("hacked")
    assert "hacked" not in b


def test_is_plugin_curated_true():
    assert plugin.is_plugin_curated("feature-dev") is True
    assert plugin.is_plugin_curated("code-review") is True


def test_is_plugin_curated_false():
    assert plugin.is_plugin_curated("random-plugin") is False
    assert plugin.is_plugin_curated("") is False


# ---------- Kural C: MCP filter ----------


def test_is_mcp_plugin_detects_mcp_json(tmp_path):
    plugin_root = tmp_path / "some-plugin"
    plugin_root.mkdir()
    (plugin_root / ".mcp.json").write_text('{"mcpServers": {}}', encoding="utf-8")
    assert plugin.is_mcp_plugin(plugin_root) is True


def test_is_mcp_plugin_false_when_no_mcp_json(tmp_path):
    plugin_root = tmp_path / "binary-cli-tool"
    plugin_root.mkdir()
    assert plugin.is_mcp_plugin(plugin_root) is False


def test_filter_mcp_excludes_mcp_plugins(tmp_path):
    """CLAUDE.md Kural C: .mcp.json içeren plugin elenir."""
    a = tmp_path / "feature-dev"
    a.mkdir()
    b = tmp_path / "mcp-plugin"
    b.mkdir()
    (b / ".mcp.json").write_text("{}", encoding="utf-8")
    c = tmp_path / "code-review"
    c.mkdir()
    result = plugin.filter_mcp([a, b, c])
    paths = [p.name for p in result]
    assert "feature-dev" in paths
    assert "code-review" in paths
    assert "mcp-plugin" not in paths


def test_filter_mcp_empty_input(tmp_path):
    assert plugin.filter_mcp([]) == []


# ---------- isolation ----------


def test_config_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "proj_a"
    b = tmp_path / "proj_b"
    a.mkdir()
    b.mkdir()
    plugin.set_git_init_consent("approved", project_root=str(a))
    plugin.set_git_init_consent("declined", project_root=str(b))
    assert plugin.git_init_consent(project_root=str(a)) == "approved"
    assert plugin.git_init_consent(project_root=str(b)) == "declined"


# ---------- state.py'den git_init_consent kaldırıldı (regresyon) ----------


def test_git_init_consent_not_in_state_default(tmp_project):
    """git_init_consent state.json'da değil; plugin.py config.json'da yönetiyor."""
    from hooks.lib import state
    s = state.read()
    assert "git_init_consent" not in s, (
        "git_init_consent state.py default'undan kaldırıldı; plugin.py "
        "config.json'da kanonik yönetiyor (separation of concerns)."
    )
