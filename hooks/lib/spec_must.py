"""spec_must — Spec MUST takibi + linked artifact graph (Disiplin #10, #11).

Pseudocode + CLAUDE.md disiplin katmanları:
    #10: Spec MUST takibi (parameter binding)
    #11: Linked artifact graph (Aşama 22 raporu)

Sözleşme:
    - Aşama 4 spec onayı sonrası `extract_and_save_must_list()` spec
      body'sinden MUST_1..MUST_N + SHOULD_1..SHOULD_N etiketleri
      çıkarır, state.spec_must_list'e yazar.
    - Sonraki faz audit'leri `covers=MUST_3,MUST_5` formatında
      `record_coverage()` ile binding ekler.
    - Aşama 22 hook `uncovered_musts()` ile kapsanmamış MUST'ları
      yüzeye çıkarır + `linked_graph()` ile MUST → audit zincirini
      raporlar.

Audit detail format:
    `<event-name> | caller | covers=MUST_1,MUST_3 ...`

Audit isimleri:
    spec-must-extracted count=N
    (sonraki audit'lerin detail'ine 'covers=' eklenir)

API:
    extract_and_save_must_list(spec_text) → list[dict]
    must_list() → list[dict]  (state'ten okur)
    must_ids() → list[str]    (sadece ID'ler)
    record_coverage(audit_name, caller, must_ids, extra_detail)
    coverage_for_must(must_id) → list[audit]
    uncovered_musts() → list[str] (kapsanmamış MUST/SHOULD ID'leri)
    linked_graph() → dict {must_id: [audit_name, ...]}
"""

from __future__ import annotations

import re

from hooks.lib import audit, spec_detect, state

_COVERS_RE = re.compile(r"covers=([A-Z_0-9,]+)")


def extract_and_save_must_list(
    spec_text: str | None,
    caller: str = "stop.py",
    project_root: str | None = None,
) -> list[dict[str, str]]:
    """spec_detect.extract_must_list + state.set_field.

    Aşama 4 spec onayı sonrası çağrılır.
    Returns:
        Etiketli liste [{id: 'MUST_1', text: '...'}, ...].
    """
    body = spec_detect.extract_body(spec_text or "")
    items = spec_detect.extract_must_list(body)
    state.set_field("spec_must_list", items, project_root=project_root)
    audit.log_event(
        "spec-must-extracted",
        caller,
        f"count={len(items)}",
        project_root=project_root,
    )
    return items


def must_list(project_root: str | None = None) -> list[dict[str, str]]:
    """state'ten must list."""
    val = state.get("spec_must_list", [], project_root=project_root)
    if not isinstance(val, list):
        return []
    return [
        i for i in val
        if isinstance(i, dict) and "id" in i
    ]


def must_ids(project_root: str | None = None) -> list[str]:
    """Sadece MUST/SHOULD ID'leri (sıralı)."""
    return [str(i["id"]) for i in must_list(project_root=project_root)]


def record_coverage(
    audit_name: str,
    caller: str,
    must_ids_covered: list[str] | None = None,
    extra_detail: str = "",
    project_root: str | None = None,
) -> None:
    """Audit yaz + detail'e `covers=MUST_3,MUST_5` ekle.

    Bu helper sonraki faz audit'leri için (Aşama 9 TDD AC, Aşama 11
    review item, Aşama 20 verify row vb.). Ana audit emit'inden
    bağımsız: ana audit'i kendi caller'ı yazar, bu helper ek binding.
    """
    if not audit_name or not caller:
        return
    parts: list[str] = []
    if must_ids_covered:
        # ID'ler büyük harf + alfanumerik; pipe yok
        clean_ids = [
            i for i in must_ids_covered
            if i and " | " not in i
        ]
        if clean_ids:
            parts.append(f"covers={','.join(clean_ids)}")
    if extra_detail:
        # extra_detail'de pipe varsa replace
        clean_extra = extra_detail.replace(" | ", " / ")
        parts.append(clean_extra)
    detail = " ".join(parts)
    audit.log_event(audit_name, caller, detail, project_root=project_root)


def _parse_covers(detail: str) -> set[str]:
    """detail string'inden 'covers=MUST_X,MUST_Y' parse."""
    m = _COVERS_RE.search(detail or "")
    if not m:
        return set()
    return {x.strip() for x in m.group(1).split(",") if x.strip()}


def coverage_for_must(
    must_id: str,
    project_root: str | None = None,
) -> list[dict[str, str]]:
    """Belirli MUST_X'i kapsayan audit'lerin listesi."""
    if not must_id:
        return []
    out: list[dict[str, str]] = []
    for ev in audit.read_all(project_root=project_root):
        if must_id in _parse_covers(ev.get("detail", "")):
            out.append(ev)
    return out


def uncovered_musts(project_root: str | None = None) -> list[str]:
    """state.spec_must_list'teki ID'lerden hiçbir audit'le kapsanmamış olanlar."""
    all_ids = set(must_ids(project_root=project_root))
    if not all_ids:
        return []
    covered: set[str] = set()
    for ev in audit.read_all(project_root=project_root):
        covered |= _parse_covers(ev.get("detail", ""))
    uncovered = all_ids - covered
    # Sıralı dön: state'teki orijinal sıraya göre
    ordered = [i for i in must_ids(project_root=project_root) if i in uncovered]
    return ordered


def linked_graph(
    project_root: str | None = None,
) -> dict[str, list[str]]:
    """MUST_X → [audit_name, ...] zinciri (Aşama 22 raporu).

    Returns:
        {must_id: [audit_name, ...]} — kapsayan audit'lerin sıralı listesi.
        Kapsanmamış MUST'lar boş list ile yer alır.
    """
    graph: dict[str, list[str]] = {i: [] for i in must_ids(project_root=project_root)}
    for ev in audit.read_all(project_root=project_root):
        covered = _parse_covers(ev.get("detail", ""))
        for must_id in covered:
            if must_id in graph:
                graph[must_id].append(ev.get("name", ""))
    return graph
