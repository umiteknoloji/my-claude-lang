# MCL Özellik Kataloğu

**Güncel sürüm:** 10.0.0

---

## Temel Mimari

### Faz Modeli (10.0.0)

MCL her geliştirici mesajını sıralı 6 fazdan geçirir. Phase 2 yalnızca `is_ui_project=true` projeler için çalışır; UI olmayan projelerde Phase 1 → Phase 3 doğrudan geçilir.

| Faz | İsim | Sorumluluk | Onay gate'i |
|---|---|---|---|
| 1 | INTENT | Clarifying soru, precision audit, brief, `is_ui_project` tespiti | Summary-confirm askq |
| 2 | DESIGN_REVIEW | UI iskeleti + dev server (yalnızca UI projeleri) | Tasarım onay askq'i |
| 3 | IMPLEMENTATION | 📋 Spec dokümantasyonu + tam kod (TDD, scope guard) | Yok |
| 4 | RISK_GATE | Security, DB, UI/a11y, ops, perf, mimari drift, intent ihlali | HIGH'da otomatik blok |
| 5 | VERIFICATION | Test, lint, build, smoke raporu | Yok |
| 6 | FINAL_REVIEW | Audit trail tamlığı, regresyon, söz-vs-teslimat double-check | Yok |

```
Phase 1 ──onay──▶ [Phase 2 (is_ui_project ise)] ──onay──▶ Phase 3 ──▶ Phase 4 ──▶ Phase 5 ──▶ Phase 6
```

### Dil Köprüsü
- Tüm iletişim geliştiricinin dilinde (TR + EN destekli)
- Spec ve kod İngilizce — model her zaman İngilizce mühendislik çıktısı üretir
- Dil otomatik tespiti — ilk mesajdan belirlenir, sonraki tüm fazlarda korunur

### Hook Altyapısı

| Hook | Tetiklenme | Görev |
|---|---|---|
| `mcl-activate.sh` | Her `UserPromptSubmit` | STATIC_CONTEXT enjekte eder; ilk activate'te v2→v3 state migration çalıştırır |
| `mcl-stop.sh` | Her `Stop` | Faz geçişlerini yönetir, session log yazar, brief parse eder |
| `mcl-pre-tool.sh` | Her `PreToolUse` | Risk gate enforcement, scope guard, intent violation, drift check |
| `mcl-post-tool.sh` | Her `PostToolUse` | Session diary — her araç çağrısı için tek satır log |

**Hook Dominance İlkesi**
Behavioral kurallar yerine hook kararları (`decision:block`) tercih edilir. Aşağıdaki araç çağrıları hook seviyesinde bloke edilir:

| Blok | Koşul |
|---|---|
| `TodoWrite` | Phase 1-2'de (Phase 3+ serbest) |
| `Task` → Phase 4/5 | description'da faz anahtar kelimeleri varsa |
| `Bash` → state.json yazımı | Her zaman (state yalnızca hook sistemine ait) |

---

## Özellikler (Faz Bazlı)

### Phase 1 — INTENT

**Disambiguation Triage**
Belirsiz parametreleri iki kategoriye ayırır:
- **SILENT** — varsayılan al, brief'e `[assumed: X]` yaz (pagination size, hata mesajı metni, log level)
- **GATE** — tek tek sor (schema/migration, auth modeli, public API yüzeyi, geri döndürülemez iş mantığı)

**GATE Answer Coherence Check**
Kullanıcı bir GATE sorusunu yanıtladıktan sonra, cevabın teknik imlikasyonu tarif edilen mimariyle tutarlı mı kontrol eder.

**Contradiction Detection**
- Mantıksal çelişkiler ("offline AND real-time data" → hangisi öncelikli?)
- Nested conditional requirements: karmaşık şart cümlelerini numaralı listeye böler
- Hidden sub-tasks tespit

**Precision Audit (eski Phase 1.7, şimdi Phase 1 alt-aşaması)**
7 core boyut + `mcl-stack-detect.sh` tag'lerine göre stack add-on boyutları walk edilir. Her boyut üç sınıftan birine düşer:
- **SILENT-ASSUME** — industry default var, reversible. Brief'te `[assumed: X]` markla.
- **SKIP-MARK** — güvenli default yok. Brief'te `[unspecified: X]` markla.
- **GATE** — mimari etki var, tek soru sor.

