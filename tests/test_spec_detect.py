"""hooks/lib/spec_detect.py birim testleri.

Kritik invariantlar:
    - Line-anchored regex (prose içindeki "📋 Spec:" yanlış pozitif vermez)
    - 📋 emoji opsiyonel (v13.1.2 öğrenimi)
    - Hash stability (whitespace normalize)
    - MUST_N parameter binding (Disiplin #10)
"""

from __future__ import annotations

import hashlib

from hooks.lib import spec_detect


# ---------- contains ----------


def test_contains_with_emoji():
    text = "Birinci satır.\n\n📋 Spec:\nObjective: foo"
    assert spec_detect.contains(text) is True


def test_contains_without_emoji():
    """v13.1.2 öğrenimi: model bazen emoji yazmıyor."""
    text = "Spec:\nObjective: foo"
    assert spec_detect.contains(text) is True


def test_contains_with_heading():
    text = "## 📋 Spec (revised):\nbody"
    assert spec_detect.contains(text) is True


def test_contains_with_list_marker():
    text = "- 📋 Spec — Backoffice:\nbody"
    assert spec_detect.contains(text) is True


def test_contains_inline_prose_safe():
    """Prose içinde 'Spec:' kelimesi yanlış pozitif vermesin —
    line-anchored regex sayesinde sadece satır başı match eder."""
    text = "Bu cümlede Spec: bir kelime ama satır başı değil."
    # 'Spec:' satır başında değil → eşleşmemeli
    # Aslında split sonrası "Spec: bir kelime..." satır başında olmaz
    # ancak ilk pozisyon test edilmeli — buradaki örnek tek satır:
    assert spec_detect.contains(text) is False


def test_contains_empty_returns_false():
    assert spec_detect.contains("") is False
    assert spec_detect.contains(None) is False  # type: ignore[arg-type]


# ---------- extract_body ----------


def test_extract_body_until_next_heading():
    text = (
        "📋 Spec:\n"
        "Objective: foo\n"
        "MUST: bar\n"
        "\n"
        "## Sonraki bölüm\n"
        "Bu artık spec değil."
    )
    body = spec_detect.extract_body(text)
    assert body is not None
    assert "Objective: foo" in body
    assert "MUST: bar" in body
    assert "Sonraki bölüm" not in body


def test_extract_body_until_eof():
    text = "📋 Spec:\nObjective: foo\nMUST: bar\n"
    body = spec_detect.extract_body(text)
    assert body is not None
    assert body.endswith("MUST: bar")


def test_extract_body_picks_last_spec_when_multiple():
    """Trailing 'revise' turu: ikinci spec daha güncel."""
    text = (
        "📋 Spec:\nbody1\n\n"
        "## Sonraki\n"
        "Devam ettim.\n\n"
        "📋 Spec (revised):\nbody2"
    )
    body = spec_detect.extract_body(text)
    assert body is not None
    assert "body2" in body
    assert "body1" not in body


def test_extract_body_none_when_no_spec():
    assert spec_detect.extract_body("merhaba") is None
    assert spec_detect.extract_body("") is None


# ---------- normalize ----------


def test_normalize_squeezes_blank_lines():
    raw = "line1\n\n\n\nline2"
    norm = spec_detect.normalize(raw)
    assert norm == "line1\n\nline2"


def test_normalize_strips_trailing_whitespace():
    raw = "line1   \nline2  \nline3"
    norm = spec_detect.normalize(raw)
    assert norm == "line1\nline2\nline3"


def test_normalize_strips_leading_trailing_blank():
    raw = "\n\nline1\nline2\n\n"
    norm = spec_detect.normalize(raw)
    assert norm == "line1\nline2"


def test_normalize_empty():
    assert spec_detect.normalize("") == ""
    assert spec_detect.normalize(None) == ""  # type: ignore[arg-type]


# ---------- compute_hash ----------


def test_hash_is_sha256_hex():
    h = spec_detect.compute_hash("📋 Spec:\nObjective: foo")
    assert h is not None
    assert len(h) == 64
    assert all(c in "0123456789abcdef" for c in h)


def test_hash_stable_across_whitespace():
    """Whitespace farklı ama anlamlı içerik aynı → aynı hash."""
    h1 = spec_detect.compute_hash("📋 Spec:\nObjective: foo\n\n\nMUST: x")
    h2 = spec_detect.compute_hash("📋 Spec:\nObjective: foo\n\nMUST: x  ")
    assert h1 == h2


def test_hash_different_for_different_content():
    h1 = spec_detect.compute_hash("📋 Spec:\nfoo")
    h2 = spec_detect.compute_hash("📋 Spec:\nbar")
    assert h1 != h2


def test_hash_none_for_empty():
    assert spec_detect.compute_hash("") is None
    assert spec_detect.compute_hash(None) is None  # type: ignore[arg-type]


