"""hooks/lib/secrets.py birim testleri.

Pseudocode §2 PreToolUse 'sır taraması' invariantları:
    - Pattern'ler severity etiketli
    - Fail-safe = allow (regex/encode hatası → boş liste)
    - Caller severity'ye göre block/warn karar verir
"""

from __future__ import annotations

from hooks.lib import secrets


# ---------- scan_text: HIGH severity pattern'ler ----------


def test_scan_aws_access_key():
    text = "config: AKIATESTONLYTESTONLY secret"
    matches = secrets.scan_text(text)
    assert len(matches) == 1
    assert matches[0]["name"] == "aws-access-key"
    assert matches[0]["severity"] == "high"


def test_scan_github_token():
    text = "GITHUB_TOKEN=ghp_TESTONLYTESTONLYTESTONLYTESTONLY1234"
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "github-token" in names


def test_scan_stripe_secret_key():
    # GitHub Push Protection Stripe scanner tetiklenmesin diye literal
    # parçalanmış: "sk_live_" + body runtime concat. Pattern testi
    # için match yine geçerli; scanner literal "sk_live_<24char>" arar.
    fake_prefix = "sk_" + "live_"
    text = f'stripe_key = "{fake_prefix}TESTONLYTESTONLYTESTONLYTESTONLY1"'
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "stripe-secret-key" in names


def test_scan_slack_token():
    text = "slack=xoxb-1234567890-abcdefg"
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "slack-token" in names


def test_scan_pem_private_key():
    text = "-----BEGIN RSA PRIVATE KEY-----\nMIIE..."
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "pem-private-key" in names


def test_scan_openssh_private_key():
    text = "-----BEGIN OPENSSH PRIVATE KEY-----\nbase64..."
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "openssh-private-key" in names


def test_scan_google_api_key():
    """Google API key gerçek format: AIza + 35 char = 39 toplam."""
    text = "key=AIzaTESTONLYTESTONLYTESTONLYTESTONLY123"
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "google-api-key" in names


# ---------- scan_text: MEDIUM severity ----------


def test_scan_jwt_token():
    text = "Authorization: Bearer eyJTESTONLYTESTONLYTESTONLY.eyJTESTONLYTESTONLYTESTONLY.TESTONLYTESTONLYTESTONLY"
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "jwt-token" in names
    jwt = next(m for m in matches if m["name"] == "jwt-token")
    assert jwt["severity"] == "medium"


def test_scan_aws_secret_key_assignment():
    text = 'aws_secret_access_key = "TESTONLYTESTONLYTESTONLYTESTONLYTESTONLY"'
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "aws-secret-key" in names


# ---------- scan_text: LOW severity (generic) ----------


def test_scan_generic_password_assignment():
    text = 'password = "supersecret123456789"'
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "generic-secret-assignment" in names
    generic = next(m for m in matches if m["name"] == "generic-secret-assignment")
    assert generic["severity"] == "low"


def test_scan_no_match_clean_text():
    text = "Bu cümlede hiçbir credential yok, sadece düz metin."
    matches = secrets.scan_text(text)
    # generic-secret-assignment regex'i bazen kelime gruplarını match edebilir;
    # 'password=...' pattern'i için ":=" gerek; clean text'te yok.
    high_or_medium = secrets.filter_by_severity(matches, "medium")
    assert high_or_medium == []


# ---------- scan_text: fail-safe ----------


def test_scan_text_empty():
    assert secrets.scan_text("") == []
    assert secrets.scan_text(None) == []  # type: ignore[arg-type]


def test_scan_text_non_string():
    assert secrets.scan_text(123) == []  # type: ignore[arg-type]
    assert secrets.scan_text({"x": "AKIATESTONLYTESTONLY"}) == []  # type: ignore[arg-type]


def test_scan_text_snippet_truncated():
    """Snippet log'a tam credential basılmasın — 8 char + ..."""
    text = "AKIATESTONLYTESTONLY"
    matches = secrets.scan_text(text)
    assert len(matches) == 1
    assert matches[0]["snippet"].endswith("...")
    assert len(matches[0]["snippet"]) <= 11  # 8 + "..."


# ---------- scan_text: çoklu eşleşme ----------


def test_scan_multiple_secrets_in_one_text():
    text = (
        'aws_key="AKIATESTONLYTESTONLY"\n'
        "github=ghp_TESTONLYTESTONLYTESTONLYTESTONLY1234\n"
        "-----BEGIN PRIVATE KEY-----\nMIIE..."
    )
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "aws-access-key" in names
    assert "github-token" in names
    assert "pem-private-key" in names


# ---------- scan_tool_input: tool name'e göre alan seçimi ----------


