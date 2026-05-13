"""spec_detect — Spec bloğu tespit, body normalize, SHA256, MUST_N extract.

Pseudocode referansı: MyCL_Pseudocode.md §2 Stop hook adım 1
(spec_hash hesapla, state'e yaz) + §3 Aşama 4 (15+ yıllık kıdemli
mühendis kalitesinde 📋 Spec: bloğu) + Disiplin #10 (Spec MUST takibi
parameter binding).

CLAUDE.md kural: line-anchored regex MULTILINE, opsiyonel başta
boşluk / liste işareti / heading marker. Loose `search` kullanılmaz
(prose içindeki "📋 Spec:" referansı yanlış pozitif vermesin).

v13.1.2 öğrenimi: 📋 emoji **opsiyonel** — model kimi zaman düz
"Spec:" yazıyor (cached prompt). Hook her iki formu da yakalar.

API:
    contains(text)              — text spec bloğu içeriyor mu?
    extract_body(text)          — spec başlığından heading'e kadar gövde
    normalize(body)             — whitespace squeeze
    compute_hash(body)          — SHA256 hex (64 char)
    extract_must_list(body)     — MUST_N + SHOULD_N etiketli liste
"""

from __future__ import annotations

import hashlib
import re
from typing import Optional

# Spec başlığı — line-anchored, emoji opsiyonel.
# Eşleşen formlar: "📋 Spec:", "Spec:", "## 📋 Spec (revised):",
# "- 📋 Spec — Web App:", "Spec — Backoffice:".
SPEC_LINE_RE = re.compile(
    r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?(?:\U0001F4CB[ \t]+)?Spec\b[^\n:]*:",
    re.MULTILINE,
)

# 1.0.37: Aşama 1 niyet özeti başlığı — line-anchored, emoji opsiyonel.
# Aşama 4 spec marker'ıyla simetrik. Eşleşen formlar:
# "🎯 Niyet özeti:", "Niyet özeti:", "## 🎯 Intent summary:",
# "- 🎯 Intent summary —:", "Intent summary — TODO app:".
INTENT_SUMMARY_LINE_RE = re.compile(
    r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?(?:\U0001F3AF[ \t]+)?"
    r"(?:Niyet özeti|Intent summary)\b[^\n:]*:",
    re.MULTILINE | re.IGNORECASE,
)

# Yeni heading body'nin sonu: line başında # ile başlar
HEADING_RE = re.compile(r"^#+\s", re.MULTILINE)


def contains(text: str) -> bool:
    """text içinde spec başlığı var mı? Line-anchored, prose-safe."""
    if not text:
        return False
    return SPEC_LINE_RE.search(text) is not None


def contains_intent_summary(text: str) -> bool:
    """1.0.37: text içinde Aşama 1 niyet özeti başlığı var mı?

    Aşama 1 skill kontratı: "Tüm değişkenler net olunca özet hazırla
    + AskUserQuestion onay". Marker olmayan özet, prose içinde
    karışabilir; line-anchored regex prose-safe detection sağlar.
    Aşama 4 `contains` deseniyle simetrik.
    """
    if not text:
        return False
    return INTENT_SUMMARY_LINE_RE.search(text) is not None


def extract_body(text: str) -> Optional[str]:
    """Spec başlığından bir sonraki heading'e (veya EOF'a) kadar gövde.

    Trailing prose (örn. "Şimdi spec'i yazıyorum") spec'i gizleyemez —
    SPEC_LINE_RE en son spec başlığını bulur.
    """
    if not text:
        return None
    matches = list(SPEC_LINE_RE.finditer(text))
    if not matches:
        return None
    # En son spec block ile başla
    m = matches[-1]
    start = m.start()
    # spec başlığından sonraki kısım
    rest = text[start:]
    lines = rest.splitlines()
    if not lines:
        return None
    body_lines = [lines[0]]  # spec başlık satırı
    for line in lines[1:]:
        if HEADING_RE.match(line):
            break
        body_lines.append(line)
    body = "\n".join(body_lines).rstrip()
    return body if body else None


def normalize(body: str) -> str:
    """Whitespace normalize:

    - Her satırın trailing whitespace'i strip
    - Ardışık boş satırları tek boş satıra indir
    - Body başı/sonu boş satırlar temizle

    Hash stability için zorunlu — aynı spec farklı whitespace ile
    farklı hash üretmesin.
    """
    if not body:
        return ""
    lines = [ln.rstrip() for ln in body.splitlines()]
    out: list[str] = []
    prev_blank = False
    for ln in lines:
        if not ln:
            if not prev_blank:
                out.append("")
            prev_blank = True
        else:
            out.append(ln)
            prev_blank = False
    return "\n".join(out).strip()