Core 7 boyut (her projede): Permission/access, algorithmic failure modes, out-of-scope boundaries, PII handling, audit/observability, performance SLA, idempotency/retry.

**Stack add-on'lar:** Web base (typescript/javascript), frontend frameworks (react/vue/svelte/html-static), backend (python, java, csharp, ruby, php, go, rust), system (cpp, lua), mobile (swift, kotlin), domain-shape (cli, data-pipeline, ml-inference). Her add-on 2-5 delta boyut içerir.

**GATE Batching:** Aynı kategoride (Security / Database / UI / Operations / Performance) birden fazla GATE dimension fire ettiğinde tek `AskUserQuestion` (`multiSelect: true`) ile sorulur — her kategori en fazla 1 turn.

**Engineering Brief (Upgrade-Translator)**
Phase 1'in son adımı brief üretir. İki görev:
1. **Translate** — non-İngilizce parametreleri İngilizce'ye sadık çeviri
2. **Upgrade vague verbs** — `list`/`listele` → `render a paginated table`, `manage`/`yönet` → `expose CRUD operations`, vb.

Surgical verb'lerin standart teknik default'ları `[default: X, changeable]` marker'larıyla annotate edilir. Yasak eklemeler: yeni entity, feature, NFR, auth, audit, persistence.

**`is_ui_project` Tespiti (10.0.0)**
Phase 1 brief parser, `state.is_ui_project`'i üç sinyalden set eder:
- Intent anahtar kelimeleri (`UI`, `frontend`, `tasarım`, `mockup`, `design`, …)
- `mcl-stack-detect.sh`'tan stack tag'leri (react-frontend, vue-frontend, svelte-frontend, html-static, expo, …)
- Proje dosya ipuçları (`vite.config.*`, `next.config.*`, `tailwind.config.*`, kökte `index.html`, …)

Sinyaller belirsizse default `is_ui_project=true` (false negative maliyeti > false positive maliyeti).

**Summary-Confirm askq**
Phase 1'in tek onay gate'i. Geliştirici intent / constraints / success / context özetini onaylar. Onay sonucu:
- `is_ui_project=true` → `current_phase=2`, Phase 2 başlar
- `is_ui_project=false` → `current_phase=3`, Phase 3 başlar

Bu tek askq kanonik scope kontratıdır. Ayrı bir spec onayı yoktur (10.0.0 breaking).

### Phase 2 — DESIGN_REVIEW (10.0.0, yalnızca UI projeleri)

UI projesinde, Phase 1 onayı sonrası MCL tıklanabilir bir UI iskeleti + dev server kurar ve onay alır.

**UI iskeleti:**
- Build config dosyaları (vite/tailwind/tsconfig) önce yazılır
- Sonra dummy data ile çalışan frontend
- Stack auto-detect: vite, next, cra, vue-cli, sveltekit, expo, static (10 stack)

**Dev server:**
- Arka planda otomatik başlar
- Port allocator (default + 4 fallback)
- PID'yi `$MCL_STATE_DIR/dev-server.pid`'de takip eder
- URL state üzerinden surface edilir
- `dev-server.log`'tan tespit edilen build hataları pause-on-error tetikler
- Headless ortamlarda (`MCL_HEADLESS`, `CI`, Linux SSH no-DISPLAY) auto-start atlar

**Tasarım onayı:**
AskUserQuestion ile sabit body: "Tasarımı onaylıyor musun?" / "Approve this design?". Onay → `state.design_approved=true`, `state.current_phase=3`. Loop `/mcl-design-approve` ile manuel de kapatılabilir.

### Phase 3 — IMPLEMENTATION

Phase 2 (UI projesi) veya Phase 1 (UI olmayan) onayı sonrası başlar. İlk adım `📋 Spec:` bloğu yazmak; sonra TDD ile implementation.

**📋 Spec dokümantasyonu (10.0.0)**
Spec artık state-gating değildir — dokümantasyondur. Üç görev:
- Audit artifact (`.mcl/specs/NNNN.md` via `mcl-spec-save.sh`)
- Scope guard input (Technical Approach path'leri `state.scope_paths`'i doldurur)
- İngilizce olmayan prompt'lar için İngilizce semantic bridge

