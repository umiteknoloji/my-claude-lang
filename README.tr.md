# my-claude-lang (MCL)

[![Lisans](https://img.shields.io/badge/lisans-MIT-green.svg)](LICENSE)

MCL, Claude Code'a iki kanat ekleyen bir plugin: bir **dil köprüsü** — geliştirici kendi dilinde düşünür, Claude senior seviye İngilizce mühendislik çıktısı üretir; ve bir **AI disiplini** katmanı — her değişikliği deterministik bir faz pipeline'ından (Phase 1 → 1.5 → 1.7 → 2 → 3 → 3.5 → 4 → 4.5 → 5 → 6) geçirir, güvenlik / DB tasarımı / UI erişilebilirliği / operasyonel hijyen için hook-enforced gate'ler uygular. Her şey projenin **dışında** çalışır — 8.5.0'dan itibaren projene sıfır dosya yazılır.

---

## Hızlı kurulum

```bash
git clone https://github.com/YZ-LLM/my-claude-lang.git
bash my-claude-lang/install.sh
```

Bu kurar:
- **Kütüphane:** `~/.mcl/lib/` (klonlanan repo — tek kaynak)
- **Wrapper launcher:** `~/.local/bin/mcl-claude` (symlink)
- **Proje-bazlı state kökü:** `~/.mcl/projects/<sha1(realpath)>/` (ilk çalıştırmada otomatik yaratılır)

Sonra herhangi bir projede `claude` yerine `mcl-claude` çalıştır:

```bash
cd ~/projects/my-app
mcl-claude
```

Wrapper, `$PWD`'nin realpath'inden stable bir project key türetir, ilk çalıştırmada `~/.mcl/projects/<key>/` scaffolding'ini oluşturur, hook'lar için `MCL_STATE_DIR` env'ini export eder, sonra izole `--settings` + `--plugin-dir` ile `claude`'u `exec` eder. **Tüm Claude Code bayrakları transparan geçer.** Projen hiçbir şey almaz — `.mcl/`, `.claude/`, settings dosyası yok.

**Güncelleme:**
```bash
cd ~/.mcl/lib && git pull --ff-only && bash install.sh
```
Veya bir oturumun içinde `/mcl-update` yaz.

---

## Özellik kataloğu

### Dil köprüsü
İlk mesajdan geliştiricinin dilini tespit eder; her clarifying question, risk dialog, doğrulama raporu, section başlığı o dilde kalır. İç mühendislik çıktısı (spec, kod, teknik token) İngilizce. 14 dil desteği (TR / EN / AR / DE / ES / FR / HE / HI / ID / JA / KO / PT / RU / ZH); araç çıktıları için TR + EN tam lokalize, diğerleri scan rapor metinlerinde İngilizce fallback.

### Per-project izolasyon
MCL projene **sıfır dosya yazar**. State, hook, skill, agent, audit log, scan cache, dev-server log — her şey `~/.mcl/projects/<key>/` altında. Project key'ler `realpath($PWD)` SHA1; rename'de state kaybolur (kasıtlı, migration yok). Birden çok projede paralel çalışırken state çakışması olmaz.

### Codebase scan — `/codebase-scan`
Projeyi tek seferde 12 pattern extractor'la tarar (P1–P12: stack tespiti, mimari işaretler, naming convention, error handling stili, test pattern, API stili, state management, DB layer, logging, lint sıkılığı, build/deploy, README intent). Yüksek güvenlikli bulgular `project.md`'ye `<!-- mcl-auto -->` marker'ları arasına yazılır (Phase 5 bölümleri korunur); orta/düşük güven `project-scan-report.md`'ye.

### Backend güvenlik — 3-katmanlı — `/mcl-security-report`
13 generic core kural + 7 stack add-on (Django ALLOWED_HOSTS, FastAPI CORS, React unsafe HTML setter, Spring CSRF disabled, Rails strong params, Laravel debug, …) + Semgrep `p/default` entegrasyonu + SCA tool dispatch (npm/pip/cargo/go/bundle audit). OWASP Top 10 + ASVS L1 alt kümesi. Severity-tiered: HIGH=`decision:deny` block, MEDIUM=Phase 4.5 sequential dialog, LOW=audit log.
- **L1 Phase 1.7** — 5 design-time dimension (auth model, authz unit, CSRF stance, secret management, deserialization input)
- **L2 Phase 4 per-Edit** — Edit/Write/MultiEdit'te incremental scan; HIGH ise `decision:deny`
- **L3 Phase 4.5 START gate** — full scan; HIGH varsa state `pending`'de kalır, fix edilene kadar Phase 4.5 dialog başlamaz

### DB tasarım disiplini — `/mcl-db-report`, `/mcl-db-explain`
10 generic core kural (eksik PK, SELECT *, eksik FK index, WHERE'siz UPDATE/DELETE, validation'sız JSONB, timezone'suz TIMESTAMP, text-id-not-UUID, enum-as-text, kullanıcı verisinde cascade-delete, statik N+1) + 8 ORM add-on × 3 anchor (Prisma, SQLAlchemy, Django ORM, ActiveRecord, Sequelize, TypeORM, GORM, Eloquent) = 34 kural. External delegate'ler: `squawk` (Postgres migration linter) + `alembic check`. Opsiyonel `MCL_DB_URL` env, `/mcl-db-explain` ile canlı `EXPLAIN` plan analizi sunar (default `ANALYZE` yok — production güvenliği).

### UI enforcement — `/mcl-ui-report`, `/mcl-ui-axe`
10 generic core HTML/a11y kuralı (img-no-alt, button-no-name, link-no-href, input-no-label, div-onClick-no-keyboard, heading-skip, hardcoded color/spacing/font-size, magic breakpoint) + 12 framework add-on React / Vue / Svelte / HTML-static = 22 kural. **Severity UI iteration tempo'suna göre tunelendi:** sadece a11y-critical bulgular (9 kural — örn. img-no-alt, controlled-input-without-onChange, html-no-lang) HIGH `decision:deny` tetikler; design tokens / reuse / responsive / naming = MEDIUM dialog; advisory = LOW audit. Design tokens C3 hibrit detect: project'in `tailwind.config` / CSS vars / `theme.ts` / `design-tokens.json`'u; yoksa MCL default 8px grid + Tailwind-ish scale fallback. Opsiyonel `MCL_UI_URL` env ile `/mcl-ui-axe` Playwright üzerinden runtime `axe-core` taramasını etkinleştirir.

### Pause-on-error — `/mcl-resume`
Scan helper crash, validator malformed JSON, audit log write fail, hook script crash veya external delegate non-graceful failure durumlarında MCL **explicit pause** yapar — silent fail-open yerine: state.paused_on_error.active=true, sonraki her tool `decision:deny` döner, error context + suggested fix + last-known phase'le. `/mcl-resume <çözümün>` (free-form doğal dil argüman) ya da skill-driven doğal dil ack ile resume edilir. Session boundary'ları arasında sticky — paused state Claude Code restart'ından sağ çıkar. Dev server build hataları aynı kanaldan beslenir.

### Phase 6 Double-check — `/mcl-phase6-report`
Phase 5 verification sonrası, üç ortogonal check session kapanmadan önce çalışır:
- **(a) Audit trail tamlığı** — gerekli STEP audit event'leri emit edildi mi? (Sessizce atlanan fazları yakalar.)
- **(b) Final scan kümülasyonu** — security + DB + UI taramaları tekrar koşar; Phase 4.5 START baseline'ından sonra yeni HIGH bulgu = regression block.
- **(c) Söz-vs-teslimat** — Phase 1 confirmed parametreleri (intent + constraints) modified source dosyalarda keyword olarak match edilir (ters Lens-e izlenebilirliği).

Skip imkânsız: state field `phase6_double_check_done` `decision:block` ile enforce edilir.

### Interactive design loop — `/mcl-design-approve`, `/mcl-dev-server-start`, `/mcl-dev-server-stop`
Phase 4a UI build sonrası MCL arka planda dev server başlatır (10 stack detect: vite, next, cra, vue-cli, sveltekit, rails, django, flask, expo, static), port atar (default + 4 fallback), PID'yi `$MCL_STATE_DIR/dev-server.pid`'de takip eder, URL'yi state üzerinden surface eder. `dev-server.log`'tan tespit edilen build hataları (stack-spesifik regex haritası) pause-on-error tetikler. Headless ortamlar (`MCL_HEADLESS`, `CI`, Linux SSH no-DISPLAY) auto-start atlar, manuel talimat verir. Loop `/mcl-design-approve` ile kapanır (`ui_reviewed=true` set, Phase 4c BACKEND'e geçer).

### Operasyonel disiplin — `/mcl-ops-report`
4 rule pack × 20 kural — deployment / monitoring / test coverage / documentation:
- **Deployment** (8): no-CI, workflow YAML hatası, Dockerfile root user, `:latest` tag, `HEALTHCHECK` yok, `.env.example` eksik, env drift, secret docs yok
- **Monitoring** (4): structured logger yok (winston/pino/loguru/structlog), `/metrics` endpoint yok, error tracker yok (Sentry/Bugsnag/Rollbar), level'sız logger
- **Testing** (3): coverage threshold altı (configurable: HIGH < %50, MEDIUM < %70), test framework yok, değiştirilmiş dosya test'siz
- **Docs** (5): README yok, install bölümü yok, usage bölümü yok, OpenAPI/Swagger'sız API surface, düşük fonksiyon-level docstring coverage

Coverage delegate'i vitest / jest / pytest / go-test / cargo-tarpaulin (binary yoksa graceful skip). Konfigürasyon `$MCL_STATE_DIR/ops-config.json` üzerinden.

### Performans bütçesi — `/mcl-perf-report`, `/mcl-perf-lighthouse`
3 rule pack × 11 kural — **bundle / Core Web Vitals / image** — FE-only trigger:
- **Bundle** (4): over-budget critical (>2× HIGH), over-budget (100-200% MEDIUM), build çıktısı yok (LOW advisory), large chunk (LOW). `dist/`, `build/`, `.next/static/chunks/`, `out/` taranır; gzipped JS toplamı. Build **invoke edilmez** — `npm run build` çalıştırılmış varsayılır.
- **Core Web Vitals** (4): LCP poor (>4s HIGH), LCP needs improvement (2.5-4s MEDIUM), CLS poor (>0.25 MEDIUM), TBT poor (>600ms MEDIUM). Lighthouse delegate (`npx lighthouse --output=json --only-categories=performance`); yalnızca `/mcl-perf-lighthouse` veya `/mcl-perf-report` ile tetiklenir (L3 stop-hook gate'inde çalışmaz — 60s overhead).
- **Image** (3): image huge (>500KB HIGH), image large (100-500KB MEDIUM), WebP/AVIF fallback'siz PNG (LOW). `public/`, `static/`, `assets/`, `src/assets/`, `app/static/` taranır.

`/mcl-perf-lighthouse` `/mcl-ui-axe` ile aynı **`MCL_UI_URL`** env var'ını kullanır — kullanıcı tek URL set eder, iki runtime tool da çalışır. Audit log'ta `tool=axe|lighthouse` ayrımı. Konfigürasyon `$MCL_STATE_DIR/perf-config.json` üzerinden.

---

## Keyword referansı

Tüm keyword'ler normal MCL pipeline'ını atlar ve özel bir mod çalıştırır. Keyword'ü tüm prompt olarak yaz.

| Keyword | Amaç |
|---|---|
| `/mcl-doctor` | Token & maliyet raporu (per-turn injection overhead, oturum toplamları) |
| `/mcl-update` | MCL repo'yu `git pull` + yeniden kur (`bash install.sh`) |
| `/mcl-restart` | Aynı oturumda MCL state'i Phase 1'e sıfırla (proje korunur) |
| `/codebase-scan` | 12-pattern codebase taraması, `project.md` + `project-scan-report.md` yaz |
| `/mcl-security-report` | Tam backend güvenlik taraması (generic + stack + Semgrep + SCA), lokalize markdown |
| `/mcl-db-report` | Tam DB tasarım taraması (generic + ORM + migration delegate), lokalize markdown |
| `/mcl-db-explain` | Kayıtlı sorgu dosyalarında `EXPLAIN` çalıştır (`MCL_DB_URL` env gerekir) |
| `/mcl-ui-report` | Tam UI taraması (generic + framework + token + ESLint a11y delegate), lokalize markdown |
| `/mcl-ui-axe` | Playwright üzerinden runtime `axe-core` erişilebilirlik taraması (`MCL_UI_URL` env gerekir) |
| `/mcl-resume <çözüm>` | `paused_on_error` state'ini free-form çözüm metniyle temizle |
| `/mcl-phase6-report` | On-demand Phase 6 double-check raporu (audit trail + regression + söz-teslimat) |
| `/mcl-design-approve` | Dev server'ı durdur, Phase 4b UI_REVIEW'dan Phase 4c BACKEND'e geç |
| `/mcl-dev-server-start` | Dev server'ı manuel başlat (auto-detect stack) |
| `/mcl-dev-server-stop` | Dev server'ı manuel durdur (loop açık kalır) |
| `/mcl-ops-report` | Tam operasyonel disiplin taraması (deployment + monitoring + testing + docs) |
| `/mcl-perf-report` | Tam performans taraması (gzipped bundle + image walk + opt-in Lighthouse CWV) |
| `/mcl-perf-lighthouse` | Lighthouse üzerinden runtime Core Web Vitals taraması (`MCL_UI_URL` env gerekir, `/mcl-ui-axe` ile shared) |

---

## Faz pipeline

Her geliştirici mesajı bu sıradan akar. Bir faz, gerekli parametreleri olmadan ilerlemez.

```
Phase 1     Anlama                     intent / constraints / success / context
Phase 1.5   Engineering Brief          translator + verb yükseltme (vague → surgical İngilizce)
Phase 1.7   Precision Audit            7 core boyut + stack add-on + 5 security + 7 DB; SILENT-ASSUME / SKIP-MARK / GATE
Phase 2     Spec emission              📋 Spec block, MUST/SHOULD gereksinimleriyle
Phase 3     Doğrulama + onay           geliştirici scope-changes callout'u inceler, onaylar
Phase 3.5   Pattern matching           proje kodunu okur, convention çıkarır
Phase 4     Kod yazımı (TDD)           4a BUILD_UI dummy data → 4b UI_REVIEW (dev server) → 4c BACKEND
Phase 4.5   Risk Review                sticky-pause → security gate → db gate → ui gate → ops gate → standart reminder
Phase 4.6   Etki analizi               fix'lerin downstream etkilerini izle
Phase 5     Doğrulama raporu           spec coverage + manuel-test surface + process trace + 5.5 lokalize
Phase 6     Double-check               audit trail + final scan regression + söz-vs-teslimat
```

Tüm gate'lerde severity tier: **HIGH** = `decision:deny` / `decision:block`; **MEDIUM** = sequential dialog item; **LOW** = audit-only.

---

## Bilinen sınırlar

- **Proje rename** state kaybeder (path-SHA1 keying; setup-free için kasıtlı).
- **Headless `/mcl-ui-axe`, `/mcl-perf-lighthouse` ve `/mcl-db-explain`** explicit env var gerektirir (`MCL_UI_URL` axe + Lighthouse arasında shared; `MCL_DB_URL` DB EXPLAIN); yoksa lokalize advisory ile skip.
- **Bundle size** sadece mevcut build çıktısından ölçülür — `npm run build` otomatik invoke edilmez; `dist/`/`build/`/`.next/static/chunks/`/`out/` yoksa advisory.
- **External tool delegate'leri** (Semgrep, squawk, hadolint, eslint-plugin-jsx-a11y, `axe-core`, `playwright`, `pip-audit`, `cargo-audit`, `govulncheck`, `bundle-audit`) binary yoksa graceful skip — tam kapsam için kur.
- **14 dil destekli, ama tool raporları için sadece TR + EN tam lokalize.** Diğerleri scan çıktısı için İngilizce fallback (clarifying question + risk dialog yine geliştirici dilinde, skill prose ile).
- **N+1 detection statik-only**; runtime profiling (test runner entegrasyonu) 8.x patch'lerine ertelendi.
- **Phase 5 `phase5-verify` audit event'i** model-behavioral; eski skill dosyaları emit etmiyor. Phase 6 (a) yokluğu LOW soft fail kabul ediyor + transcript fallback (`Verification Report` / `Doğrulama Raporu` string match).
- **L2 ops scan** (per-Edit Dockerfile / workflow / README block) 8.13.x'e ertelendi; 8.13.0 sadece L3 + manuel `/mcl-ops-report`.
- **Cloud DB** (BigQuery / Snowflake / DynamoDB) stack-tag seviyesinde tespit ediliyor; dialect-spesifik kural paketleri 8.8.x'e ertelendi.

Sürüm-bazlı tam ayrıntı için: [CHANGELOG.md](CHANGELOG.md).

---

## Repository

- Kaynak: <https://github.com/YZ-LLM/my-claude-lang>
- Issue / tartışma: yukarıdaki repo'da GitHub Issues
- Lisans: [MIT](LICENSE)