def compute_hash(body: str | None) -> Optional[str]:
    """Spec body → SHA256 hex digest (64 char). Boş body → None."""
    if not body:
        return None
    norm = normalize(body)
    if not norm:
        return None
    return hashlib.sha256(norm.encode("utf-8")).hexdigest()


def find_and_hash(text: str) -> Optional[str]:
    """Convenience: text → body → hash. Stop hook tek çağrı."""
    body = extract_body(text)
    return compute_hash(body)


# ---------- MUST_N extractor (Disiplin #10) ----------


_MUST_SECTION_RE = re.compile(
    r"^[ \t]*(?:#+[ \t]+)?(?:MUST(?:[ \t]+Requirements)?|MUST'lar|Zorunlu|Mandatory)[ \t]*:?[ \t]*$",
    re.MULTILINE | re.IGNORECASE,
)
_SHOULD_SECTION_RE = re.compile(
    r"^[ \t]*(?:#+[ \t]+)?(?:SHOULD(?:[ \t]+Requirements)?|SHOULD'lar|Önerilen|Recommended)[ \t]*:?[ \t]*$",
    re.MULTILINE | re.IGNORECASE,
)
_LIST_ITEM_RE = re.compile(
    r"^[ \t]*(?:[-*+][ \t]+|\d+\.[ \t]+)(.+?)$",
    re.MULTILINE,
)
# Bir bölümün sonu: yeni heading veya yeni "Capitalized Section:" etiketi.
# Unicode-aware: Türkçe başlıklar (Önerilen:, Zorunlu:, Şartlar:) ASCII
# `[A-Z]` ile yakalanmıyordu → bug, test_turkish_section_keys çakıyordu.
# `[^\W\d_]` UNICODE letter, `[\w ]` Türkçe karakter dahil.
_SECTION_TERM_RE = re.compile(
    r"^[ \t]*(?:#+[ \t]+|[^\W\d_][\w ]*:[ \t]*$)",
    re.MULTILINE | re.UNICODE,
)
# H-1 inline fallback: "X MUST Y" ve "X SHOULD Y" satır kalıpları
# spec_must_extractor.json'daki must_inline_marker / should_inline_marker.
# Section bulunamazsa devreye girer.
# NOT: Case-sensitive (sadece BÜYÜK HARF) — küçük harf 'must'/'should'
# doğal dil cümlelerde çok sık geçer, false-positive üretir.
_MUST_INLINE_RE = re.compile(
    r"\b(?:MUST|SHALL|REQUIRED)\b\s+(.+?)(?:\.|$)",
    re.MULTILINE,
)
_SHOULD_INLINE_RE = re.compile(
    r"\b(?:SHOULD|RECOMMENDED|OUGHT)\b\s+(.+?)(?:\.|$)",
    re.MULTILINE,
)


def _extract_section_items(body: str, section_re: re.Pattern[str]) -> list[str]:
    """body içinde section başlığı bul, ardından list_item'ları topla."""
    m = section_re.search(body)
    if not m:
        return []
    rest = body[m.end():]
    term = _SECTION_TERM_RE.search(rest)
    section_text = rest[:term.start()] if term else rest
    return [li.group(1).strip() for li in _LIST_ITEM_RE.finditer(section_text)]


def extract_must_list(body: str | None) -> list[dict[str, str]]:
    """Spec body'den MUST_N + SHOULD_N etiketli liste çıkar.

    Output formatı state.spec_must_list ile aynı:
        [{"id": "MUST_1", "text": "..."}, ...]

    Aşama 4 spec onayı sonrası state'e yazılır; sonraki faz audit'leri
    `covers=MUST_3,MUST_5` ile bu listedeki ID'lere referans verir.
    Aşama 22 hook kapsanmamış MUST'ları yüzeye çıkarır.

    Strateji (H-1 fix):
        1. Section-based: "MUST Requirements:" başlığı altındaki maddeleri çıkar.
        2. Inline fallback (spec_must_extractor.json): Section bulunamazsa
           "X MUST Y" / "X SHOULD Y" satır kalıpları taranır.
    """
    if not body:
        return []
    items: list[dict[str, str]] = []
    must_texts = _extract_section_items(body, _MUST_SECTION_RE)
    should_texts = _extract_section_items(body, _SHOULD_SECTION_RE)

    # Inline fallback: section bulunamazsa satır içi MUST/SHOULD kalıpları
    if not must_texts:
        must_texts = [
            m.group(1).strip()
            for m in _MUST_INLINE_RE.finditer(body)
            if m.group(1).strip()
        ]
    if not should_texts:
        should_texts = [
            m.group(1).strip()
            for m in _SHOULD_INLINE_RE.finditer(body)
            if m.group(1).strip()
        ]

    for i, txt in enumerate(must_texts, 1):
        items.append({"id": f"MUST_{i}", "text": txt})
    for i, txt in enumerate(should_texts, 1):
        items.append({"id": f"SHOULD_{i}", "text": txt})
    return items