**Senior Engineer Spec — BASE bölümler:**
- Objective, MUST/SHOULD requirements, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope

**Koşullu Bölümler** (yalnızca tetiklendiğinde):
- **Non-functional Requirements** — performans/ölçek kısıtları belirtildiğinde
- **Failure Modes & Degradation** — dış bağımlılıklar veya async operasyonlar
- **Observability** — kritik prod yolu, güvenlik audit trail, kullanıcı davranış takibi
- **Reversibility/Rollback** — DB migration, feature flag, destructive operasyon
- **Data Contract** — API yüzeyi değişiklikleri, cross-service boundary

**Spec Format Advisory (10.0.0)**
Format ihlalleri (eksik H2 bölümleri, `📋` prefix yok) advisory'dir. Hook `spec-format-warn` audit emit eder; `decision:block` yok. Tur boyunca 3+ ihlal Phase 6 LOW soft fail tetikler. `state.spec_format_warn_count` sayar.

**Pattern Matching (eski Phase 3.5)**
Phase 3 başlamadan önce mevcut sibling dosyalar okunur:
- **Naming Convention**, **Error Handling Pattern**, **Test Pattern** — 3 zorunlu başlık
- 4 seviyeli cascade: sibling → proje geneli → ekosistem standardı → kullanıcıya sor
- Sonuçlar Phase 3 boyunca `PATTERN_RULES_NOTICE` olarak context'te tutulur

**Incremental TDD**
Batch TDD yerine gerçek red-green-refactor döngüsü:
1. Bir Acceptance Criterion için tek test yaz → RED verify
2. Minimum kodu yaz → GREEN verify
3. Refactor → GREEN verify
4. Sonraki criterion

**Test Komutu Çözümü**
Öncelik sırası: config dosyası → auto-detect → spec'ten çıkarım → geliştirici sorusu

**Kod Tasarım İlkeleri**
- Composition over inheritance
- SOLID
- Extension over modification
- Design pattern yalnızca gerçek problemi çözdüğünde

**Scope Guard**
Phase 3'te Write/Edit yalnızca `state.scope_paths`'te (spec'in Technical Approach'ından populate edilen) yollara izin verir. Glob pattern desteği (`src/auth/*.ts`).

**Scope Discipline**
Her Phase 3 turunda üç kural:
- Rule 1 SPEC-ONLY: spec'in MUST/SHOULD'larında olmayan hiçbir şey yapılmaz
- Rule 2 FILE SCOPE: sadece `scope_paths`'teki dosyalar değiştirilir
- Rule 3 ROOT CAUSE: semptomu değil sebebi düzelt

**Rollback Checkpoint**
Phase 1 onayında `git rev-parse HEAD` → `state.rollback_sha`. Her turda SHA ve `git reset --hard` komutu gösterilir (ilk tur, `/mcl-rollback` ile yeniden).

### Phase 4 — RISK_GATE

Tek faz, sıralı diyalog. Phase 3'ten sonra ve Phase 5'ten önce çalışır.

**Sıralı Diyalog**
Tüm riskler birer birer AskUserQuestion ile sunulur. Her risk için: `apply-fix / override` (skip kaldırıldı). Override reason zorunlu — `<mcl_state_emit kind="phase4-override">{rule_id, severity, category, reason}</mcl_state_emit>` marker'ı ile audit + Phase 5 raporu'na akar.

**4 Lens Kalitesi Tarama**
Eş zamanlı çalışır: (a) Code Review, (b) Simplify, (c) Performance, (d) Security. Semgrep SAST HIGH/MEDIUM bulguları otomatik uygulanır.

**Kategoriler:**

