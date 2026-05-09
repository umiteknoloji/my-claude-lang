# MyCL STATIC_CONTEXT — Project Rules (TR + EN)

Bu dosya her UserPromptSubmit turunda model'e gönderilen değişmeyen
proje kurallarıdır. Çift dil bölümler — Türkçe önce, İngilizce sonra.

---

## 1. XML Tag Vocabulary / XML Tag Sözlüğü

[Türkçe]

MyCL üç tür XML tag kullanır:

- `<mycl_core>` — Kanonik proje çerçevesi (CLAUDE.md başında).
- `<mycl_constraint name="…">` — Yakalanmış kurallar bloğu.
- `<mycl_active_phase_directive>`, `<mycl_phase_status>`,
  `<mycl_phase_allowlist_escalate>` — DSI mesajları (turun başında
  mcl-activate.py tarafından gönderilir).

Tag içeriği değişebilir; tag adları sabittir. Hook bunları string
match ile arar.

[English]

MyCL uses three kinds of XML tags:

- `<mycl_core>` — Canonical project frame (top of CLAUDE.md).
- `<mycl_constraint name="…">` — Captured rules block.
- `<mycl_active_phase_directive>`, `<mycl_phase_status>`,
  `<mycl_phase_allowlist_escalate>` — DSI messages (sent at turn
  start by mcl-activate.py).

Tag content may vary; tag names are fixed. Hook searches them by
string match.

---

## 2. Plugin Orchestration / Plugin Orkestrasyon

[Türkçe]

**Kural A — Yerel git deposu:** Her MyCL-yönetimli projede yerel
`.git/` olmalı. İlk açılışta git deposu yoksa, geliştiriciye dilinde
tek kez "MyCL `git init` çalıştırsın mı?" sorulur (uzak yok, push
yok, otomatik commit yok). Onay `.mycl/config.json`'a kalıcı yazılır.

**Kural B — Curated plugin'ler sessizce çalıştırılır:** Curated
plugin set (örn. feature-dev, code-review, pr-review-toolkit,
security-guidance) her zaman çağrılır — MyCL fazıyla örtüşse bile.
Örtüşme fazlalık değil çok-açılı doğrulamadır. Çatışma → tek bir
Aşama 10 risk maddesi (provenance + iki gerekçe + AskUserQuestion).
Otomatik tiebreaker yok.

**Kural C — MCP-server plugin'leri yasak:** Kaynak ağacında
`.mcp.json` bulunan plugin curated setten elenir. Sadece binary CLI
araçları (semgrep, linter, formatter) izinlidir — MCP transport
taşımazlar.

[English]

**Rule A — Local git repository:** Every MyCL-managed project must
have a local `.git/`. On first activation, if no git repo exists, the
developer is asked once in their language whether MyCL may run
`git init` (no remote, no push, no auto-commit). Consent persisted in
`.mycl/config.json`.

**Rule B — Curated plugins dispatched silently:** The curated plugin
set (e.g. feature-dev, code-review, pr-review-toolkit,
security-guidance) is always invoked — even when its scope overlaps a
MyCL phase. Overlap is multi-angle validation, not redundancy.
Conflict → a single Phase 10 risk item (provenance + both rationales
+ AskUserQuestion). No automatic tiebreaker.

**Rule C — MCP-server plugins forbidden:** Plugins whose source tree
contains `.mcp.json` are filtered out at curation. Only binary CLI
tools (semgrep, linters, formatters) are allowed — they do not carry
MCP transport.

---

## 3. Phase Sequence Invariant / Faz Sıralılık İnvariantı

[Türkçe]

Faz durumu sıralı ilerletilir: her geçiş `current_phase`'i tam olarak
bir artırır. Faz atlatan doğrudan state setter'ları (örn. 1→4, 4→7)
ASLA kullanılmaz. Faz ilerlemesi tespit eden hook kodu durumu
downstream sentinel değere zorla atlatmaz; universal completeness
döngüsüne bırakılır. Sıralılık ihlali yasak — head/tail atlamalar
audit-driven invariant'ları kırar.

