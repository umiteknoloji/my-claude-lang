#!/usr/bin/env python3
"""pre_tool — PreToolUse hook (Layer B + spec-approval + state lock).

Pseudocode §2 PreToolUse + CLAUDE.md design principles.

Akış (sırasıyla):
    1. Self-project guard (recursive friction)
    2. Phase transition emit denylist (Bash içinde audit hile)
    3. State-mutation lock (Bash kanalından state.set_field DENY)
    4. Spec-approval block (spec_approved=false → mutating Bash/Write/Edit
       DENY; git init Plugin Kural A istisna)
    5. Layer B: gate.evaluate(tool, file_path) → deny olursa
       phase-allowlist audit + REASON döner
    6. 5 strike sonrası `*-escalation-needed` audit (görünür sinyal)

STRICT mode: fail-open YOK. Block sonsuza kadar; kullanıcı
müdahalesine kadar deny sürer.

Output (Claude Code JSON):
    {"hookSpecificOutput": {"hookEventName": "PreToolUse",
     "permissionDecision": "allow" | "deny",
     "permissionDecisionReason": "..."}}
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
    activation, audit, bilingual, gate, spec_detect, state, transcript,
)


def _read_version() -> str:
    """VERSION dosyasından sürümü oku — banner/block prefix'leri için."""
    version_file = _REPO_ROOT / "VERSION"
    try:
        return version_file.read_text(encoding="utf-8").strip() or "0.0.0"
    except OSError:
        return "0.0.0"


_MYCL_VERSION = _read_version()

_STRIKE_ESCALATION_THRESHOLD = 5

# Mutating Bash detection
_BASH_REDIRECT_RE = re.compile(r"(?:^|[^<>&0-9])>>?\s*[^&\s]")
_BASH_TEE_RE = re.compile(r"\btee\b(?!\s*--help)")
_BASH_MUTATING_PATTERNS = [
    re.compile(r"(?:^|[\s|;&`(])(rm|mv|cp|touch|mkdir|rmdir|chmod|chown|chgrp|ln|truncate|dd|patch|install|unlink)\b"),
    re.compile(r"(?:^|[\s|;&`(])sed\b[^|;&`]*?\s-i\b"),
    re.compile(r"(?:^|[\s|;&`(])git\s+(commit|push|add|rm|mv|reset|checkout|restore|switch|rebase|merge|pull|fetch|clone|stash|tag|branch|clean|cherry-pick|revert|apply|am|worktree)\b"),
    re.compile(r"(?:^|[\s|;&`(])(npm|yarn|pnpm|bun|pip|pip3|poetry|uv|gem|bundle|cargo|go|brew|apt|apt-get|dnf|yum|pacman|zypper)\s+(install|i|ci|add|remove|uninstall|update|upgrade|mod)\b"),
]
# State mutation pattern (Python lib çağrıları)
_STATE_MUTATION_RE = re.compile(
    r"\b(?:hooks\.lib\.state\.|state\.)(?:set_field|update|reset)\b"
)
# Audit hile (phase_transition / asama-N-progression-from-emit yasak)
_PHASE_TRANSITION_EMIT_RE = re.compile(
    r"phase_transition\s+\d+\s+\d+|asama-\d+-progression-from-emit"
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


def _emit(decision: str, reason: str = "") -> None:
    """Claude Code permission JSON output."""
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
        }
    }
    if reason:
        out["hookSpecificOutput"]["permissionDecisionReason"] = reason
    print(json.dumps(out))


def _allow() -> int:
    _emit("allow")
    return 0


def _deny(reason: str) -> int:
    _emit("deny", reason)
    return 0


def _is_bash_mutating(cmd: str) -> bool:
    """Bash command mutating mi?"""
    if not cmd:
        return False
    if _BASH_REDIRECT_RE.search(cmd) or _BASH_TEE_RE.search(cmd):
        return True
    return any(p.search(cmd) for p in _BASH_MUTATING_PATTERNS)


_BOOTSTRAP_CMD_PATTERNS = [
    re.compile(r"^\s*git\s+init\s*$"),
    re.compile(r"^\s*mkdir(?:\s+-p)?\s+\.mycl(?:/[^\s]*)?\s*$"),
]