- **Security** — 3-tier:
  - L1 design-time (Phase 1 dimension): auth model, authz unit, CSRF stance, secret management, deserialization input
  - L2 per-Edit incremental scan (Edit/Write/MultiEdit'te); HIGH ise `decision:deny`
  - L3 Phase 4 START full scan; HIGH varsa state `pending`'de kalır

- **DB tasarımı** — 10 generic + 8 ORM × 3 anchor = 34 kural; `squawk` + `alembic check`

- **UI / a11y** — 22 kural (10 generic + 12 framework). Yalnızca a11y-critical bulgular HIGH; design tokens / reuse / responsive = MEDIUM

- **Ops** — 4 pack × 20 kural (deployment / monitoring / testing / docs)

- **Performans** — 3 pack × 11 kural (bundle / CWV / image), FE-only

- **Mimari drift (10.0.0 yeni)** — `state.scope_paths` (spec'ten) vs Phase 3 yazımları:
  - Scope boş → LOW (advisory)
  - Sibling layer ihlali → MEDIUM
  - Cross-layer ihlal (frontend → backend) → HIGH

- **Intent ihlali (10.0.0 yeni)** — `state.phase1_intent` negation'ları (`auth yok`, `DB yok`, `frontend only`) import path'leri ve modified dosyalarla match edilir. HIGH ihlaller Write'ı bloklar.

**Spec Compliance**
Phase 3 kodunun her MUST/SHOULD'u karşılayıp karşılamadığı kontrol edilir.

**Test layer coverage lens**
`hooks/lib/mcl-test-coverage.py`. 8 manifest format scan; 4 kategori (unit/integration/e2e/load) eksikse finding:
- TST-T01 HIGH: source code var, unit framework yok
- TST-T02 MEDIUM: integration framework yok
- TST-T03 MEDIUM: ui_flow_active + e2e yok
- TST-T04 MEDIUM: backend stack + production deployment + load tool yok

**Root Cause Chain**
Her bug fix veya davranış değişikliği için çok seviyeli kök sebep zinciri:
1. Görünür süreç — düşünce zinciri açık yazılır
2. Removal test — sebep kalkarsa üst problem çözülür mü?
3. Falsification — sebep doğruysa kontrol edilebilir X gözlemlenmeli

**Regression Guard Smart-Skip**
TDD green-verify GREEN + son yazımdan sonra → Regression Guard suite koşmaz. `last_write_ts` ve `tdd_last_green` state'e yazılır.

**Session Recovery**
Phase 4 yarıda kesilebilir. `.mcl/risk-session.md` her karar sonrası güncellenir.

**Plugin Dispatch Audit**
Phase 4 çalışırken her turda `trace.log` kontrol edilir. `pr-review-toolkit:*` veya `code-review:*` sub-agent dispatch'i + `semgrep_ran` trace eventi yoksa `PLUGIN_MISS_NOTICE` enjekte edilir, Phase 5'e geçiş engellenir.

**Impact Analysis (Phase 4 impact lens)**
Yeni yazılan kodun başka bölümlere etkileri: Import eden dosyalar, shared utility davranış değişikliği, API/contract kırılması, schema/migration etkileri, build/toolchain/dependency değişimleri.

**Plugin Çatışması — Provenance-First**
İki plugin çelişen hüküm verirse `[PLUGIN CONFLICT]` formatıyla her iki gerekçe gösterilir, geliştirici karar verir.

### Phase 5 — VERIFICATION

**Spec Coverage Tablosu**
`| Requirement | Test | Status |` — tüm MUST/SHOULD satırları (✅/⚠️/❌).

**Automation Barriers**
Call-graph tabanlı "gerçekten otomatize edilemeyen" liste. Hiçbiri tetiklenmezse omit edilir.

**Phase 5 Skip Detection**
`mcl-stop.sh` her stop'ta state kontrol eder. State `running` ise ve bu turda MCL prefix'li AskUserQuestion çalışmamışsa, audit'e `phase5-skipped-warn` yazılır. `mcl-activate.sh` bir sonraki turda `PHASE5_SKIP_NOTICE` enjekte eder.

**Hook Health Check**
Dört MCL hook'u son başarılı çalışma timestamp'ini `.mcl/hook-health.json`'a yazar. `mcl check-up` eksik veya 24 saatten eski bir alan bulursa WARN üretir.

**Lokalize rapor**
EN → geliştirici dili çevirisi. `phase5-verify` audit event'i emit edilir.

### Phase 6 — FINAL_REVIEW

Phase 5 sonrası, üç ortogonal check session kapanmadan önce çalışır:

- **(a) Audit trail tamlığı** — gerekli STEP audit event'leri emit edildi mi? (Sessizce atlanan fazları yakalar.)
- **(b) Final scan kümülasyonu** — security + DB + UI taramaları tekrar koşar; Phase 4 START baseline'ından sonra yeni HIGH bulgu = regression block.
- **(c) Söz-vs-teslimat** — Phase 1 confirmed parametreleri (intent + constraints) modified source dosyalarda keyword olarak match edilir (ters Lens-e izlenebilirliği).

Skip imkânsız: state field `phase6_double_check_done` `decision:block` ile enforce edilir.

**Severity-aware skip violations**
Phase 4'te HIGH skip + override yoksa LOW soft fail.

**Spec format advisory tally**
`state.spec_format_warn_count >= 3` ise LOW soft fail.

---

## Hook-First Architecture

Tüm "model Bash zorunlu" path'leri "hook fallback" path'lerine taşındı. Skill prose Bash opt-in optimization olarak kalır (caller=skill-prose audit provenance, synchronous-write); yokluğunda hook her şeyi sessizce halleder.

**Hook-level state population fallback**
`hooks/lib/mcl-phase-detect.py` Engineering Brief'i parse eder + `<mcl_state_emit kind="...">PAYLOAD</mcl_state_emit>` text marker'larını tarar. mcl-stop.sh idempotent çalıştırır → `phase1_intent / constraints / stack_declared / ops / perf / is_ui_project / ui_sub_phase` skill prose Bash çağrılmadığında bile populate olur. Audit `caller=mcl-stop, source=brief-parse|marker-emit` ile fallback path traceable.

**Skill prose auth**
Skill prose Bash invocation'ları (`bash -c '...mcl_state_set...'`) `MCL_SKILL_TOKEN` env + project-scoped token dosyası ile authenticate olur. Token her UserPromptSubmit'te rotate edilir (32-hex, mode 0600); replay window tek turn.

**Stack tag validation**
Phase 1 handoff sırasında set edilen `phase1_stack_declared` CSV'si, kanonik stack-tag set'ine karşı validate edilir. Bilinmeyen token stderr'e WARN üretir + `stack-tag-unknown` audit kaydı atılır.

---

## Hook Güvenlik Katmanları

**Güvenlik Refleksleri**
Write/Edit çağrıları credential ve secret taramasından geçer:
- Tier 1: `.env`, `*.pem`, `*.key`, `credentials.json` — gerçek değer içeriyorsa blok
- Tier 2: Bilinen token pattern'leri (`sk-...`, `ghp_...`, `AKIA...`, JWT vb.)
- Tier 3: Yüksek entropi assignment (Shannon ≥ 3.5, uzunluk ≥ 20)

**Scope Guard**
Phase 3'te Write/Edit yalnızca `scope_paths`'teki yollara izin verir. Glob pattern desteği.

**Architectural Drift Detection (10.0.0 yeni)**
Phase 4'te `state.scope_paths` ve gerçek Phase 3 yazımlarının layer signature'ı karşılaştırılır. Cross-layer ihlal (frontend → backend) HIGH; sibling layer MEDIUM.

**Intent Violation Check (10.0.0 yeni)**
Phase 4'te `state.phase1_intent` negation listesini import path'leri ve modified dosyalarla karşılaştırır. "no auth" + `import bcrypt` veya "no DB" + `import sqlalchemy` HIGH violation, Write blok.

---

## Genel Mekanizmalar

### Devtime Plan Critique
Plan üretildiğinde `general-purpose` subagent (claude-sonnet-4-6, extended thinking) planı 10 lens ile eleştirir: kök sebep derinliği, yan etki tahmini, boş/eksik durumlar, disambiguation eksiği, plan belirsizliği, halüsinasyon kontrolü, mevcut özelliklerle çakışma, extension/modification, kullanıcı görünürlüğü, test edilebilirlik. Sadece devtime.

### Anti-Sycophancy
- **Verdict-first formatı**: Olumsuz bulgu varsa ilk cümlede söylenir
- **Proaktif firing**: Geliştirici sormadan da teknik sorun yüzeylenir
- **Pressure resistance**: Yeni kanıt yoksa pozisyon korunur
- **Self-critique loop**: Her yanıt öncesi 4 soru, maks 3 iterasyon

### `/mcl-self-q`
Mesaj içine yazılınca o yanıt için self-critique süreci görünür hale gelir. Per-message, kalıcı değil.

### Kural Yakalama (Rule Capture)
Geliştirici bir fix'i genel kural yapmak istediğinde kapsam seçimi + preview + onay akışı çalışır.

### Human Authority — Karar Kapanışı
Geliştirici açık karar verdikten sonra (ret, seçim, risk kabulü) MCL konuyu yeniden açmaz.

### Proje Hafızası
`.mcl/project.md` — proje bilgi tabanı. Phase 5 sonrası güncellenir.

### Plan Critique Substance Validation
Pre-tool, general-purpose+sonnet Task'ı yakaladığında transcript'i tarayıp en son `Task(subagent_type=*mcl-intent-validator*)` çağrısının JSON verdict'ini okur. `verdict=yes` → allow + `plan_critique_done=true`; `verdict=no` → `decision:block` + reason.

### Session Context Bridge
Cross-session bilgi köprüsü: `mcl-stop.sh` her Stop'ta `.mcl/session-context.md` yazar. Yeni session başında `mcl-activate.sh` dosyayı okur ve `SESSION_CONTEXT_NOTICE` olarak `additionalContext`'e enjekte eder.

### Root Cause Chain Discipline
Plan-mode + all-mode keyword scan: TR + EN heuristik trigger keyword seti. Eksikse audit'e `root-cause-chain-skipped-warn` yazılır.

---

## Komutlar

| Komut | Açıklama |
|---|---|
| `/mcl` | MCL'yi zorla aktive eder |
| `/mcl-version` | Kurulu sürümü gösterir |
| `/mcl-update` | MCL'yi git pull + install.sh ile günceller |
| `/mcl-restart` | Tüm faz state'ini sıfırlar |
| `/mcl-finish` | Birikmiş Phase 4 etkilerini özetler + Semgrep taraması |
| `/mcl-doctor` | Token & maliyet raporu |
| `/mcl-checkup` | Sağlık kontrolü |
| `/mcl-self-q` | O yanıt için self-critique sürecini görünür yapar |
| `/mcl-rollback` | Rollback checkpoint SHA'sını gösterir |
| `/mcl-design-approve` | Phase 2 dev server'ı durdur, Phase 3'e geç |
| `/mcl-dev-server-start` | Dev server'ı manuel başlat |
| `/mcl-dev-server-stop` | Dev server'ı manuel durdur |
| `/mcl-phase6-report` | On-demand Phase 6 double-check raporu |
| `/codebase-scan` | 12-pattern codebase taraması |
| `/mcl-security-report` | Tam backend güvenlik taraması |
| `/mcl-db-report` | Tam DB tasarım taraması |
| `/mcl-db-explain` | `EXPLAIN` çalıştır (`MCL_DB_URL` gerekir) |
| `/mcl-ui-report` | Tam UI taraması |
| `/mcl-ui-axe` | Runtime `axe-core` (`MCL_UI_URL` gerekir) |
| `/mcl-ops-report` | Tam operasyonel disiplin taraması |
| `/mcl-perf-report` | Tam performans taraması |
| `/mcl-perf-lighthouse` | Lighthouse ile runtime CWV taraması |
| `/mcl-resume <çözüm>` | `paused_on_error` state'ini temizle |

---

## Token & Maliyet Muhasebesi

- Her tur `FULL_CONTEXT` karakter sayısı `.mcl/cost.json`'a loglanır
- `/mcl-doctor` komutu: injection overhead, cache write/read maliyet dökümü, "MCL açık vs kapalı" karşılaştırması
- Sonnet 4.6 fiyatlandırması ($3/MTok input, $0.30/MTok cache read)

---

## Session & State Yönetimi

### State Dosyası (`.mcl/state.json`)
Hook sistemi tarafından yönetilir — doğrudan Bash yazımı bloke edilir. Schema v3 (10.0.0). Ayrıntı için: [docs/state-schema.md](docs/state-schema.md).

**State migration v2 → v3:**
- İlk activate'te otomatik
- Backup: `.mcl/state.json.backup.pre-v3`
- Audit event: `state-migrated-10.0.0`
- Migration kuralları: phase 2/3/4 → 3, phase 4.5 → 4 (legacy schema migration), `spec_approved` → `design_approved` (true preserved), `phase4_5_*` → `phase4_*`, drop `precision_audit_*` ve `phase_review_state`

**`mcl_get_active_phase()`**
Tüm state field'larını okuyup tek bir effective phase string döndürür: `"1"`, `"2"`, `"3"`, `"4"`, `"5"`, `"6"`, `"?"`.

### Session Log (`.mcl/log/*.md`)
Her Stop hook'unda tur özeti.

---

## Güvenlik & Sınırlama Kuralları

**Plugin Orkestrasyon**
- **Rule A**: Projede `.git/` yoksa tek seferlik onay alarak `git init`
- **Rule B**: Curated plugin'ler sessizce çalıştırılır; çatışmada provenance-first
- **Rule C**: MCP-server plugin'leri yasaklı; binary CLI araçlar (semgrep) izinli

**Hook Dominance**
`mcl-pre-tool.sh` şu araç çağrılarını bloke eder:
- `TodoWrite` Phase 1-2 → MCL state.json ile yönetiyor
- `Task` → Phase 4/5 dispatch → bu fazlar sub-agent'a devredilemez
- `Bash` → state.json yazımı → state yalnızca hook sistemine ait

**Pasted CLI Passthrough**
Shell komutu yapıştırıldığında MCL Phase 1'i atlar. Destructive operasyonlar yine de onay alır.

---

## Stack-Agnostik Disiplin

MCL kuralları tek bir ekosisteme bağlı değildir. Stack tespiti (`mcl-stack-detect.sh`) hangi add-on rule pack'lerin çalışacağını bilgilendirir; core pipeline'ı asla gate'lemez. TDD, scope guard, risk gate, verification raporu her stack'te aynı şekilde çalışır.

---

## Bilinen Sınırlamalar

### post-tool hook race — paralel tool batch

**Sorun.** Claude Code'un resmi hook lifecycle belgelerine göre `PostToolUse` hook'ları async, non-deterministic sırada fire eder. `PostToolBatch` shell hook'larda mevcut değil.

**MCL'deki etki.** İki paralel `mcl-post-tool.sh` aynı snapshot'ı okuyup farklı field yazarsa, son yazar kazanır → diğer field'ın update'i kaybolur.

**Etki seviyesi: düşük-orta.**
- `last_write_ts` kaybı → regression-guard smart-skip yanlış değerlendirir → gereksiz suite re-run (perf only, korrektlik etkisi yok)
- `regression_block_active=false` kaybı → eventual consistency ile sonraki turda kapanır

**Mitigasyon kasıtlı eklenmedi.** Audit trail (`audit.log`) append-only olduğu için forensic olarak kayıp yok; state.json field kaybı stop hook'un re-evaluation pattern'i ile telafi edilir.

### Diğer hook'lar
- `mcl-pre-tool.sh` state yazımları **güvenli** — PreToolUse serileşik (resmi garanti).
- `mcl-activate.sh` ve `mcl-stop.sh` turda 1 kez fire eder — race yok.

---

## Kurulum

```bash
git clone https://github.com/YZ-LLM/my-claude-lang.git
bash my-claude-lang/install.sh
```

`install.sh` global tek seferlik kurulum yapar:
- `~/.mcl/lib/` altına repo'yu klonlar (veya günceller)
- `~/.local/bin/mcl-claude` symlink'ini oluşturur
- `~/.mcl/projects/` kökünü hazırlar

**Kullanım:**
```bash
cd <herhangi-bir-proje>
mcl-claude
```

**9.x'ten yükseltme.** `bash install.sh` sonrası, projendeki ilk `mcl-claude` çağrısında `mcl-activate.sh` state'i v2'den v3'e otomatik migrate eder. Backup `.mcl/state.json.backup.pre-v3`'te tutulur.

**Kaldırma:**
```bash
rm -rf ~/.mcl ~/.local/bin/mcl-claude
```
