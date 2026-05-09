# Changelog

All notable changes to MyCL.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-05-09

### Yeni Başlangıç / Fresh Start

MyCL 1.0.0 sıfırdan yeniden inşa. Eski MCL (my-claude-lang) v13.x'in
~5000 satırlık Bash + Python heredoc karışımından **pure Python 3.8+**
ile çıkış. Pseudocode (22 faz) kanonik tasarım olarak korundu;
kod sıfırdan yazıldı. v13.x mekanizmaları **kavramsal aktarım**
ile geldi (kod değil).

MyCL 1.0.0 is a from-scratch rebuild. Migrating away from the legacy
MCL v13.x's ~5000-line Bash + Python heredoc mix to **pure Python
3.8+**. The pseudocode (22 phases) remained canonical; code was
rewritten. v13.x mechanisms transferred **conceptually** (not as
code).

### Eklenenler / Added

- **22-faz pipeline** (Aşama 1-22) — niyet toplamadan tamlık
  denetimine her adım skill dosyası ile detaylı belgelendi
- **4 hook** (Pure Python):
  - `activate.py` (UserPromptSubmit) — DSI + Plugin Kural A consent
  - `pre_tool.py` (PreToolUse) — 6 katmanlı STRICT karar
    (self-guard → phase-transition emit denylist → state-mutation
    lock → spec-approval block → Layer B → 5-strike escalation)
  - `post_tool.py` (PostToolUse) — reaktif state (last_write_ts,
    ui_flow_active, regression-clear) + askq sonrası stop trigger
  - `stop.py` (Stop) — spec hash + askq intent + Aşama 4 spec-approve
    + universal completeness loop
- **23 lib modülü** `hooks/lib/`:
  - state, audit, trace, transcript, spec_detect, askq, gate, plugin
  - dsi, bilingual, framing, progress, tokens, commitment,
    rationale, selfcritique, confidence, spec_must,
    subagent_check, post_mortem, skill_loader, tdd
- **22 skill dosyası** + 1 ana skill + 3 ortak (tag-schema,
  plugin-rules, reasons)
- **8 veri dosyası** `data/`: gate_spec, phase_meta, approve_cues,
  manifesto, static_context, bilingual_messages, commitment_template,
  spec_must_extractor — TR + EN ikilisi
- **521 birim + integration test** — pseudocode invariantları uçtan
  uca smoke matrix
- **`setup.sh`** — Python check, repo kopyala, settings.json
  idempotent merge, smoke test
- **STRICT mode** (v13.1.3 kazanımı korundu) — fail-open YOK,
  5-strike escalation, state mutation lock
- **TR + EN çift dil** — tüm hook mesajları, skill dosyaları, askq
  prompt'ları (boş satır ayrılı, etiketsiz)

### Değişen / Changed (vs MCL v13.x)

- **Stack**: Bash + Python heredoc → **Pure Python 3.8+ standard
  library** (json, re, hashlib, sys, os; dış bağımlılık yok)
- **Dil desteği**: 14 dil → **TR + EN** (askq cue'ları, narration,
  manifesto)
- **Versiyon**: 13.x patch döngüsü → **1.0.0 yeni başlangıç**
- **Klasör yapısı**: `mcl/` → `mycl/`, `.mcl/` → `.mycl/`, `MCL_*`
  → `MyCL_*`
- **State schema_version**: 3 → 1 (yeni başlangıç, eski state ile
  migration yok)
- **Hook isim formatı**: `mcl-pre-tool.sh` → `pre_tool.py`
  (snake_case Python)
- **Skill dosya isimleri**: `phase4_5-risk-review.md` →
  `asama04-spec.md` (Türkçe + tire ayraç)

### Reddedilen Yaklaşımlar / Rejected Approaches

- ❌ **AI agent / LangGraph** — Claude Code'u yeniden yazmak
  anlamsız; pseudocode 22 faz zaten state machine, framework
  gereksiz
- ❌ **MCP server** — Plugin Kural C `.mcp.json` filter
- ❌ **Drift detection** — v13.x'te yanlış-pozitif gürültüsü
  üretmişti; geliştirici doğal olarak spec'ten sapar
- ❌ **Fail-fast giriş kontrolleri** — kullanıcıyı pipeline'dan
  koparır; soft guidance tercih edildi
- ❌ **3-strike fail-open** — STRICT mode korundu (5-strike
  escalation, fail-open yok)
- ❌ **Para tutarı görünürlüğü** — token sayısı OK (objektif),
  USD tutarı YOK (negatif çağrışım)
- ❌ **Gamification puan toplama** — Goodhart's Law
- ❌ **secrets.py runtime pattern match** — Aşama 14 (Güvenlik)
  zaten semgrep + paket audit ile derin tarama yapıyor; pre-tool
  runtime overlap bakım yükü üretiyordu

### v13.x'ten Kavramsal Aktarım / Conceptual Transfer

Kod olarak silindi ama mekanizma korundu:

- Universal completeness loop (audit-driven phase walk)
- Layer B fail-closed allowlist (gate-spec eksikse mutating DENY)
- Persuasion manifesto framing (v13.0.16)
- Spec-approve audit chain + auto-fill (v13.0.14, v13.0.17)
- Audit-driven active phase resolver
- Devtime/runtime REASON split (v13.0.13)
- TDD compliance score
- DSI render (PHASE_META → mcl_active_phase_directive)
- AskUserQuestion sonrası stop manuel tetikleme (v13.1.1 Bug 2)
- STRICT mode (v13.1.3 — 5 strike escalation, fail-open yok)
- State mutation lock Bash'ten (v13.1.3)
- Compound `git init` regex (v13.1.2)
- Spec emoji opsiyonel regex (v13.1.2)

### Tag noktaları / Tag points

- `mcl-13.1.3-final` — eski sürüm sabit (commit `916c271`)
- `pre-mycl-rebuild` — clean slate snapshot (commit `dd15d9d`)
- `mycl-1.0.0` — bu release

[1.0.0]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.0