def _is_bootstrap_command(cmd: str) -> bool:
    """Plugin Kural A bootstrap için izinli komut(lar) mı?

    Kabul: `git init`, `mkdir [-p] .mycl[/sub]`. Compound separator'lar
    `&&` ve `;` desteklenir — her parça allowlist'ten birini matchlemeli.
    Pipe (`|`) ve OR (`||`) reddedilir (riskli akış kontrolü).

    1.0.11: 1.0.10'daki `_is_git_init_only` `git init && mkdir -p .mycl`
    gibi compound bootstrap'leri kaçırıyordu; model'in tek turda hem
    git init hem `.mycl/` setup yapması doğal → kapsam genişletildi.
    """
    if not cmd:
        return False
    parts = re.split(r"\s*(?:&&|;)\s*", cmd.strip())
    return bool(parts) and all(
        any(p.match(part) for p in _BOOTSTRAP_CMD_PATTERNS)
        for part in parts if part
    )


def _bilingual_block(key: str, **kwargs) -> str:
    """bilingual.render — fail-safe (eksik key → key adı).

    1.0.9: `version` placeholder otomatik enjekte edilir — block
    template'lerinde `MyCL {version} | ` prefix kullanılır.
    """
    kwargs.setdefault("version", _MYCL_VERSION)
    text = bilingual.render(key, **kwargs)
    return text if text and not text.startswith("[") else ""


def _count_askq_in_last_assistant_turn(transcript_path: str) -> int:
    """Son assistant message içinde kaç AskUserQuestion tool_use var.

    1.0.16: Aşama 1 skill 'tek soru per turn' diyor (pseudocode §3
    Aşama 1 dictat). Model bu kuralı görmezden geliyorsa tek mesajda
    paralel askq açar. Deny yapamayız — Claude Code parallel tool
    calls feature'ı race condition oluşturur. Audit-only sinyal:
    `multi-askq-attempt` log'a yazılır, bir sonraki sürümde sıkılaştırma
    için zemin hazırlar.
    """
    from hooks.lib import transcript as _t
    last_msg = None
    for msg in _t.iter_messages(transcript_path):
        is_assistant = (
            msg.get("type") == "assistant"
            or (isinstance(msg.get("message"), dict)
                and msg["message"].get("role") == "assistant")
        )
        if is_assistant:
            last_msg = msg
    if not last_msg:
        return 0
    inner = (
        last_msg.get("message")
        if isinstance(last_msg.get("message"), dict)
        else last_msg
    )
    content = inner.get("content") if isinstance(inner, dict) else []
    if not isinstance(content, list):
        return 0
    return sum(
        1 for c in content
        if isinstance(c, dict)
        and c.get("type") == "tool_use"
        and c.get("name") == "AskUserQuestion"
    )


def _record_strike_and_escalation(
    block_kind: str, tool: str, project_root: str,
) -> None:
    """Block audit + 5 strike eşiği aşılırsa escalation audit."""
    audit.log_event(
        block_kind, "pre_tool.py",
        f"tool={tool}", project_root=project_root,
    )
    count = gate.deny_count_in_session(block_kind, project_root=project_root)
    if count == _STRIKE_ESCALATION_THRESHOLD:
        audit.log_event(
            f"{block_kind}-escalation-needed", "pre_tool.py",
            f"strike={count} developer-intervention-required",
            project_root=project_root,
        )


def _advance_phase_from_transcript(
    transcript_path: str, project_dir: str,
) -> None:
    """1.0.41: PreToolUse'da text-trigger detection + completeness loop.

    1.0.39 PostToolUse'a aynı pattern eklendi ama PostToolUse **tool
    deny olunca fire etmiyor** — Bash deny'dan sonra advance hiç
    çalışmıyor, state donuyor, model retry → sonsuz deny döngüsü
    (canlı bug).

    Bu fix: PreToolUse'a aynı advance hook'unu ekler ama gate
    evaluation'dan ÖNCE çağrılır. Model tek turn içinde text-trigger
    + tool çağrısı yapsa bile state advance edilir, gate doğru
    faza göre evaluate eder.

    Idempotent (post_tool.py::_advance_phase_after_tool ile aynı
    pattern — audit set check ile duplicate emit yok).
    """
    if not transcript_path:
        return
    from hooks.stop import (  # noqa: E402
        _detect_phase_complete_trigger,
        _detect_phase_extended_trigger,
        _detect_phase_9_ac_trigger,
        _detect_phase_items_triggers,
        _detect_phase_quality_triggers,
        _detect_phase_testing_triggers,
        _detect_mid_reconfirm_acked,
        _detect_selfcritique_triggers,
        _detect_commitment_trigger,
        _detect_phase_20_mock_cleanup,
        _run_completeness_loop,
    )
    _detect_phase_complete_trigger(transcript_path, project_dir)
    _detect_phase_extended_trigger(transcript_path, project_dir)
    _detect_phase_9_ac_trigger(transcript_path, project_dir)
    _detect_phase_items_triggers(transcript_path, project_dir)
    _detect_phase_quality_triggers(transcript_path, project_dir)
    _detect_phase_testing_triggers(transcript_path, project_dir)
    _detect_mid_reconfirm_acked(transcript_path, project_dir)
    _detect_selfcritique_triggers(transcript_path, project_dir)
    _detect_commitment_trigger(transcript_path, project_dir)
    _detect_phase_20_mock_cleanup(transcript_path, project_dir)
    _run_completeness_loop(project_dir)


