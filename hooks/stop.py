#!/usr/bin/env python3
"""stop — Stop hook (faz advance motoru).

Pseudocode §2 Stop:
    1. Self-project guard
    2. Transcript son assistant text → spec_detect → spec_hash + MUST_N
       state'e yaz (line-anchored, emoji opsiyonel)
    3. Son AskUserQuestion tool_use + tool_result eşleştir → askq intent
       classify (approve/revise/cancel)
    4. Aşama 4 spec onay özel akışı:
         intent=approve + spec_hash + current_phase=4 →
         spec_approved=True + audit chain auto-fill (Aşama 1, 2, 3, 4)
    5. Universal completeness loop:
         while phase_complete(current): gate.advance(); current = state.current_phase
       (audit-driven sıralı walk; her tur +1; CLAUDE.md sequence invariantı.)
    6. Phase-done audit (advance sonrası DSI'da bir sonraki turda görünür)

Faz-spesifik mercekler (Aşama 6 sunucu+tarayıcı, Aşama 10/19/20
enforcement, Aşama 22 hook-yazılı tamlık raporu) 1.0.x'te detaylanır;
1.0.0 motorun çekirdeği — askq onay zinciri + completeness loop.

Stop hook output:
    Claude Code Stop event sessiz olabilir — yan etkiler (state, audit)
    asıl değer. Output boş = "continue" (default). 1.0.0'da Stop hook
    block etmez; sadece state/audit mutate eder.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from hooks.lib import (  # noqa: E402
    activation, askq, audit, gate, orchestrator, spec_detect, state,
    transcript,
)


def _is_self_project(project_dir: str) -> bool:
    repo_path = os.environ.get("MYCL_REPO_PATH") or str(Path.home() / "my-claude-lang")
    try:
        cwd = Path(project_dir).resolve()
        myc = Path(repo_path).resolve()
    except OSError:
        return False
    return cwd == myc


def _read_input() -> dict:
    try:
        raw = sys.stdin.read()
    except (OSError, ValueError):
        return {}
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


# ---------- spec hash detect ----------


def _detect_and_store_spec(transcript_path: str, project_dir: str) -> str | None:
    """Transcript son assistant text'inde spec varsa hash + MUST listele.

    Returns: yeni spec_hash (yazıldıysa) veya None.
    """
    if not transcript_path:
        return None
    text = transcript.last_assistant_text(transcript_path)
    if not text or not spec_detect.contains(text):
        return None
    body = spec_detect.extract_body(text)
    if not body:
        return None
    normalized = spec_detect.normalize(body)
    new_hash = spec_detect.compute_hash(normalized)
    if new_hash is None:
        return None
    current_hash = state.get("spec_hash", project_root=project_dir)
    if current_hash == new_hash:
        return None
    must_list = spec_detect.extract_must_list(body)
    state.update(
        {"spec_hash": new_hash, "spec_must_list": must_list},
        project_root=project_dir,
    )
    audit.log_event(
        "spec-hash-stored", "stop.py",
        f"hash={new_hash[:12]} must_count={len(must_list)}",
        project_root=project_dir,
    )
    return new_hash


# ---------- askq intent ----------


def _detect_askq_intent(transcript_path: str) -> str | None:
    """Transcript'in son AskUserQuestion sonucundan intent çıkar.

    AskQ tool_result yoksa son user mesajı düz text olarak classify edilir
    (H-2 fix: kullanıcı normal chat'te 'tamam' yazarsa da onay detect edilir).

    Returns: "approve" | "revise" | "cancel" | "ambiguous" | None
    """
    if not transcript_path:
        return None
    _, result = transcript.latest_askq_pair(transcript_path)
    if result is not None:
        return askq.classify_tool_result(result)
    # Fallback: AskQ tool_result yok → son user mesajı text'ini classify et
    user_text = transcript.last_user_text(transcript_path)
    if not user_text:
        return None
    intent = askq.classify(user_text)
    # Ambiguous'u None olarak döndür — belirsiz intent action tetiklememeli
    return intent if intent != askq.INTENT_AMBIGUOUS else None


# ---------- Aşama 4 spec-approve flow ----------


def _spec_approve_flow(project_dir: str) -> bool:
    """Aşama 4 spec onayı işle.

    Koşullar:
      - state.current_phase == 4
      - state.spec_hash mevcut (None değil)
      - state.spec_approved == False (idempotent guard)

    Yan etkiler (atomik):
      - state.spec_approved = True
      - audit chain auto-fill: asama-1-complete, asama-2-complete,
        asama-3-complete (varsa atla), asama-4-complete

    Returns: yeni onay yapıldıysa True, no-op ise False.
    """
    cp = state.get("current_phase", 1, project_root=project_dir)
    if cp != 4:
        return False
    spec_hash = state.get("spec_hash", project_root=project_dir)
    if not spec_hash:
        return False
    if state.get("spec_approved", False, project_root=project_dir):
        return False

    state.set_field("spec_approved", True, project_root=project_dir)

    # Audit chain auto-fill — aşağı sıralı (idempotent: zaten varsa atla)
    existing = {ev.get("name") for ev in audit.read_all(project_root=project_dir)}
    for n in (1, 2, 3, 4):
        name = f"asama-{n}-complete"
        if name not in existing:
            audit.log_event(
                name, "stop.py",
                f"spec-approve-chain hash={spec_hash[:12]}",
                project_root=project_dir,
            )
    return True


# ---------- universal completeness loop ----------


def _run_completeness_loop(project_dir: str) -> int:
    """Audit-driven sıralı faz advance.

    Her iterasyonda:
      1. current_phase oku
      2. silent_phase: true ise ve required audit yoksa hook otomatik
         emit (1.0.14 — pseudocode "hook auto-completes" tasarımı,
         önceden gate_spec flag tanımlıydı ama hiçbir hook okumuyordu)
      3. gate.is_phase_complete (required_audits_any var mı audit'te?)
      4. Var → gate.advance() → +1
      5. Yok → break

    Returns: tamamlanan advance sayısı.
    """
    spec = gate.load_gate_spec()
    advance_count = 0
    # Sonsuz döngü koruması: max 22 iterasyon
    for _ in range(22):
        cp = state.get("current_phase", 1, project_root=project_dir)
        if cp >= 22:
            break
        phase_def = spec.get("phases", {}).get(str(cp), {})
        if isinstance(phase_def, dict) and phase_def.get("silent_phase"):
            _silent_phase_auto_emit(cp, phase_def, project_dir)
        if not _is_phase_complete(cp, project_dir):
            break
        gate.advance(project_root=project_dir, caller="stop.py")
        advance_count += 1
    return advance_count


def _silent_phase_auto_emit(
    phase: int, phase_def: dict, project_dir: str,
) -> None:
    """Silent phase için hook otomatik audit emit.

    Pseudocode: SESSİZ faz (Aşama 3 Mühendislik Özeti) — model
    `asama-N-complete` emit etmez, askq açılmaz; hook universal
    completeness loop sırasında otomatik geçirir.

    Implementation gap (1.0.14 öncesi): `silent_phase: true` flag
    `gate_spec.json`'da tanımlıydı ama hiçbir hook okumuyordu →
    Aşama 3 `required_audits_any` (`asama-3-complete` veya
    `engineering-brief`) hiçbir yerden yazılmıyor → completeness
    loop break → state cp=3'te stuck → Aşama 4 spec onayı askq'sı
    `_spec_approve_flow`'un `cp == 4` kontrolüne takılıyor →
    `spec_approved=False` → Bash deny.

    Strategy: `required_audits_any` listesindeki **ilk** audit'i
    hook yazar (gate_spec.json'da semantic sıralı tanımlanmış —
    Aşama 3 için `["asama-3-complete", "engineering-brief"]`).
    Audit zaten varsa no-op (idempotent). CLAUDE.md sequential
    invariant'a uyumlu — sentinel atlama yok, `gate.advance()`
    bir sonraki iterasyonda normal akışla çalışır.
    """
    required_all = phase_def.get("required_audits_all") or []
    required_any = phase_def.get("required_audits_any") or []
    if not required_all and not required_any:
        return
    existing = {
        ev.get("name") for ev in audit.read_all(project_root=project_dir)
    }
    if required_all:
        # _all (AND): hepsi varsa idempotent no-op; değilse eksiklerin
        # **hepsini** tek seferde yaz (bir sonraki completeness check'in
        # geçmesi için zorunlu, yoksa loop break + faz stuck).
        if all(name in existing for name in required_all):
            return
        for name in required_all:
            if name not in existing:
                audit.log_event(
                    name, "stop.py",
                    f"silent-phase-auto-emit phase={phase}",
                    project_root=project_dir,
                )
                existing.add(name)
        return
    # _any (OR): biri varsa idempotent no-op; değilse listenin ilkini yaz
    # (gate_spec.json'da semantic sıralı tanımlanmış).
    if any(name in existing for name in required_any):
        return
    audit.log_event(
        required_any[0], "stop.py",
        f"silent-phase-auto-emit phase={phase}",
        project_root=project_dir,
    )


def _is_phase_complete(phase: int, project_dir: str) -> bool:
    """Faz `phase` için required audit'ler log'da var mı?

    1.0.17: `required_audits_all` öncelikli (AND mantığı — Aşama 2
    `precision-audit + asama-2-complete` ikisi de yazılmalı, OR
    bypass riski kapatılır). Yoksa `required_audits_any` fallback
    (OR mantığı — diğer fazlar).
    """
    spec = gate.load_gate_spec()
    phase_def = spec.get("phases", {}).get(str(phase))
    if not isinstance(phase_def, dict):
        return False
    existing = {ev.get("name") for ev in audit.read_all(project_root=project_dir)}
    required_all = phase_def.get("required_audits_all") or []
    if required_all:
        return all(name in existing for name in required_all)
    required = phase_def.get("required_audits_any") or []
    if not required:
        return False
    return any(name in existing for name in required)


# ---------- text trigger phase complete ----------


_PHASE_COMPLETE_TRIGGER_RE = re.compile(r"asama-(\d+)-complete", re.IGNORECASE)

# 1.0.20: Aşama 5 emit metninde `pattern-summary: <özet>` satırı varsa
# state.pattern_summary'e yaz. Skill'de model formatı: `pattern-summary:
# camelCase, try-catch, jest fixtures`. Aşama 9 DSI bu özeti her turda
# hatırlatır (dsi.render_pattern_rules_notice).
_PATTERN_SUMMARY_RE = re.compile(
    r"^[ \t]*pattern-summary:[ \t]*(.+?)[ \t]*$",
    re.MULTILINE | re.IGNORECASE,
)
# `[ \t]*` (newline yok) — `\s*` newline yutar ve sonraki satırı yanlışlıkla
# yakalardı. Sadece tab/space whitespace, satır içi.

# 1.0.21: Generic extended phase trigger — `complete` dışındaki suffix'leri
# yakalar. Mevcut `_PHASE_COMPLETE_TRIGGER_RE` sadece "complete" suffix.
# Pseudocode'da diğer çıktılar: skipped (5, 6, 7, 21), end (6, 8),
# end-green (15-17), end-target-met (18), not-applicable (8, 15-18, 22).
# Önemli sıralama: "end-target-met" ve "end-green" "end"den ÖNCE — longest
# match (regex alternation greedy değil; ilk match kazanır).
_PHASE_EXTENDED_TRIGGER_RE = re.compile(
    r"asama-(\d+)-(end-target-met|end-green|skipped|not-applicable|end)"
    r"\b(?:[ \t]+(\S[^\n]*))?",
    re.IGNORECASE,
)


def _extract_pattern_summary(text: str, project_dir: str) -> bool:
    """`pattern-summary: <özet>` satırı varsa state'e yaz.

    Returns: True if extracted + written; False otherwise (idempotent —
    aynı özet tekrar yazılır, no-op değil — model güncellerse override).
    """
    if not text:
        return False
    m = _PATTERN_SUMMARY_RE.search(text)
    if not m:
        return False
    summary = m.group(1).strip()
    if not summary:
        return False
    state.set_field("pattern_summary", summary, project_root=project_dir)
    return True


def _detect_phase_complete_trigger(
    transcript_path: str, project_dir: str,
) -> bool:
    """Modelin son cevabında `asama-N-complete` varsa kayıt at.

    Üç durum:
      - N == cp → audit emit (idempotent).
      - N > cp  → gerçek atlama denemesi → `phase-skip-attempt`
        audit (görünür sinyal, sıralılık invariant'ı korunur).
      - N < cp  → stale-emit (faz zaten geçilmiş, model özet
        amaçlı eski etiketi tekrar yazmış) → SESSİZ, audit yazma.
        Bu durum sıralılık ihlali değil; gürültü olmasın diye log
        edilmez.

    Trigger içeren EN SON assistant text turn'ünü tarar —
    `last_assistant_text` turn1'de emit + turn2 prose senaryosunda
    gölgelenirdi. `_detect_and_store_spec` `last_assistant_text`
    kullanmaya devam eder (kasıtlı: spec son-turn semantiği).

    Aşama 4 chain auto-fill bu fonksiyonla paralel kanaldır; ikisi
    çakışırsa idempotent (aynı audit varsa no-op).

    Returns: yeni audit yazıldıysa True.
    """
    if not transcript_path:
        return False
    text = transcript.find_last_assistant_text_matching(
        lambda t: bool(_PHASE_COMPLETE_TRIGGER_RE.search(t)),
        transcript_path,
    )
    if not text:
        return False
    matches = _PHASE_COMPLETE_TRIGGER_RE.findall(text)
    if not matches:
        return False
    cp = state.get("current_phase", 1, project_root=project_dir)
    existing = {ev.get("name") for ev in audit.read_all(project_root=project_dir)}
    # Dedupe + ascending sort — model tek cevapta `asama-5-complete
    # asama-6-complete asama-7-complete` zinciri yazarsa her birini
    # sıralı işle. 1.0.13 öncesi `cp` lokal güncellenmiyor, sadece
    # ilki audit olup kalanı `phase-skip-attempt` oluyordu → DSI bir
    # sonraki turda yanlış fazda kalıyor, model self-debug paniği.
    unique_nums = sorted({
        int(n_str) for n_str in matches if n_str.isdigit()
    })
    wrote = False
    for n in unique_nums:
        if n == cp:
            audit_name = f"asama-{n}-complete"
            if audit_name in existing:
                # Idempotent — audit zaten var; yine de lokal `cp`'yi
                # ilerlet ki zincirdeki sonraki trigger'lar düşmesin.
                cp = n + 1
                continue
            audit.log_event(
                audit_name, "stop.py",
                f"text-trigger-emit phase={n}",
                project_root=project_dir,
            )
            existing.add(audit_name)
            wrote = True
            # 1.0.17: side_audits — fazın yan audit'leri hook paralel
            # emit eder (model yazmaz). Aşama 2 için `precision-audit`
            # gibi. Generic feature; gate_spec'te `side_audits` listesi
            # tanımlanmış fazlar için fire eder.
            spec_def = gate.load_gate_spec().get("phases", {}).get(str(n))
            side_audits = (
                spec_def.get("side_audits", [])
                if isinstance(spec_def, dict) else []
            )
            for side_name in side_audits:
                if side_name in existing:
                    continue
                audit.log_event(
                    side_name, "stop.py",
                    f"side-audit-emit phase={n}",
                    project_root=project_dir,
                )
                existing.add(side_name)
            # 1.0.20: Aşama 5 — `pattern-summary: <özet>` satırını
            # state.pattern_summary'e yaz (DSI Aşama 9'da hatırlatır).
            if n == 5:
                _extract_pattern_summary(text, project_dir)
            cp = n + 1  # lokal advance — gerçek state advance completeness loop'ta
        elif n > cp:
            audit.log_event(
                "phase-skip-attempt", "stop.py",
                f"emit_phase={n} current_phase={cp}",
                project_root=project_dir,
            )
        # else n < cp: stale-emit, sessiz geç
    return wrote


def _phase7_ui_review_flow(intent: str | None, project_dir: str) -> bool:
    """1.0.22: Aşama 7 (UI İncelemesi — DEFERRED) intent flow.

    Pseudocode'a göre Aşama 7 askq önceden açılmaz; kullanıcının
    free-form cevabı `askq.classify` ile intent'e dönüşür. Stop hook
    cp==7'de intent'e göre:
      - approve  → asama-7-complete + ui_reviewed=True
      - cancel   → asama-7-cancelled (soft halt sinyali, hard deny değil)
      - revise   → 1.0.23'e ertelendi (audit append-only invariant
                   çelişki; cp=6 set sonrası completeness loop
                   infinite advance riski)
      - ambiguous/None → no-op (model fallback askq açabilir)

    Returns: yeni audit yazıldıysa True.
    """
    if intent is None:
        return False
    cp = state.get("current_phase", 1, project_root=project_dir)
    if cp != 7:
        return False
    existing = {
        ev.get("name") for ev in audit.read_all(project_root=project_dir)
    }
    if intent == askq.INTENT_APPROVE:
        if "asama-7-complete" in existing:
            return False  # idempotent
        state.set_field("ui_reviewed", True, project_root=project_dir)
        audit.log_event(
            "asama-7-complete", "stop.py",
            "phase7-ui-review-approve intent=approve",
            project_root=project_dir,
        )
        return True
    if intent == askq.INTENT_CANCEL:
        if "asama-7-cancelled" in existing:
            return False
        audit.log_event(
            "asama-7-cancelled", "stop.py",
            "phase7-ui-review-cancel intent=cancel — pipeline halt sinyali",
            project_root=project_dir,
        )
        return True
    # revise (1.0.23'e ertelendi) veya ambiguous: no-op
    return False


def _check_phase7_auto_skip(project_dir: str) -> bool:
    """1.0.22: Aşama 6 atlandıysa Aşama 7 otomatik atlama.

    Pseudocode: "Aşama 6 atlandıysa otomatik atlanır →
    asama-7-skipped reason=asama-6-skipped". cp==7 + asama-6-skipped
    audit var + Aşama 7 audit'i henüz yok ise hook auto-emit eder.

    Returns: auto-skip yazıldıysa True.
    """
    cp = state.get("current_phase", 1, project_root=project_dir)
    if cp != 7:
        return False
    existing = {
        ev.get("name") for ev in audit.read_all(project_root=project_dir)
    }
    if "asama-6-skipped" not in existing:
        return False
    if any(name.startswith("asama-7-") for name in existing):
        return False  # Aşama 7 zaten bir karar audit'i var
    audit.log_event(
        "asama-7-skipped", "stop.py",
        "auto-skip reason=asama-6-skipped",
        project_root=project_dir,
    )
    return True


_PHASE_9_AC_TRIGGER_RE = re.compile(
    r"\basama-9-ac-(\d+)-(red|green|refactor)\b",
    re.IGNORECASE,
)
# Line anchor yok — diğer trigger regex'leri ile tutarlı
# (_PHASE_COMPLETE_TRIGGER_RE word boundary kullanıyor).

# 1.0.25: Aşama 10 + 19 item trigger'ları — generic regex.
# Pseudocode Aşama 10 risk maddeleri + Aşama 19 etki maddeleri aynı
# yapıda: items-declared count=K, item-{n}-resolved decision=apply|skip|rule.
_PHASE_ITEMS_DECLARED_RE = re.compile(
    r"\basama-(\d+)-items-declared\s+count=(\d+)\b",
    re.IGNORECASE,
)
_PHASE_ITEM_RESOLVED_RE = re.compile(
    r"\basama-(\d+)-item-(\d+)-resolved\s+decision=(apply|skip|rule)\b",
    re.IGNORECASE,
)


def _detect_phase_9_ac_trigger(
    transcript_path: str, project_dir: str,
) -> bool:
    """1.0.24: Aşama 9 TDD AC audit'leri yakala.

    Pseudocode: her AC için 3 audit (red/green/refactor). Mevcut
    `_PHASE_COMPLETE_TRIGGER_RE` ve `_PHASE_EXTENDED_TRIGGER_RE` özel
    `asama-9-ac-{i}-(red|green|refactor)` format'ını kapsamıyor.

    Bu helper:
      - Son assistant text'te pattern'i bul
      - Her (ac_idx, stage) çifti için audit emit (idempotent)
      - GREEN stage → `state.tdd_last_green` = `asama-9-ac-{idx}-green`

    Returns: yeni audit yazıldıysa True.
    """
    if not transcript_path:
        return False
    text = transcript.find_last_assistant_text_matching(
        lambda t: bool(_PHASE_9_AC_TRIGGER_RE.search(t)),
        transcript_path,
    )
    if not text:
        return False
    matches = _PHASE_9_AC_TRIGGER_RE.findall(text)
    if not matches:
        return False
    existing = {
        ev.get("name") for ev in audit.read_all(project_root=project_dir)
    }
    wrote = False
    seen: set[tuple[int, str]] = set()
    for ac_idx_str, stage in matches:
        try:
            ac_idx = int(ac_idx_str)
        except ValueError:
            continue
        stage_lower = stage.lower()
        key = (ac_idx, stage_lower)
        if key in seen:
            continue
        seen.add(key)
        audit_name = f"asama-9-ac-{ac_idx}-{stage_lower}"
        if audit_name in existing:
            continue
        audit.log_event(
            audit_name, "stop.py",
            f"phase9-tdd-ac-trigger ac={ac_idx} stage={stage_lower}",
            project_root=project_dir,
        )
        existing.add(audit_name)
        wrote = True
        if stage_lower == "green":
            state.set_field(
                "tdd_last_green", audit_name,
                project_root=project_dir,
            )
    return wrote


def _detect_phase_items_triggers(
    transcript_path: str, project_dir: str,
) -> bool:
    """1.0.25: Aşama 10 + 19 item trigger'ları (items-declared + item-N-resolved).

    Pseudocode:
      - `asama-N-items-declared count=K` → toplam risk/etki sayısı
        bildirimi (Aşama 10 risk, Aşama 19 etki).
      - `asama-N-item-M-resolved decision=apply|skip|rule` → her madde
        için karar (askq classifier sonucu).
      - decision=rule → kalıcı kural (Rule Capture); ek audit
        `asama-N-rule-capture-M`.

    Hook:
      - items-declared audit emit + Aşama 10 için state.open_severity_count
        güncelle (count=K).
      - item-resolved audit emit + decision=rule ise rule-capture audit
        ek emit (DSI directive'ini hatırlatma için zemin).

    Returns: yeni audit yazıldıysa True.
    """
    if not transcript_path:
        return False
    text = transcript.find_last_assistant_text_matching(
        lambda t: bool(
            _PHASE_ITEMS_DECLARED_RE.search(t)
            or _PHASE_ITEM_RESOLVED_RE.search(t)
        ),
        transcript_path,
    )
    if not text:
        return False
    existing = {
        ev.get("name") for ev in audit.read_all(project_root=project_dir)
    }
    wrote = False

    # items-declared count=K
    seen_declared: set[int] = set()
    for n_str, count_str in _PHASE_ITEMS_DECLARED_RE.findall(text):
        try:
            n = int(n_str)
            count = int(count_str)
        except ValueError:
            continue
        if n in seen_declared:
            continue
        seen_declared.add(n)
        audit_name = f"asama-{n}-items-declared"
        if audit_name not in existing:
            audit.log_event(
                audit_name, "stop.py",
                f"count={count} phase={n}",
                project_root=project_dir,
            )
            existing.add(audit_name)
            wrote = True
        # Aşama 10 için state.open_severity_count yaz (Aşama 19 için
        # ileri release'te ayrı state alanı tanımlanabilir; şu an Aşama
        # 19 hash sayım Aşama 22 turunda).
        if n == 10:
            state.set_field(
                "open_severity_count", count,
                project_root=project_dir,
            )

    # item-{m}-resolved decision=apply|skip|rule
    seen_resolved: set[tuple[int, int]] = set()
    for n_str, m_str, decision in _PHASE_ITEM_RESOLVED_RE.findall(text):
        try:
            n = int(n_str)
            m = int(m_str)
        except ValueError:
            continue
        key = (n, m)
        if key in seen_resolved:
            continue
        seen_resolved.add(key)
        decision_lower = decision.lower()
        audit_name = f"asama-{n}-item-{m}-resolved"
        if audit_name not in existing:
            audit.log_event(
                audit_name, "stop.py",
                f"phase={n} item={m} decision={decision_lower}",
                project_root=project_dir,
            )
            existing.add(audit_name)
            wrote = True
        # Rule Capture: decision=rule → ek audit (DSI directive
        # CLAUDE.md captured-rules'a ekleme zemini için)
        if decision_lower == "rule":
            rule_audit = f"asama-{n}-rule-capture-{m}"
            if rule_audit not in existing:
                audit.log_event(
                    rule_audit, "stop.py",
                    f"rule-capture phase={n} item={m}",
                    project_root=project_dir,
                )
                existing.add(rule_audit)
                wrote = True
    return wrote


# 1.0.26: Aşama 11-13 Kalite Boru Hattı trigger'ları — generic regex.
# 1.0.27: Aşama 14 (Güvenlik) scope'a dahil edildi. Gerekçe:
# mycl-phase-runner subagent Bash kullanamadığı için semgrep/npm
# audit/secret scanner çalıştıramıyordu; eski subagent_orchestration:
# true bayrağı fiilen kırıktı. Şimdi Aşama 11-13 ile aynı text-trigger
# kanalı kullanılır; model ana context'te semgrep'i Bash ile koşar,
# JSON output'u parse eder, audit emit eder.
# Pseudocode (satır 354-386): her kalite fazı aynı 3-step döngü:
# scan count=K → issue-N-fixed → rescan count=K' → ... → rescan count=0.
# Max 5 rescan aşıldıysa model asama-N-escalation-needed yazar.
_PHASE_QUALITY_PHASES = frozenset({11, 12, 13, 14})
_PHASE_SCAN_TRIGGER_RE = re.compile(
    r"\basama-(\d+)-scan\s+count=(\d+)\b",
    re.IGNORECASE,
)
_PHASE_ISSUE_FIXED_TRIGGER_RE = re.compile(
    r"\basama-(\d+)-issue-(\d+)-fixed\b",
    re.IGNORECASE,
)
_PHASE_RESCAN_TRIGGER_RE = re.compile(
    r"\basama-(\d+)-rescan\s+count=(\d+)\b",
    re.IGNORECASE,
)
_PHASE_ESCALATION_TRIGGER_RE = re.compile(
    r"\basama-(\d+)-escalation-needed\b",
    re.IGNORECASE,
)


def _detect_phase_quality_triggers(
    transcript_path: str, project_dir: str,
) -> bool:
    """1.0.26+1.0.27: Aşama 11-14 Kalite Boru Hattı text-trigger'ları.

    Yakalanan trigger'lar (Aşama 11, 12, 13, 14 ortak):
      - `asama-N-scan count=K` → yeni tarama döngüsü, K issue tespit
      - `asama-N-issue-M-fixed` → tek issue auto-fix
      - `asama-N-rescan count=K` → fix sonrası yeniden tarama; K=0
        bitiş sinyali (ama `asama-N-complete` audit'i model yazar,
        bu hook auto-emit ETMEZ — sorumluluk sınırı)
      - `asama-N-escalation-needed` → max 5 rescan aşıldı,
        geliştirici müdahalesi (model yazar; hook yakalar, auto-emit
        ETMEZ — STRICT mode bypass ödülünü önler)

    Hook her dört trigger için idempotent audit emit yapar; başka
    state mutation veya complete/escalation auto-emit yoktur.

    Returns: yeni audit yazıldıysa True.
    """
    if not transcript_path:
        return False
    text = transcript.find_last_assistant_text_matching(
        lambda t: bool(
            _PHASE_SCAN_TRIGGER_RE.search(t)
            or _PHASE_ISSUE_FIXED_TRIGGER_RE.search(t)
            or _PHASE_RESCAN_TRIGGER_RE.search(t)
            or _PHASE_ESCALATION_TRIGGER_RE.search(t)
        ),
        transcript_path,
    )
    if not text:
        return False
    existing = {
        ev.get("name") for ev in audit.read_all(project_root=project_dir)
    }
    wrote = False

    seen_scan: set[int] = set()
    for n_str, count_str in _PHASE_SCAN_TRIGGER_RE.findall(text):
        try:
            n = int(n_str)
            count = int(count_str)
        except ValueError:
            continue
        if n not in _PHASE_QUALITY_PHASES or n in seen_scan:
            continue
        seen_scan.add(n)
        audit_name = f"asama-{n}-scan"
        if audit_name not in existing:
            audit.log_event(
                audit_name, "stop.py",
                f"quality-pipeline scan phase={n} count={count}",
                project_root=project_dir,
            )
            existing.add(audit_name)
            wrote = True

    seen_issue: set[tuple[int, int]] = set()
    for n_str, m_str in _PHASE_ISSUE_FIXED_TRIGGER_RE.findall(text):
        try:
            n = int(n_str)
            m = int(m_str)
        except ValueError:
            continue
        key = (n, m)
        if n not in _PHASE_QUALITY_PHASES or key in seen_issue:
            continue
        seen_issue.add(key)
        audit_name = f"asama-{n}-issue-{m}-fixed"
        if audit_name not in existing:
            audit.log_event(
                audit_name, "stop.py",
                f"quality-pipeline issue-fixed phase={n} issue={m}",
                project_root=project_dir,
            )
            existing.add(audit_name)
            wrote = True

    seen_rescan: set[int] = set()
    for n_str, count_str in _PHASE_RESCAN_TRIGGER_RE.findall(text):
        try:
            n = int(n_str)
            count = int(count_str)
        except ValueError:
            continue
        if n not in _PHASE_QUALITY_PHASES or n in seen_rescan:
            continue
        seen_rescan.add(n)
        audit_name = f"asama-{n}-rescan"
        if audit_name not in existing:
            audit.log_event(
                audit_name, "stop.py",
                f"quality-pipeline rescan phase={n} count={count}",
                project_root=project_dir,
            )
            existing.add(audit_name)
            wrote = True

    seen_esc: set[int] = set()
    for n_str in _PHASE_ESCALATION_TRIGGER_RE.findall(text):
        try:
            n = int(n_str)
        except ValueError:
            continue
        if n not in _PHASE_QUALITY_PHASES or n in seen_esc:
            continue
        seen_esc.add(n)
        audit_name = f"asama-{n}-escalation-needed"
        if audit_name not in existing:
            audit.log_event(
                audit_name, "stop.py",
                f"quality-pipeline escalation phase={n}",
                project_root=project_dir,
            )
            existing.add(audit_name)
            wrote = True

    return wrote


def _check_phase6_browser(detail: str, project_dir: str) -> None:
    """1.0.21: Aşama 6 `asama-6-end` detail parametrelerini incele.

    `asama-6-end server_started=true browser_opened=false` durumunda
    `asama-6-no-browser-warn` soft audit emit eder (pseudocode "KATI
    mod sertifikası" gereği). Hard deny değil — geliştirici uyarıyı
    görür, tarayıcı açma sorumluluğu modelin/kullanıcının.
    """
    if not detail:
        return
    if "browser_opened=false" not in detail.lower():
        return
    existing = {
        ev.get("name") for ev in audit.read_all(project_root=project_dir)
    }
    if "asama-6-no-browser-warn" in existing:
        return  # idempotent
    audit.log_event(
        "asama-6-no-browser-warn", "stop.py",
        f"browser_opened=false detected in detail: {detail[:80]}",
        project_root=project_dir,
    )


def _detect_phase_extended_trigger(
    transcript_path: str, project_dir: str,
) -> bool:
    """Aşama N için `complete` dışındaki audit suffix'lerini yakala.

    1.0.21 — mevcut `_detect_phase_complete_trigger` sadece "complete"
    suffix yakalıyordu; `asama-6-end`, `asama-5-skipped`, `asama-15-end-green`
    gibi audit'ler hook'a hiç ulaşmıyordu (text-trigger kanalı kayıp).
    Generic fix: extended trigger regex (skipped|end|end-green|
    end-target-met|not-applicable).

    Sıralılık:
      - N == cp → audit emit (idempotent).
      - N != cp → sessiz geç (skip-attempt yazma; extended trigger'lar
        opsiyonel/yan kanal — sıralılık zorunluluğu yok, `_detect_phase_complete_trigger`
        bu işi yapıyor).

    Aşama 6 spesifik: `asama-6-end` detail parametrelerinde
    `browser_opened=false` varsa `_check_phase6_browser` warn emit.

    Returns: yeni audit yazıldıysa True.
    """
    if not transcript_path:
        return False
    text = transcript.find_last_assistant_text_matching(
        lambda t: bool(_PHASE_EXTENDED_TRIGGER_RE.search(t)),
        transcript_path,
    )
    if not text:
        return False
    matches = _PHASE_EXTENDED_TRIGGER_RE.findall(text)
    if not matches:
        return False
    cp = state.get("current_phase", 1, project_root=project_dir)
    existing = {
        ev.get("name") for ev in audit.read_all(project_root=project_dir)
    }
    wrote = False
    seen: set[tuple[int, str]] = set()
    for n_str, suffix, detail in matches:
        try:
            n = int(n_str)
        except ValueError:
            continue
        key = (n, suffix.lower())
        if key in seen:
            continue
        seen.add(key)
        if n != cp:
            # Extended trigger'lar sıralılık zorunlu değil — sessiz geç.
            continue
        audit_name = f"asama-{n}-{suffix.lower()}"
        if audit_name in existing:
            continue
        audit.log_event(
            audit_name, "stop.py",
            f"extended-trigger-emit phase={n} suffix={suffix} detail={detail or ''}",
            project_root=project_dir,
        )
        existing.add(audit_name)
        wrote = True
        # Aşama 6 spesifik: end audit detail kontrolü
        if n == 6 and suffix.lower() == "end":
            _check_phase6_browser(detail or "", project_dir)
    return wrote


# ---------- subagent orchestration (Aşama N) ----------


def _find_phase_runner_output(transcript_path: str) -> str | None:
    """Transcript'te son `mycl-phase-runner` Task çağrısının tool_result text'i."""
    if not transcript_path:
        return None
    use_id: str | None = None
    last_result: str | None = None
    for msg in transcript.iter_messages(transcript_path):
        for content in msg.get("message", {}).get("content", []):
            if not isinstance(content, dict):
                continue
            ctype = content.get("type")
            if ctype == "tool_use" and content.get("name") == "Task":
                inp = content.get("input") or {}
                if isinstance(inp, dict) and inp.get("subagent_type") == "mycl-phase-runner":
                    use_id = content.get("id")
            elif ctype == "tool_result" and use_id is not None:
                if content.get("tool_use_id") == use_id:
                    raw = content.get("content")
                    if isinstance(raw, list):
                        parts = [
                            blk.get("text", "")
                            for blk in raw
                            if isinstance(blk, dict) and blk.get("type") == "text"
                        ]
                        last_result = "\n".join(p for p in parts if p)
                    elif isinstance(raw, str):
                        last_result = raw
    return last_result


def _detect_subagent_phase_output(
    transcript_path: str, project_dir: str,
) -> bool:
    """mycl-phase-runner subagent çıktısını parse et, audit + state advance.

    Aşama N'de `subagent_orchestration: true` ise:
      - complete → `asama-N-complete` audit
      - skipped  → `asama-N-skipped reason=X` audit
      - pending  → `asama-N-pending question=X` audit (advance YOK)
      - error    → `asama-N-subagent-error` audit (advance YOK, STRICT)

    Universal completeness loop advance'i complete/skipped audit'inden
    sonra sağlar (audit-driven walk paterni).

    Returns: yeni audit yazıldıysa True.
    """
    if not transcript_path:
        return False
    cp = state.get("current_phase", 1, project_root=project_dir)
    if not orchestrator.is_orchestration_enabled(cp):
        return False

    output_text = _find_phase_runner_output(transcript_path)
    if not output_text:
        return False

    parsed = orchestrator.parse_phase_output(output_text)
    existing = {ev.get("name") for ev in audit.read_all(project_root=project_dir)}

    if parsed.outcome == orchestrator.PhaseOutcome.COMPLETE:
        audit_name = f"asama-{cp}-complete"
        if audit_name in existing:
            return False
        audit.log_event(
            audit_name, "stop.py",
            f"subagent-emit summary={parsed.summary[:80]}",
            project_root=project_dir,
        )
        state.set_field(
            "last_phase_output", parsed.summary,
            project_root=project_dir,
        )
        return True

    if parsed.outcome == orchestrator.PhaseOutcome.SKIPPED:
        audit_name = f"asama-{cp}-skipped"
        if audit_name in existing:
            return False
        audit.log_event(
            audit_name, "stop.py",
            f"reason={parsed.reason} detail={parsed.detail[:80]}",
            project_root=project_dir,
        )
        state.set_field(
            "last_phase_output", f"skipped reason={parsed.reason}",
            project_root=project_dir,
        )
        return True

    if parsed.outcome == orchestrator.PhaseOutcome.PENDING:
        audit.log_event(
            f"asama-{cp}-pending", "stop.py",
            f"question={parsed.question[:120]}",
            project_root=project_dir,
        )
        return False

    # ERROR
    audit.log_event(
        f"asama-{cp}-subagent-error", "stop.py",
        f"detail={parsed.detail[:120]}",
        project_root=project_dir,
    )
    return False


# ---------- main ----------


def main() -> int:
    payload = _read_input()
    project_dir = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    if _is_self_project(project_dir):
        return 0

    # 1.0.5: opt-in `/mycl` — aktif değilse hook no-op (spec hash kayıt,
    # askq classify, completeness loop hiçbiri çalışmaz).
    session_id = str(payload.get("session_id", "") or "")
    if not activation.is_session_active(session_id, project_root=project_dir):
        return 0

    transcript_path = str(payload.get("transcript_path") or "")

    # 1. Spec hash detect (line-anchored Spec regex)
    _detect_and_store_spec(transcript_path, project_dir)

    # 2. AskUserQuestion intent classify
    intent = _detect_askq_intent(transcript_path)

    # 3. Aşama 4 spec-approve flow (intent=approve + spec_hash mevcut)
    if intent == askq.INTENT_APPROVE:
        _spec_approve_flow(project_dir)

    # 3.1. (1.0.22) Aşama 7 UI review intent flow + auto-skip
    _phase7_ui_review_flow(intent, project_dir)
    _check_phase7_auto_skip(project_dir)

    # 3.5. Subagent orkestrasyon — Aşama N'de subagent_orchestration
    # aktifse mycl-phase-runner Task tool çıktısını parse et, audit +
    # state advance (universal loop sonradan ilerletir).
    _detect_subagent_phase_output(transcript_path, project_dir)

    # 3.6. Faz tamamlama text trigger (fallback — orchestration yoksa
    # veya subagent çıktısı yoksa modelin cevabındaki `asama-N-complete`
    # tetik kelimesi kanalı).
    _detect_phase_complete_trigger(transcript_path, project_dir)

    # 1.0.21: Extended trigger — `skipped`, `end`, `end-green`,
    # `end-target-met`, `not-applicable` suffix'leri yakalar. Aşama 6
    # `asama-6-end` parametre parse + soft warn; Aşama 5/7/21 skipped
    # de bu kanaldan yakalanır.
    _detect_phase_extended_trigger(transcript_path, project_dir)

    # 1.0.24: Aşama 9 TDD AC audit'leri (red/green/refactor) — özel
    # format `asama-9-ac-{i}-(red|green|refactor)`. Generic extended
    # trigger bu format'ı kapsamıyor (ac-{i} ek segment).
    _detect_phase_9_ac_trigger(transcript_path, project_dir)

    # 1.0.25: Aşama 10 + 19 item trigger'ları — items-declared count=K
    # + item-{m}-resolved decision=apply|skip|rule. decision=rule ek
    # rule-capture audit (CLAUDE.md captured-rules zemini).
    _detect_phase_items_triggers(transcript_path, project_dir)

    # 1.0.26+1.0.27: Aşama 11-14 Kalite Boru Hattı text-trigger'ları
    # (scan / issue-fixed / rescan / escalation-needed). 1.0.27'de
    # Aşama 14 de scope'a alındı — eski subagent_orch bayrağı kırıktı.
    # Hook auto-emit YOK — `asama-N-complete` ve `escalation-needed`
    # model sorumluluğunda.
    _detect_phase_quality_triggers(transcript_path, project_dir)

    # 4. Universal completeness loop (audit-driven walk)
    _run_completeness_loop(project_dir)

    # Stop hook sessiz — output yok ("continue" default)
    return 0


if __name__ == "__main__":
    sys.exit(main())
