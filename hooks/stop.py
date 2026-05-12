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
            cp = n + 1  # lokal advance — gerçek state advance completeness loop'ta
        elif n > cp:
            audit.log_event(
                "phase-skip-attempt", "stop.py",
                f"emit_phase={n} current_phase={cp}",
                project_root=project_dir,
            )
        # else n < cp: stale-emit, sessiz geç
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

    # 3.5. Subagent orkestrasyon — Aşama N'de subagent_orchestration
    # aktifse mycl-phase-runner Task tool çıktısını parse et, audit +
    # state advance (universal loop sonradan ilerletir).
    _detect_subagent_phase_output(transcript_path, project_dir)

    # 3.6. Faz tamamlama text trigger (fallback — orchestration yoksa
    # veya subagent çıktısı yoksa modelin cevabındaki `asama-N-complete`
    # tetik kelimesi kanalı).
    _detect_phase_complete_trigger(transcript_path, project_dir)

    # 4. Universal completeness loop (audit-driven walk)
    _run_completeness_loop(project_dir)

    # Stop hook sessiz — output yok ("continue" default)
    return 0


if __name__ == "__main__":
    sys.exit(main())
