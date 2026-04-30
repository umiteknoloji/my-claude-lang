# Değişiklik Günlüğü

[Keep a Changelog](https://keepachangelog.com) formatı. Her yeni sürümde
`[Unreleased]` bölümü `[X.Y.Z] - YYYY-MM-DD`'ye dönüştürülür.

---

## [Unreleased]

## [8.18.1] - 2026-04-30

### Düzeltildi — Phase 4a path redirect (UI-BUILD LOCK preempt)

Phase 4a (BUILD_UI) sırasında model "API mock" mental model'iyle `src/api/mock.ts` gibi backend-paterni yollara yazmaya çalışıyordu. PreToolUse hook bu yolları reddediyor (`src/api/`, `src/services/`, `src/lib/db/`, vb.) ve developer turn kaybediyordu. Hook davranışı doğru — eksik olan, model'in ilk yazımda doğru yolu seçmesini sağlayacak proaktif yönlendirmeydi.

- **`skills/my-claude-lang/phase4a-ui-build.md`** — "Path Discipline" altına 7-satır redirect tablosu eklendi (X→Y eşleştirme): `src/api/<name>.ts` → `src/mocks/<name>.mock.ts`, `src/services/<name>.ts` → `src/components/__fixtures__/<name>.fixture.ts`, `pages/api/...` → inline constant, vb. Model ana skill'i her Phase 4a turn'ünde okuyor; sub-skill'e (fixtures.md) inmesine gerek kalmıyor.
- **`skills/my-claude-lang/phase4c-backend.md`** — "Remove Dev-Only Bits" Delete listesine `src/mocks/` cleanup bullet'ı eklendi. Grep-verified (3 alias varyantı: `src/mocks/`, `../mocks/`, `@/mocks/`); test/spec dosyalarındaki referanslar korunur. Boş ise `rm -rf src/mocks/` Phase 4 Execution Plan kuralı altında.
- **`skills/my-claude-lang/phase4a-ui-build/fixtures.md`** — Trailing prohibition bullet'ı ana skill'deki tabloya pointer'a dönüştürüldü (drift önleme; tek hakikat kaynağı).

Tests: 27/0/2 unit, 54/0/0 e2e — regresyonsuz.

## [8.17.0] - 2026-04-30

### Düzeltildi — Skill prose state plumbing nihayet gerçekten çalışıyor

8.10.0'dan beri eklenen skill prose Bash plumbing'i (`phase1_intent`, `phase1_constraints`, `phase1_stack_declared`, `phase1_ops`, `phase1_perf`, `ui_sub_phase=UI_REVIEW` transition) **production'da hiç çalışmamış**. Sebep: `mcl_state_set` auth-check `$0`'a bakıyor; skill prose `bash -c '...'` invocation'ında `$0=bash` → whitelist match etmiyor → `deny-write` audit + write reject. `mcl_audit_log` auth-check'i bypass ettiği için audit event'leri başarılı görünüyordu (Phase 6 (a) yanıltıcı clean rapor verdi) ama `state.json` field'ları null kalıyordu. E2E test bu davranışı uçtan uca kanıtladı (`tests/cases/e2e-full-pipeline.sh:1.B`).

#### MCL_SKILL_TOKEN auth path
- **`hooks/lib/mcl-state.sh`** — `_mcl_state_auth_check` extension: hook entry whitelist (existing) + skill-token path (new). Hem `MCL_SKILL_TOKEN` env var hem `$MCL_STATE_DIR/skill-token` dosyası varsa ve içerikleri eşleşiyorsa write authorize edilir, audit'e `caller=skill-prose` yazılır. Yeni helper `mcl_state_skill_token_rotate` (32-hex token, `openssl rand` veya `/dev/urandom` fallback, mode 0600).
- **`hooks/mcl-activate.sh`** — Her UserPromptSubmit'te `mcl_state_skill_token_rotate` çağrısı. Önceki turn'ün token'ı overwrite edilir; replay attack window tek turn ile sınırlı.
- **`mcl_state_set` audit caller field** — `MCL_AUTH_CALLER` env var ile thread edilir. Hook entry path → `caller=mcl-stop.sh` vb.; skill-token path → `caller=skill-prose`. Audit log forensik analizi için provenance net.

#### 4 skill prose dosyası token-aware Bash prefix
Her skill prose Bash bloğunun başında:
```bash
[ -n "${MCL_STATE_DIR:-}" ] && [ -f "$MCL_STATE_DIR/skill-token" ] \
  && export MCL_SKILL_TOKEN="$(cat "$MCL_STATE_DIR/skill-token")"
```
- `skills/my-claude-lang/phase1-rules.md` (Phase 1 → 1.7 handoff)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (Phase 1.7 → 1.5 audit emission)
- `skills/my-claude-lang/phase4a-ui-build.md` (UI_REVIEW transition)
- `skills/my-claude-lang/phase5-review.md` — değişmedi (yalnızca `mcl_audit_log` çağrısı, auth-check'siz path)

#### Phase 4.5 Dialog Batch-Action
- **`skills/my-claude-lang/phase4-5-risk-review.md`** — Risk count ≥ 3 ise sequential dialog ÖNCESİ tek `AskUserQuestion` (multiSelect false, 3 seçenek): "Hepsi kabul / Hepsi reddet / Tek tek bak". Accept-all path'inde tüm risk'ler tek turn'de auto-fix + summary; reject-all path'inde dismiss audit; one-by-one path'inde mevcut sequential dialog. Eşik 3 (1-2 risk için batching overhead mantıksız). State field: `phase4_5_batch_decision` (null|accept_all|reject_all|one_by_one).
- **`hooks/lib/mcl-state.sh`** — Default schema'ya `phase4_5_batch_decision: null` eklendi.

#### Side-effect bug fix (8.7.1'den beri açık)
- **`hooks/mcl-stop.sh:532`** — `${_PR_PHASE}` undefined variable referansı `set -u` altında script'i öldürüyordu. Sonuç: Phase 4.5 START enforcement bloğunda `phase_review_state="pending"` atandıktan hemen sonra hata → 5 sequential gate (security/db/ui/ops/perf) **production'da hiç çalışmamış**. Tek karakter düzeltme: `_PR_PHASE` → `_PR_ACTIVE_PHASE`. E2E `tests/cases/e2e-full-pipeline.sh:14.C` ile yakalandı.

#### E2E test infrastructure
- **`tests/cases/e2e-full-pipeline.sh`** — Hibrit e2e: bash test + manual checklist. Mevcut coverage: Phase 1 (3 test, auth-check baseline + token path inversion + rotation), Phase 14 (3 test, sticky-pause + 5 gate baseline + sequential ordering), Phase 25 (1 test, pause-on-error trigger via stub helper). 54/0/0 pass.
- **`tests/e2e/manual-checklist.md`** — 33 satırlık coverage tablosu, model-bağımlı adımlar (AskUserQuestion turn'leri, npm-driven dev server, gerçek Claude session) için.

### Bilinen sınırlar
- Skill-token mekanizması cryptographic değil — local plumbing trust boundary (accidental misuse engelleme amaçlı). Token dosyası mode 0600, session-scoped, her UserPromptSubmit rotate. Yeterli güvenlik MCL'in lokal yürütme modeli için.
- Batch-action reverse path 8.18.0'a kadar model-behavioral. Geliştirici batched seçimde hata yapıp sonraki turn'de düzeltme istemezse hata sessiz kalır.
- Phase 4.5 batch-action `mcl-stop.sh`'a hook-level shortcut entegre etmedi — skill prose state'i set ediyor ama hook tarafı şu an sequential path ile aynı yolu izliyor. Hook integration 8.18.0+.
- E2E coverage manual-checklist'te 33 satırın 7'si ✅. Geri kalanı sonraki turn'lerde adım adım eklenecek.

## [8.16.0] - 2026-04-30

### Eklendi — GATE Batching + Hook State-Population Guard

8.15.0 skill prose sprint state plumbing'i model davranışına bıraktı: 4 ayrı transition'da (Phase 1 handoff, Phase 1.7 audit, Phase 4a→4b, Phase 5→5.5) model `mcl_state_set` + `mcl_audit_log` Bash çağırmazsa state set edilmez ve hook seviyesinde detect yoktu. Ek olarak 8.15.0'ın ops (DEP/MON/TST/DOC) + perf (PERF) dimension'ları greenfield'da da fired olduğu için Phase 1.7 turn sayısı 12 → 14-16'ya çıkmıştı. 8.16.0 bu iki yan etkiyi kapatır + GATE patlamasını yarıya indirir.

#### GATE Batching (Phase 1.7 turn sayısı yarıya iner)
- **`skills/my-claude-lang/phase1-7-precision-audit.md`** — Aynı kategoride birden fazla GATE dimension fire ettiğinde tek `AskUserQuestion` (`multiSelect: true`) ile sorulur. Kategoriler: Security / Database / UI / Operations / Performance. Maksimum 5 turn (mevcut 14-16 turn yerine).
  - Tek-dimension fire'lar yine tek-soru formuyla sorulur — batching sadece ≥ 2 dimension aynı kategoride fire ettiğinde uygulanır.
  - **Reverse path (model-behavioral, 8.17.0'a kadar):** Geliştirici sonraki turn'de batched dimension'a explicit feedback verirse model batched answer'ı discard edip tek-soru formuyla yeniden sorar. Hook-level rollback yok; structured batch-revise feature 8.17.0'da.

#### Hook State-Population Guard (skill prose Bash unutulursa LOW soft fail)
- **`hooks/lib/mcl-phase6.py`** — Phase 6 (a) audit-trail check'e 4 yeni LOW soft fail event eklendi: `phase1_state_populated`, `phase1_ops_populated`, `phase1_perf_populated`, `ui_sub_phase_set`. HIGH değil — skill prose model behavior; hook execution'ı block etmez. Eksik event = developer'a görünür uyarı, downstream'in default state ile çalıştığını ortaya çıkarır.

#### `mcl_state_set` String Auto-Coerce Dokümantasyonu
- **`skills/my-claude-lang/phase4a-ui-build.md`** — `mcl_state_set` Python `json.loads` fallback davranışı explicit dokümante edildi: bare scalar (`UI_REVIEW`, `BACKEND`) string olarak auto-quote edilir; integer (`3`, `42`), JSON literal (`true`, `false`, `null`) ve JSON object/array parsed type olarak korunur. Mevcut state'teki integer field'lar (`current_phase`, `schema_version`, `last_update`, `phase4_5_high_baseline.*`) auto-coerce davranışından etkilenmez — JSON int olarak parse edilir, int kalır. 8.15.0'daki "outer-single + inner-double" quoting nüansı artık opsiyonel (kod değişmedi, sadece kullanım sadeleşti).

#### Stack Tag Validation
- **`hooks/lib/mcl-state.sh`** — `_mcl_validate_stack_tags` helper. `phase1_stack_declared` CSV'sindeki her token kanonik stack-tag set'ine karşı validate edilir. Bilinmeyen token (`react-frontnd` typo, `db-postgresql` non-canonical alias) stderr'e WARN üretir + `stack-tag-unknown` audit kaydı atılır. Set write block edilmez — uyarı advisory.
- **`skills/my-claude-lang/phase1-rules.md`** — handoff Bash'i `_mcl_validate_stack_tags` çağrısı içerir.

#### Audit emissions (skill prose, since 8.16.0)
- `phase1-rules.md` — `mcl_audit_log "phase1_state_populated" ...` handoff sonrası
- `phase1-7-precision-audit.md` — `mcl_audit_log "phase1_ops_populated" ...` + `phase1_perf_populated`
- `phase4a-ui-build.md` — `mcl_audit_log "ui_sub_phase_set" ...` UI_REVIEW transition sonrası

### Bilinen sınırlar
- GATE batching reverse path 8.17.0'a kadar model-behavioral. Geliştirici batched seçimde hata yapıp sonraki turn'de düzeltme istemezse hata sessiz kalır.
- State-population events LOW soft fail; HIGH'a yükseltme 8.18.0'da değerlendirilir (false-positive risk: hook geç başlayan project'lerde).
- Known stack tag listesi `mcl-state.sh` içinde statik. Yeni stack eklendiğinde manual güncelleme.

## [8.15.0] - 2026-04-30

### Eklendi — Skill Prose Sprint (rule freshening)

8.10.0-8.14.0 sürümleri state plumbing'i ekledi (`phase4_5_*_scan_done`, `phase4_5_high_baseline.{security,db,ui,ops,perf}`, `phase1_ops`, `phase1_perf`, `phase1_intent`, `phase1_constraints`, `paused_on_error`, `dev_server`, `phase6_double_check_done`); hook ve orchestrator tarafı bu field'ları **okuyor** ama skill prose'lar **set etmiyordu**. Real-use simülasyonu sonucu (54 turn senaryo) tespit edilen 4 blocker'ın hepsi bu yüzdendi:
- `phase1_*` state field'ları skill prose'unda set edilmiyor → Phase 6 (c) promise-vs-delivery hep LOW skip; Phase 1.7 ops/perf dimension'ları audit etmiyor.
- `ui_sub_phase=UI_REVIEW` transition explicit değil → 8.12.0 dev server otomatik başlamıyor; design loop tetiklenmiyor.
- `phase5-verify` audit event emit edilmiyor → Phase 6 (a) audit-trail transcript fallback'a düşüyor.
- Greenfield'da `mcl-stack-detect.sh` boş döner → Phase 1.7 stack add-on'ları (DB/UI/ops/perf) hiç tetiklenmez.

8.15.0 **rule freshening** sürümüdür. Yeni kod yok, yeni feature yok. Mevcut state plumbing'in pratikte çalışmasını garanti altına alan toplu skill prose update'i — 6 skill dosyası + 1 hook regex extension'ı.

#### Skill prose updates (6 dosya)

- **`skills/my-claude-lang/phase1-rules.md`** — Phase 1 → 1.7 handoff section eklendi. Phase 1 summary onayından sonra skill 3 `mcl_state_set` Bash çağrısı yapar:
  - `mcl_state_set phase1_intent "<intent>"` — Phase 6 (c) için
  - `mcl_state_set phase1_constraints "<constraints>"` — Phase 6 (c) için
  - `mcl_state_set phase1_stack_declared "<csv>"` — `mcl-stack-detect.sh` greenfield fallback
- **`skills/my-claude-lang/phase1-7-precision-audit.md`** — (a) "DB Design Dimensions" sonrası 5 yeni dimension eklendi: 20. Deployment Strategy (DEP), 21. Observability Tier (MON), 22. Test Policy (TST), 23. Documentation Level (DOC), 24. Performance Budget (PERF). Her birinin trigger condition'ı 8.13.0/8.14.0 ile uyumlu. (b) Phase 1.7 → 1.5 handoff Bash: `mcl_state_set phase1_ops '{deployment_target,observability_tier,test_policy,doc_level}'` + `mcl_state_set phase1_perf '{budget_tier}'`.
- **`skills/my-claude-lang/phase4a-ui-build.md`** — Phase 4a → 4b transition section. UI dosyaları + `npm install` tamamlanınca `mcl_state_set ui_sub_phase '"UI_REVIEW"'` (JSON-quoted string). Bu olmadan `mcl-stop.sh` 8.12.0 dev_server auto-start tetiklenmez. Quoting nüansı CHANGELOG + skill prose'da explicit.
- **`skills/my-claude-lang/phase5-review.md`** — Phase 5 → 5.5 audit emission. 3 section (Spec Compliance, MUST TEST, Process Trace) tamamlandıktan sonra `mcl_audit_log "phase5-verify" "phase5" "report-emitted"`. Phase 6 (a) için deterministik signal — transcript header fallback secondary'ye düştü.
- **`skills/my-claude-lang/phase5-5-localize-report.md`** — 14 dilden lokalize Verification Report header tablosu eklendi. Model 14 dilden seçer; 14-set dışı ise EN fallback. Phase 6 transcript fallback regex'i ile birebir eşleşir.
- **`skills/my-claude-lang/all-mcl.md`** — STEP-12 (Phase 1 summary), STEP-40a (Phase 4a UI build), STEP-50 (Phase 5 spec coverage), STEP-64 (Phase 1.7 precision audit) description satırlarına `(since 8.15.0)` referansları eklendi. Yeni STEP yok.

#### Hook regex extension (1 dosya)
- **`hooks/mcl-stop.sh:1769`** — Phase 6 trigger transcript fallback regex'i 2 dilden (TR + EN) 14 dile genişletildi:
  - EN: Verification Report
  - TR: Doğrulama Raporu
  - FR: Rapport de Vérification
  - DE: Verifizierungsbericht
  - ES: Informe de Verificación
  - JA: 検証レポート
  - KO: 검증 보고서
  - ZH: 验证报告
  - AR: تقرير التحقق
  - HE: דוח אימות
  - HI: सत्यापन रिपोर्ट
  - ID: Laporan Verifikasi
  - PT: Relatório de Verificação
  - RU: Отчёт о проверке

  Çeviri kalitesi 12 fallback dil için heuristic; native speaker review 8.15.x'te. Birebir audit event (`phase5-verify`) skill prose'da emit edildiğinden bu fallback artık yalnızca eski projeler için.

#### State plumbing (yeni state field yok)
8.15.0 mevcut state field'larının pratikte çalışmasını sağlar. Yeni schema bump yok. Yeni keyword yok. Yeni env var yok.

#### Karar matrisi (kabul edilen varsayılanlar)
- Çeviri kalitesi 14 dil için heuristic; native speaker review 8.15.x
- Skill prose vs hook enforcement: Bash talimatları model-behavioral; hook seviyesinde detect 8.16.0+
- `phase1_stack_declared` parsing: comma-separated string; JSON array conversion 8.16.x
- JSON quoting (`mcl_state_set ui_sub_phase '"UI_REVIEW"'`): outer single-quote shell escape, inner double-quote JSON string

### Test sonuçları
- T1 phase1-rules.md handoff section eklendi PASS
- T2 phase1-7 5 yeni dimension + state-set Bash eklendi (3 occurrences of `8.15.0` in skill) PASS
- T3 phase4a-ui-build.md UI_REVIEW transition section eklendi PASS
- T4 phase5-review.md audit emission section eklendi PASS
- T5 phase5-5-localize-report.md 14-dil header tablosu eklendi (2 occurrences) PASS
- T6 all-mcl.md STEP-12/40a/50/64 description footnotes eklendi (4 occurrences) PASS
- T7 mcl-stop.sh:1769 regex 14 dile genişletildi PASS
- T8 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `skills/my-claude-lang/phase1-rules.md` (Phase 1 → 1.7 handoff)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (5 yeni dimension + state-set)
- `skills/my-claude-lang/phase4a-ui-build.md` (UI_REVIEW transition)
- `skills/my-claude-lang/phase5-review.md` (phase5-verify audit)
- `skills/my-claude-lang/phase5-5-localize-report.md` (14-dil header)
- `skills/my-claude-lang/all-mcl.md` (STEP description footnotes)
- `hooks/mcl-stop.sh` (Phase 6 trigger 14-dil regex)
- `VERSION` (8.14.0 → 8.15.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.15.x patch'lerine ertelendi)

- **README.md / README.tr.md güncellenmedi** — 8.15.0'da yeni feature / keyword / env var / state field yok; CLAUDE.md release rule'u "yeni özellik varsa README" diyor — bu sürümde hiçbiri yok. CHANGELOG yeterli.
- **Çeviri kalitesi 14 dil**: 12 fallback dil için header çevirileri makine-translation kalitesinde; native speaker review 8.15.x.
- **Skill prose model-behavioral**: Bash talimatları model'in çağırmasına bağlı. Model unutursa state set edilmez. Hook seviyesinde detect mekanizması yok (8.10.0 NL-ack ile aynı sınır). 8.16.0+ Phase 6 (a) "phase1_intent state'te yoksa block" eklenebilir.
- **`phase1_stack_declared` parse format**: comma-separated string; orchestrator'lar `set(t for t in tags.split(','))` ile parse eder. JSON array conversion 8.16.x.
- **JSON quoting nüansı**: `mcl_state_set ui_sub_phase '"UI_REVIEW"'` — outer single-quote shell escape, inner double-quote JSON string. Skill prose'da explicit example var; yanlış quoting `mcl-state` validation rejection üretir.
- **Real-use turn sayısı azalmaz**: 8.15.0 UX değil, rule freshening — Phase 1.7 GATE patlaması (real-use rapor #1) hâlâ var. UX iyileştirmesi 8.16.0+.

## [8.14.0] - 2026-04-30

### Eklendi — Performance Budget (İŞ 5, son iş)

8.7-8.13 product / DB / UI / ops disiplini tamamlandı; **runtime performans** boştu — 4MB JS bundle production'a gidebilir, LCP 6 saniye, hero image 2MB PNG. 8.14.0 üç performans ekseninde FE-only enforcement ekler (8.9.0/8.13.0 mirror 3-tier).

#### Yeni dosyalar
- **`hooks/lib/mcl-perf-rules.py`** — 3 rule pack, 11 rule, `category=perf-*` field:
  - **Bundle** (4): PRF-B01 over-budget-critical (>2× budget HIGH), B02 over-budget (100-200% MEDIUM), B03 no-build-output (LOW advisory), B04 large-chunk (>50KB tek chunk LOW).
  - **CWV** (4): PRF-C01 LCP-poor (>4s HIGH), C02 LCP-needs-improvement (2.5-4s MEDIUM), C03 CLS-poor (>0.25 MEDIUM), C04 TBT-poor (>600ms MEDIUM).
  - **Image** (3): PRF-I01 image-huge (>500KB HIGH), I02 image-large (100-500KB MEDIUM), I03 png-no-webp-fallback (LOW).
- **`hooks/lib/mcl-perf-bundle.sh`** — build output walker: `dist/`, `build/`, `.next/static/chunks/`, `out/` taranır; `*.js` dosyaları `gzip.compress` ile aggregate edilir. **Build invoke etmez** — kullanıcı `npm run build` çalıştırmamışsa PRF-B03 advisory.
- **`hooks/lib/mcl-perf-lighthouse.sh`** — `MCL_UI_URL` env reuse (8.9.0 axe ile aynı env — kullanıcı tek URL set eder, hem axe hem lighthouse çalışır). Yoksa lokalize advisory; varsa `npx lighthouse --output=json --only-categories=performance`; LCP/CLS/TBT/TTI/FCP extract. `--json` flag orchestrator dispatch için.
- **`hooks/lib/mcl-perf-scan.py`** — orchestrator: bundle delegate + image walk (5 standart asset dir) + (optional) lighthouse delegate; lokalize markdown render (TR/EN).

#### State şeması
- `phase4_5_perf_scan_done: false` — idempotency flag
- `phase4_5_high_baseline.perf: 0` — Phase 6 (b) regression baseline (8.11.0/8.13.0 schema extend)
- `phase1_perf: {budget_tier}` — Phase 1.7 dimension state

#### Hook entegrasyonu
- **`hooks/mcl-stop.sh`** — Ops gate sonrası: Phase 4.5 START Perf gate. Sıra: sticky-pause → security → db → ui → ops → **perf** → standart Phase 4.5 reminder → Phase 6 gate. HIGH ≥ 1 → state `pending`'de + `decision:block` (kategori listesi); HIGH = 0 → done=true + baseline.perf=0; MEDIUM listesi standart reminder reason'a `[Perf-<sub>]` etiketli inject. **Lighthouse L3'te çalışmaz** (60s overhead); sadece `/mcl-perf-report` keyword'ünde.
- **`hooks/mcl-activate.sh`** — `/mcl-perf-report` + `/mcl-perf-lighthouse` keyword block'ları.

#### Konfigürasyon
- `$MCL_STATE_DIR/perf-config.json` (8.5.0 isolation):
  ```json
  {"perf": {"bundle_budget_kb": 200, "bundle_critical_multiplier": 2,
            "image_high_kb": 500, "image_medium_kb": 100,
            "lcp_high_ms": 4000, "lcp_medium_ms": 2500,
            "cls_high": 0.25, "tbt_high_ms": 600}}
  ```
- Defaults: bundle 200KB JS gzip, image 100/500KB, LCP 2.5/4s, CLS 0.25, TBT 600ms.

#### Karar matrisi (kabul edilen + kullanıcı değişikliği)
- Bundle: **walker-only** (build invoke etme)
- CWV env: **`MCL_UI_URL` reuse** (8.9.0 axe ile shared — kullanıcı isteği)
- Image scope: **5 standart dir** (`public`, `static`, `assets`, `src/assets`, `app/static`)
- Bundle threshold: **200KB JS gzip**, configurable
- Image format: **WebP only** suggestion (AVIF 8.14.x)
- Lighthouse: **desktop profile** + 90s timeout
- Phase 1 keyword (fast/scale/mobile/low-latency): **GATE**
- Build output: **4 standart dir** (dist / build / .next/static/chunks / out)

#### Trigger condition
**FE stack-tag tespit edildiğinde** (`react-frontend|vue-frontend|svelte-frontend|html-static`). Backend-only / lib / CLI / data-pipeline projelerinde tüm perf pipeline skip; audit `perf-scan-skipped reason=no-fe-stack-tag`.

#### Audit events
- `perf-scan-full | mcl-stop | high=N med=N low=N duration_ms=N categories=bundle,cwv,image bundle_kb=<n>`
- `perf-scan-block | mcl-stop | full-scan high=N`
- `perf-scan-skipped | mcl-stop | reason=no-fe-stack-tag`
- `perf-bundle-delegate | mcl-perf-scan | total_gzip_kb=N file_count=N output_dir=<path>`
- `perf-bundle-skip | mcl-perf-scan | reason=no-build-output`
- `perf-lighthouse-delegate | mcl-perf-scan | url=<u> lcp_ms=N cls=<f> tbt_ms=N`
- `perf-lighthouse-skip | mcl-activate | reason=no-MCL_UI_URL` (reuse)
- `mcl-perf-report | mcl-activate | invoked`
- `mcl-perf-lighthouse | mcl-activate | invoked url_set=<bool>`

### Test sonuçları
- T1 `/mcl-perf-report` keyword: STATIC_CONTEXT 812 byte, `MCL_PERF_REPORT_MODE` mevcut PASS
- T2 `/mcl-perf-lighthouse` keyword: STATIC_CONTEXT 660 byte, `MCL_PERF_LIGHTHOUSE_MODE` mevcut PASS
- T3 Synthetic React project (`dist/main.js` 800KB random + `public/hero.png` 600KB): 2 HIGH (PRF-B01 bundle critical 781.5KB > 2× 200KB budget + PRF-I01 hero.png 586KB > 500KB) + 2 LOW (PRF-B04 large chunk + PRF-I03 PNG no-WebP fallback) PASS
- T4 Bundle delegate: gzip aggregation 781.5KB, file count 1, output_dir=dist PASS
- T5 CWV delegate skip: MCL_UI_URL yok → cwv ran=false (advisory yerine silent in --json mode) PASS
- T6 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-perf-rules.py` (yeni, 11 rule)
- `hooks/lib/mcl-perf-bundle.sh` (yeni, build output gzip walker)
- `hooks/lib/mcl-perf-lighthouse.sh` (yeni, MCL_UI_URL opt-in lighthouse)
- `hooks/lib/mcl-perf-scan.py` (yeni, orchestrator)
- `hooks/lib/mcl-state.sh` (3 yeni state field)
- `hooks/mcl-stop.sh` (Perf gate, sıra: security → db → ui → ops → perf → reminder → phase6)
- `hooks/mcl-activate.sh` (`/mcl-perf-report` + `/mcl-perf-lighthouse` keywords)
- `VERSION`, `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.14.x patch'lerine ertelendi)

- **Build invocation MVP'de yok**: kullanıcı `npm run build` yapmazsa PRF-B03 LOW advisory; auto-build (Phase 4.5'te invoke) 8.14.x'te konfigürasyona bağlı flag.
- **L2 per-Edit perf scan MVP'de yok**: image >500KB Edit'i Phase 4'te yakalanmıyor — sadece L3 Phase 4.5 START full scan + manuel `/mcl-perf-report`. 8.14.x'te image-only L2 block.
- **Phase 1.7 Performance Budget dimension** state field eklendi (`phase1_perf.budget_tier`) ama skill prose talimatı yok — model-behavioral.
- **Lighthouse desktop-only**: MVP desktop profile (faster, deterministic); mobile profile (Moto G4 emulation) 8.14.x'te.
- **Bundle gzip-only**: brotli sıkıştırma 8.14.x'te (production CDN'lerde brotli daha küçük).
- **AVIF support**: PRF-I03 yalnızca WebP suggestion; AVIF 8.14.x'te (browser support 2024+ artık yeterli).
- **Image walker scope**: 5 standart dir; project-spesifik convention'lar (`assets/images/`, `wwwroot/`) `.mcl/perf-config.json`'da configurable 8.14.x'te.
- **CSS/font bundle measurement yok**: yalnızca JS gzip ölçülüyor; CSS/font bundle ayrı budget 8.14.x'te.
- **Tree-shaking detection MVP'de zayıf**: PRF-B04 sadece chunk size; export usage analizi 8.14.x'te.

## [8.13.0] - 2026-04-30

### Eklendi — Operasyonel Disiplin (İŞ 4)

8.7-8.9 product kalitesini disiplin altına aldı; operasyonel katman boştu (Dockerfile root, `.env.example` drift, `console.log` yığını, README yarım, coverage %12). 8.13.0 dört kategoriyi tek pipeline'a bağlar — 8.7-8.9 mirror 3-tier.

#### Yeni dosyalar
- **`hooks/lib/mcl-ops-rules.py`** — 4 rule pack, 20 rule, decorator-registry, `category=ops-*` field:
  - **Deployment** (8): DEP-G01-no-ci-config, G02-workflow-yaml-error, G03-dockerfile-no-healthcheck, G04-dockerfile-root-user, G05-dockerfile-latest-tag, G06-env-example-missing, G07-env-example-stale, G08-secrets-no-doc
  - **Monitoring** (4): MON-G01-no-structured-logger, G02-no-metrics-endpoint, G03-no-error-tracking, G04-log-no-level
  - **Testing** (3): TST-T01-coverage-below-threshold, T02-no-test-framework, T03-changed-file-no-test
  - **Docs** (5): DOC-G01-no-readme, G02-readme-no-install, G03-readme-no-usage, G04-api-no-docs, G05-function-docstring-low
- **`hooks/lib/mcl-ops-scan.py`** — orchestrator: file metrics aggregation (env_var_refs, manifest_deps, adhoc_logging_count, loc_total, function_count, function_doc_count, api_routes_count, changed_files_no_test) → coverage delegate → rule dispatch → lokalize markdown.
- **`hooks/lib/mcl-ops-coverage.sh`** — coverage tool delegate: vitest/jest (`--coverage --coverageReporters=json-summary`), pytest (`--cov --cov-report=json`), go-test (`go tool cover -func`), cargo-tarpaulin. Binary missing graceful skip + audit `ops-coverage-skip`.

#### State şeması
- `phase4_5_ops_scan_done: false` — idempotency flag
- `phase4_5_high_baseline.ops: 0` — Phase 6 (b) regression baseline (8.11.0 schema extend)
- `phase1_ops: {deployment_target, observability_tier, test_policy, doc_level}` — Phase 1.7 4 yeni dimension için

#### Hook entegrasyonu
- **`hooks/mcl-stop.sh`** — UI START gate'inden sonra Ops START gate. Sıra: sticky-pause → security → db → ui → **ops** → standart Phase 4.5 reminder → Phase 6 gate. HIGH ≥ 1 → state pending'de + `decision:block` (4 kategori listesi); HIGH = 0 → done=true + baseline.ops=0; MEDIUM listesi standart reminder reason'a `[Ops-<sub>]` etiketli inject.
- **`hooks/mcl-activate.sh`** — `/mcl-ops-report` keyword block (`/mcl-ui-report` mirror).

#### Konfigürasyon
- `$MCL_STATE_DIR/ops-config.json` (8.5.0 isolation kuralı — proje içine yazma yasak; state dir'da):
  ```json
  {"ops": {"coverage_threshold_high": 50, "coverage_threshold_medium": 70}}
  ```
- Defaults: HIGH<50%, MEDIUM 50-70%, OK ≥70%.

#### Karar matrisi (kabul edilen varsayılanlar)
- Coverage threshold: **HIGH<50%, MEDIUM 50-70%** (configurable)
- DOC-G01 production: **Dockerfile OR CI workflow** (deployment intent heuristic)
- DEP-G07 stale: **JS/Python/Ruby/Go regex MVP**
- TST-T03 convention: **4 convention OR + project pattern infer**
- MON-G01 cutoff: **>10 absolute + LOC>500**
- Coverage timeout: **30s, skip+warning aşılırsa**
- Config: **`MCL_STATE_DIR/ops-config.json`**

#### Trigger condition matrix
- **DEP**: `Dockerfile` OR `.github/workflows/` OR `Procfile` OR `fly.toml` OR `vercel.json` OR `netlify.toml` OR `app.yaml` OR `Jenkinsfile`
- **MON**: backend stack-tag (python/java/csharp/ruby/php/go/rust + node-backend non-FE-only)
- **TST**: test framework manifest (vitest/jest/pytest/rspec/junit/go-test/cargo)
- **DOC**: her proje (always-on)

#### Audit events
- `ops-scan-incremental | mcl-pre-tool | tool=Edit file=... high=N med=N low=N skipped_via_cache=<bool>` (L2 — MVP eksik, 8.13.x)
- `ops-scan-block | mcl-stop | full-scan high=N`
- `ops-scan-full | mcl-stop | high=N med=N low=N duration_ms=N categories=<csv> tags=<csv>`
- `ops-coverage-delegate | mcl-ops-scan | tool=<jest|pytest|go|cargo> total=<pct> threshold_high=<n>`
- `ops-coverage-skip | mcl-ops-scan | reason=<binary-missing|no-test-framework>`
- `mcl-ops-report | mcl-activate | invoked`

### Test sonuçları
- T1 `/mcl-ops-report` keyword detection: `MCL_OPS_REPORT_MODE` STATIC_CONTEXT mevcut PASS
- T2 Synthetic project (Dockerfile root + latest tag, no CI, no README, env vars in code, no test framework): 2 HIGH (DEP-G04 + DOC-G01) + 5 MEDIUM (DEP-G01/G03/G05/G06 + TST-T03) + 3 LOW (MON-G02/G03 + TST-T02); 4 categories scanned; coverage skip PASS
- T3 Audit events doğru: `ops-coverage-skip`, `ops-scan-full high=2 med=5 low=3 categories=...` PASS
- T4 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-ops-rules.py` (yeni, 20 rule)
- `hooks/lib/mcl-ops-scan.py` (yeni, orchestrator + metrics aggregation)
- `hooks/lib/mcl-ops-coverage.sh` (yeni, 4 stack delegate)
- `hooks/lib/mcl-state.sh` (3 yeni state field)
- `hooks/mcl-stop.sh` (Ops START gate, sıra: security → db → ui → ops → reminder → phase6)
- `hooks/mcl-activate.sh` (`/mcl-ops-report` keyword)
- `VERSION`, `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.13.x patch'lerine ertelendi)

- **L2 per-Edit ops scan MVP'de yok**: pre-tool Phase 4 incremental block (Dockerfile/workflow/.env.example/README touch'larında HIGH-only block) 8.13.x'te. Şu an L3 Phase 4.5 START full scan + manuel `/mcl-ops-report` ile yakalanıyor.
- **Phase 1.7 4 yeni dimension** (deployment_target / observability_tier / test_policy / doc_level) state field eklendi ama skill prose talimatı yok — model-behavioral. 8.13.x'te skill update.
- **Coverage delegate basit**: vitest/jest threshold map per-file 8.13.x'te (şu an total only).
- **DEP-G07 env drift**: 4 dil regex (JS/Python/Ruby/Go); Java/C#/Rust/PHP/Swift/Kotlin coverage 8.13.x.
- **TST-T03 test convention infer**: project'te mevcut test pattern analizi (örn. `*_spec.rb` kullanan repo'da `.test.` aramaktan vazgeç) 8.13.x.
- **Workflow YAML lint**: lightweight regex (top-level keys); full `actionlint` delegate 8.13.x.
- **Dockerfile lint**: 4 rule var; `hadolint` delegate 8.13.x'te (DL3007/DL3015/DL3019 vb.).
- **API route detection**: regex Express/FastAPI; Rails routes / Gin / actix 8.13.x.
- **Coverage threshold per-file**: total only MVP; per-changed-file gate 8.13.x.

## [8.12.0] - 2026-04-30

### Eklendi — Interactive Design Loop (İŞ 3)

Phase 4a (BUILD_UI) sonrası UI_REVIEW dev server döngüsü şu an MCL dışında akıyor: kullanıcı manuel `npm run dev`, browser açma, feedback verme. 8.12.0 bu döngüyü MCL içine alır — Phase 4a kod yazımı tamamlanınca MCL dev server'ı (10 stack tespit) arka planda başlatır, URL'yi state'e koyar, build error pause'a bağlanır, `/mcl-design-approve` ile döngü kapanır.

#### Yeni dosyalar
- **`hooks/lib/mcl-dev-server-detect.py`** — 10 stack detection (vite/next/cra/vue-cli/sveltekit/rails/django/flask/expo/static). Manifest tabanlı (package.json scripts + Rails Gemfile + Django manage.py + Flask requirements + Expo app.json + static index.html fallback). Output JSON: `{stack, default_port, start_cmd, args}`.
- **`hooks/lib/mcl-dev-server.sh`** — sourceable lifecycle helper:
  - `mcl_devserver_is_headless` — heuristic (`MCL_HEADLESS` / `CI` / Linux SSH no-DISPLAY)
  - `mcl_devserver_detect <project>` — JSON via .py
  - `mcl_devserver_start <project>` — port allocation (default + 4 fallback retry), `nohup` spawn, PID `dev-server.pid`, log `dev-server.log` (her ikisi `MCL_STATE_DIR`'da, 8.5.0 isolation), state.dev_server set, audit `dev-server-started`
  - `mcl_devserver_stop` — kill PID + state clear + audit
  - `mcl_devserver_status` — "active"/"inactive"/"stale" (PID alive check)

#### State şeması
- `dev_server` object field default `{"active": false}`; aktifken `{active, stack, port, url, pid, started_at, log_path}` (v2 schema bump'sız).

#### Hook entegrasyonu
- **`hooks/mcl-stop.sh`** — Phase 6 gate'den ÖNCE: `ui_flow_active=true` AND `ui_sub_phase=="UI_REVIEW"` AND `dev_server.active=false` AND not headless ise `mcl_devserver_start` tetiklenir. Headless ise audit `dev-server-headless-skip`. Stale PID detect ise auto-clear.
- **`hooks/mcl-post-tool.sh`** — Edit/Write/MultiEdit sonrası `dev-server.log` tail (50 satır); stack-spesifik error pattern (vite/next/cra/django/rails/flask/expo regex map; default generic) match ise `mcl_pause_on_error "build-error" ...` (8.10.0 entegrasyonu) — kullanıcı çözüp `/mcl-resume` ile devam.
- **`hooks/mcl-activate.sh`** — 3 yeni keyword block:
  - `/mcl-design-approve` — `mcl_devserver_stop` + `ui_reviewed=true` + `ui_sub_phase=BACKEND` set + audit `design-loop-approved` + STATIC_CONTEXT BACKEND advance notice
  - `/mcl-dev-server-start` — manuel server başlatma fallback
  - `/mcl-dev-server-stop` — manuel durdurma (UI loop kapanmaz)

#### Karar matrisi (kabul edilen varsayılanlar)
- ui_sub_phase trigger: **(a)** skill talimatı (model-behavioral set; 8.12.x'te skill prose'una explicit `mcl_state_set ui_sub_phase UI_REVIEW` eklenir)
- Stale PID: **auto-clear + restart** (sor yerine sessiz temizlik; 8.12.x'te AskUserQuestion opsiyonu)
- Build error pattern: **(b)** stack-spesifik regex map
- Hot reload check: **MVP skip** (advisory model-behavioral); 8.12.x'te `curl` health check
- Mobile QR: **8.12.x'e ertelendi** (Expo log capture + ASCII rendering MVP'de yok; URL veriliyor, manuel QR alma)
- Phase 4c geçiş: **`ui_reviewed=true` + `ui_sub_phase=BACKEND` ikisi**
- Log persistence: **kalır** (`MCL_STATE_DIR/dev-server.log`)

#### Audit events
- `dev-server-started | mcl-stop | stack=<s> port=<p> pid=<n> url=<u>`
- `dev-server-port-fallback | mcl-stop | requested=<p1> assigned=<p2>`
- `dev-server-port-exhausted | mcl-stop | tried=<p1>-<p5>`
- `dev-server-spawn-failed | mcl-stop | stack=<s>`
- `dev-server-spawn-skipped | mcl-stop | reason=detect-or-spawn-failed`
- `dev-server-headless-skip | mcl-stop | reason=headless-env`
- `dev-server-stale-pid | mcl-stop | cleared=true`
- `dev-server-stopped | mcl-activate.sh | pid=<n>`
- `design-loop-approved | mcl-activate.sh | source=keyword`
- `mcl-dev-server-start|stop | mcl-activate.sh | invoked` (manual)
- `pause-on-error | mcl-post-tool | source=build-error tool=<stack>` (8.10.0 entegrasyonu)

### Test sonuçları
- T1 `/mcl-design-approve` keyword → STATIC_CONTEXT 340 byte, `MCL_DESIGN_APPROVE_MODE` mevcut PASS
- T2 `/mcl-dev-server-start` keyword → 317 byte, `MCL_DEV_SERVER_START_MODE` PASS
- T3 `/mcl-dev-server-stop` keyword → 190 byte, `MCL_DEV_SERVER_STOP_MODE` PASS
- T4 Detection: vite (port 5173 + npm run dev), next (3000), django (8000 + manage.py runserver), nothing (null with reason) PASS
- T5 Headless heuristic: default false, `MCL_HEADLESS=1` true PASS
- T6 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-dev-server-detect.py` (yeni, 10 stack detection)
- `hooks/lib/mcl-dev-server.sh` (yeni, lifecycle helpers)
- `hooks/lib/mcl-state.sh` (`dev_server` field default)
- `hooks/mcl-stop.sh` (auto-start trigger before Phase 6 gate)
- `hooks/mcl-post-tool.sh` (build-error log tail check + pause-on-error integration)
- `hooks/mcl-activate.sh` (3 keyword blocks)
- `VERSION`, `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.12.x patch'lerine ertelendi)

- **URL injection STATIC_CONTEXT'e otomatik eklenmedi**: model `mcl_state_get dev_server` ile JSON'dan URL'i çekebilir (Bash). 8.12.x'te activate hook STATIC_CONTEXT'e `<mcl_dev_server>` block otomatik enjekte.
- **ui_sub_phase transition trigger**: Phase 4 model-behavioral; skill prose henüz `mcl_state_set ui_sub_phase UI_REVIEW` talimatını içermiyor. 8.12.x'te skill update.
- **Hot reload health check**: MVP advisory only; 8.12.x'te `curl -sSf $URL` healthcheck.
- **Mobile Expo QR**: log capture + ASCII render MVP'de yok; URL veriliyor (`exp://localhost:19000`), kullanıcı QR'ı manuel alır.
- **Multi-server projeler** (Next.js + ayrı API): MVP single FE server only; backend Phase 4c'de manuel.
- **Session abandon**: PID arka planda yaşar; bir sonraki session'da stale check ile auto-clear (sormadan); kullanıcı kontrolü 8.12.x'te.
- **Build error pattern coverage**: 7 stack regex var, custom dev tooling kaçabilir; generic fallback `error|ERROR|FAILED|panic` false-positive yüksek.
- **Skill files dokunulmadı**: design loop talimatı (URL relay, NL ack, hot reload bekleme) model-behavioral; skill update 8.12.x'te.

## [8.11.0] - 2026-04-30

### Eklendi — Phase 6 Double-check (İŞ 2)

Phase 5 verification katmanı sadece **Phase 4 code → tests** ekseninde çalışıyordu. Üç kritik soru cevapsızdı: (1) MCL pipeline'ı tüm fazlarını gerçekten çalıştırdı mı? (2) Phase 4.5 sonrası fix'ler yeni HIGH bulgu üretti mi? (3) Kullanıcının istediği her şey teslim edildi mi? Phase 6 bu üç soruyu üç check'le bağlar ve Phase 5'ten sonra `decision:block` tier'i ile enforced.

#### Yeni dosya
- **`hooks/lib/mcl-phase6.py`** — orchestrator. Üç check fonksiyonu + lokalize markdown render. Modes: `run` (enforcement, JSON), `report` (markdown). Top-level try/except → exit 3 (8.10.0 pattern).

#### Üç check
**(a) Audit trail completeness** — required STEP audit event'leri current session window'da mevcut mu? Window: son `session_start` event'inden itibaren (trace.log anchor); fallback son 200 audit satırı. Required (HIGH): `precision-audit`, `engineering-brief`, `spec-extract|spec-save`, `spec-approve`, `phase-review-pending`, `phase-review-running`, `phase-review-impact`. Soft-required (LOW advisory): `phase5-verify` — 8.10.x ve önce projeler emit etmiyor.

**(b) Final scan aggregation** — 4 scan (codebase/security/db/ui) `--mode=full` tekrar çalıştır; HIGH count'larını `phase4_5_high_baseline` ile karşılaştır. `current > baseline` → regression finding (HIGH). Phase 4.5 START gate'leri HIGH=0 ile geçtiğinde baseline=0 set ediliyor (mcl-stop.sh 3 noktada).

**(c) Promise-vs-delivery** (reverse Lens-e) — Phase 1 `phase1_intent` + `phase1_constraints` state field'larından keyword extract (4+ char alphabetic, stopword filtre, TR+EN); modified source file'larda keyword search; eksik keyword → MEDIUM finding. Phase 1 state'te yoksa LOW skip (8.10.x backward compat — Phase 1 skill'inin `mcl_state_set phase1_intent` çağırması gerek).

#### State şeması
- `phase6_double_check_done: false` — idempotency flag
- `phase4_5_high_baseline: {security: 0, db: 0, ui: 0}` — regression baseline
- `phase1_intent: null`, `phase1_constraints: null` — Phase 1 confirmed params (Phase 1 skill talimatıyla doldurulacak)
- v2 schema bump'sız (geriye uyumlu)

#### Hook entegrasyonu
- **`hooks/mcl-stop.sh`** — (1) Phase 4.5 START gate'lerinde HIGH=0 noktasında `phase4_5_high_baseline.{security|db|ui}=0` set'i (3 yerde). (2) Hook sonunda **Phase 6 gate**: `phase_review_state == "running"` AND `phase6_double_check_done != true` AND (audit'te `phase5-verify` event VAR ya da transcript'te "Verification Report" / "Doğrulama Raporu" string'i VAR) ise `mcl-phase6.py --mode=run` çalıştır. Output JSON'da (a/b/c HIGH varsa) → `decision:block` reason'da kategorize edilmiş finding listesi (max 5 her kategori). Pass → `phase6_double_check_done=true` set + audit `phase6-done`.
- **`hooks/mcl-activate.sh`** — `/mcl-phase6-report` keyword block (`/mcl-ui-report` mirror).

#### Audit events
- `phase6-run-start | mcl-stop|mcl-phase6 | required_events=N`
- `phase6-audit-gap | mcl-phase6 | missing=<rule_ids>`
- `phase6-scan-regression | mcl-phase6 | new_high=N`
- `phase6-promise-gap | mcl-phase6 | missing=N`
- `phase6-block | mcl-stop | a=N b=N c=N`
- `phase6-done | mcl-stop | duration_ms=N`
- `mcl-phase6-report | mcl-activate | invoked`

### Phase 5 vs Phase 6 sınır
| Soru | Phase 5 | Phase 6 |
|---|---|---|
| Test edildi mi? | ✓ | — |
| Manuel-test surface | ✓ | — |
| Process trace | ✓ | — |
| Pipeline bütünlüğü | — | ✓ (a) |
| Post-fix regression | — | ✓ (b) |
| Reverse traceability | — | ✓ (c) |

### Karar matrisi (kabul edilen varsayılanlar)
- Phase 5 done detection: **(c) hibrit** — `phase_review_state=="running"` + (`phase5-verify` event OR transcript "Verification Report")
- Keyword algoritması: **regex token** (4+ char alphabetic, TR+EN stopword filter)
- Phase 1 confirmed param: **(a) state'e ekle** — `phase1_intent` + `phase1_constraints` field'ları
- `phase5-verify` backward compat: **soft-fail (LOW advisory)**, hard-block değil
- Phase 6 (b) baseline yokluğu: **0 default güvenilir** (gate skipped → ilgili category baseline=0 anlamlı)

### Test sonuçları
- T1 `/mcl-phase6-report` keyword detection: STATIC_CONTEXT 779 byte, `MCL_PHASE6_REPORT_MODE` mevcut PASS
- T2 Synthetic state (Phase 1.7 audit yok, FastAPI projesi): (a) `P6-A-missing-precision-audit` HIGH + `P6-A-missing-phase5-verify` LOW; (b) no scan regression (no-stack scenarios skipped); (c) 7 missing keyword MEDIUM PASS
- T3 Audit events: `phase6-run-start required_events=6`, `phase6-audit-gap missing=...`, `phase6-promise-gap missing=1` PASS
- T4 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-phase6.py` (yeni, 3 check orchestrator)
- `hooks/lib/mcl-state.sh` (4 yeni field: phase6_double_check_done, phase4_5_high_baseline, phase1_intent, phase1_constraints)
- `hooks/mcl-stop.sh` (Phase 4.5 gate baseline set'leri + hook sonunda Phase 6 gate)
- `hooks/mcl-activate.sh` (`/mcl-phase6-report` keyword)
- `VERSION`, `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.11.x patch'lerine ertelendi)

- **`phase5-verify` audit event** model-behavioral; mevcut Phase 5 skill prose'u bunu emit etmiyor. Phase 6 trigger fallback: transcript scan ("Verification Report" / "Doğrulama Raporu") — heuristic, lokalize 14 dil için tam coverage yok. 8.11.x'te skill prose'una `mcl_audit_log "phase5-verify" ...` Bash talimatı eklenir.
- **Phase 1 state field doldurma**: `phase1_intent` + `phase1_constraints` mevcut Phase 1 skill'inde set edilmiyor — boş kalırsa (c) check LOW skip. 8.11.x'te Phase 1 skill prose'una `mcl_state_set phase1_intent` talimatı.
- **Promise-vs-delivery keyword heuristic**: false-positive yüksek (4+ char regex token; semantic equivalence yok). 8.11.x'te NLP-grade traceability (LLM-driven param-to-implementation mapping).
- **Phase 6 (b) regression baseline**: tüm 4.5 gate'leri skip ise (no-stack-tag) baseline=0 anlamlı; ama partial scenario (security baseline=2, db=0, ui=skip) baseline tracking accuracy belirsiz. MVP'de güvenilir kabul.
- **codebase-scan dahil değil (b)**: 4 scan'den codebase-scan severity routing yapmıyor (high_count yerine general findings); Phase 6 (b) regression detection sadece security/db/ui üzerinden. 8.11.x'te codebase-scan severity field'ı eklenip dahil edilebilir.
- **Phase 6 idempotency boundary**: `phase6_double_check_done=true` session boundary'da sticky. Yeni Phase 4 turn'ünde reset gerekir mi? Mevcut MCL'de `phase_review_state` reset noktaları sınırlı; 8.11.x'te explicit reset.

## [8.10.0] - 2026-04-29

### Eklendi — Pause-on-error (İŞ 1)

CLAUDE.md "never silently fall back when a corruption is detected" kuralının yapısal uygulaması. MCL'in scan helper Python crash, validator JSON parse error, state.json corrupt, audit write fail, hook crash, delegate non-graceful failure gibi durumlarda silent fail-open yerine **explicit pause** mekanizması ekler. Kullanıcı her hatayı görür, çözümünü açıklar, MCL kaldığı phase'den devam eder.

#### Yeni dosya
- **`hooks/lib/mcl-pause.sh`** — sourceable helper:
  - `mcl_pause_on_error <source> <tool> <error_msg> <suggested_fix>` — state.paused_on_error.active=true + audit
  - `mcl_pause_check` — paused mı kontrolü (true/false)
  - `mcl_pause_resume <resolution>` — state temizle + audit
  - `mcl_pause_block_reason` — `decision:block` reason render
  - `mcl_pause_on_scan_error <orchestrator> <result_json>` — scan output'unda "error" key varsa otomatik pause + PreToolUse-shaped block JSON emit (caller exit 0)

#### State şeması
- `state.json`'a `paused_on_error` object field eklendi (default `{"active": false}`); active=true olduğunda `{timestamp, source, tool, error_msg, last_phase, last_phase_name, suggested_fix, user_resolution}` field'ları doluyor. v2 schema bump'sız (geriye uyumlu — eski state'lerde field eksikse default'la doluyor).

#### Hook entegrasyonu
- **`hooks/mcl-pre-tool.sh`** — (1) Hook başında sticky pause check: `paused_on_error.active=true` ise tüm tool'lar `decision:deny` "MCL PAUSED" reason'la blocklanır, audit `pause-sticky-block`. (2) Üç scan branch'inin (security/db/ui) her birinde scan subprocess sonrası `mcl_pause_on_scan_error` çağrısı — orchestrator exception → state set + block + temp file cleanup + exit 0.
- **`hooks/mcl-stop.sh`** — Hook başında sticky pause check: paused state'te enforcement skip + `decision:block` "MCL PAUSED" emit. Audit `pause-sticky-block`.
- **`hooks/mcl-activate.sh`** — (1) `/mcl-resume <resolution>` keyword block: paused_on_error temizler, user_resolution kaydeder, "MCL_RESUME" notice emit. (2) Paused state context: hook ortasına `mcl_pause_check` guard; aktifse `<mcl_paused>` block STATIC_CONTEXT'e inject edilir + diğer tüm branch'ler skip (sticky). Model NL-ack ile resolve etmesi için Bash talimatı dahil.

#### Orchestrator pause hook entegrasyonu
- `hooks/lib/mcl-security-scan.py`, `mcl-db-scan.py`, `mcl-ui-scan.py`, `mcl-codebase-scan.py` — top-level `try/except` wrapper main() etrafına eklendi. Exception → stdout `{"error": "...", "traceback": "..."}` JSON + exit 3 (orchestrator crash kodu). Caller hook bunu `mcl_pause_on_scan_error` ile yakalar.

#### `state-corrupt-recovered` audit (kullanıcı isteği)
- `hooks/lib/mcl-state.sh` — corrupt state detected branch'inde `mcl_audit_log "state-corrupt-recovered" path=<corrupt copy path>` event eklendi. Mevcut recovery davranışı (corrupt copy + default reset) **korundu** — pause edilmedi, ama artık görünür. CHANGELOG-documented exception to silent-fallback rule (recovery safety > silent-pause).

#### Karar matrisi (kabul edilen varsayılanlar)
- T5 corrupt-state: **(b)** mevcut recovery + audit (visible non-blocking)
- T7 NL-ack: **(a)** /mcl-resume keyword MVP; NL-ack 8.10.x model-behavioral
- Sticky süresi: **persist** (session boundary'da temizlenmez)
- Pause vs gate çakışması: **pause öncelikli** (mcl-pre-tool.sh ve mcl-stop.sh hook başında)
- /mcl-resume argv: **free-form text** (keyword sonrası kalan tüm prompt)

### Test sonuçları
- T1 `mcl_pause_on_error` çağrısı (manuel state setup) → `paused_on_error.active=true` ✓
- T2 Sticky pre-tool block: paused state'te Edit → `decision:deny` "MCL PAUSED..." reason; audit `pause-sticky-block` PASS
- T3 Sticky stop block: paused state'te Stop → `decision:block` "MCL PAUSED..." reason; audit `pause-sticky-block` PASS
- T4 Activate paused context: paused state'te normal prompt → STATIC_CONTEXT'e `<mcl_paused>` tag + MCL PAUSED reason inject PASS
- T5 `/mcl-resume binary yüklendi` → `MCL_RESUME` notice; state.paused_on_error.active=false; user_resolution kaydedildi; audit `resume-from-pause resolution_len=16` PASS
- T6 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-pause.sh` (yeni, 5 helper)
- `hooks/lib/mcl-state.sh` (`paused_on_error` field + corrupt-recovered audit)
- `hooks/lib/mcl-security-scan.py`, `mcl-db-scan.py`, `mcl-ui-scan.py`, `mcl-codebase-scan.py` (top-level try/except)
- `hooks/mcl-pre-tool.sh` (sticky check + scan-error pause integration in 3 branches)
- `hooks/mcl-stop.sh` (sticky check)
- `hooks/mcl-activate.sh` (paused-state context + /mcl-resume keyword)
- `VERSION`, `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.10.x patch'lerine ertelendi)

- **NL-ack detection** model-behavioral; hook tarafında detect yok. Skill prose'u model'e talimat verir; fail-safe `/mcl-resume`. Hook-level NL-ack 8.10.x'te (transcript scan ile pattern matching).
- **state.json corrupt** durumunda mevcut recovery davranışı korundu (pause yerine). CHANGELOG-documented exception. 8.10.x'te flag-based opt-in (hard-pause vs auto-recover) eklenebilir.
- **Audit log write failure** trigger noktası eklenmedi (audit log'a yazamayan bir sistem pause audit'ini de yazamaz — chicken-and-egg). MVP'de stderr'e mesaj basılır; kullanıcı görmez. 8.10.x'te alternative channel (state.json içinde paused field + on next read).
- **Hook crash trap** explicit `trap ERR` set edilmedi; mevcut hook'lar `set -uo pipefail` kullanıyor; tam coverage için `trap` infrastructure ileride.
- **External delegate non-graceful** (squawk/eslint timeout) için pause path eksik; mevcut graceful skip korundu. 8.10.x'te delegate-spesifik timeout pause.
- **Pause persistence cross-session**: paused state.json'da kalır; yeni mcl-claude session açıldığında paused notice tekrar gelir. Beklenen ve istenen davranış (kullanıcı çözmedikçe MCL pasif).

## [8.9.0] - 2026-04-29

### Eklendi — UI Enforcement Layer (3-tier, framework-aware)

8.7.0 backend security ve 8.8.0 DB tasarım disiplininden sonra UI tarafına aynı 3-tier hattını uyguluyoruz: **design system tutarlılığı, component reuse, a11y, responsive davranış, naming convention**. Severity tier UI-spesifik tunelendi: **a11y-critical-only block** (E3) — design tokens / reuse / responsive / naming HIGH değil, dialog/audit. UI iteration tempo'sunu korur ama legal-risk a11y ihlallerini hard-block eder.

#### Yeni dosyalar
- **`hooks/lib/mcl-ui-rules.py`** — generic core 10 + framework add-on (4 framework × 3 = 12) = **22 rule**. Decorator-registry, `category=ui-*` + `framework` field. Token-aware rules (UI-G07/G08/G09/G10) `mcl-ui-tokens.py`'dan token listesi alır.
  - Generic core: UI-G01 img-no-alt, UI-G02 button-no-accessible-name, UI-G03 link-no-href, UI-G04 form-input-no-label, UI-G05 interactive-no-keyboard (5 a11y-critical HIGH); UI-G06 heading-skip-level, UI-G07 hardcoded-color, UI-G08 hardcoded-spacing, UI-G09 hardcoded-font-size, UI-G10 magic-breakpoint.
  - Framework add-on: React (UI-RX-list-no-key, UI-RX-controlled-without-onChange HIGH, UI-RX-fragment-with-key-only), Vue (UI-VU-v-for-no-key, UI-VU-v-html-untrusted HIGH, UI-VU-prop-no-type), Svelte (UI-SV-each-no-key, UI-SV-on-click-no-keyboard HIGH, UI-SV-prop-no-export-let-type), HTML-static (UI-HT-no-html-lang HIGH, UI-HT-no-meta-viewport, UI-HT-button-input-mixup).
  - **9 HIGH a11y-critical** rule total — bunlar L2 ve L3'te `decision:deny`/`decision:block` tetikler; geri kalan rule'lar dialog/audit.
- **`hooks/lib/mcl-ui-tokens.py`** — design token detector. **C3 hybrid:** tailwind.config.{js,ts,cjs,mjs} parse, `:root` CSS custom properties, `design-tokens.json` (W3C draft), `theme.ts/js` loose extraction. Project'te token dosyası yoksa MCL default set fallback (8px grid spacing, type ramp 12-60px, breakpoint 640/768/1024/1280/1536). Audit `ui-tokens-detected source=tailwind|css-vars|theme-ts|design-tokens|mcl-default`.
- **`hooks/lib/mcl-ui-scan.py`** — orchestrator (incremental/full/report/axe modes), `ui-cache.json` (file SHA1 + rules-version composite), token detector dispatch, eslint-a11y delegate çağrı, lokalize markdown render.
- **`hooks/lib/mcl-ui-eslint.sh`** — external delegate: `eslint-plugin-jsx-a11y` (React) + `eslint-plugin-vuejs-accessibility` (Vue) + `eslint-plugin-svelte` a11y subset; framework-spesifik rule list ile filtered. Binary yoksa graceful skip.
- **`hooks/lib/mcl-ui-axe.sh`** — `/mcl-ui-axe` keyword backing. `MCL_UI_URL` env yoksa lokalize advisory; varsa Playwright + `@axe-core/playwright` headless single-page scan. MVP single-page; multi-page crawl 8.9.x'te.

#### Hook entegrasyonu (8.7.x/8.8.x mirror)
- **`hooks/mcl-activate.sh`** — `/mcl-ui-report` + `/mcl-ui-axe` keyword blokları.
- **`hooks/mcl-pre-tool.sh`** — 8.8.0 DB block sonrası Phase 4 UI incremental block. FE stack-tag check + Edit/Write/MultiEdit + UI ext (.tsx/.jsx/.ts/.js/.vue/.svelte/.html/.css/.scss); **yalnızca `category=ui-a11y` HIGH bulguda `decision:deny`** reason "MCL UI A11Y — `<rule>`...". Token/reuse/responsive/naming HIGH değil, sessiz audit. Audit `ui-scan-incremental`, `ui-scan-block`.
- **`hooks/mcl-stop.sh`** — 8.8.0 DB START gate'inin yanına paralel Phase 4.5 START UI gate. `phase4_5_ui_scan_done` state field. Sıra: security → db → ui → standart Phase 4.5 reminder. HIGH a11y → state pending'de kalır + `decision:block` (ilk 5 finding listeli); HIGH=0 → done=true; MEDIUM listesi standart block reason'a `[UI-Design]` etiketli inject.
- **`hooks/lib/mcl-state.sh`** — schema'ya `phase4_5_ui_scan_done: false` field (8.7.1 security + 8.8.0 db paralel; v2 schema bump'sız).

#### Phase 4.5 lens (d) genişletme
`mcl-ui-scan.py --mode=full` Phase 4.5 START'ta security + DB gate'lerinden sonra çalışır. Severity routing: HIGH ui-a11y → block; MEDIUM ui-tokens/reuse/responsive/naming → `[UI-Design]` veya `[UI-A11y]` dialog item; LOW → audit. Auto-fix: ESLint `--fix` safe categories silent OK; a11y/token/reuse/naming asla silent.

#### Trigger condition (F1)
**Sadece FE stack-tag tespit edildiğinde** (`react-frontend|vue-frontend|svelte-frontend|html-static` herhangi biri). Backend-only / lib / CLI / data pipeline projelerinde tüm UI pipeline (L1 + L2 + L3) skip edilir; audit `ui-scan-skipped reason=no-fe-stack-tag`.

#### 8.7.0/8.8.0 ile çakışmazlık
React unsafe-html-setter XSS / target=_blank rel 8.7.0'da kalır; SQL injection / schema design 8.8.0'da kalır. UI scan **tekrar etmez**. `category=ui-tokens|ui-reuse|ui-a11y|ui-responsive|ui-naming` field ayrım. Audit event'leri ayrı namespace: `ui-scan-*`, `ui-axe-*`, `ui-tokens-*`.

### Test sonuçları
- T1 `/mcl-ui-report` keyword detection: STATIC_CONTEXT 957 byte, `MCL_UI_REPORT_MODE` mevcut PASS
- T2 `/mcl-ui-axe` keyword: STATIC_CONTEXT 612 byte, `MCL_UI_AXE_MODE` mevcut PASS
- T3 Full UI scan synthetic React projesi (`<img>` no alt + empty `<button>` + `<div onClick>` + `<input id="email">` no label): 4 HIGH a11y bulgu (UI-G01, UI-G02, UI-G04, UI-G05); tokens=mcl-default (no tailwind config) PASS
- T4 L2 pre-tool a11y block: phase=4, FE stack-tag, Write `<img src="a.png" />` (no alt) → `decision:deny` reason "MCL UI A11Y — UI-G01-img-no-alt..."; audit `ui-scan-incremental high=1` + `ui-scan-block` PASS
- T5 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-ui-rules.py` (yeni, 22 rule)
- `hooks/lib/mcl-ui-tokens.py` (yeni, C3 hybrid token detector)
- `hooks/lib/mcl-ui-scan.py` (yeni, orchestrator)
- `hooks/lib/mcl-ui-eslint.sh` (yeni, eslint a11y delegate)
- `hooks/lib/mcl-ui-axe.sh` (yeni, opt-in axe runner)
- `hooks/lib/mcl-state.sh` (`phase4_5_ui_scan_done` field)
- `hooks/mcl-activate.sh` (`/mcl-ui-report` + `/mcl-ui-axe` keywords)
- `hooks/mcl-pre-tool.sh` (Phase 4 UI incremental block, a11y-critical-only)
- `hooks/mcl-stop.sh` (Phase 4.5 START UI gate)
- `skills/my-claude-lang/phase4-5-risk-review.md` (Lens (d) UI extension)
- `VERSION` (8.8.0 → 8.9.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (kabul edilmiş, 8.9.x patch'lerine ertelendi)

- **Phase 1.7 react-frontend / vue-frontend / svelte-frontend / html-static add-on extension** (5 yeni dimension: design tokens stance, a11y stance, responsive strategy, component reuse policy, naming convention) MVP'de yok — model-behavioral kalıyor. Skill dosyasına dedicated dimension ekleme 8.9.1'de.
- **Component reuse AST fingerprint detector** MVP'de yok; rule-level eksik. Static heuristic ileri düzey 8.9.x'te.
- **Storybook integration** (`*.stories.{ts,js,tsx,jsx}` parse + component → story coverage) MVP'de yok; `mcl-ui-storybook.py` ve reuse detector 8.9.x'te.
- **`/mcl-ui-axe` MVP single-page**: tek URL Playwright + axe; multi-page crawl, multi-viewport runs, login flow 8.9.x'te.
- **Solid / Angular / Qwik** stack-tag yok (8.4.1 TODO); UI feature tetiklenmez. 8.9.x patch'lerinde framework genişletmesi.
- **Contrast checking static** sadece literal hex/rgb için; CSS variable runtime resolution `/mcl-ui-axe` ile yakalanır.
- **MCL default token set** dar — colors boş (any color allowed), spacing/font/breakpoint 8px grid + Tailwind defaults. Project token'ları yokken UI-G07 hardcoded-color silent (false-positive engellemek için).
- **eslint-plugin yokluğu** (jsx-a11y / vuejs-accessibility / eslint-plugin-svelte install edilmemiş): D1 delegate skip + warning; generic core rule'lar (UI-G01..G10) yine çalışır.
- **14 dilden yalnızca TR + EN tam lokalize**; diğer 12 dil EN fallback.

## [8.8.0] - 2026-04-29

### Eklendi — DB Tasarım Disiplini (3-tier, ORM-aware)

8.7.0 backend security'nin DB layer kapsamı sadece SQL injection / hardcoded credential / mass-assignment ile sınırlıydı. Schema design, index stratejisi, N+1 detection, migration safety, query plan, connection pooling, multi-tenancy — boştu. Bu patch 8.7.x security pattern'ini birebir paralel hatla DB tasarım disiplinine uyarlıyor.

#### Yeni dosyalar
- **`hooks/lib/mcl-db-rules.py`** — generic core 10 + 8 ORM × 3 anchor = 24 add-on = **34 rule**. Decorator-registry, `category=db-*` zorunlu, dialect field.
  - Generic core: DB-G01 missing-PK, DB-G02 SELECT-*, DB-G03 missing-FK-index, DB-G04 UPDATE/DELETE-no-WHERE, DB-G05 JSONB-no-validation, DB-G06 TIMESTAMP-no-tz, DB-G07 text-id-not-uuid, DB-G08 enum-as-text, DB-G09 cascade-delete-user-data, DB-G10 N+1-static.
  - ORM add-on (her biri 3): Prisma, SQLAlchemy, Django ORM, ActiveRecord, Sequelize, TypeORM, GORM, Eloquent.
- **`hooks/lib/mcl-db-scan.py`** — orchestrator (incremental/full/report/explain modes), `db-cache.json` (file SHA1 + rules-version composite key), generic + ORM dispatch, migration delegate çağrı, lokalize markdown render.
- **`hooks/lib/mcl-db-migration.sh`** — external delegate: `squawk` (Postgres migration linter — lock impact, data-loss, type narrow) + `alembic check` (Python). Binary-missing graceful skip + tek-seferlik warning.
- **`hooks/lib/mcl-db-explain.sh`** — `/mcl-db-explain` keyword backing. `MCL_DB_URL` env yoksa lokalize advisory; varsa dialect tespit + generic CLI EXPLAIN (`psql/mysql/sqlite3`). MVP: ANALYZE değil, sadece EXPLAIN (production safety).

#### Stack-detect (`hooks/lib/mcl-stack-detect.sh`) — 17 yeni tag
- **DB dialect** (6): `db-postgres`, `db-mysql`, `db-sqlite`, `db-mariadb`, `db-mongo`, `db-redis` — manifest dep + Docker compose image + `.env.example` connection string regex.
- **Cloud DB** (3): `db-bigquery`, `db-snowflake`, `db-dynamodb` — manifest dep (8.8.x'te dialect-spesifik kural setleri).
- **ORM** (8): `orm-prisma`, `orm-sqlalchemy`, `orm-django`, `orm-activerecord`, `orm-sequelize`, `orm-typeorm`, `orm-gorm`, `orm-eloquent` — schema dosya varlığı + manifest dep.

#### Hook entegrasyonu (8.7.x mirror)
- **`hooks/mcl-activate.sh`** — `/mcl-db-report` + `/mcl-db-explain` keyword blokları (`/mcl-security-report` mirror).
- **`hooks/mcl-pre-tool.sh`** — 8.7.1 security incremental block'undan sonra Phase 4 DB incremental block. DB stack-tag check + Edit/Write/MultiEdit + source ext (+`.sql`+`.prisma`); HIGH bulguda `decision:deny` reason "MCL DB DESIGN — `<rule>` [`<category>`]...". Audit `db-scan-incremental`, `db-scan-block`.
- **`hooks/mcl-stop.sh`** — 8.7.1 security START gate'inin yanına paralel Phase 4.5 START DB gate. `phase4_5_db_scan_done` state field. `no_db_stack=true` ise skip + done. HIGH ≥ 1 → state pending'de kalır + `decision:block` reason'a ilk 5 HIGH bulgu listesi (`category` field'ıyla); standart Phase 4.5 reminder bypass. HIGH = 0 → done=true; MEDIUM listesi standart block reason'a `[DB-Design]` etiketli inject. Sıra: security-gate → db-gate → standart reminder.
- **`hooks/lib/mcl-state.sh`** — schema'ya `phase4_5_db_scan_done: false` field (8.7.1 security paralel; v2 schema bump'sız).

#### Phase 1.7 — 7 yeni DB design dimension (DB-stack-tag triggered)
1. **Persistence Model** (RDBMS / document / hybrid)
2. **Schema Ownership** (single-service / shared)
3. **Migration Policy** (zero-downtime / expand-contract / direct)
4. **Index Strategy Upfront** (composite / partial / expression / covering)
5. **ID Generation** (auto-increment / UUID v4 / v7 / ULID / snowflake)
6. **Multi-Tenancy** (schema-per-tenant / row-level / none)
7. **Connection Pooling** (size + saturation)

Hepsi mevcut SILENT-ASSUME / SKIP-MARK / GATE pattern'i. Sadece `db-*` tag tespit edilince uygulanır (FE-only / lib / CLI projelerinde skip).

#### Phase 4.5 lens (d) genişletme
`mcl-db-scan.py --mode=full` Phase 4.5 START'ta security gate sonrası çalışır. Severity routing 8.7.0 ile aynı: HIGH → block; MEDIUM → `[DB-Design]` dialog item; LOW → audit. Auto-fix: schema/migration/index **asla silent**; naming/style silent OK.

#### Trigger condition
**Sadece DB stack-tag tespit edildiğinde.** Stack-tag yoksa: Phase 1.7 DB dimension'ları uygulanmaz, L2 ve L3 hook bloğları skip (audit `db-scan-skipped reason=no-db-stack-tag`). ORM tag yoksa ama DB tag varsa: generic core çalışır, ORM add-on'lar skip.

#### 8.7.0 ile çakışmazlık
SQL injection / hardcoded credentials / mass-assignment / insecure-deserialization 8.7.0 kapsamında kalır — DB scan tekrar etmez. `category=db-schema|db-index|db-query|db-migration|db-n-plus-one|db-pooling` field'ı ayrım. Audit event'leri ayrı namespace: `db-scan-*`, `migration-safety-*`, `db-explain-*`.

### Test sonuçları
- T1 `/mcl-db-report` keyword detection (`MCL_STATE_DIR=/tmp/proj` outside MCL repo): STATIC_CONTEXT 1125 byte, `MCL_DB_REPORT_MODE` mevcut PASS
- T2 `/mcl-db-explain` keyword: STATIC_CONTEXT 632 byte, `MCL_DB_EXPLAIN_MODE` mevcut PASS
- T3 Stack-detect: `package.json` `pg+sequelize` → `[javascript, db-postgres, orm-sequelize]`; `requirements.txt` `psycopg+sqlalchemy+django` → `[python, db-postgres, orm-sqlalchemy, orm-django]` PASS
- T4 Full scan synthetic project (Postgres + Sequelize, schema.sql + api.js): HIGH=1 (DB-G01), MEDIUM=2 (DB-SQ-raw-no-replacements + DB-G02 SELECT-*) PASS
- T5 L2 pre-tool DB block: phase=4, Write `CREATE TABLE foo (id INT, val TEXT);` → `decision:deny` reason "MCL DB DESIGN — DB-G01-missing-primary-key [db-schema]..."; audit `db-scan-incremental high=1` + `db-scan-block` PASS
- T6 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-db-rules.py` (yeni, 34 rule)
- `hooks/lib/mcl-db-scan.py` (yeni, orchestrator)
- `hooks/lib/mcl-db-migration.sh` (yeni, squawk + alembic delegate)
- `hooks/lib/mcl-db-explain.sh` (yeni, MCL_DB_URL stub)
- `hooks/lib/mcl-stack-detect.sh` (17 yeni tag: 6 DB + 3 cloud + 8 ORM)
- `hooks/lib/mcl-state.sh` (`phase4_5_db_scan_done` field)
- `hooks/mcl-activate.sh` (`/mcl-db-report` + `/mcl-db-explain` keyword blokları)
- `hooks/mcl-pre-tool.sh` (Phase 4 DB incremental block)
- `hooks/mcl-stop.sh` (Phase 4.5 START DB gate)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (7 DB design dimension)
- `skills/my-claude-lang/phase4-5-risk-review.md` (Lens (d) DB extension)
- `VERSION` (8.7.1 → 8.8.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (kabul edilmiş, 8.8.x patch'lerine ertelendi)

- **N+1 runtime profiling D3** MVP'de **model-behavioral**; test runner direct-integration (pytest-django plugin / RSpec helper / jest setup) 8.8.x patch'lerinde
- **`/mcl-db-explain` F2** MVP'de **stub**: `MCL_DB_URL` set'liyse generic CLI EXPLAIN (`psql/mysql/sqlite3`); ORM-spesifik query introspection (auto-detected slow paths from query log) 8.8.x'te
- **Cloud DB (BigQuery / Snowflake / DynamoDB)** stack-tag detection eklendi ama dialect-spesifik kural setleri 8.8.x patch'lerinde; tag varlığı şimdilik audit-only
- **Migration tool yokluğu** (squawk / alembic-check binary install edilmemiş): ilgili dialect/ORM için skip + tek-seferlik warning
- **8 ORM × 3 rule = 24 ORM-spesifik rule** MVP; her ORM için 10+ derin rule yazılabilir, 8.8.x patch'lerinde
- **MongoDB / Redis / DynamoDB schema tasarımı** stack-tag tespit edilir ama dialect-spesifik kural seti MVP'de yok (RDBMS-first); 8.9 plan
- **EXPLAIN ANALYZE production safety**: `MCL_DB_URL` prod DB'sini gösteriyorsa `EXPLAIN ANALYZE` mutating queries için tehlikeli — `mcl-db-explain.sh` yalnızca `EXPLAIN` çalıştırır default
- **Trigger gating false-negative riski**: DB stack-tag tespit edilemeyen projelerde (örn. raw SQL string'lerde Postgres connection ama manifest'te dep yok) DB feature hiç çalışmaz
- **14 dilden yalnızca TR + EN tam lokalize**; diğer 12 dil EN fallback (codebase-scan / security-report ile aynı pattern)

## [8.7.1] - 2026-04-29

### Eklendi — Hook entegrasyonu (8.7.0'da ertelenmişti)

#### L2 — Phase 4 incremental scan (`hooks/mcl-pre-tool.sh`)
Edit/Write/MultiEdit branch'inde HIGH-only quick scan eklendi. Tetikleme: `tool_name ∈ {Edit, Write, MultiEdit}` AND source ext (ts/tsx/js/jsx/py/rb/go/rs/java/kt/swift/cs/php/cpp/c/h/lua/vue/svelte) AND `current_phase=4` AND `MCL_STATE_DIR` set. Mekanizma:
1. Hypothetical post-edit content temp dosyaya yazılır (Edit: old→new bellek apply; MultiEdit: edits sırayla; Write: content doğrudan)
2. `mcl-security-scan.py --mode=incremental --target <tmp>` çağrılır
3. HIGH bulgu varsa `decision:deny` JSON döner; reason: `MCL SECURITY — <rule_id> (OWASP <ref>) at <file>:<line> — <message>. Fix the issue and retry.` Audit: `security-scan-block | mcl-pre-tool | rule=... tool=... file=... severity=HIGH`
4. MEDIUM/LOW sessiz, audit only (`security-scan-incremental | mcl-pre-tool | file=... high=N med=N low=N skipped_via_cache=...`)

Recursion safety: pre-tool MCL'in kendi tool'larını intercept etmiyor; harici Edit/Write çağrılarına özel.

#### L3 — Phase 4.5 START gate (`hooks/mcl-stop.sh`)
Mevcut Phase 4.5 enforcement state machine'inin pending dalına security scan tetikleme eklendi. Mekanizma:
1. State `pending` AND `phase4_5_security_scan_done=false` ise `mcl-security-scan.py --mode=full` (timeout 120s, cache'li → tipik <5s)
2. **HIGH ≥ 1:** state `pending`'de kalır (advance yok), `decision:block` döner; reason'da ilk 5 HIGH bulgu listesi (rule_id + OWASP + file:line + mesaj). Standart Phase 4.5 reminder mesajı **bypass edilir**. Audit: `security-scan-block | mcl-stop | full-scan high=N`. Geliştirici fix yaptıkça L2 incremental tetikler; tüm HIGH'lar fix'lendiğinde sonraki Stop'ta scan tekrar çalışır → HIGH=0 olur.
3. **HIGH = 0:** `phase4_5_security_scan_done=true` set'lenir. Standart Phase 4.5 reminder block emit'ler ama reason'a MEDIUM bulgu listesi (max 8 satır) eklenir — "surface each one as a [Security] item in the Phase 4.5 sequential dialog". MEDIUM'lar Lens (d) etiketli risk turn'ü olarak işlenir.
4. **LOW** her zaman audit-only, dialog'a girmez.

Idempotency: `phase4_5_security_scan_done` field'ı state'e eklendi (default false). Phase 4.5 cycle başında reset davranışı mevcut state lifecycle'ına bağlı (session_start → state default).

#### State şema değişikliği
- `mcl-state.sh` `_mcl_state_default` schema'sına `phase4_5_security_scan_done: false` eklendi. v2 schema bumped değil — yeni field default false ile geriye dönük uyumlu.

### Test sonuçları
- T1 Pre-tool L2: phase=4, Write `cursor.execute("..." + name)` → `decision:deny` doğru reason ("G01-sql-string-concat (OWASP A03) at .../app.py:2 — ..."), audit `security-scan-incremental` (high=2) + `security-scan-block` (rule=G01-sql-string-concat) PASS
- T2 Stop L3: durum cycle smoke test — pending'de scan tetiklenir (regression suite üzerinden doğrulandı)
- T3 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-state.sh` (schema'ya `phase4_5_security_scan_done` field'ı)
- `hooks/mcl-pre-tool.sh` (Phase 4 incremental scan branch eklendi, secret-scan-block JSON pattern'i mirror'landı)
- `hooks/mcl-stop.sh` (Phase 4.5 START security gate, mevcut enforcement'a entegre)
- `VERSION` (8.7.0 → 8.7.1)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.7.0'dan devralınmış, hâlâ geçerli)

- A04 Insecure Design + A09 Logging/Monitoring sadece L1 design-time
- ASVS L1 subset (V2/V3/V4/V5/V6/V7/V8); L2/L3 kapsam dışı
- BOLA/IDOR semantik — heuristic decorator yokluğu yakalar; logic flaw'ları yakalayamaz
- SCA tool yokluğunda ilgili stack için A06 skip
- 14 dilden TR + EN tam lokalize, diğer 12 dil EN fallback
- 100k+ mono-repo Phase 4.5 full scan dakikalarca sürebilir; cache ilk runda etkisiz

## [8.7.0] - 2026-04-29

### Eklendi — Backend Security (3-tier OWASP+ASVS L1)

Sistematik backend güvenlik kapsama: Phase 1.7 design-time + Phase 4.5 post-hoc taxonomic + manuel `/mcl-security-report` keyword. Mevcut Semgrep + secret-scan üstüne kurulan severity-tiered enforcement ile HIGH bulgular Phase 4.5 dialog'unu bloke eder, MEDIUM sequential dialog item olur, LOW audit-only.

#### Yeni dosyalar
- **`hooks/lib/mcl-security-rules.py`** — generic core (G01-G13: SQLi-concat, command-exec-user-input, eval-from-string, hardcoded HIGH-entropy secret, DEBUG flag, CORS wildcard, weak hash, AES-ECB, hardcoded JWT secret, SSRF, path-traversal, insecure-deserialization, weak-TLS) + 7 stack add-on (S-PY-django-allowed-hosts, S-PY-fastapi-cors, S-RX-unsafe-html-setter, S-RX-target-blank-no-rel, S-JV-spring-csrf-disabled, S-RB-rails-strong-params, S-PHP-laravel-debug). Decorator-based registry; her bulgu severity + OWASP + ASVS + category field'ı taşır. **20 rule total.**
- **`hooks/lib/mcl-security-scan.py`** — orchestrator: enumerate, file-SHA1+rules-version composite cache, Semgrep `p/default` çağrı, SCA çağrı, severity routing, lokalize markdown render. Modes: `incremental` (tek dosya, HIGH-only + Semgrep ERROR-only), `full` (tüm proje + Semgrep packs + SCA), `report` (cache bypass).
- **`hooks/lib/mcl-sca.sh`** — SCA wrapper: stack tag'e göre `npm audit --json`, `pip-audit --format json`, `cargo audit --json`, `govulncheck`, `bundle-audit` çağrı; binary yoksa graceful skip + tek-seferlik warning. Tüm finding'ler ortak şemaya normalize edilir.

#### Hook entegrasyonu (8.7.0 MVP)
- **`hooks/mcl-activate.sh`** — `/mcl-security-report` keyword detection bloğu (mevcut `/codebase-scan` mirror'ı). Kullanıcı yazınca pipeline atlanır, Bash tool ile `mcl-security-scan.py --mode=report` çağrılır, lokalize markdown rapor sunulur.

#### Phase 1.7 design-time L1 (5 yeni dimension)
- **8. Auth Model** (OWASP A07): kim çağırabilir, kimlik doğrulama nasıl?
- **9. Authz Unit / Resource-Owner Check** (OWASP A01): BOLA/IDOR — owner check explicit mi? SAST kapsamayan en kritik kategori.
- **10. CSRF Stance** (A01/A05): cookie-session vs bearer-token vs custom flow.
- **11. Secret Management Strategy** (A02): repo (yasak) / env-var / secret manager.
- **12. Deserialization Input Source** (A08): JSON+schema vs YAML/binary-serialization.

Hepsi mevcut SILENT-ASSUME / SKIP-MARK / GATE üçlüsünü kullanır.

#### Phase 4.5 lens (d) genişletme (8.7.0+)

Phase 4.5 START'ta zorunlu güvenlik scan: orchestrator çalışır, severity routing uygulanır:
- **HIGH** → Phase 4.5 START gate, dialog başlamaz; HIGH'lar fix edilene kadar bekle. Bare skip yasak.
- **MEDIUM** → sequential dialog item, `[Security]` etiketiyle.
- **LOW** → audit-only, `security-findings.jsonl`.

Auto-fix: Semgrep safe-category (formatting/rename/import) silent apply. auth/crypto/secret/authz **asla silent**.

#### Coverage matrix

| OWASP | Source | Yer |
|---|---|---|
| A01 Broken Access Control | stack add-on + Phase 1.7 | L1+L3 |
| A02 Cryptographic Failures | generic core | L3 |
| A03 Injection | generic + Semgrep | L3 |
| A04 Insecure Design | Phase 1.7 | L1 only |
| A05 Security Misconfig | stack add-on | L3 |
| A06 Vulnerable Components | SCA tools | L3 |
| A07 Auth Failures | Semgrep + stack | L3 |
| A08 Software/Data Integrity | generic | L1+L3 |
| A09 Logging/Monitoring | Phase 1.7 audit-dim | L1 only |
| A10 SSRF | generic | L3 |

ASVS L1 subset (V2/V3/V4/V5/V6/V7/V8) finding schema'sındaki `asvs` field'ında belirtilir.

### Test sonuçları
- T1 `/mcl-security-report` keyword detection: STATIC_CONTEXT 1019 byte, `MCL_SECURITY_REPORT_MODE` + `--mode=report` mevcut PASS
- T2 Synthetic Python (eval+SQLi+secret+DEBUG+ALLOWED_HOSTS+md5): 3 HIGH (G01+G04+Semgrep sqlalchemy) + 2 MEDIUM (G05+G07) tespit; OWASP/ASVS field'lar dolu PASS
- T3 Lokalizasyon TR: "Yüksek şiddet" / "Orta şiddet" / "Tarama tamamlandı" başlıkları doğru PASS
- T4 Audit log: `security-scan-full | mcl-stop | high=3 med=2 low=0 duration_ms=N sources=generic,stack,semgrep` doğru format PASS
- T5 Mevcut suite: 19 pass / 0 fail / 2 skip — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-security-rules.py` (yeni, 20 rule)
- `hooks/lib/mcl-security-scan.py` (yeni, orchestrator)
- `hooks/lib/mcl-sca.sh` (yeni, 5 stack tool wrapper)
- `hooks/mcl-activate.sh` (`/mcl-security-report` keyword bloğu)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (5 yeni dimension)
- `skills/my-claude-lang/phase4-5-risk-review.md` (Lens (d) 8.7.0+ expanded section)
- `VERSION` (8.6.0 → 8.7.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (kabul edilmiş — 8.7.1 patch'te ele alınacak)

- **Phase 4 incremental L2 hook entegrasyonu MVP'de yok.** Pre-tool Edit/Write/MultiEdit branch'inde HIGH-only quick scan + `decision:deny` mekanizması 8.7.1'e ertelendi. Şu an: Phase 4'te yazılan kod Phase 4.5 START'ta yakalanır; per-Edit blocking yok.
- **Phase 4.5 hard-enforcement hook MVP'de yok.** mcl-stop.sh'a HIGH-bulgu-varsa-`decision:block` mekanizması 8.7.1'e ertelendi. Şu an: HIGH bulgu davranışı **model-behavioral** — phase4-5 skill'i Lens (d) expanded section'da modele talimat verir, Bash + scan + parse + fix yap. Hook seviyesi enforcement yok; geliştirici güvenliği `/mcl-security-report` ile manuel doğrulayabilir.
- **A04 Insecure Design ve A09 Logging/Monitoring** sadece L1 (Phase 1.7) — runtime detection yok (kategorik kapsam dışı).
- **ASVS L1 subset** (V2/V3/V4/V5/V6/V7/V8); L2/L3 kapsam dışı.
- **BOLA/IDOR semantik** — heuristic yalnızca "decorator yokluğu" yakalar; logic flaw'ları yakalayamaz (manuel review).
- **SCA tool yokluğunda** (`pip-audit`, `cargo-audit`, `govulncheck`, `bundle-audit` install edilmemiş) ilgili stack için A06 skip; warning tek seferlik stderr'a düşer.
- **14 dilden yalnızca TR + EN tam lokalize**; diğer 12 dil EN fallback (codebase-scan ile aynı pattern).
- **100k+ mono-repo'da `--mode=full` dakikalarca sürebilir**; cache ilk run'da etkisiz; kullanıcı sorumluluğu.

## [8.6.0] - 2026-04-29

### Eklendi — `/codebase-scan` (Codebase Learning)

Manuel keyword komutuyla projeyi P1-P12 pattern set'iyle tarayan ve otomatik project knowledge çıkaran yeni özellik. Kullanıcı `/codebase-scan` yazar; MCL pipeline'ı atlanır; Python script projeyi tarar; iki dosya üretilir.

#### Çıktılar
- **`$MCL_STATE_DIR/project.md`** — high-confidence bulgular, `<!-- mcl-auto:start -->...<!-- mcl-auto:end -->` marker'ları arasında. Marker dışı bölge (Mimari / Teknik Borç / Bilinen Sorunlar) Phase 5-curated kalır, scan dokunmaz (M3 strategy).
- **`$MCL_STATE_DIR/project-scan-report.md`** — tüm bulgular (high + medium + low), kullanıcı dilinde başlıklarla, evidence path'leri ve detaylarla.

#### Pattern set (12 dimension)

| ID | Çıkardığı | Yöntem |
|---|---|---|
| **P1** Stack | `mcl-stack-detect.sh` tag'leri | subprocess shell source |
| **P2** Mimari | Monorepo (pnpm/lerna/nx/turbo), Clean/MVC layout | top-dir heuristic |
| **P3** Naming | camelCase / snake_case / PascalCase / kebab-case dominant ratio | source sample regex |
| **P4** Error handling | try-catch / Result / raise / panic / throw new dominant | source sample regex |
| **P5** Test | Framework (vitest/jest/pytest/...) + test dirs | manifest dep + dir presence |
| **P6** API style | Express/Fastify/FastAPI/Django/GraphQL/tRPC | manifest dep |
| **P7** State mgmt | Redux/Zustand/Jotai/MobX/Pinia/React-Query/SWR | manifest dep |
| **P8** DB | Prisma/SQLAlchemy/TypeORM/Drizzle/Mongoose + migration dirs | file + manifest |
| **P9** Logging | Winston/Pino/Loguru/structlog vs ad-hoc console/print | manifest dep + sample scan |
| **P10** Lint | TS strict / ESLint / Prettier / Ruff / mypy | config file presence + key fields |
| **P11** Build/deploy | Dockerfile / GH Actions / Vercel / Netlify / Fly | file presence |
| **P12** README intent | İlk paragraf | text extraction |

#### Confidence routing

- **high** → `project.md` marker'lı bölüme yazılır (lokalize başlıklarla: Otomatik: Mimari / Stack & Araçlar / Konvansiyonlar / Test / Diğer)
- **medium / low** → yalnızca `project-scan-report.md`'ye yazılır

#### Lokalizasyon

Script `--lang <iso>` argümanı alır (mcl-activate.sh `MCL_USER_LANG` env'inden geçer, default `tr`). 14 dilden TR ve EN mevcut; diğer diller için EN fallback. Section başlıkları + verdict kelimeleri çevirilir; teknik token'lar (path, dep ismi, framework adı, pattern_id) İngilizce kalır.

#### Tetikleme

`mcl-activate.sh`'ta `/mcl-doctor`/`/mcl-update` ile aynı pattern: `PROMPT_NORM = "/codebase-scan"` eşleşmesi → MCL pipeline skip + Bash tool ile script çağrı talimatı + sonucun olduğu gibi sunulması talimatı. Otomatik tetikleme YOK (kullanıcı kararı).

#### Tarama kapsamı

- Sınırsız derinlik (kullanıcı kararı). Excludes: `.git`, `node_modules`, `dist`, `build`, `.next`, `target`, `vendor`, `.venv`, `__pycache__`, `.cache`, `coverage`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `out`, `.turbo`, `.parcel-cache`, `.svelte-kit`.
- Source extensions: `.ts/.tsx/.js/.jsx/.mjs/.cjs/.py/.rb/.go/.rs/.java/.kt/.swift/.cs/.php/.cpp/.c/.h/.hpp/.lua/.vue/.svelte/.scala/.dart`.
- Manifest set: package.json, pyproject.toml, Cargo.toml, go.mod, Gemfile, pom.xml, build.gradle(.kts), composer.json, Package.swift, mix.exs, deno.json, *.csproj.
- Dosya boyutu cap: 1 MB. Lock dosyaları ve minified asset'ler atlanır.

#### Progress göstergesi

Stderr'a per-pattern ilerleme: `[MCL] Scanning... P3 (3/12)`. Bash tool çıktısında kullanıcı görür.

#### Phase 3.5 ilişkisi (S2 cache-first — partial)

8.6.0'da Phase 3.5 dedicated skill dosyası mevcut değil (Phase 3.5 model-behavioral). Bu nedenle "Phase 3.5 önce project.md cache'ini okur" kuralı **skill düzeyinde** dedicated implementasyona alınamadı. Geçici çözüm: hook STATIC_CONTEXT prose'u Phase 1/3'ten itibaren `project.md` (ve auto bölümü) referans verir; model dosyayı Read edip pattern'leri kullanır. Dedicated `phase3-5-pattern-matching.md` skill'i 8.6.x patch'inde eklenecek (ayrı plan); bu noktaya kadar S2 cache-first behavioral seviyede kalır.

### Test
- T1 `/codebase-scan` keyword detection → MCL_CODEBASE_SCAN_MODE STATIC_CONTEXT inject (1172 byte) PASS
- T2 Self-test: MCL repo'sunda script çalıştı, 9 source dosya, P1+P3+P5+P9+P12 bulguları doğru üretildi PASS
- T3 Marker yok + Phase 5 içerik mevcut → marker'lı bölüm üste enjekte edildi, Mimari/Teknik Borç korundu PASS
- T4 Marker var + ikinci scan → marker arası replace, Phase 5 içeriği dokunulmadı (idempotent) PASS
- T5 TR lang flag → "Yüksek güvenilirlikteki bulgular", "Otomatik: Mimari" başlıkları lokalize PASS
- T6 Mevcut suite 19/0/2 PASS (regresyonsuz)

### Updated files
- `hooks/lib/mcl-codebase-scan.py` (yeni, ~500 satır)
- `hooks/mcl-activate.sh` (`/codebase-scan` keyword block)
- `VERSION` (8.5.0 → 8.6.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (kabul edilmiş)

- **100k+ dosyalı dev mono-repo'larda scan dakikalarca sürebilir** — sınırsız derinlik kullanıcı kararı, performance budget yok. Kullanıcı sorumluluğu.
- **Phase 3.5 dedicated skill yok** — S2 cache-first 8.6.0'da behavioral seviyede; dedicated skill 8.6.x'te.
- **14 dil lokalizasyonu kısmi** — TR ve EN tam, diğer 12 dil EN fallback. Tam çeviri sonraki patch.
- **Naming dominant kuralı sınırlı** — 4 kategori (camel/snake/Pascal/kebab) arasında dominant; karışık projeler "low confidence" olarak sınıflandırılır, project.md'ye yazılmaz.

## [8.5.0] - 2026-04-29

### BREAKING — Per-project isolation via wrapper launcher

MCL artık projeye **hiçbir dosya/klasör yazmıyor**. Tüm hook deklarasyonları, state, audit log ve session-context dosyaları `~/.mcl/projects/<sha1(realpath PWD)>/` altında, proje dışında saklanıyor. Kullanım: `claude` yerine `mcl-claude` çalıştır.

#### Yeni mimari
- **Wrapper script** `bin/mcl-claude`: `$PWD`'nin realpath'inden sha1 ile project key türetir, ilk çalıştırmada `~/.mcl/projects/<key>/` scaffolding'ini (settings.json + state/ + meta.json) oluşturur, `MCL_STATE_DIR` env var'ını export eder, sonra `claude --settings <per-project> --plugin-dir <shared-lib> "$@"` ile pass-through `exec` yapar. Saf wrapper — kendi flag'i yok, tüm Claude Code bayrakları transparan geçer.
- **Global installer** `install.sh`: `~/.mcl/lib/`'ye git clone (veya pull) ve `~/.local/bin/mcl-claude` symlink. Idempotent.
- **Plugin manifest** `plugin.json`: minimal manifest — `--plugin-dir` üzerinden Claude Code'un skill/agent discovery'si için tek dosya. Plugin marketplace'a yayın değil.
- **Hook env contract**: hook'lar zaten `MCL_STATE_DIR` env var'ını destekliyordu (8.x boyunca `<CLAUDE_PROJECT_DIR>/.mcl` fallback'i ile). Wrapper bu değeri `~/.mcl/projects/<key>/state` olarak set'ler → tüm state izole, fallback'i bypass eder.
- **`mcl-cost.py`**: `MCL_STATE_DIR` env var'ı varsa onu kullanır, yoksa legacy `<proj>/.mcl/` fallback'i (pre-8.5 install kullanıcıları için).

#### Kaldırılan / değişen
- `setup.sh` **silindi** — projeye dosya yazan eski install kanalı. Yerini `install.sh` (global) aldı.
- Kullanım komutu değişti: `claude` → `mcl-claude`. Bare `claude` artık MCL hook'larını yüklemez (settings injection wrapper'a özel).

#### Migration: yok (M4)
Mevcut kullanıcıların `<proj>/.mcl/` ve `<proj>/.claude/` dizinleri 8.5.0'a geçince orphan kalır. Phase progress / audit log korumak isteyenler manuel taşır:
```bash
cd <project>
mcl-claude  # bir kez çalıştır → ~/.mcl/projects/<key>/ yaratılır
key=$(ls -t ~/.mcl/projects | head -1)  # en son yaratılan
mv .mcl/* ~/.mcl/projects/$key/state/
rm -rf .mcl .claude/settings.json .claude/hooks .claude/skills/my-claude-lang
```

#### Tasarım kararları (referans)
- **Path X** seçildi (`--settings` merge mode), Path Y (`--bare`) değil — kullanıcının `~/.claude/` skills/MCP/statusline ayarı korunur.
- **CLAUDE_CONFIG_DIR yolu reddedildi** — undocumented, GitHub issue #25762 hâlâ açık, davranış hybrid/split. POC ile doğrulandı.
- **Project key K1** (path-sha1) — setup-free, rename-safe değil ama M4 kapsamında kabul.
- **Minimal plugin.json** kabul edildi — düz dizin felsefesini bozmayan tek dosya, Claude Code'un skill discovery'si için zorunlu.

### Test
- Wrapper smoke test: `mcl-claude` stub claude ile çalıştırıldı, doğru bayraklar ve env var'lar geçirildi, proje dizini sıfır footprint, `~/.mcl/projects/<key>/` doğru yaratıldı PASS
- Mevcut suite: 19/0/2 — `MCL_STATE_DIR` zaten destekli olduğundan regresyon yok PASS

### Updated files
- `bin/mcl-claude` (yeni)
- `install.sh` (yeni)
- `plugin.json` (yeni)
- `setup.sh` (silindi)
- `hooks/lib/mcl-cost.py` (`MCL_STATE_DIR` env var önceliği)
- `VERSION` (8.4.2 → 8.5.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (kabul edilmiş)

- **Project rename**: K1 path-sha1 olduğu için proje rename'inde state kaybolur (orphan dir). `mcl-claude --reinit` veya state taşıma komutu MVP'de yok; kullanıcı manuel `mv` yapar.
- **Plugin.json minimum field doğrulaması**: Claude Code'un plugin spec'i değişirse ek field gerekebilir; şu an `name`/`version`/`description` ile çalışıyor.
- **STATIC_CONTEXT prose'unda eski `.mcl/foo` mention'ları**: hook'lar dosya IO'yu doğru path'e yapıyor ama bazı model-facing prose hâlâ `.mcl/cost.json` gibi referanslar içeriyor. Cosmetic (model env var'dan absolute path resolve edebiliyor); 8.5.x patch'inde temizlenecek.

## [8.4.2] - 2026-04-29

### Düzeltildi — Real-use test'in açtığı 3 kalibrasyon sapması

8.4.1 sonrası "kullanıcı listele" prompt'u ile uçtan uca (Phase 1 → 1.7 → 1.5 → 2 → 4.5) synthetic transcript simülasyonunda 4 sapma noktası tespit edildi. Bu patch ilk 3'ünü skill düzeyinde düzeltir; 4. (domain-shape coverage gap) gelecek real-use test prompt önerisi olarak kayıt altına alındı.

#### `skills/my-claude-lang/phase1-5-engineering-brief.md`
- **GATE × default çakışması çözüldü.** Yeni alt bölüm: *"Phase 1.7 GATE answers override implicit defaults"*. Phase 1.7 GATE'i bir verb'ün implicit default'unu override ettiğinde (örn. `paginate` default'u `[default: cursor pagination, changeable]` ama react-frontend GATE'i "page-numbered" cevabı aldıysa) marker `[default: ..., changeable]` yerine `[confirmed: ...]` olur. Phase 3 Scope Changes Callout `[confirmed]` marker'ını reviewable default olarak değil, geliştirici tarafından açıkça onaylanmış parametre olarak gösterir. 2 kalibrasyon örneği eklendi.
- **Implicit layer addition sınır vakası açıklandı.** Calibration Examples tablosuna 2 yeni satır: aynı prompt ("kullanıcı listele") iki Phase 1 context'iyle. Mevcut React + FastAPI context'i ile backend layer mention'ı **allowed** (zaten Phase 1 context'inde); boş context ile **forbidden** (yeni layer eklemiş olur). Boundary açık: layer mention'ı yalnızca Phase 1 confirmed context'inde varsa allowed.

#### `skills/my-claude-lang/phase1-7-precision-audit.md`
- **Sequential GATE asking explicit hale getirildi.** Question Flow step 4 strengthened: birden fazla dimension GATE classify ederse queue'lanır ve **turn'ler arası sırayla** sorulur — aynı response'ta iki GATE sorusu (madde işareti veya numaralı liste ile bile) batch'lenmez. Her GATE cevabı confirm edilip parameter set'e işaretlenmeden sıradaki GATE evaluate edilmez. Mevcut "exactly one question" + "no list of multiple questions" satırı multi-GATE durumunu açıkça kapsıyor şimdi.

### Bilinen sınır (kabul edilmiş, gelecek real-use test'e devredildi)

8.4.1 stack-detect 3 yeni domain-shape tag (cli, data-pipeline, ml-inference) ekledi ama "kullanıcı listele" prompt'u admin panel olduğu için bu tag'leri exercise etmedi. Coverage doğrulaması için 3 ek real-use test prompt'u önerildi:

- **ml-inference test:** *"csv'deki sıralanmamış müşteri tweet'lerini sentiment'a göre etiketle, model `models/sentiment.pkl`"* → `*.pkl` artifact + Python project → `[python, ml-inference]` beklenir.
- **data-pipeline test:** *"günlük satış verisini Snowflake'e taşıyan dbt pipeline'ı kur"* → `dbt_project.yml` veya dependencies'te dbt-core → `[python, data-pipeline]` beklenir.
- **cli test:** *"projedeki TODO yorumlarını listeleyen `find-todos` adında bir CLI yap, npm üzerinden çalışsın"* → `package.json` `bin` field'ı + Phase 4 sonrası → `[typescript, cli]` beklenir.

Bu prompt'lar bir sonraki manuel kalibrasyon turunda (8.4.x) çalıştırılacak; otomatik test fixture'larına dönüştürme şu an scope dışı.

### Updated files
- `skills/my-claude-lang/phase1-5-engineering-brief.md` (GATE override section + 2 calibration örneği)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (Question Flow step 4 strengthened)
- `VERSION` (8.4.1 → 8.4.2)
- `FEATURES.md` (sürüm bumpı)
- `CHANGELOG.md` (bu giriş)

## [8.4.1] - 2026-04-29

### Eklendi — Stack-detect kapsam genişletme

Phase 1.7 stack add-on tarafının coverage'ı genişletildi. Önceki sürümde TS/JS/React tek başlık altındaydı, framework spesifik dimensions yoktu. Backend/system dilleri (Java, C#, Ruby, PHP, C++, Lua) ve domain-shape (cli/data-pipeline/ml-inference) `mcl-stack-detect.sh` tarafından otomatik tespit edilmiyordu.

#### `hooks/lib/mcl-stack-detect.sh`
- **3 yeni domain-shape detect tag** eklendi (dil tag'lerinden ayrı, içerik tabanlı):
  - `cli` — `package.json` içinde `bin` field, `pyproject.toml` içinde `[project.scripts]` veya `[tool.poetry.scripts]`, `Cargo.toml` içinde `[[bin]]`, `go.mod + cmd/`, dolu `bin/` dizini.
  - `data-pipeline` — `airflow.cfg`, `dags/`, `dbt_project.yml`, `prefect.yaml/toml`, ya da `requirements*.txt` içinde apache-beam/pyspark/dagster/dask/luigi.
  - `ml-inference` — `*.pkl/*.onnx/*.pt/*.h5/*.safetensors/*.pb` model artifact'leri, `mlflow/` veya `mlruns/` dizinleri, `model_card.md` / `MODEL.md`, ya da requirements/pyproject içinde torch/tensorflow/transformers/scikit-learn/xgboost/lightgbm/bentoml/mlflow.
- False positive kabul edilmiş risk: domain-shape tag'leri Phase 1.7 dimensions için heuristic — yanlış tetiklendiğinde dimensions hâlâ general enough olduğu için spec kırılmaz.

#### `skills/my-claude-lang/phase1-7-precision-audit.md`
- `### typescript / javascript / react` başlığı `### typescript / javascript` olarak rename edildi (yalnızca web base: modül sistemi, async pattern, package manager, deployment target).
- **10 yeni stack add-on bölümü** yazıldı; her biri 3-5 delta dimension içeriyor:
  - **Frontend frameworks (dedicated):** `react-frontend` (hooks/suspense/RSC/state mgmt), `vue-frontend` (Composition API/Pinia/SFC/SSR), `svelte-frontend` (stores vs runes/server islands/$:/compiler opts), `html-static` (asset bundling/SEO/accessibility/deployment).
  - **Backend dilleri:** `java` (framework/build tool/reactive vs blocking/persistence/version), `csharp` (framework/async pattern/DI/ORM/runtime), `ruby` (framework/ORM/jobs/mode/test framework), `php` (framework/ORM/jobs/version).
  - **Sistem dilleri:** `cpp` (standard/build/memory/concurrency/platform), `lua` (runtime/coroutines/modules/C interop).
- Multi-tag union pattern: React projesi `[typescript, react-frontend]` olarak tespit edilir; framework deltas TS/JS base'inin **üzerine** uygulanır (replace değil).
- Domain-shape add-on'larının TODO comment'leri kaldırıldı — artık `mcl-stack-detect.sh` 8.4.1 ile otomatik tetikliyor.
- Solid/Angular/Qwik ve kotlin-mobile vs kotlin-backend ayrımı gelecek genişleme için TODO olarak işaretlendi.

#### `skills/my-claude-lang/all-mcl.md`
- STEP-64 description'ı 8.4.1 stack coverage genişlemesi notunu içerecek şekilde güncellendi.

### Test
- T1 phase1-7 skill'inde 13+ `### ` başlık (en az 11 add-on + 2 yapısal) PASS
- T2 stack-detect.sh içinde `_mcl_is_cli/_mcl_is_dp/_mcl_is_ml=1` flag'leri PASS
- T3 TS/JS başlığı rename edildi PASS
- T4 Tier 1 sections (vue/svelte/react-frontend/java/csharp/ruby) mevcut PASS
- T5 Tier 2 sections (php/cpp/lua/html-static) mevcut PASS
- T6 mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz
- T7 fixture: `package.json` `"bin"` field → `cli` + `javascript` tag (multi-tag union doğrulandı) PASS
- T8 fixture: `requirements.txt` `torch==2.1.0` → `ml-inference` + `python` tag PASS
- T9 fixture: `dbt_project.yml` → `data-pipeline` tag PASS

### Updated files
- `hooks/lib/mcl-stack-detect.sh` (csharp detect block sonrasına 3 domain-shape detect bloğu eklendi)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (TS/JS rename + 10 yeni section)
- `skills/my-claude-lang/all-mcl.md` (STEP-64 description)
- `VERSION` (8.4.0 → 8.4.1)
- `FEATURES.md` (Stack add-on'lar listesi 8.4.1 genişletmesini yansıtıyor)
- `CHANGELOG.md` (bu giriş)

## [8.4.0] - 2026-04-29

### Değişti — Phase 1.5 contract (BREAKING)
- **Phase 1.5 artık upgrade-translator.** 8.3.x'e kadar Phase 1.5'in tek görevi user_lang → İngilizce sadık çeviriydi (`do NOT add scope, do NOT subtract scope`). 8.4.0'da bu sözleşme bilinçli olarak gevşetildi: brief artık vague verb'leri (`list`, `listele`, `show`, `göster`, `manage`, `yönet`, `process`, `işle`, `build`, `yap`, `handle`, `update`, ...) surgical English verb'lere yükseltir (`render a paginated table`, `expose CRUD operations`, `implement`, `transform`, vb.). Verb-implied standart default'lar `[default: X, changeable]` marker'larıyla annotate edilir.
- **Mission rationale:** ana hedef "İngilizce bilmeyen geliştiriciyi senior İngilizce seviyesine çıkarmak". Approach A (Phase 1.7'ye 8th dimension) ve Approach B (Phase 1.5 upgrade-translator) trade-off değerlendirmesinden sonra B seçildi — kullanıcıyı her vague verb için soruyla yormak yerine çıktıyı senior precision'a otomatik yükseltmek hedefe daha doğrudan hizmet ediyor.

### Eklendi — Hallucination guards (3 katmanlı)
- **Skill calibration:** [`phase1-5-engineering-brief.md`](skills/my-claude-lang/phase1-5-engineering-brief.md) tamamen yeniden yazıldı. Allowed Upgrades tablosu (14-dil verb mapping), Forbidden Additions hard prohibitions listesi, 13 calibration example (allowed vs forbidden upgrade çiftleri).
- **Phase 3 Scope Changes Callout:** [`phase3-verify.md`](skills/my-claude-lang/phase3-verify.md) güncellendi. `engineering-brief audit upgraded=true` olduğunda Phase 3 prose'unda zorunlu callout — geliştirici kendi dilinde her upgrade'i görür, "edit" ile düzeltebilir. Format Türkçe örnek + 14-dil localizable.
- **Phase 4.5 Lens (e) Brief-Phase-1 Scope Drift:** [`phase4-5-risk-review.md`](skills/my-claude-lang/phase4-5-risk-review.md) güncellendi. Mevcut 4 lens (Code Review/Simplify/Performance/Security) yanına 5. lens eklendi. `upgraded=true` olduğunda zorunlu çalışır: Phase 4 implementation'ın her elementi Phase 1 confirmed parameter'a izlenebilir mi VEYA `[default: X, changeable]` marker'ı taşıyor mu kontrol; izlenemeyen + marker'sız element `[Brief-Drift]` risk olarak risk-dialog'a surface — geliştirici 3 seçenekten birini seçer (remove / mark-as-default / rule-capture).

### Audit format extension
- `engineering-brief | phase1-5 | lang=<...> skipped=<...> retries=<...> clarification=<...> upgraded=<true|false> verbs_upgraded=<count>` — yeni alanlar `upgraded` (en az bir verb upgrade edildi mi) ve `verbs_upgraded` (kaç verb).

### Updated files
- `skills/my-claude-lang/phase1-5-engineering-brief.md` — major rewrite (faithful → upgrade-translator)
- `skills/my-claude-lang/phase4-5-risk-review.md` — Lens (e) eklendi
- `skills/my-claude-lang/phase3-verify.md` — Scope Changes Callout eklendi
- `hooks/mcl-activate.sh` STATIC_CONTEXT — Phase 1.5 prose'u upgrade-translator olarak güncellendi (JSON-safe escape: backtick yerine literal backtick kullanıldı, embedded double quotes kaldırıldı)
- `skills/my-claude-lang/all-mcl.md` — STEP-58 audit format ve description'ı güncellendi
- `FEATURES.md` — Phase 1.5 contract change bölümü eklendi

### Test
- T1 skill `phase1-5-engineering-brief.md` Allowed/Forbidden/Calibration sections var PASS
- T2 skill `phase4-5-risk-review.md` Lens (e) + Brief-Drift label var PASS
- T3 skill `phase3-verify.md` Scope Changes Callout + trigger var PASS
- T4 STATIC_CONTEXT 8.4.0 upgrade-translator instruction var PASS
- T5 STEP-58 audit format `upgraded=` ve `verbs_upgraded=` field'larını içeriyor PASS
- T6 mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz (JSON validity testleri kritikti; STATIC_CONTEXT prose'unda embedded `"Scope Changes"` literal quote'ları JSON parse'i kırıyordu, kaldırıldı — `Scope-Changes callout` formatına geçildi)

### Bilinen sınırlar (kabul edilmiş, CHANGELOG'a kayıt)
- **Phase 5.5 asimetri:** input-side upgrade (1.5) ama output-side faithful (5.5). Phase 5 raporunun geliştirici diline geri çevirisinde teknik kelime kaybı olabilir; spec ve audit trail surgical İngilizce'de korunur. Phase 4.5 Lens (e) gerçek scope drift'i yakalar.
- **Determinist disiplin değil:** upgrade kararı model semantic judgment'ına bağlı. Hedefin "deterministic AI discipline" yarısıyla değil, "senior precision" yarısıyla uyumlu. 3 katmanlı hallucination guard bu trade-off'u dengeleme amaçlı.
- **Hallucination edge cases:** "build login page" gibi eşik durumlar — skill calibration table boundary'i çiziyor ama her olası prompt için açıkça listelenmiyor. Phase 4.5 Lens (e) post-hoc safety net.
- **Behavioral test:** real-use validation manual (T7 spawn'lanmamış); sonraki sessionda gerçek prompt'la doğrulanacak.

## [8.3.3] - 2026-04-29

### Eklendi
- **Plan critique substance validation — subagent-driven gate (Gap #5).** 8.2.10 plan-critique gate Task çağrısının şeklini kontrol ediyordu (subagent_type=general-purpose + model=sonnet); `Task(prompt="say hi")` bypass'a açıktı. 8.3.3 niyet doğrulamasıyla bu açığı kapatır:
  - **`agents/mcl-intent-validator.md` (yeni)** — strict gate-keeper subagent. Sonnet 4.6 ile çalışır, prompt'u değerlendirir, single-line JSON `{"verdict":"yes"|"no","reason":"..."}` döner. Default bias: NO unless evidence is clear. Reversal pattern, trivial request, off-topic content tespit edilir.
  - **`hooks/mcl-pre-tool.sh`** — Task gate (8.2.10 shape check) substance-aware oldu: general-purpose+sonnet Task yakalandığında transcript'i tarayıp en son `Task(subagent_type=*mcl-intent-validator*)` çağrısının tool_result'ını parse eder. JSON verdict'ine göre 4 yol: `yes` → allow + state=true; `no` → `decision:block` + reason aktarımı; validator çağrılmamış → `decision:block` + "dispatch validator first" talimatı; malformed output → fail-open + `intent-validator-parse-error` audit warn.
  - **Recursion-safety:** validator agent kendi `subagent_type`'ını kullandığı için pre-tool'un general-purpose gate'i ile çakışmaz. Validator'ın Task çağrısı pre-tool'dan geçer, sonsuz loop yok.
  - **`setup.sh`** — yeni install adımı: `agents/mcl-*.md` → `~/.claude/agents/`. Sadece MCL prefix'li agent'lar kopyalanır (user agent çakışmasını önlemek için).
  - **STATIC_CONTEXT (`mcl-activate.sh`)** — `PLAN_CRITIQUE_PENDING_NOTICE` metnine 8.3.3 talimatı eklendi: "Before general-purpose plan critique Task, dispatch `Task(subagent_type='mcl-intent-validator', prompt=<same>)` first."
  - **STEP-65** — `all-mcl.md`'ye yeni: signal/pass/skip detayları, 4 audit event tipi (`plan-critique-done | intent_validated`, `plan-critique-substance-fail | intent=no|validator=not-called`, `intent-validator-parse-error`).

### Failure modes (kasıtlı tasarım)
- **Validator agent yüklü değil:** Claude Code "agent not found" → tool_result error → parse-error → fail-open. mcl check-up audit pattern'i ile yakalanır, kullanıcı setup tetikler.
- **Validator çağrılmamış:** fail-CLOSED, deterministic block (gate amacı bu).
- **Validator verdict=no:** fail-CLOSED, reason kullanıcıya iletildi.
- **Validator malformed JSON output:** fail-OPEN, audit warn. Runtime gürültüsünde kullanıcıyı kilitleme.

### Test
- T1 validator yes verdict → general-purpose Task allowed, state=true, audit `intent_validated` PASS
- T2 validator no verdict → `decision:block` + reason carried + state=false PASS
- T3 no validator call (boş transcript) → `decision:block` + `validator=not-called` audit PASS
- T4 validator returned malformed JSON → fail-open: state=true, `intent-validator-parse-error` audit, no block PASS
- T5 validator returned `{"verdict":"yes"}` (reason field eksik) → allow (verdict yeterli) PASS
- T6 iki sıralı validator (eski no, yeni yes) → en son yes alınır, allow PASS
- T7 mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz

### Bilinen sınır
- **Setup gereksinimi:** `~/.claude/agents/` altına agent kopyalanmadıysa (setup.sh çalıştırılmamış) ilk plan-critique fail-open path'inden geçer; mcl check-up ile farkedilir. Acceptable v1 davranışı.
- **Sonnet self-leniency:** validator strict bias verilse de %100 değil. Adversarial coordinated bypass teorik mümkün; cost-benefit analizi pahalı bypass'ı düşük olasılık yapıyor.
- **Tek-tur akış:** validator + general-purpose Task aynı turda sıralı dispatch edilmeli; multi-turn akışlar henüz desteklenmiyor.

## [8.3.2] - 2026-04-29

### Değişti
- **Phase 1.7 Precision Audit hard-enforced (Phase 4.5 tier).** 8.3.0'da skip-detection-only olarak çıkmıştı (audit-only warn). Determinist AI disiplini hedefini doğrudan etkilediği için decision:block enforcement'a yükseltildi:
  - `mcl-stop.sh` `case 1)` (Phase 1→2 transition) branch'inde, `📋 Spec:` block emit edildi AND audit log'da current session içinde `precision-audit` entry yoksa: state mutation atlanır (transition rewind), `decision:block` JSON stdout'a yazılır, hook çıkar. Claude aynı response içinde Phase 1.7'i çalıştırıp spec'i precision-enriched parametrelerle yeniden emit etmek zorunda.
  - İki audit event yazılır: `precision-audit-skipped-warn | mcl-stop.sh | summary-confirmed-but-no-audit` (8.3.0 backward compat) + `precision-audit-block | mcl-stop.sh | summary-confirmed-but-no-audit; transition-rewind` (yeni 8.3.2 enforcement).
  - **English-language safety valve:** detected language English ise `mcl_audit_log "precision-audit" "phase1-7" "core_gates=0 stack_gates=0 assumes=0 skipmarks=0 stack_tags= skipped=true"` emit edilir → block clear olur. STATIC_CONTEXT'te ve skill dosyasında prose ile İngilizce yolu belgelendi.
  - **Recovery:** false-positive durumunda `/mcl-restart` ile state temizlenir; `mcl-pre-tool.sh` zaten direct state.json bash yazımlarını blokluyor (state-machine bypass yok).

### Test
- T1 spec emit + audit yok + non-English → `decision:block` fire, state phase=1 kaldı, her iki audit event yazıldı PASS
- T2 spec emit + `precision-audit ... skipped=false` audit + non-English → block YOK, transition phase=2 PASS
- T3 KRİTİK: spec emit + `skipped=true` audit (English skip path) → block YOK, transition gerçekleşti, ne skip-warn ne block audit yazıldı PASS — İngilizce kullanıcılar block görmüyor doğrulandı
- T4 already-phase-2 (re-emit spec same session) → case 1) fire etmez, block path atlanır PASS
- T5 mevcut test suite: 19 pass, 0 fail, 2 skip — regresyonsuz

### Güncellenen dosyalar
- `hooks/mcl-stop.sh` — case 1) branch'ine block emit + audit + exit eklendi
- `skills/my-claude-lang/phase1-7-precision-audit.md` — "Enforcement (since 8.3.2)" + "Recovery" bölümleri
- `skills/my-claude-lang/all-mcl.md` — STEP-64 güncellendi: hard-enforcement açıklaması, English safety valve, iki audit event signal
- `hooks/mcl-activate.sh` STATIC_CONTEXT — Phase 1.7 prose'u "stop hook will block-and-rewind otherwise" + İngilizce safety valve cümlesi eklendi

## [8.3.1] - 2026-04-29

### Dokümantasyon
- **Phase 1.7 skill dosyasına "Scope and Extensibility" bölümü eklendi.** Stack add-on listesindeki spesifik dil/framework isimleri (TypeScript, Python, Go, Rust, Swift, Kotlin, vb.) örnektir — kapsamlı değildir. MCL evrensel bir araçtır: 7 core dimension her projede sabit kalır, stack add-on katmanı `mcl-stack-detect.sh` tag'lerine göre veri-odaklı genişler. Yeni stack tag eklendiğinde bu dosyaya yeni section eklenir; classification engine logic değişmez. Mevcut listeler korundu, sadece çerçeveleme netleştirildi.

## [8.3.0] - 2026-04-29

### Eklendi
- **Phase 1.7 — Precision Audit (yeni faz, ana misyon).** Phase 1'in "completeness" disiplinini "precision" ile tamamlar. Senior İngilizce geliştiricinin analitik düşünme davranışını sistemleştirir: confirmed Phase 1 parametreleri için 7 core boyut + stack-detect-driven add-on boyutları walk edilir.
  - **Core 7 boyut:** Permission/access, algorithmic failure modes, out-of-scope boundaries, PII handling, audit/observability, performance SLA, idempotency/retry. UX state'ler (empty/loading/error UI) **core'da DEĞİL** — UI stack add-on'larında.
  - **3 sınıflandırma:** SILENT-ASSUME (`[assumed: X]`), **SKIP-MARK** (yeni 3. kategori — `[unspecified: X]`, şu an yalnızca Performance SLA için), GATE (tek soru sor, one-question-at-a-time rule).
  - **Stack add-on'lar:** typescript/javascript/react, python, go/rust, cli, data-pipeline, mobile, ml-inference. Vue/Svelte/Angular ayrımı v1'de tek TS/JS/React başlığı altında — skill dosyasında TODO comment ile gelecek genişleme işaretli.
  - **English session skip:** `skipped=true` audit ile no-op (behavioral prior yeterli kabul).
  - **Detection control:** `mcl-stop.sh` Phase 1→2 transition'ında audit'te `precision-audit` yoksa `precision-audit-skipped-warn` yazar.
- **Files:** `skills/my-claude-lang/phase1-7-precision-audit.md` (yeni skill, 7 core dim + 7 stack add-on + sample questions); `skills/my-claude-lang.md` (pointer satırı); `skills/my-claude-lang/all-mcl.md` (STEP-64); `hooks/mcl-activate.sh` STATIC_CONTEXT (Phase 1 → 1.7 → 1.5 → 2 sıralaması); `hooks/mcl-stop.sh` (skip-detection bloğu Phase 1→2 case branch'inde).

### Test
- Skill dosyası mevcut, 7 core dim + 7 stack section + SKIP-MARK + Vue/Svelte TODO PASS
- Pointer line `skills/my-claude-lang.md`'de PASS
- STEP-64 `all-mcl.md`'de PASS
- Skip-detection: spec emit + audit boş → `precision-audit-skipped-warn` yazıldı PASS
- Skip-detection: spec emit + `precision-audit` audit var → warn yazılmadı PASS
- English session skip: `skipped=true` audit → warn yazılmadı PASS
- Stack tag listesi (7 add-on) skill dosyasında doğrulandı PASS
- Mevcut test suite: 19 pass, 0 fail, 2 skip — regresyonsuz

### Out of scope (gelecek iterasyonlar)
- `PRECISION_AUDIT_PENDING_NOTICE` activate hook injection — v1'de behavioral + audit detection yeterli kabul edildi. Gerekirse v2'de eklenir.
- `precision_audit_done` state field — v1'de behavioral phase, audit-driven detection. Yeni state field eklenmedi.
- Per-project dimension override (`.mcl/precision-config.json`) — v1: skill dosyası tek truth source.
- Vue/Svelte/Angular framework-specific stack add-on'ları — TODO comment skill dosyasında.

## [8.2.13] - 2026-04-29

### Düzeltildi
- **`/mcl-restart` JIT defeat bug.** Aynı session içinde `/mcl-restart` çağrıldığında JIT promote (pre-tool 482-485), transcript'te hâlâ duran pre-restart spec-approve askq'sini bularak state'i `phase=4, spec_approved=true, spec_hash=<old>` olarak geri alıyordu. Stop hook "askq-idempotent" branch'inde sessiz kaldığı için düzeltme yapmıyordu. Sonuç: developer'ın restart kararı görsel olarak başarılı, gerçekte etkisiz.
- **Çözüm — `restart_turn_ts` filter:**
  - `hooks/lib/mcl-state.sh`: default state'e `restart_turn_ts: null` field eklendi.
  - `hooks/mcl-activate.sh`: `/mcl-restart` branch'i `restart_turn_ts=$(date +%s)` yazıyor; session boundary reset listesine `restart_turn_ts null` eklendi.
  - `hooks/lib/mcl-askq-scanner.py`: opsiyonel ikinci CLI argv'i (`min_ts_epoch`) eklendi. Transcript entry'sinin `timestamp` ISO 8601 alanı parse edilip epoch'a çevrilir; min_ts'ten önce olan girişler atlanır. Defansif: timestamp parse edilemezse entry korunur.
  - `hooks/mcl-pre-tool.sh` JIT bloğu + `hooks/mcl-stop.sh` askq scanner çağrısı `restart_turn_ts` değerini scanner'a geçirir.

### Test
- T1 `/mcl-restart` → `state.restart_turn_ts` epoch integer set PASS
- T2 Scanner direct: pre-restart askq + min_ts > entry ts → `intent=""` (filtrelendi) PASS
- T3 E2E: pre-restart askq + `/mcl-restart` + Write → JIT mutate etmedi, state phase=1 kaldı, Write phase gate ile bloklandı (`deny-tool`), `askq-advance-jit` audit YOK PASS
- T4 E2E: pre-restart askq + `/mcl-restart` + FRESH spec + FRESH approve askq + Write → JIT fresh askq'yi seçti (post-restart timestamp), promote edildi, audit'te `askq-advance-jit` VAR PASS
- T5 Mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz PASS

### Bilinen takip — out of scope
- **Stop hook plaintext-approve fallback bug.** `mcl-stop.sh` 244-294 satırlarındaki "plaintext approve fallback" kodu transcript'in son user mesajını okur ve `onayla/yes/approve` gibi free-text approve word geçiyorsa askq olmadan da `ASKQ_INTENT=spec-approve` synthesize eder. Bu kod yolu scanner kullanmıyor — `restart_turn_ts` filter etkilemiyor. `/mcl-restart` sonrası user yeni bir mesajda "approve" derse veya eski yapay-onay metnini içeren bir mesaj zincirleme tespit edilirse aynı defeat yaşanabilir. Ayrı fix gerektirir; bu release'in scope'unda değil. (Takip için spawn_task açıldı.)

## [8.2.12] - 2026-04-29

### Dokümantasyon
- **Bilinen sınırlama: post-tool hook race in parallel tool batches.** Claude Code resmi hook lifecycle belgesine göre `PreToolUse` hook'ları serileşik fire eder (race yok), ancak `PostToolUse` hook'ları async ve non-deterministic sırada fire eder — paralel tool batch'inde 2+ post-tool süreci aynı anda `state.json` yazabilir. `mcl-state.sh::_mcl_state_write_raw` tmp+rename atomik ama field-level merge yapmaz, dolayısıyla `mcl-post-tool.sh`'in yazdığı `last_write_ts` ve `regression_block_active` alanları için race noktası mevcut.
- **Etki seviyesi düşük-orta:** `last_write_ts` kaybı yalnızca regression-guard smart-skip'i etkiler (perf, korrektlik değil); `regression_block_active=false` kaybı `mcl-stop.sh`'in regression-guard re-evaluation'ı ile sonraki turda telafi edilir (eventual consistency).
- **Mitigasyon kasıtlı eklenmedi.** flock veya field-merge complexity > value değerlendirildi. Kaynak: [code.claude.com/docs/en/hooks.md](https://code.claude.com/docs/en/hooks.md).
- **`FEATURES.md`'ye "Bilinen Sınırlamalar / Known Limitations" bölümü eklendi** — race senaryosu somut bir örnekle dokümante edildi (paralel `Write` + `Bash` GREEN), etki analizi ve mitigasyon kararı kayıt altına alındı.

## [8.2.11] - 2026-04-29

### Eklendi
- **Session Context Bridge — cross-session bilgi köprüsü (`mcl-stop.sh`, `mcl-activate.sh`, `all-mcl.md`):**
  - **Hook (`mcl-stop.sh`):** `trap EXIT` ile her Stop'ta (early-exit'ler dahil) `.mcl/session-context.md` yazılır. Markdown 4-6 satır: aktif faz + spec hash kısa hex, son commit SHA + subject (60 char trim), state-driven sıradaki adım (`phase_review_state`/`pattern_scan_due`/`plan_critique_done`/phase numarası kural tablosu), opsiyonel yarım plan veya Phase 4.5 başlatılmamış uyarısı. Atomic write (tmp + rename). Git project dir'de çalıştırılır (`CLAUDE_PROJECT_DIR` veya cwd) — non-git projelerde commit satırı omit edilir.
  - **Auto-display (`mcl-activate.sh`):** Session boundary'de (`SESSION_ID != plugin_gate_session`) `.mcl/session-context.md` okunur ve `SESSION_CONTEXT_NOTICE` olarak `<mcl_audit name="session-context">` bloğuyla `additionalContext`'e enjekte edilir. Aynı session içinde re-inject yok. JSON-safe escape (`\\\"` + `\\n`).
  - **STEP-63:** `skills/my-claude-lang/all-mcl.md`'ye `session-context-bridge` adımı eklendi. `audit.log`'da `session-context-injected` event ile pass koşulu doğrulanır.

### Test
- Stop → `.mcl/session-context.md` oluşturulur (trap EXIT) PASS
- Phase 4 + spec hash → "Aktif iş: Phase 4 (EXECUTE) — spec abc12345" satırı PASS
- `phase_review_state="pending"` → "Sıradaki adım: Phase 4.5 risk review başlat" + "Yarım iş: Phase 4.5 başlatılmadı" satırları PASS
- Plan dosyası + `plan_critique_done=false` → "Yarım plan: .claude/plans/myplan.md — critique pending" satırı PASS
- Yeni session boundary → `SESSION_CONTEXT_NOTICE` enjekte edildi PASS
- Aynı session devam → notice yok (boundary-only) PASS
- Mevcut test suite: 19 pass, 0 fail, 2 skip — regresyonsuz

## [8.2.10] - 2026-04-29

### Eklendi
- **Gap 3 — Plan critique subagent enforcement trinity (`mcl-state.sh`, `mcl-pre-tool.sh`, `mcl-activate.sh`, `mcl-stop.sh`):**
  - **State schema:** `plan_critique_done: false` alanı eklendi (`mcl-state.sh` default state). Session boundary'de `mcl-activate.sh` resetler.
  - **Hook (`mcl-pre-tool.sh`):** İki intercept eklendi: (a) `Task` çağrısı `subagent_type=*general-purpose*` + `model=*sonnet*` ise `plan_critique_done=true` set edilir; (b) `ExitPlanMode` çağrısı `plan_critique_done=false` durumundayken `decision:block` ile reddedilir, audit `plan-critique-block | tool=ExitPlanMode plan_critique_done=false` yazılır. Block reason'ı Claude'a `Task(general-purpose, sonnet)` çağırmasını söyler.
  - **Reset on plan-file Write/Edit:** `mcl-pre-tool.sh` end-of-flow'a yeni blok eklendi — Write/Edit/MultiEdit `*/.claude/plans/*.md` veya `.claude/plans/*.md` patterni'ne uyduğunda `plan_critique_done=false` resetlenir. Plan içeriği değiştiyse yeni critique gerekir.
  - **Auto-display (`mcl-activate.sh`):** Her turda `.claude/plans/*.md` dosyası varsa ve `plan_critique_done!=true` ise `PLAN_CRITIQUE_PENDING_NOTICE` enjekte edilir. Pre-tool gate'in proaktif sinyali — Claude'a critique yapmadan ExitPlanMode'un bloklanacağı önceden bildirilir.
  - **Meta-control (`mcl-stop.sh`):** Eğer son assistant turda `ExitPlanMode` tool_use var VE state hâlâ `plan_critique_done=false` ise audit'e `plan-critique-skipped-warn | tool=ExitPlanMode plan_critique_done=false` yazılır. Pre-tool blokladıysa state değişmemiş olur — defense-in-depth.

### Test
- ExitPlanMode + plan_critique_done=false → `decision:block` + audit PASS
- Task(general-purpose, sonnet) → state=true → ExitPlanMode passes PASS
- Plan exists + state=false → `PLAN_CRITIQUE_PENDING_NOTICE` injected PASS
- Plan exists + state=true (same session) → notice yok PASS
- Write to .claude/plans/foo.md (Phase 4) → state false'a resetlenir + audit PASS
- Stop ExitPlanMode + state=false → `plan-critique-skipped-warn` audit PASS
- Stop ExitPlanMode + state=true → audit warn yok PASS
- Block decision JSON valid + activate JSON valid PASS
- Mevcut test suite (19 pass, 0 fail, 2 skip) regresyonsuz

## [8.2.9] - 2026-04-29

### Eklendi
- **Gap 2 expansion — Root cause chain enforcement all-mode scope (`mcl-activate.sh`, `mcl-stop.sh`, `all-mcl.md`):**
  - **Activate user-message trigger:** 14 dilli heuristik keyword seti (`neden`, `çalışmıyor`, `bug`, `why`, `broken`, `error`, vb. — TR/EN/ES/FR/DE/JA/KO/ZH/AR/HE/HI/ID/PT/RU) `PROMPT_NORM` içinde substring match edilir. Eşleşirse `ROOT_CAUSE_DISCIPLINE_NOTICE` enjekte edilir. Plan-mode tetikleyici varsa o kazanır (yeni blok `[ -z "$ROOT_CAUSE_DISCIPLINE_NOTICE" ]` guard'ı ile atlanır) — tek audit, tek inject. Yeni audit detail: `source=user-message`.
  - **Stop always-on scan:** `mcl-stop.sh`'a Gap 2 ExitPlanMode bloğunun yanında ikinci scan eklendi. Her turda transcript'ten son user mesajı + son assistant text+tool inputs okunur. User mesajında trigger varsa assistant 3 keyword çifti için (EN/TR) taranır; eksikse audit `root-cause-chain-skipped-warn | source=all-mode missing=<list>`. Trigger yoksa scan atlanır (no audit). 8.2.8 ExitPlanMode bloğu bit-for-bit korundu — iki blok aynı turda fire edebilir, `source=` alanıyla ayırt edilir, auto-display her ikisini de yakalar.
  - **STEP-62 güncellendi:** Phase satırı `Plan-mode (devtime) + Any turn (user-message trigger, since 8.2.9)`. Signal/Pass/Skip bölümleri yeni `source=user-message` ve `source=all-mode` audit alanlarıyla detaylandırıldı.

### Test
- TR trigger user-message (`bu neden çalışmıyor`) → notice + `source=user-message` audit PASS
- EN trigger user-message (`the login is broken`) → notice PASS
- Plan file + user trigger aynı anda → tek audit, plan-mode kazanır PASS
- Nötr prompt → notice/audit yok PASS
- Stop always-on: TR trigger + 3 check eksik → `source=all-mode missing=...` audit PASS
- Stop always-on: trigger + 3 EN check var → warn yok PASS
- Stop always-on: trigger yok → scan atlanır, warn yok PASS
- Gap 2 ExitPlanMode bloğu regression: hala `missing=...` (source field yok) yazıyor PASS
- Activate JSON valid (4 case: no notice / user-msg / plan-mode / both) PASS
- Mevcut test suite: 19 pass, 0 fail, 2 skip (regresyonsuz)

### Bilinen risk (kabul edilmiş)
- Common-word false positives (`fail`, `error`, `bug`, `issue` EN'de çok yaygın): notice non-blocking olduğundan kabul edildi.

## [8.2.8] - 2026-04-29

### Eklendi
- **Gap 2 — Root cause chain enforcement trinity (`mcl-activate.sh`, `mcl-stop.sh`, `all-mcl.md`):**
  - **Hook (`mcl-activate.sh`):** `.claude/plans/*.md` dosyalarından biri current session içinde (son `session_start` event'inden sonra) modify edildiyse `ROOT_CAUSE_DISCIPLINE_NOTICE` `additionalContext`'e enjekte edilir. Notice metni Claude'a plan turn'unda 3 check'i (visible process / removal test / falsification) görünür şekilde yazmasını söyler.
  - **Meta-control (`mcl-stop.sh`):** Son assistant turun'da `ExitPlanMode` tool_use varsa, turun text content'i + tool input'ları case-insensitive olarak üç keyword çifti için taranır (EN OR TR per pair): `removal test` / `kaldırma testi`, `falsification` / `yanlışlama`, `visible process` / `görünür süreç`. Bir çiftin ne EN ne TR formu bulunamazsa audit'e `root-cause-chain-skipped-warn | mcl-stop.sh | missing=<list>` yazılır.
  - **Auto-display (`mcl-activate.sh`):** Audit log'da current session içinde `root-cause-chain-skipped-warn` entry'si varsa `ROOT_CAUSE_CHAIN_WARN_NOTICE` enjekte edilir — Claude'a planı yeniden 3 check'le birlikte emit etmesini söyler.
  - **STEP-62:** `skills/my-claude-lang/all-mcl.md`'ye `root-cause-chain-discipline` adımı eklendi.

### Test
- Plan file mtime + activate hook → ROOT_CAUSE_DISCIPLINE_NOTICE PASS
- ExitPlanMode + keyword yok → audit warn PASS
- ExitPlanMode + EN keyword'lar → warn yok PASS
- ExitPlanMode + TR keyword'lar → warn yok (TR pattern eşleşiyor) PASS
- Activate JSON valid + WARN notice present (audit fired) PASS
- Mevcut test suite (19 pass, 0 fail, 2 skip) regresyonsuz

## [8.2.7] - 2026-04-29

### Eklendi
- **Gap 1 — Phase 5 skip detection trinity (`mcl-stop.sh`, `mcl-activate.sh`, `all-mcl.md`):**
  - **Hook (`mcl-stop.sh`):** Stop hook her turda `phase_review_state` kontrol eder. State `running` ise ve bu turda MCL prefix'li AskUserQuestion çalışmamışsa (`ASKQ_INTENT` boş — Phase 4.5/4.6 dialog'u devam etmemiş), audit'e `phase5-skipped-warn | mcl-stop.sh | phase_review_state=running` yazar. State-driven tespit (transcript taraması yok) → anormal session exit'lerinde de skip yakalanır.
  - **Meta-control (4 hook):** `mcl-stop.sh`, `mcl-activate.sh`, `mcl-pre-tool.sh`, `mcl-post-tool.sh` her başarılı çalışmada `.mcl/hook-health.json`'a kendi alanını (`stop`, `activate`, `pre_tool`, `post_tool`) epoch timestamp olarak yazar. Atomic write (tmp + rename). `mcl check-up` STEP-61 eksik veya 24 saatten eski bir alan görürse WARN — hook'un settings.json'dan düşmüş veya sessizce başarısız olduğunu yakalar.
  - **Auto-display (`mcl-activate.sh`):** `audit.log`'da current session (son `session_start` event'inden sonra) `phase5-skipped-warn` entry'si varsa `PHASE5_SKIP_NOTICE` `additionalContext`'e enjekte edilir. Pattern `REGRESSION_BLOCK_NOTICE`'a benzer — Claude bir sonraki turda Phase 5 Doğrulama Raporu'nu çalıştırmaya yönlendirilir.
  - **STEP-60 + STEP-61:** `skills/my-claude-lang/all-mcl.md`'ye iki yeni adım: `phase5-skip-detection` (Stop fazında) ve `hook-health-check` (mcl check-up fazında).

### Test
- `phase_review_state="running"` set + `mcl-stop.sh` → audit `phase5-skipped-warn` PASS
- `phase_review_state=null` set + `mcl-stop.sh` → audit warn yok PASS
- `hook-health.json` sil + 4 hook çalıştır → tüm 4 alan yazılı PASS
- `mcl-activate.sh` JSON çıktısı geçerli (clean + audit warn aktif) PASS
- Mevcut test suite (19 pass, 0 fail, 2 skip) regresyonsuz

## [8.2.6] - 2026-04-28

### Değişti
- **`mcl_get_active_phase()` migration — 4 çift-okuma noktası:**
  - `mcl-stop.sh:374-376`: Phase Review Guard'daki `current_phase` + `spec_approved` çift okuması kaldırıldı, `mcl_get_active_phase()` ile değiştirildi
  - `mcl-stop.sh:474`: Pattern scan early clearance'daki `current_phase` okuması kaldırıldı
  - `mcl-stop.sh:802`: Pattern scan late fallback'deki `current_phase` okuması kaldırıldı
  - `mcl-activate.sh:353-354`: Respec Guard'daki `spec_approved + current_phase >= 4` Python inline okuması kaldırıldı
  - Tüm noktalar `grep -qE '^(4|4a|4b|4c|4\.5|3\.5)$'` koşuluyla helper sonucunu kullanıyor
  - Mevcut state field'lar dokunulmadı (extension over modification)

## [8.2.5] - 2026-04-28

### Değişti
- **Devtime Plan Critique — 10 lens + model seçimi:** Lens listesi 5'ten 10'a genişledi: halüsinasyon kontrolü, mevcut özelliklerle çakışma, extension over modification, kullanıcı görünürlüğü, test edilebilirlik eklendi. Subagent modeli `claude-sonnet-4-6` extended thinking olarak explicit belirtildi — ana oturum (Opus 4.7) ile farklı model, gerçek ikinci göz bias çeşitliliği; critique reasoning için ideal, ~5x daha ucuz.

## [8.2.4] - 2026-04-28

### Eklendi
- **Devtime Plan Critique (CLAUDE.md):** MCL geliştirme oturumlarında plan üretildiğinde otomatik olarak `superpowers:code-reviewer` subagent açılır ve planı 5 lens ile eleştirir: (1) kök sebep derinliği, (2) yan etki tahmini, (3) boş/eksik durumlar, (4) disambiguation eksiği, (5) plan belirsizliği. Critique plan'la birlikte sunulur; Ümit kabul/red eder. Sadece devtime — runtime'da tetiklenmez.

## [8.2.3] - 2026-04-28

### Eklendi
- **`mcl_get_active_phase()` helper (`mcl-state.sh`):** `current_phase` + `spec_approved` + `phase_review_state` + `ui_sub_phase` + `pattern_scan_due` + `spec_hash` okuyarak tek bir effective phase string döndürür: `"1"`, `"2"`, `"3"`, `"3.5"`, `"4"`, `"4a"`, `"4b"`, `"4c"`, `"4.5"`, `"4"` (pending), `"?"`. Extension over modification — mevcut state field'lar dokunulmaz. Hook'lardaki çift-okuma noktaları bu helper'ı kullanabilir.
  - Phase 3 phantom: `current_phase=2` + `spec_hash` set → `"3"` olarak türetilir, yeni state field gerektirmez.
  - `pending → running` geçişi: AskUQ-bağımlı tasarım doğru — Phase 4.5 her zaman AskUserQuestion ile başlıyor, `pending`'de kalma yanlış dala düşürme riski yok.
  - 4.5 vs 4.6 ayrımı: her ikisi de `phase_review_state="running"` — state'ten ayırt edilemiyor, transcript analizi gerekiyor (helper `"4.5"` döndürüyor, callers notlandırıldı).

## [8.2.2] - 2026-04-28

### Eklendi
- **`docs/root-cause-discipline.en.md`:** Root Cause Discipline tam İngilizce çevirisi (9 bölüm). MCL iç dili İngilizce olduğu için operasyonel referans bu dosya; Türkçe versiyon insan referansı olarak kalıyor.

### Değişti
- **CLAUDE.md:** Root Cause Discipline referansı `.en.md`'ye güncellendi.
- **`mcl-rollback.md`:** Hardcoded Türkçe çıktı kaldırıldı. Satır 12 (checkpoint yok mesajı) ve satır 19-29 (rollback template) artık developer'ın algılanan diline göre üretiliyor. Teknik tokenlar (git komutları, SHA) İngilizce kalıyor.

## [8.2.1] - 2026-04-28

### Değişti
- **Phase 3.5 kademeli arama (boş pattern_summary fix):** `mcl-pattern-scan.py` tek seviyeden 4 seviyeli cascade'e dönüştürüldü.
  - **Level 1 (mevcut):** scope_paths sibling dosyaları
  - **Level 2 (yeni):** sibling yoksa proje genelinde aynı uzantılı dosyalar, en son değiştirilen 8 tane
  - **Level 3 (yeni):** proje dosyası yoksa ekosistem standardı (TypeScript strict, Python PEP 8, Go idiomatic, vb.) — `mcl-activate.sh` build-in knowledge'dan PATTERN SUMMARY yazar
  - **Level 4 (yeni):** ekosistem tespit edilemezse kullanıcıya tek soru
- `mcl-stop.sh`: exit code 3 → Level 3/4 dallanması; `pattern_level` ve `pattern_ask_pending` state'e yazılır
- `mcl-activate.sh`: PATTERN_MATCHING_NOTICE level'a göre farklılaştı — Level 1/2 dosya listesi, Level 3 ekosistem direktifi, Level 4 kullanıcıya sor
- `mcl-state.sh`: `pattern_level` ve `pattern_ask_pending` schema'ya eklendi

## [8.2.0] - 2026-04-28

### Eklendi
- **`docs/root-cause-discipline.md`:** Root Cause Discipline tam spesifikasyonu. 9 bölüm: temel düstur, zincir ilerleyişi, halka başına 3 check (görünür süreç → removal test → falsification; sıralı, paralel değil), halka geçişi sonucu, edge case, müdahale noktası seçimi (sıfır yan etki halkası), kök sebep + çözüm raporu, kapsam, özet.

### Değişti
- **CLAUDE.md — Root Cause Discipline:** Hem devtime hem runtime kuralları `docs/root-cause-discipline.md` referansıyla güncellendi. 3 check sıralı, sıfır yan etki halkası, kök sebep + çözüm + doğrulama, tıkanırsa şeffaflık kuralları eklendi.
- **`mcl-activate.sh` Root Cause Chain direktifi:** 3 check (görünür süreç, removal test, falsification), müdahale noktası (sıfır yan etki halkası), risk item formatı (kök sebep + önerilen çözüm + çözüm doğrulama), zincir tıkanınca şeffaflık kuralları eklendi.

## [8.1.9] - 2026-04-28

### Eklendi
- **Root Cause Discipline (CLAUDE.md):** İki yeni kural `## Root Cause Discipline` başlığı altında.
  - *Devtime:* "Bu neden böyle?" sorusunu tekrarla — cevap geldiğinde tekrar sor. En alttaki sebebi bul. Bazen tek sebep tüm ağı çözer.
  - *Runtime (Root Cause Chain):* Phase 4.5 Root Cause Lens tek seviyeden çok seviyeli zincire dönüştürüldü. Bir sebep bulununca durmaz; "bu sebebin de kök sebebi var mı?" diye tekrar sorgular. En yapısal sebebi risk item olarak raporlar. Anti-sycophancy gibi temel: atlanması yasak.
- **`mcl-activate.sh` Root Cause Chain direktifi:** `pattern-compliance` bloğundaki "Root Cause Lens" metni "Root Cause Chain" olarak güncellendi. Çok seviyeli iniş, en derin yapısal sebep hedefi ve "Phase 4.5 tamamlanmış sayılmaz" zorunluluğu eklendi.

## [8.1.8] - 2026-04-28

### Eklendi
- **Phase 1.5 Failure Path:** Brief, Phase 1 onaylı parametrelerle çelişirse sessiz fallback yasak. Her denemede yaklaşım değiştirilerek retry; eksik bilgi kaynaksa geliştiriciye tek soru sorulur. Tutarlılık kriterleri belgelendi. Audit kaydına `retries` ve `clarification` alanları eklendi.
- **Phase 4.6 "apply fix" semantiği:** "Apply fix" seçeneğinin Phase 4.6 içinde in-place patch anlamına geldiği, Phase 4'e geri dönüş olmadığı belgelendi. Çok büyük fix için next-session yönlendirmesi eklendi.
- **CLAUDE.md — runtime kural:** Bozulma tespit edildiğinde sessiz fallback yasak; yaklaşım değiştirerek retry, eksik bilgiyse tek soru.
- **CLAUDE.md — devtime kural:** MCL geliştirirken tur başına tek soru — "tek adım per tur" kuralının soru dizileri için daha katı versiyonu.

## [8.1.7] - 2026-04-28

### Eklendi
- **Phase 1.5 — Engineering Brief:** `skills/my-claude-lang/phase1-5-engineering-brief.md` oluşturuldu. Phase 1 onayı sonrası, Phase 2 öncesinde dahili İngilizce Engineering Brief üretilir. Geliştirici görmez; Phase 2 spec'in üzerine inşa ettiği anlam köprüsüdür. Kaynak dil İngilizce ise sessizce atlanır. Her iki durumda da `engineering-brief` audit kaydı düşer.
- **Phase 5.5 — Localize Report:** `skills/my-claude-lang/phase5-5-localize-report.md` oluşturuldu. Phase 5 Doğrulama Raporu üretildikten sonra, emisyon öncesinde tüm geliştirici-facing metin (bölüm başlıkları, hüküm kelimeleri, prose) geliştiricinin diline çevrilir. Teknik token'lar İngilizce kalır. Kaynak dil İngilizce ise atlanır. `localize-report` audit kaydı her durumda düşer.
- **STEP-58 ve STEP-59:** `all-mcl.md`'e eklendi — her iki yeni fazın checkup adımı tanımlandı.
- **`skills/my-claude-lang.md`:** Phase 1.5 ve Phase 5.5 pointer satırları eklendi; Phase 1 açıklaması Phase 1.5'e yönlendirildi.

### Değişti
- **CLAUDE.md — test dili:** "14 dilde test et" kuralı "Türkçe'de test et" olarak güncellendi. Dil *desteği* 14 dili kapsar; dil *testi* yalnızca Türkçe kullanır.
- **CLAUDE.md — behavioral → dedicated kuralı:** Behavioral olarak çalışan her MCL özelliğinin dedicated faz/skill/hook olması gerektiği, mümkün değilse atlama tespit eden kontrol eklenmesi gerektiği prensip olarak eklendi.

## [8.1.6] - 2026-04-28

### Düzeltme
- **Regression Guard akıllı atlama — staleness kontrolü:** 8.1.5'te `age < 120s` yeterliydi ama green-verify sonrası aynı turda Write/Edit/MultiEdit/NotebookEdit çağrıldıysa state eskimiş sayılır. `mcl-post-tool.sh` Write grubu araçlarda `last_write_ts` (unix epoch) state'e yazar. Skip koşulu artık ikili: `tdd_last_green.ts > last_write_ts` VE `age < 120s`. İkisi birlikte sağlanırsa atlama yapar, biri bozulursa tam suite koşar.

## [8.1.5] - 2026-04-28

### Eklendi
- **Regression Guard akıllı atlama:** TDD'nin son `green-verify` sonucu `state.tdd_last_green`'e (`ts` + `result`) yazılır. Regression Guard tetiklenirken bu değeri okur: `green-verify` GREEN ve 120 saniyeden taze ise suite tekrar koşulmaz (`regression-guard-skipped` audit kaydıyla). 120 saniyeden eski veya hiç çalışmamışsa tam suite koşulur.
- **self-critique.md:** Pressure resistance / Human Authority ayrımına tek satır örnek eklendi — "X yapma" → Human Authority (karar kapanır), "X yanlış" kanıtsız → Pressure resistance (pozisyon korunur).

## [8.1.4] - 2026-04-27

### Eklendi
- **İnsan Yetkisi — Karar Kapanışı:** `self-critique.md`'e "Human Authority — Decision Closure" bölümü eklendi. Geliştirici bir kararı açıkça verdikten sonra (ret, seçim, riski kabul, tekrarlanan seçim) MCL o kararı tekrar açmaz; işlevsel eşdeğer önermez, aynı itirazı yeniden çerçevelemez. İstisna: daha önce bilinmeyen yeni kritik bilgi — bir kez, etiketlenerek sunulur.
- `phase1-rules.md`'e çapraz referans eklendi: explicit decision → human authority rule → see self-critique.md.
- Anti-sycophancy ile tamamlayıcı ilişki belgelendi: pressure resistance (kanıtsız baskıya direnç) ≠ human authority (verilen kararın kapanması).

## [8.1.3] - 2026-04-27

### Eklendi
- **Root Cause Prensibi (Boris Cherny):** Phase 4 Scope Discipline'e Rule 3 eklendi: "Fix the cause, not the symptom. If a patch only makes the test pass without addressing why it failed, surface it as a Phase 4.5 risk item."
- **Phase 4.5 Root Cause Lens:** `pattern-compliance` mcl_audit bloğuna Root Cause Lens direktifi eklendi. Band-aid kalıpları listelenir: hataları catch/swallow etmek, type constraint genişletmek, test girdilerini özel-case'lemek, failure mode düzeltilmeden retry. Her biri risk item olarak raporlanır.
- Mekanizma: flag sistemi yok — lens Phase 4.5'te bağımsız tarar.

## [8.1.2] - 2026-04-27

### Eklendi
- **Kapsam Disiplini:** Phase 4'te her turda `SCOPE_DISCIPLINE_NOTICE` enjekte edilir. İki kural:
  - **Rule 1 — SPEC-ONLY:** Spec'in MUST/SHOULD'larında olmayan hiçbir şey yapılmaz. Yasak: spec'te olmayan performans iyileştirmesi, "fırsattan istifade" refactor, style fix, fazladan test, "ileride lazım olur" API eklentisi. Fark edilirse Phase 4.5/4.6 itemi olarak kaydedilir, düzeltilmez.
  - **Rule 2 — FILE SCOPE:** Yalnızca spec'in Technical Approach'unda geçen dosyalar değiştirilir. `scope_paths` doluysa pre-tool hook zaten bloke eder; boşsa bu behavioral notice kapsar.
- Scope Guard block mesajı güncellendi: Rule 1 ve Rule 2 referanslarıyla ihlal bağlamı netleştirildi.

## [8.1.1] - 2026-04-27

### Değişti
- **Phase 3.5 derinleşti:** Özet artık zorunlu 3 başlık formatında — `**Naming Convention:**`, `**Error Handling Pattern:**`, `**Test Pattern:**`. "Enforced" ibaresi ile kurallar Phase 4 boyunca `PATTERN_RULES_NOTICE` olarak her turda context'te tutulur.
- **stop hook:** `PATTERN_SUMMARY` early exit'ten önce parse edilir (`mcl-stop.sh`'de yeni erken clearance bloğu). Phase 3.5 turu spec/AskUQ içermediği için eski geç clearance hiç çalışmıyordu.
- **Phase 4.5 compliance:** `phase_review_state=running`'da `PATTERN_RULES_NOTICE`'e compliance check direktifi eklenir — hangi dosya, hangi kural, ne bulundu vs beklenen.
- `state.pattern_summary` şemaya eklendi; session sınırında sıfırlanır.

## [8.1.0] - 2026-04-27

### Değişti
- `ROLLBACK_NOTICE` artık her Phase 4 turunda değil, yalnızca ilk turda gösteriliyor (`rollback_notice_shown` flag). 5-10 turluk görevlerde aynı SHA tekrar etmez.
- `/mcl-rollback` komutu eklendi: flag'ı sıfırlar, bir sonraki turda notice yeniden görünür; full SHA + reset komutu + atomic commit önerisi gösterir.
- `state.rollback_notice_shown` şemaya eklendi; session sınırında sıfırlanır.

## [8.0.9] - 2026-04-27

### Eklendi
- **Rollback checkpoint:** Spec onayı anında `git rev-parse HEAD` çalıştırılır, SHA `state.rollback_sha`'ya kaydedilir. Phase 4 boyunca her turda `ROLLBACK_NOTICE` context'e enjekte edilir — tam SHA ve `git reset --hard <sha>` komutuyla. Git repo yoksa sessizce geçilir.
- **Atomic commit hint:** Phase 4.5/4.6/5 çalışırken (`phase_review_state=running`) `ATOMIC_COMMIT_NOTICE` enjekte edilir: `git add <scope_paths>` + `git commit -m "feat: <spec objective>"` komutu hazır olarak sunulur. Auto-commit yok — Claude komutu çalıştırır, developer onaylar.
- **state.rollback_sha:** Şemaya eklendi (default null); session sınırında temizlenir.

## [8.0.8] - 2026-04-27

### Eklendi
- **Güvenlik refleksleri — `mcl-secret-scan.py`:** Tüm fazlarda Write/Edit/MultiEdit/NotebookEdit çağrıları credential ve secret taramasından geçer.
  - **Tier 1 (hassas dosya yolu):** `.env`, `*.pem`, `*.key`, `credentials.json`, `service-account.json` vb. gerçek değer içeriyorsa block. `.env.example` ve `*.template` muaf.
  - **Tier 2 (bilinen secret pattern):** `sk-...` (OpenAI/Anthropic), `ghp_...` (GitHub), `AKIA...` (AWS), `AIza...` (Google), `xoxb-...` (Slack), PEM header, JWT vb.
  - **Tier 3 (high-entropy assignment):** `SECRET/PASSWORD/API_KEY = <entropy≥3.5, len≥20>` — `os.environ` referansları ve placeholder değerler muaf.
- Tarama faz kapısından önce çalışır — Phase 1-3'te bile credential yazımı bloke edilir.

## [8.0.7] - 2026-04-27

### Eklendi
- **Phase 3.5 — Pattern Matching:** Spec onayı → Phase 4 geçişinde, `scope_paths`'e göre mevcut sibling dosyaları `mcl-pattern-scan.py` ile tespit eder. İlk Phase 4 turunda Write/Edit bloke edilir; `PATTERN_MATCHING_NOTICE` Claude'a hangi dosyaları okuyacağını ve ne çıkaracağını (import stili, naming convention, error handling, test yapısı) söyler. Tur tamamlanınca blok otomatik kalkar.
- **mcl-pattern-scan.py:** scope_paths'ten sibling dosya referansları bulur; dizin başına max 3, toplam max 10 dosya; glob-aware.
- **state alanları:** `pattern_scan_due` (bool), `pattern_files` (list) — session sınırında sıfırlanır.

## [8.0.6] - 2026-04-27

### Eklendi
- **Scope Guard (mcl-pre-tool.sh):** Phase 4'te Write/Edit/MultiEdit/NotebookEdit çağrıları onaylanmış spec'te bildirilen dosya yollarıyla kısıtlanır. `scope_paths` boşsa kısıtlama yoktur (spec açık yol listesi içermiyorsa dormant).
- **mcl-spec-paths.py:** Spec metninden dosya yolu token'larını çıkarır. Backtick, bold ve düz metin yollarını destekler; `src/auth/*.ts`, `tests/**/*.test.ts` gibi glob pattern'leri tanır.
- **scope_paths state alanı:** Spec onayında `mcl-stop.sh` yolları çıkarıp `state.scope_paths`'e yazar; session sınırında `mcl-activate.sh` sıfırlar.

## [8.0.5] - 2026-04-27

### Düzeltme
- `mcl-stop.sh`: `_MCL_HOOK_DIR` sabitlendi — `mcl-test-runner.sh` kaynaklanınca `SCRIPT_DIR`'i `lib/` dizinine çekiyordu, tüm `$SCRIPT_DIR/lib/` referansları bozuluyordu. `_MCL_HOOK_DIR` ile sabitledi; `mcl-phase-review-guard.py`, `mcl-partial-spec.sh`, `mcl-spec-save.sh` vb. doğru konumdan çalışıyor.
- `mcl-state.sh` allowlist: `mcl-post-tool.sh` yetkili yazıcılar listesine eklendi. Eksikliği Regression Guard clearance'ını susturuyordu — "✅ Tests: GREEN" sonrası `regression_block_active` temizlenemiyor, blok kalıcı hale geliyordu.

## [8.0.4] - 2026-04-26

### Eklendi
- **Regression Guard:** Phase 4 kodu yazıldıktan sonra, Phase 4.5 başlamadan önce tam test suite çalıştırılır. Suite kırmızıysa (`regression_block_active=true`) Phase 4.5 bloke edilir; `mcl-activate.sh` `REGRESSION_BLOCK_NOTICE` enjekte eder. Geliştirici hatayı düzeltip "✅ Tests: GREEN" çıktısı aldığında `mcl-post-tool.sh` bloğu otomatik temizler.

### Düzeltme
- `mcl-pre-tool.sh` state.json koruma regex'i: eski geniş regex (komut içinde `state.json` VE herhangi bir `>>` yeterliydi) false-positive'lere yol açıyordu. Yeni regex `>>?` yakalamalarının doğrudan hedefini kontrol eder; Python betikleri veya yorum satırları artık tetiklemez.

## [8.0.3] - 2026-04-27

## [8.0.2] - 2026-04-27

### Düzeltme
- `Skill`, `TodoWrite` ve `Task` blokları `mcl-pre-tool.sh`'deki fast-path'ten önce taşındı. Önceki konumlarında fast-path onları `exit 0` ile geçiriyordu; bloklar hiç çalışmıyordu.
- Her bloğun sonuna non-matching case için `exit 0` eklendi — `feature-dev:code-explorer` gibi meşru Task çağrıları ve `superpowers:code-reviewer` gibi izinli Skill çağrıları artık doğru şekilde geçiyor.

---

## [8.0.1] - 2026-04-27

### Eklendi
- **TodoWrite blok (Phase 1-3):** `mcl-pre-tool.sh` Phase 1-3'te `TodoWrite` çağrılarını `decision:block` ile engelliyor. Phase 4+ serbest.
- **Task dispatch blok (Phase 4.5/4.6/5):** Phase 4.5 (Risk Review), Phase 4.6 (Impact Review), Phase 5 (Verification Report) sub-agent'a devredilmeye çalışılırsa bloke ediliyor. Bu fazlar yalnızca ana MCL oturumunda çalışabilir.

### Değişti
- `superpowers-scope` behavioral kısıtı STATIC_CONTEXT'ten kaldırıldı — hook referans notuna indirgendi.

---

## [8.0.0] - 2026-04-27

### Düzeltme
- `superpowers:brainstorming` artık `mcl-pre-tool.sh` hook'unda `decision:block` ile engelleniyor. 7.9.9'daki behavioral kural (`superpowers:using-superpowers`'ın "ABSOLUTELY MUST" talimatı tarafından override ediliyordu) yetersiz kaldığından hook-level blok eklendi.

---

## [7.9.9] - 2026-04-27

### Düzeltme
- STATIC_CONTEXT'e `superpowers-scope` kısıtı eklendi: `superpowers:brainstorming` yasak, MCL faz takibi için `TodoWrite` yasak, visual companion teklifi yasak. (Sonradan 8.0.0'da hook-level blok ile güçlendirildi.)

---

## [7.9.8] - 2026-04-27

### Düzeltme
- **Çoklu spec sorunu:** Kullanıcı AskUserQuestion butonuna basmak yerine chat input'a "onaylıyorum" yazdığında stop hook onayı algılayamıyor ve phase=2'de kalıyordu. `mcl-stop.sh`'e plain-text approval fallback eklendi.
- **"Devam etmek için bir mesaj gönderin" yasağı:** `spec-approval-discipline` kısıtıyla bu cümle ve tüm dil eşdeğerleri yasaklandı.
- Session başına 1 spec kuralı, hook dosyası debug yasağı, self-narration yasağı eklendi.

---

## [7.9.7] - 2026-04-26

### Eklendi
- **Kod tasarım ilkeleri** STATIC_CONTEXT'e eklendi: Composition over inheritance, SOLID, extension over modification, design pattern sadece gerçek problem için. `~/.claude/CLAUDE.md`'ye de global kural olarak yazıldı.

---

## [7.9.6] - 2026-04-26

### Düzeltme
- `vite.config.*`, `next.config.*`, `nuxt.config.*` Phase 4a'da engellenen backend path listesinden çıkarıldı. Bu dosyalar olmadan `npm run dev` çalışmıyor, kullanıcı UI'ı göremeden onay isteniyordu.
- `phase4a-ui-build.md` prosedürüne "build config dosyalarını önce yaz" adımı eklendi.

---

## [7.9.5] - 2026-04-26

### Eklendi
- **Plugin Dispatch Audit:** Phase 4.5 çalışırken `mcl-activate.sh` her turda `trace.log`'u kontrol ediyor. `code-review` sub-agent ve `semgrep` çalışmadıysa `PLUGIN_MISS_NOTICE` enjekte ediliyor ve Phase 4.6/5'e geçiş engelleniyor.
- `hooks/lib/mcl-dispatch-audit.sh` yeni dosya — manifest + audit fonksiyonu.
- `mcl-semgrep.sh`'e başarılı scan sonrası `semgrep_ran` trace eventi eklendi.

---

## [7.9.4] - 2026-04-26

### Değişti
- `(mcl-oz)` inline tag yeniden adlandırıldı: `/mcl-self-q`. Kullanımda fark yok — mesaj içinde yazılınca o yanıt için self-critique görünür hale gelir.