def test_hash_matches_manual_sha256():
    body = "Spec:\nfoo"
    norm = spec_detect.normalize(body)
    expected = hashlib.sha256(norm.encode("utf-8")).hexdigest()
    assert spec_detect.compute_hash(body) == expected


# ---------- find_and_hash ----------


def test_find_and_hash_full_pipeline():
    text = (
        "Önsöz prose\n\n"
        "📋 Spec:\n"
        "Objective: foo\n"
        "MUST: bar\n\n"
        "## Sonraki\n"
        "trailing"
    )
    h = spec_detect.find_and_hash(text)
    assert h is not None
    assert len(h) == 64


def test_find_and_hash_returns_none_when_no_spec():
    assert spec_detect.find_and_hash("no spec here") is None


# ---------- extract_must_list (Disiplin #10) ----------


def test_extract_must_list_section_form():
    body = (
        "📋 Spec:\n"
        "Objective: foo\n\n"
        "MUST Requirements:\n"
        "- Auth via session\n"
        "- RBAC three roles\n"
        "- Password bcrypt\n\n"
        "SHOULD Requirements:\n"
        "- Pagination\n"
        "- Flash messages\n\n"
        "Acceptance Criteria:\n"
        "- AC1\n"
    )
    items = spec_detect.extract_must_list(body)
    ids = [it["id"] for it in items]
    assert ids == ["MUST_1", "MUST_2", "MUST_3", "SHOULD_1", "SHOULD_2"]
    assert items[0]["text"] == "Auth via session"
    assert items[3]["text"] == "Pagination"


def test_extract_must_list_with_numeric_lists():
    body = (
        "Spec:\n"
        "MUST:\n"
        "1. First mandate\n"
        "2. Second mandate\n"
    )
    items = spec_detect.extract_must_list(body)
    assert len(items) == 2
    assert items[0]["id"] == "MUST_1"
    assert items[0]["text"] == "First mandate"


def test_extract_must_list_section_terminates_at_heading():
    body = (
        "MUST:\n"
        "- A\n"
        "- B\n"
        "\n"
        "## Other\n"
        "- C\n"  # heading sonrası — bu MUST'a girmez
    )
    items = spec_detect.extract_must_list(body)
    must_texts = [i["text"] for i in items if i["id"].startswith("MUST")]
    assert "A" in must_texts
    assert "B" in must_texts
    assert "C" not in must_texts


def test_extract_must_list_empty_when_no_section():
    assert spec_detect.extract_must_list("") == []
    assert spec_detect.extract_must_list("Spec:\nno must section here") == []


def test_extract_must_list_turkish_section_keys():
    body = (
        "Zorunlu:\n"
        "- Yetkilendirme\n"
        "- Şifre hash\n"
        "\n"
        "Önerilen:\n"
        "- Sayfalama\n"
    )
    items = spec_detect.extract_must_list(body)
    ids = [it["id"] for it in items]
    assert ids == ["MUST_1", "MUST_2", "SHOULD_1"]


# ---------- CLAUDE.md kuralı (line-anchored) ----------


def test_line_anchored_does_not_match_inline_prose():
    """CLAUDE.md kural: 'Always use a line-anchored regex...' — prose
    içindeki 'Spec:' kelimesi spec block olarak görülmez."""
    # prose şu cümle: "X kelimesi 📋 Spec: yazısını içeriyor"
    # 📋 Spec: satır başında değil → eşleşmemeli
    text = "Bir cümle: 📋 Spec: yazısı bu satırda inline."
    # Line-anchored regex bunu yakalamamalı
    # NOT: text tek satır; "📋 Spec:" başında non-whitespace prose var.
    # Regex `^[ \t]*` allow eder ama prose'la başlayan satırda match
    # vermez (regex `^` line başı, başında boşluk değil "Bir" var).
    assert spec_detect.contains(text) is False


# ---------- H-1: inline fallback ----------


def test_extract_must_list_inline_fallback_uppercase_only():
    """H-1 fix: section yoksa büyük harf MUST inline taranır."""
    body = (
        "📋 Spec: Todo App\n\n"
        "Uygulama kullanıcı login MUST sağlamalıdır.\n"
        "Sistem SHOULD pagination desteklemelidir.\n"
    )
    items = spec_detect.extract_must_list(body)
    assert len(items) >= 1
    ids = [it["id"] for it in items]
    assert "MUST_1" in ids


def test_extract_must_list_inline_lowercase_not_matched():
    """H-1 fix: küçük harf 'must'/'should' false-positive üretmemeli."""
    body = "Spec:\nno must section here"
    items = spec_detect.extract_must_list(body)
    assert items == []


def test_extract_must_list_section_takes_priority_over_inline():
    """H-1: section var → sadece section öğeleri döner."""
    body = (
        "📋 Spec: App\n\n"
        "MUST Requirements:\n"
        "- Section item A\n\n"
        "Uygulama MUST yedekleme yapmalıdır.\n"
    )
    items = spec_detect.extract_must_list(body)
    texts = [it["text"] for it in items]
    assert "Section item A" in texts
