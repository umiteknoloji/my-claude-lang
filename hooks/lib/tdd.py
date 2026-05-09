"""tdd — TDD compliance score (audit-driven 0-100).

Pseudocode referansı: MyCL_Pseudocode.md §2 PostToolUse (TDD desen
tespit) + §5 "TDD Uyumluluk Skoru" (Aşama 22 denetimi için).

Sözleşme:
    - post_tool.py her Write/Edit'te `record_write(path)` çağırır →
      path'e göre `tdd-test-write` veya `tdd-prod-write` audit yazılır.
    - `compute_score()` audit'leri kronolojik tarayıp ratio hesaplar:
      her prod write için önceden en az bir test write var mı?
      compliant_prod / total_prod * 100.
    - Aşama 22 hook bu skoru `state.tdd_compliance_score`'dan okur ve
      tamlık raporunda yorumlar.

Test path heuristics (regex):
    - Python: test_*.py, *_test.py, tests/, test/
    - JS/TS:  *.test.{js,jsx,ts,tsx}, *.spec.{js,jsx,ts,tsx,rb},
              __tests__/, spec/
    - Go:     *_test.go
    - Java:   **/src/test/**, *Test.java
    - Ruby:   *_spec.rb, spec/

Prod path: kod uzantılı (`.py`, `.js`, `.ts`, ...) + test değil.
Yapılandırma dosyaları (json/yaml/md) "other" — TDD takibi dışı.

API:
    is_test_path(path)        → bool
    is_prod_path(path)        → bool
    record_write(path)        → "test" | "prod" | "other"
    compute_score()           → int 0-100 veya None
    update_compliance_score() → score hesap + state'e yaz
"""

from __future__ import annotations

import re
from pathlib import Path

from hooks.lib import audit, state

# Test path pattern'leri (TR + EN dosya yolları)
_TEST_PATH_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"(^|/)test_[^/]+\.py$"),       # Python: test_foo.py
    re.compile(r"(^|/)[^/]+_test\.py$"),        # Python: foo_test.py
    re.compile(r"(^|/)tests?/"),                # tests/, test/
    re.compile(r"\.test\.(js|jsx|ts|tsx|mjs|cjs)$"),  # JS/TS *.test.*
    re.compile(r"\.spec\.(js|jsx|ts|tsx|mjs|rb)$"),   # Spec *.spec.*
    re.compile(r"(^|/)__tests__/"),             # Jest convention
    re.compile(r"(^|/)spec/"),                  # Ruby/Rails spec
    re.compile(r"_test\.go$"),                  # Go *_test.go
    re.compile(r"/src/test/"),                  # Maven/Gradle
    re.compile(r"Test\.java$"),                 # Java *Test.java
    re.compile(r"_spec\.rb$"),                  # Ruby *_spec.rb
]

# Prod kod uzantıları (test path değilse)
_CODE_EXTENSIONS: frozenset[str] = frozenset({
    ".py", ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs",
    ".java", ".kt", ".scala", ".swift",
    ".go", ".rs", ".rb", ".php",
    ".c", ".cpp", ".h", ".hpp", ".cc",
    ".cs", ".fs", ".vb",
})


def is_test_path(path: str | None) -> bool:
    """path test dosyası mı? Heuristic-based."""
    if not path or not isinstance(path, str):
        return False
    # Windows backslash normalize
    norm = path.replace("\\", "/")
    for pat in _TEST_PATH_PATTERNS:
        if pat.search(norm):
            return True
    return False


def is_prod_path(path: str | None) -> bool:
    """path prod kod mu? (test değil + kod uzantılı)."""
    if not path or not isinstance(path, str):
        return False
    if is_test_path(path):
        return False
    ext = Path(path).suffix.lower()
    return ext in _CODE_EXTENSIONS


def record_write(
    path: str | None,
    caller: str = "post_tool",
    project_root: str | None = None,
) -> str:
    """Write'ı kategoriye göre audit'e kaydet.

    Returns:
        "test" | "prod" | "other"
    """
    if not path:
        return "other"
    if is_test_path(path):
        audit.log_event(
            "tdd-test-write",
            caller,
            f"path={path}",
            project_root=project_root,
        )
        return "test"
    if is_prod_path(path):
        audit.log_event(
            "tdd-prod-write",
            caller,
            f"path={path}",
            project_root=project_root,
        )
        return "prod"
    return "other"


def compute_score(project_root: str | None = None) -> int | None:
    """TDD compliance score (0-100) veya None.

    Algoritma:
        1. Tüm audit'leri kronolojik oku
        2. Her tdd-test-write için running counter artır
        3. Her tdd-prod-write için: önceden en az bir test varsa compliant
        4. Score = (compliant_prod / total_prod) * 100

    Returns:
        0-100 int — yeterli prod write varsa
        None      — henüz prod write yok (skor anlamsız)
    """
    all_audits = audit.read_all(project_root=project_root)

    test_count_running = 0
    compliant_prod = 0
    total_prod = 0

    for ev in all_audits:
        name = ev.get("name", "")
        if name == "tdd-test-write":
            test_count_running += 1
        elif name == "tdd-prod-write":
            total_prod += 1
            if test_count_running > 0:
                compliant_prod += 1

    if total_prod == 0:
        return None
    return int((compliant_prod / total_prod) * 100)


def update_compliance_score(
    project_root: str | None = None,
) -> int | None:
    """compute_score sonucunu state'e yaz.

    None ise state'i değiştirme (mevcut değer korunur).
    """
    score = compute_score(project_root=project_root)
    if score is not None:
        state.set_field(
            "tdd_compliance_score", score, project_root=project_root
        )
    return score
