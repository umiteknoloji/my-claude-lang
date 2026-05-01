# my-claude-lang (MCL) 10.0.0

[![Lisans](https://img.shields.io/badge/lisans-MIT-green.svg)](LICENSE)

MCL, Claude Code'a iki kanat ekleyen bir plugin: bir **dil köprüsü** — geliştirici kendi dilinde düşünür, Claude senior seviye İngilizce mühendislik çıktısı üretir; ve bir **AI disiplini** katmanı — her değişikliği deterministik bir 6-fazlı pipeline'dan geçirir, güvenlik / DB tasarımı / UI erişilebilirliği / operasyonel hijyen için hook-enforced gate'ler uygular. Her şey projenin **dışında** çalışır — 8.5.0'dan itibaren projene sıfır dosya yazılır. Kurallar stack-agnostik: aynı disiplin React, Python, Go, Rust, Java, Ruby ve diğer tüm stack'lere uygulanır.

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

> **9.x'ten yükseltiyor musun?** Kurulum sonrası ilk activate'te state otomatik olarak schema v3'e migrate edilir. `.mcl/state.json.backup.pre-v3` altında yedek tutulur. Manuel işlem gerekmez. Detay için [CHANGELOG.md](CHANGELOG.md#1000).

---

## Faz Modeli

MCL 10.0.0'ın altı fazı vardır. Phase 2 (DESIGN_REVIEW) yalnızca UI projeleri için çalışır; UI olmayan projelerde akış doğrudan Phase 1 → Phase 3 olur.

| Faz | İsim | Sorumluluk | Onay gate'i |
|---|---|---|---|
| 1 | INTENT | Clarifying soru, precision audit, brief, `is_ui_project` tespiti | Summary-confirm askq |
| 2 | DESIGN_REVIEW | UI iskeleti + dev server (yalnızca UI projeleri) | Tasarım onay askq'i |
| 3 | IMPLEMENTATION | 📋 Spec emit + tam kod (TDD, scope guard) | Yok |
| 4 | RISK_GATE | Security, DB, UI/a11y, ops, perf, mimari drift, intent ihlali | HIGH'da otomatik blok |
| 5 | VERIFICATION | Test, lint, build, smoke raporu | Yok |
| 6 | FINAL_REVIEW | Audit trail tamlığı, regresyon, söz-vs-teslimat double-check | Yok |

### Akış

```
Phase 1 ──onay──▶ [Phase 2 (is_ui_project ise)] ──onay──▶ Phase 3 ──▶ Phase 4 ──▶ Phase 5 ──▶ Phase 6
```

Tüm gate'lerde severity tier: **HIGH** = `decision:deny` / `decision:block`; **MEDIUM** = sequential dialog item; **LOW** = audit-only.

### Onay gate'leri

Yalnızca iki askq onay noktası vardır:
1. **Phase 1 summary-confirm** — geliştirici intent / constraints / success / context özetini onaylar. Kanonik scope kontratı budur. Ayrı bir spec onayı yoktur.
2. **Phase 2 tasarım onayı** — yalnızca UI projeleri. Tıklanabilir iskelet + dev server çalıştıktan sonra MCL "Tasarımı onaylıyor musun?" / "Approve this design?" sorusunu sorar. Onay `state.design_approved=true` set eder ve Phase 3'e geçirir.

Phase 3'ün `📋 Spec:` bloğu **dokümantasyondur** — implementation fazının entry artifact'i, scope guard için `state.scope_paths`'i doldurur ve İngilizce olmayan prompt'lar için İngilizce semantic bridge görevi görür. Format ihlalleri advisory'dir: hook `spec-format-warn` audit yazar ve devam eder; tur boyunca 3+ ihlal Phase 6 LOW soft fail tetikler, hiçbir zaman Write blok'u değil.

### `is_ui_project` tespiti

Phase 1 brief parser, `state.is_ui_project`'i üç sinyalden set eder:
- Intent anahtar kelimeleri (`UI`, `frontend`, `tasarım`, `mockup`, `design`, …)
- `mcl-stack-detect.sh`'tan stack tag'leri (react-frontend, vue-frontend, svelte-frontend, html-static, expo, …)
- Proje dosya ipuçları (`vite.config.*`, `next.config.*`, `tailwind.config.*`, kökte `index.html`, …)

Sinyaller belirsizse MCL `is_ui_project=true` default'una düşer (UI olmayan projede design review'ün maliyeti ekstra bir confirmation; gerçek UI projesinde atlamanın maliyeti yanlış-tasarım implementasyonu).

### Phase 4 risk gate

Phase 4, her Phase 3 implementation adımından sonra ve Phase 5'ten önce çalışır. Bulguları kategorilere göre toplar:

- **Security** — 3-tier scan (design dimension'lar, per-Edit incremental, START gate full scan); 13 generic core kural + 7 stack add-on + Semgrep `p/default` + SCA dispatch. HIGH Write'ı bloklar.
- **DB tasarımı** — 10 generic + 8 ORM × 3 anchor = 34 kural; `squawk` + `alembic check` delegate.
- **UI / a11y** — 9 a11y-critical kural HIGH tetikler; design tokens / reuse / responsive = MEDIUM dialog.
- **Ops** — 4 pack × 20 kural (deployment / monitoring / testing / docs).
- **Performans** — 3 pack × 11 kural (bundle / CWV / image), FE-only trigger.
- **Mimari drift** — `state.scope_paths` (spec'ten) vs gerçek Phase 3 yazımları. Scope boşsa LOW (advisory), yazımlar sibling layer'a değiyorsa MEDIUM, farklı katmana geçiyorsa (frontend → backend) HIGH.
- **Intent ihlali** — `state.phase1_intent` negation'ları (`auth yok`, `DB yok`, `frontend only`) import path'leri ve değiştirilen dosyalarla karşılaştırılır. HIGH ihlaller Write'ı bloklar.

Spec compliance da burada kontrol edilir (her MUST/SHOULD vs implementation), ama format issue'ları advisory kalır.

### Phase 6 double-check

Üç ortogonal check session kapanmadan önce çalışır:
- **(a) Audit trail tamlığı** — gerekli STEP audit event'leri emit edildi mi? (Sessizce atlanan fazları yakalar.)
- **(b) Final scan regresyonu** — security + DB + UI taramaları tekrar koşar; Phase 4 START baseline'ından sonra yeni HIGH = blok.
- **(c) Söz-vs-teslimat** — Phase 1 confirmed parametreleri modified dosyalarda keyword olarak match edilir (ters Lens-e izlenebilirliği).

Skip imkânsız: state field `phase6_double_check_done` `decision:block` ile enforce edilir.

---

## Özellik kataloğu

### Dil köprüsü
İlk mesajdan geliştiricinin dilini tespit eder; her clarifying question, risk dialog, doğrulama raporu, section başlığı o dilde kalır. İç mühendislik çıktısı (spec, kod, teknik token) İngilizce. 14 dil desteği (TR / EN / AR / DE / ES / FR / HE / HI / ID / JA / KO / PT / RU / ZH); araç çıktıları için TR + EN tam lokalize.

### Per-project izolasyon
MCL projene **sıfır dosya yazar**. State, hook, skill, agent, audit log, scan cache, dev-server log — her şey `~/.mcl/projects/<key>/` altında. Project key'ler `realpath($PWD)` SHA1; rename'de state kaybolur (kasıtlı, migration yok).

### Codebase scan — `/codebase-scan`
Projeyi tek seferde 12 pattern extractor'la tarar (P1–P12). Yüksek güvenlikli bulgular `project.md`'ye yazılır; orta/düşük güven `project-scan-report.md`'ye.

### Pause-on-error — `/mcl-resume`
Scan helper crash, validator malformed JSON, audit log write fail, hook script crash veya external delegate non-graceful failure'da MCL **explicit pause** yapar — silent fail-open yerine. `/mcl-resume <çözüm>` ile resume edilir.

### Interactive design loop — `/mcl-design-approve`, `/mcl-dev-server-start`, `/mcl-dev-server-stop`
Phase 2 DESIGN_REVIEW boyunca MCL arka planda dev server başlatır (10 stack detect: vite, next, cra, vue-cli, sveltekit, rails, django, flask, expo, static), port atar, PID'yi `$MCL_STATE_DIR/dev-server.pid`'de takip eder, URL'yi state üzerinden surface eder. `dev-server.log`'tan tespit edilen build hataları pause-on-error tetikler. Headless ortamlar (`MCL_HEADLESS`, `CI`, Linux SSH no-DISPLAY) auto-start atlar. Loop `/mcl-design-approve` ile kapanır (`design_approved=true` set, Phase 3'e geçer).

---

## Keyword referansı

Tüm keyword'ler normal MCL pipeline'ını atlar ve özel bir mod çalıştırır.

| Keyword | Amaç |
|---|---|
| `/mcl-doctor` | Token & maliyet raporu |
| `/mcl-update` | MCL repo'yu `git pull` + yeniden kur |
| `/mcl-restart` | Aynı oturumda MCL state'i Phase 1'e sıfırla |
| `/codebase-scan` | 12-pattern codebase taraması |
| `/mcl-security-report` | Tam backend güvenlik taraması |
| `/mcl-db-report` | Tam DB tasarım taraması |
| `/mcl-db-explain` | `EXPLAIN` çalıştır (`MCL_DB_URL` gerekir) |
| `/mcl-ui-report` | Tam UI taraması |
| `/mcl-ui-axe` | Runtime `axe-core` (`MCL_UI_URL` gerekir) |
| `/mcl-resume <çözüm>` | `paused_on_error` state'ini temizle |
| `/mcl-phase6-report` | On-demand Phase 6 double-check raporu |
| `/mcl-design-approve` | Dev server'ı durdur, Phase 2'den Phase 3'e geç |
| `/mcl-dev-server-start` | Dev server'ı manuel başlat |
| `/mcl-dev-server-stop` | Dev server'ı manuel durdur |
| `/mcl-ops-report` | Tam operasyonel disiplin taraması |
| `/mcl-perf-report` | Tam performans taraması |
| `/mcl-perf-lighthouse` | Lighthouse ile runtime CWV taraması |

---

## Örnek transcript (UI projesi)

```
geliştirici:  Küçük bir task list app yap, React + Tailwind, backend yok — sadece dummy data.

MCL Phase 1 — INTENT
  - 2 GATE sorusu sorar (auth modeli? persistence?)
  - is_ui_project=true tespit eder (intent + stack ipuçları)
  - Summary askq: "Bu kapsamı onaylıyor musun?" → geliştirici onaylar → state.current_phase=2

MCL Phase 2 — DESIGN_REVIEW
  - Tıklanabilir iskelet kurar (React + Tailwind, dummy data)
  - vite dev server'ı http://localhost:5173'te otomatik başlatır
  - askq: "Tasarımı onaylıyor musun?" → geliştirici onaylar
    → state.design_approved=true, current_phase=3

MCL Phase 3 — IMPLEMENTATION
  - 📋 Spec bloğu emit eder (dokümantasyon; scope_paths'i doldurur)
  - Acceptance Criteria üzerinde TDD red-green-refactor
  - Proje convention'larıyla pattern matching

MCL Phase 4 — RISK_GATE
  - Security / DB / UI / ops / perf taramaları
  - Mimari drift: scope_paths vs yazımlar
  - Intent ihlali: phase1_intent negation'ları vs import'lar
  - HIGH bulgular Write'ı bloklar; MEDIUM → sequential dialog

MCL Phase 5 — VERIFICATION
  - Test + lint + build + smoke raporu
  - Spec coverage tablosu (MUST/SHOULD vs testler)

MCL Phase 6 — FINAL_REVIEW
  - Audit trail tamlık kontrolü
  - Phase 4 baseline'a karşı regresyon
  - Söz-vs-teslimat (Phase 1 parametreleri vs modified dosyalar)
```

UI olmayan bir projede (örn. Go CLI) Phase 2 atlanır: Phase 1 → Phase 3 → Phase 4 → Phase 5 → Phase 6.

---

## Stack-agnostik disiplin

MCL kuralları tek bir ekosisteme bağlı değildir. Stack tespiti (`mcl-stack-detect.sh`) hangi add-on rule pack'lerin çalışacağını bilgilendirir; core pipeline'ı asla gate'lemez. Aynı TDD disiplini, scope guard, risk gate ve verification raporu şu stack'lerin tümünde geçerlidir:

- **Frontend** — React, Vue, Svelte, plain HTML
- **Backend** — Python (FastAPI/Django), Java (Spring/Quarkus), C# (ASP.NET), Ruby (Rails/Sinatra), PHP (Laravel/Symfony), Go, Rust, Node.js
- **Mobile** — Swift, Kotlin
- **Sistem / data** — C/C++, Lua, data pipeline'lar (Airflow/dbt/Prefect/Dagster), ML inference

Tespit add-on seçimini bilgilendirir; core pipeline'ı asla gate'lemez.

---

## Bilinen sınırlar

- **Proje rename** state kaybeder (path-SHA1 keying; setup-free için kasıtlı).
- **Headless `/mcl-ui-axe`, `/mcl-perf-lighthouse` ve `/mcl-db-explain`** explicit env var gerektirir (`MCL_UI_URL` axe + Lighthouse arasında shared; `MCL_DB_URL` DB EXPLAIN).
- **Bundle size** sadece mevcut build çıktısından ölçülür — `npm run build` otomatik invoke edilmez.
- **External tool delegate'leri** (Semgrep, squawk, hadolint, eslint-plugin-jsx-a11y, `axe-core`, Playwright, `pip-audit`, `cargo-audit`, `govulncheck`, `bundle-audit`) binary yoksa graceful skip.
- **14 dil destekli, ama tool raporları için sadece TR + EN tam lokalize.** Diğerleri scan çıktısı için İngilizce fallback.
- **N+1 detection statik-only**; runtime profiling ertelendi.

Sürüm-bazlı tam ayrıntı için: [CHANGELOG.md](CHANGELOG.md).

---

## Repository

- Kaynak: <https://github.com/YZ-LLM/my-claude-lang>
- Issue / tartışma: yukarıdaki repo'da GitHub Issues
- Lisans: [MIT](LICENSE)