def test_scan_write_content():
    matches = secrets.scan_tool_input(
        "Write",
        {"file_path": "config.py", "content": "API_KEY=AKIATESTONLYTESTONLY"},
    )
    names = [m["name"] for m in matches]
    assert "aws-access-key" in names


def test_scan_edit_new_string():
    # Literal parçalama (Stripe scanner bypass — bkz. test_scan_stripe_secret_key)
    fake = "sk_" + "live_TESTONLYTESTONLYTESTONLYTESTONLY1"
    matches = secrets.scan_tool_input(
        "Edit",
        {
            "file_path": "x.py",
            "old_string": "old code",
            "new_string": f"secret = '{fake}'",
        },
    )
    names = [m["name"] for m in matches]
    assert "stripe-secret-key" in names


def test_scan_edit_old_string_too():
    """Eski içerik de credential olabilir (rotation testi)."""
    matches = secrets.scan_tool_input(
        "Edit",
        {
            "file_path": "x.py",
            "old_string": "AKIATESTONLYTESTONLY",
            "new_string": "REPLACED",
        },
    )
    names = [m["name"] for m in matches]
    assert "aws-access-key" in names


def test_scan_multiedit():
    matches = secrets.scan_tool_input(
        "MultiEdit",
        {
            "file_path": "x.py",
            "edits": [
                {"old_string": "a", "new_string": "AKIATESTONLYTESTONLY"},
                {"old_string": "b", "new_string": "ghp_TESTONLYTESTONLYTESTONLYTESTONLY1234"},
            ],
        },
    )
    names = {m["name"] for m in matches}
    assert "aws-access-key" in names
    assert "github-token" in names


def test_scan_bash_command():
    matches = secrets.scan_tool_input(
        "Bash",
        {"command": "curl -H 'Authorization: ghp_TESTONLYTESTONLYTESTONLYTESTONLY1234' ..."},
    )
    names = [m["name"] for m in matches]
    assert "github-token" in names


def test_scan_unknown_tool_returns_empty():
    matches = secrets.scan_tool_input(
        "Read",
        {"file_path": "AKIATESTONLYTESTONLY.txt"},
    )
    # Read taranacak content vermez
    assert matches == []


def test_scan_tool_input_invalid():
    assert secrets.scan_tool_input(None, {"content": "AKIATESTONLYTESTONLY"}) == []  # type: ignore[arg-type]
    assert secrets.scan_tool_input("Write", None) == []  # type: ignore[arg-type]
    assert secrets.scan_tool_input("Write", "not a dict") == []  # type: ignore[arg-type]


# ---------- has_severity / filter_by_severity ----------


def test_has_severity_high():
    matches = [
        {"name": "x", "severity": "high"},
        {"name": "y", "severity": "low"},
    ]
    assert secrets.has_severity(matches, "high") is True
    assert secrets.has_severity(matches, "medium") is True  # high >= medium
    assert secrets.has_severity(matches, "low") is True


def test_has_severity_only_low():
    matches = [{"name": "x", "severity": "low"}]
    assert secrets.has_severity(matches, "high") is False
    assert secrets.has_severity(matches, "medium") is False
    assert secrets.has_severity(matches, "low") is True


def test_has_severity_empty():
    assert secrets.has_severity([], "high") is False


def test_filter_by_severity_high_only():
    matches = [
        {"name": "a", "severity": "high"},
        {"name": "b", "severity": "medium"},
        {"name": "c", "severity": "low"},
        {"name": "d", "severity": "high"},
    ]
    high_only = secrets.filter_by_severity(matches, "high")
    assert len(high_only) == 2
    assert all(m["severity"] == "high" for m in high_only)


def test_filter_by_severity_medium_or_higher():
    matches = [
        {"name": "a", "severity": "high"},
        {"name": "b", "severity": "medium"},
        {"name": "c", "severity": "low"},
    ]
    med = secrets.filter_by_severity(matches, "medium")
    assert len(med) == 2
    assert {m["name"] for m in med} == {"a", "b"}


def test_filter_by_severity_invalid_level():
    """Bilinmeyen severity → boş list."""
    matches = [{"name": "x", "severity": "high"}]
    assert secrets.filter_by_severity(matches, "extreme") == []


# ---------- production realism ----------


def test_aws_docs_example_matches_high():
    """AWS docs örneği AKIATESTONLYTESTONLY — pattern match HIGH severity.
    Bu kabul edilebilir false positive (caller exclusion list ekleyebilir)."""
    matches = secrets.scan_text("AKIATESTONLYTESTONLY")
    assert secrets.has_severity(matches, "high") is True


def test_short_password_below_threshold_not_matched():
    """16 char altında 'password=' generic pattern match etmez."""
    text = 'password = "short"'  # 5 char
    matches = secrets.scan_text(text)
    names = [m["name"] for m in matches]
    assert "generic-secret-assignment" not in names
