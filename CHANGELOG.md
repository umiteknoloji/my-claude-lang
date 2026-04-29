# Değişiklik Günlüğü

[Keep a Changelog](https://keepachangelog.com) formatı. Her yeni sürümde
`[Unreleased]` bölümü `[X.Y.Z] - YYYY-MM-DD`'ye dönüştürülür.

---

## [Unreleased]

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