[English]

Phase state advances strictly sequentially: each transition
increments `current_phase` by exactly one. Direct state setters that
skip phases (e.g. 1→4, 4→7) are NEVER used. Hook code that detects
phase progression must not force-advance the state to a downstream
sentinel value; it defers to the universal completeness loop.
Sequence violations are forbidden — head/tail jumps break
audit-driven invariants.

---

## 4. STRICT Mode / KATI Mod

[Türkçe]

MyCL'de hiçbir block kategorisi otomatik açılmaz (fail-open YOK):

- spec-approval-block: sonsuza kadar deny
- asama-N-skip-block: sonsuza kadar deny
- ui-review-skip-block (Aşama 6b): sonsuza kadar deny
- phase-review-pending (Aşama 10/19/20): sonsuza kadar deny

5 strike'ta `*-escalation-needed` audit yazılır (kullanıcı görünür
sinyal). Block KALMAZ — kullanıcı bilinçli müdahale edene kadar deny
sürer.

State mutation (`mcl_state_set`/`reset`) Bash kanalından YASAK.
State, faz mantığının iç invariantı; sadece hook'lar mutate eder.
Faz ilerlemesi için: doğru `mcl_audit_log asama-N-complete` emit
(legitim recovery yolu).

[English]

In MyCL, no block category opens automatically (NO fail-open):

- spec-approval-block: deny forever
- asama-N-skip-block: deny forever
- ui-review-skip-block (Phase 6b): deny forever
- phase-review-pending (Phases 10/19/20): deny forever

At strike 5, an `*-escalation-needed` audit is written (user-visible
signal). Block REMAINS — deny continues until the user intervenes
intentionally.

State mutation (`mcl_state_set`/`reset`) is FORBIDDEN via the Bash
channel. State is the inner invariant of phase logic; only hooks
mutate it. To advance: emit `mcl_audit_log asama-N-complete`
correctly (legitimate recovery path).

---

## 5. Bilingual Output / Çift Dil Çıktı

[Türkçe]

Tüm MyCL hook çıktıları, DSI mesajları, AskUserQuestion soru ve
seçenekleri, manifesto, faz sonu notification — ÇİFT DİL halinde:
Türkçe blok önce (kullanıcının dili), boş satır, sonra İngilizce
blok (model'in çalışma dili). Etiket (TR:/EN:) yok.

İstisnalar (tek seferlik, çevrilmez): kod tanımlayıcıları, dosya
yolları, audit isimleri (`asama-4-complete`), CLI komutları, kod
parçaları, sabit teknik tokenlar (MUST/SHOULD).

[English]

All MyCL hook outputs, DSI messages, AskUserQuestion questions and
options, manifesto, phase-end notification — rendered as DUAL-LANG:
Turkish block first (user's language), blank line, then English
block (model's working language). No labels (TR:/EN:).

Exceptions (rendered once, not translated): code identifiers, file
paths, audit names (`asama-4-complete`), CLI commands, code
fragments, fixed technical tokens (MUST/SHOULD).

---

## 6. Filesystem Layout / Dosya Düzeni

```
.mycl/
├── state.json       (current_phase, spec_approved, spec_hash, ...)
├── audit.log        (append-only, sequential phase events)
├── trace.log        (append-only, transition records)
├── config.json      (git_init_consent, plugin choices)
├── specs/           (saved spec snapshots, sha256.md)
└── log/             (per-session post-tool diary)
```

Hooks: `~/.claude/hooks/{activate,pre_tool,post_tool,stop}.py`.
Lib: `~/.claude/hooks/lib/*.py`.
Skills: `~/.claude/skills/mycl/*.md`.
Data: `~/.claude/data/*.json`.