def main() -> int:
    payload = _read_input()
    project_dir = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    if _is_self_project(project_dir):
        return _allow()

    # 1.0.5: opt-in `/mycl` — aktif değilse hook no-op (her tool allow).
    session_id = str(payload.get("session_id", "") or "")
    if not activation.is_session_active(session_id, project_root=project_dir):
        return _allow()

    # 1.0.41: Gate evaluation öncesi state advance. Model tek turn içinde
    # `asama-N-complete` text-trigger + tool çağrısı yaparsa, PostToolUse
    # fire etmeden ÖNCE PreToolUse burada advance eder; gate doğru
    # cp'ye göre evaluate eder.
    transcript_path_pre = str(payload.get("transcript_path") or "")
    _advance_phase_from_transcript(transcript_path_pre, project_dir)

    tool_name = str(payload.get("tool_name", ""))
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        tool_input = {}

    # Bash command extract
    bash_cmd = ""
    if tool_name == "Bash":
        bash_cmd = str(tool_input.get("command", ""))

    # ---------- 2. Phase transition emit denylist ----------
    if tool_name == "Bash" and _PHASE_TRANSITION_EMIT_RE.search(bash_cmd):
        audit.log_event(
            "phase-transition-illegal-emit-attempt", "pre_tool.py",
            f"tool=Bash", project_root=project_dir,
        )
        return _deny(
            "MyCL deterministic gate: phase_transition / asama-N-progression-from-emit "
            "model tarafından emit edilemez. Hook bu audit'leri yazar.\n\n"
            "MyCL deterministic gate: phase_transition / asama-N-progression-from-emit "
            "cannot be model-emitted. Hook writes these audits."
        )

    # ---------- 3. State-mutation lock ----------
    if tool_name == "Bash" and _STATE_MUTATION_RE.search(bash_cmd):
        audit.log_event(
            "state-mutation-attempt", "pre_tool.py",
            "tool=Bash", project_root=project_dir,
        )
        return _deny(
            _bilingual_block("state_mutation_block")
            or "STATE LOCK — state.set_field/update/reset Bash kanalından çağrılamaz."
        )

    # ---------- 3.5. MyCL state dosyaları koruma (H-5 fix) ----------
    # .mycl/state.json ve .mycl/audit.log doğrudan Write/Edit/Bash ile
    # değiştirilemez. Elle spec_approved=True yazmak kilidi bypass eder;
    # bu özel blok faz/spec durumundan bağımsız her zaman aktiftir.
    _PROTECTED_MYCL_PATTERNS = re.compile(
        r"\.mycl[\\/](?:state\.json|audit\.log)",
        re.IGNORECASE,
    )
    if tool_name in {"Write", "Edit", "MultiEdit"}:
        fp_check = str(tool_input.get("file_path") or tool_input.get("path") or "")
        if _PROTECTED_MYCL_PATTERNS.search(fp_check):
            audit.log_event(
                "mycl-state-direct-write-attempt", "pre_tool.py",
                f"tool={tool_name} path={fp_check}", project_root=project_dir,
            )
            return _deny(
                f"MyCL {_MYCL_VERSION} | Koruma: `.mycl/state.json` "
                "ve `.mycl/audit.log` doğrudan yazılamaz — state "
                "hook'lar tarafından yönetilir. Audit emit etmek için "
                "cevap metnine `asama-N-complete` tetik kelimesini düz "
                "yazıyla yaz; stop hook bunu okuyup audit'i kendisi "
                "yazar.\n\n"
                f"MyCL {_MYCL_VERSION} | Guard: `.mycl/state.json` and "
                "`.mycl/audit.log` cannot be written directly — state "
                "is managed by hooks. To emit an audit, plainly write "
                "the trigger word `asama-N-complete` in your reply; "
                "the stop hook reads it and writes the audit itself."
            )
    if tool_name == "Bash" and _PROTECTED_MYCL_PATTERNS.search(bash_cmd):
        # Bash ile state.json veya audit.log redirect/yazma girişimi
        if _BASH_REDIRECT_RE.search(bash_cmd) or _BASH_TEE_RE.search(bash_cmd):
            audit.log_event(
                "mycl-state-direct-write-attempt", "pre_tool.py",
                f"tool=Bash cmd_excerpt={bash_cmd[:80]}", project_root=project_dir,
            )
            return _deny(
                f"MyCL {_MYCL_VERSION} | Koruma: `.mycl/state.json` ve "
                "`.mycl/audit.log` Bash redirect (`>`/`>>`/`tee`) ile "
                "yazılamaz — state hook'lar tarafından yönetilir. Audit "
                "emit etmek için cevap metnine `asama-N-complete` tetik "
                "kelimesini düz yazıyla yaz; stop hook bunu okuyup "
                "audit'i kendisi yazar. Bootstrap'i bu komutsuz tekrar "
                "dene: `git init && mkdir -p .mycl` yeterli.\n\n"
                f"MyCL {_MYCL_VERSION} | Guard: `.mycl/state.json` and "
                "`.mycl/audit.log` cannot be overwritten via Bash "
                "redirect (`>`/`>>`/`tee`) — hooks manage state. To "
                "emit an audit, plainly write the trigger word "
                "`asama-N-complete` in your reply; the stop hook reads "
                "it and writes the audit itself. Retry bootstrap "
                "without that part: `git init && mkdir -p .mycl` is "
                "enough."
            )

    # ---------- 4. Spec-approval block ----------
    spec_approved = bool(state.get("spec_approved", False, project_root=project_dir))
    if not spec_approved:
        # Mutating tool mu? (Write/Edit/MultiEdit/NotebookEdit veya mutating Bash)
        is_mutating = tool_name in {"Write", "Edit", "MultiEdit", "NotebookEdit"}
        if tool_name == "Bash" and _is_bash_mutating(bash_cmd):
            # Plugin Kural A bootstrap istisnası (git init + .mycl mkdir)
            if _is_bootstrap_command(bash_cmd):
                is_mutating = False
            else:
                is_mutating = True
        if is_mutating:
            _record_strike_and_escalation(
                "spec-approval-block", tool_name, project_dir,
            )
            return _deny(
                _bilingual_block("spec_approval_block", tool=tool_name)
                or f"Spec onayı yok; `{tool_name}` engellendi."
            )

    # ---------- 4.5. Plugin Kural A bootstrap istisnası ----------
    # `git init` ve `.mycl/` mkdir zararsız (remote yok, push yok);
    # consent prompt'u activate.py'de zaten gösteriliyor. Faz
    # allowlist'inin Bash'i kapsamadığı Aşama 1 dahil her durumda
    # allow et — başarılı çağrı sonrası post_tool.py consent'i
    # `approved` olarak işaretler. Compound (`git init && mkdir -p
    # .mycl`) destekli (1.0.11).
    if tool_name == "Bash" and _is_bootstrap_command(bash_cmd):
        return _allow()

    # ---------- 4.7. AskUserQuestion özel kontroller ----------
    if tool_name == "AskUserQuestion":
        transcript_path = str(payload.get("transcript_path") or "")
        cp = state.get("current_phase", 1, project_root=project_dir)

        # 4.7.a — Multi-askq audit (1.0.16). Tek mesajda paralel askq →
        # görünürlük sinyali. Deny YOK (Claude Code parallel tool calls
        # race condition oluşturur); audit log'da trail kalır.
        if transcript_path:
            askq_count = _count_askq_in_last_assistant_turn(transcript_path)
            if askq_count > 1:
                audit.log_event(
                    "multi-askq-attempt", "pre_tool.py",
                    f"phase={cp} count={askq_count}",
                    project_root=project_dir,
                )

        # 4.7.b — Aşama 4 spec format izleme (1.0.42: soft, 1.0.19'dan
        # devralma). 1.0.19'da DENY semantiğiyle eklenmişti ama
        # transcript timing false-positive üretti: model spec'i markerla
        # yazıp askq açtı, ama PreToolUse fire'da aynı turn'ün text
        # content'i transcript snapshot'ta görünmedi (tool_use bloğu
        # text'ten önce stream'lendi) → contains False → DENY → model
        # spec'i yeniden yazdı (gereksiz retry; canlı kullanıcı raporu
        # 1.0.41 sonrası).
        #
        # 1.0.42: 1.0.38 Aşama 1 deseniyle simetrik soft guidance.
        # Güvenlik kayıp YOK çünkü spec marker yoksa `_spec_approve_flow`
        # zaten spec_approved=True yapmaz (spec_hash null) → Aşama 5+'da
        # Bash/Write `spec_lock` deny zinciri ikincil savunma olarak
        # devrede. UX kazancı: false-positive retry kaybolur; gerçek
        # spec'siz akış Bash deny zincirinde takılır.
        if cp == 4:
            last_text = (
                transcript.last_assistant_text(transcript_path)
                if transcript_path else ""
            )
            # Yalnızca text VAR ama marker YOKSA audit yaz; text boş ise
            # (transcript snapshot eski olabilir) hiçbir şey yapma.
            if last_text and not spec_detect.contains(last_text):
                existing_audits = {
                    ev.get("name")
                    for ev in audit.read_all(project_root=project_dir)
                }
                if "spec-format-missing" not in existing_audits:
                    audit.log_event(
                        "spec-format-missing", "pre_tool.py",
                        "phase=4 spec_body_marker_absent (soft)",
                        project_root=project_dir,
                    )

        # 4.7.c — Aşama 1 niyet özeti format izleme (1.0.38: soft).
        # 1.0.37'de Aşama 4 deseninin aynısı DENY ile eklenmişti ama
        # iki false-positive yan etki üretti:
        #   1. PreToolUse fire edildiğinde model'in AYNI turn'deki text
        #      content'i `last_assistant_text` tarafından henüz
        #      görülmüyor olabilir (tool_use bloğu text'ten önce
        #      stream'leniyor); marker yazılsa bile deny çıkıyor.
        #   2. Aşama 1 ilk faz — geliştirici pipeline'ı bilmiyor
        #      olabilir; agresif deny "MyCL çalışmıyor" izlenimi
        #      yaratır (CLAUDE.md captured rule "soft guidance over
        #      fail-fast" + v13.1.3 STRICT kapı tasarımı — sadece 4
        #      kapı, fazla değil).
        # 1.0.38: DENY KALDIRILDI; sadece audit kalır (visibility).
        # Aşama 22 invariant kanalı zaten selfcritique/commitment
        # gibi disiplin eksikliklerini yüzeye çıkarıyor (1.0.33+).
        # Aşama 4 spec format guard'ı (1.0.19) sıkı kalır — orada
        # gerçek bypass riski var (Bash deny zinciri); Aşama 1'de
        # sadece kontrat hatırlatma.
        if cp == 1:
            last_text = (
                transcript.last_assistant_text(transcript_path)
                if transcript_path else ""
            )
            # Yalnızca text VAR ama marker YOKSA audit yaz; text boş
            # ise (transcript snapshot eski olabilir) hiçbir şey yapma.
            if last_text and not spec_detect.contains_intent_summary(last_text):
                # Idempotent — aynı turda tekrar tekrar yazmasın
                existing = {
                    ev.get("name")
                    for ev in audit.read_all(project_root=project_dir)
                }
                if "intent-summary-format-missing" not in existing:
                    audit.log_event(
                        "intent-summary-format-missing", "pre_tool.py",
                        "phase=1 intent_summary_marker_absent (soft)",
                        project_root=project_dir,
                    )

    # ---------- 5. Layer B (gate.evaluate) ----------
    file_path = tool_input.get("file_path") or tool_input.get("path") or ""
    allowed, reason = gate.evaluate(
        tool_name,
        file_path=file_path or None,
        project_root=project_dir,
    )
    if not allowed:
        # phase-allowlist veya phase-path audit (gate'e göre)
        block_kind = (
            "phase-allowlist-tool"
            if "izinli değil" in reason or "fail-closed" in reason
            else "phase-allowlist-path"
        )
        _record_strike_and_escalation(block_kind, tool_name, project_dir)
        # bilingual mesaj — phase_allowlist_block veya phase_path_block
        msg_key = "phase_allowlist_block" if block_kind == "phase-allowlist-tool" else "phase_path_block"
        phase = gate.active_phase(project_root=project_dir)
        msg = _bilingual_block(
            msg_key,
            phase=phase,
            tool=tool_name,
            allowed="(see gate_spec.json)",
            path=str(file_path),
            denied="(see gate_spec.json)",
        )
        return _deny(msg or reason)

    # ---------- 6. ALLOW ----------
    return _allow()


if __name__ == "__main__":
    sys.exit(main())
