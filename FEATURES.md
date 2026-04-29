# MCL Özellik Kataloğu

**Güncel sürüm:** 8.11.0

---

## Temel Mimari

### Faz Modeli
MCL her geliştirici mesajını sıralı fazlardan geçirir. Bir faz eksik parametre olmadan ilerlemez.

```
Phase 1   → Anlama (intent, constraints, success_criteria, context)
Phase 1.7 → Precision Audit (7 core boyut + stack add-on; SILENT-ASSUME / SKIP-MARK / GATE)
Phase 1.5 → Engineering Brief (8.4.0+ upgrade-translator: çeviri + vague verb → surgical verb)
Phase 2   → Spec üretimi
Phase 3   → Spec doğrulama + geliştirici onayı
Phase 3.5 → Pattern Matching (proje kodu okunur, convention çıkarılır)
Phase 4   → Kod yazımı (TDD ile)
  Phase 4a → BUILD_UI  — dummy data ile çalışan frontend
  Phase 4b → UI_REVIEW — geliştirici UI'ı tarayıcıda görür, onaylar
  Phase 4c → BACKEND   — gerçek API/veri katmanı
Phase 4.5 → Risk incelemesi
Phase 4.6 → Etki analizi
Phase 5   → Doğrulama raporu
Phase 5.5 → Lokalize rapor (EN → geliştirici dili çevirisi)
```

### Dil Köprüsü
- Tüm iletişim geliştiricinin dilinde (14 dil: TR, EN, AR, DE, ES, FR, HE, HI, ID, JA, KO, PT, RU, ZH)
- Spec ve kod İngilizce — model her zaman İngilizce mühendislik çıktısı üretir
- Dil otomatik tespiti — ilk mesajdan belirlenir, sonraki tüm fazlarda korunur

### Hook Altyapısı
| Hook | Tetiklenme | Görev |
|---|---|---|
| `mcl-activate.sh` | Her `UserPromptSubmit` | STATIC_CONTEXT + durum bildirimleri inject eder |
| `mcl-stop.sh` | Her `Stop` | Faz geçişlerini yönetir, session log yazar |
| `mcl-pre-tool.sh` | Her `PreToolUse` | Phase 4.5 state advance, respec koruması, hook dominance blokları |
| `mcl-post-tool.sh` | Her `PostToolUse` | Session diary — her araç çağrısı için tek satır log |

**Hook Dominance İlkesi** (8.0.x)
Behavioral kurallar yerine hook kararları (`decision:block`) tercih edilir — bunlar model talimatlarından önce gelir ve override edilemez. Aşağıdaki araç çağrıları hook seviyesinde bloke edilir:

| Blok | Koşul |
|---|---|
| `Skill: superpowers:brainstorming` | MCL aktifken her zaman |
| `TodoWrite` | Phase 1-3'te (Phase 4+ serbest) |
| `Task` → Phase 4.5/4.6/5 | description'da faz anahtar kelimeleri varsa |
| `Bash` → `.mcl/state.json` yazımı | Her zaman (state yalnızca hook sistemine ait) |

---

## Özellikler (Faz Bazlı)

### Phase 1 — Anlama

**Disambiguation Triage** (7.3.3)
Belirsiz parametreleri iki kategoriye ayırır:
- **SILENT** — varsayılan al, spec'e `[assumed: X]` yaz (pagination size, hata mesajı metni, log level)
- **GATE** — tek tek sor (schema/migration, auth modeli, public API yüzeyi, geri döndürülemez iş mantığı)
Buluşsal kural: "Bu cevap olmadan spec yazabilir miyim?" → Evet = sessiz, Hayır = gate.

**GATE Answer Coherence Check** (7.7.0)
Kullanıcı bir GATE sorusunu yanıtladıktan sonra, cevabın teknik imlikasyonu tarif edilen mimariyle tutarlı mı kontrol eder.
- JWT seçildi ama server-side state gerektiren flow tarif edildi → çelişki yüzeylenir
- "Bu iki şeyden hangisini kastediyordunuz?" sorusu sorulur, spec yazılmaz
- Sadece mimari seçimler için tetiklenir (auth, storage, API shape, consistency model)
- Kullanıcı ısrar ederse pressure-resistance kuralı devreye girer

**Contradiction Detection**
- Mantıksal çelişkiler: "offline AND real-time data" → hangisi öncelikli?
- Nested conditional requirements: karmaşık şart cümlelerini numaralı listeye böler
- Hidden sub-tasks: tek istek gibi görünen ama birden fazla bağımsız görev içerenleri tespit eder

### Phase 1.7 — Precision Audit (8.3.0)

Phase 1 "completeness" sağlar; Phase 1.7 "precision" sağlar. Phase 1 onayı sonrası, Phase 1.5 brief'inden önce çalışır. 7 core boyut + `mcl-stack-detect.sh` tag'lerine göre stack add-on boyutları walk eder. Her boyut üç sınıftan birine düşer:

- **SILENT-ASSUME** — industry default var, reversible. Spec'te `[assumed: X]` markla.
- **SKIP-MARK** — güvenli default yok, varsayım yapma. Spec'te `[unspecified: X]` markla. Şu an yalnızca **Performance SLA**'da kullanılıyor.
- **GATE** — mimari etki var, tek soru sor (one-question-at-a-time).

**Core 7 boyut (her projede):** Permission/access, algorithmic failure modes, out-of-scope boundaries, PII handling, audit/observability, performance SLA, idempotency/retry. UX state'leri (empty/loading/error UI) UI stack add-on'larında — core'da değil.

**Stack add-on'lar (8.4.1 genişletmesi):**
- **Web base:** typescript/javascript (modül sistemi, async patterns, package manager, deployment target).
- **Frontend frameworks (dedicated add-on):** react-frontend, vue-frontend, svelte-frontend, html-static. Her biri base TS/JS add-on'una **ek olarak** uygulanır (multi-tag union — örn. React projesi `[typescript, react-frontend]`).
- **Backend dilleri:** python (FastAPI/Django), java (Spring/Quarkus), csharp (ASP.NET), ruby (Rails/Sinatra), php (Laravel/Symfony), go, rust.
- **Sistem dilleri:** cpp, lua.
- **Mobile:** swift, kotlin.
- **Domain-shape (içerik tabanlı, dil değil):** cli, data-pipeline (Airflow/dbt/Prefect/Dagster + Beam/Spark), ml-inference (model artifact / torch/tensorflow/scikit-learn/mlflow). 8.4.1'de `mcl-stack-detect.sh` heuristik tespit eder; daha önce TODO idi.
- Her add-on 2-5 delta boyut içerir. Solid/Angular/Qwik ve kotlin-mobile vs kotlin-backend ayrımı gelecek genişleme için TODO.

İngilizce session'da skip — audit entry yine emit edilir (`skipped=true`) detection control olarak. **Hard enforcement (8.3.2):** `mcl-stop.sh` Phase 1→2 transition'ında audit'te `precision-audit` entry yoksa hem `precision-audit-skipped-warn` (8.3.0 detection signal, backward compat) hem `precision-audit-block` audit'leri yazar VE `decision:block` JSON döndürür — Phase 1→2 transition rewind edilir, Claude aynı response içinde Phase 1.7'i çalıştırıp spec'i yeniden emit etmek zorunda. Phase 4.5 ile aynı tier. İngilizce session safety valve: `skipped=true` audit emit edildiğinde block fire etmez.

### Phase 1.5 — Engineering Brief (Upgrade-Translator, 8.4.0+)

**Contract change:** 8.4.0 öncesi Phase 1.5 yalnızca faithful translator'dı (`do NOT add scope, do NOT subtract scope`). 8.4.0'dan itibaren brief iki görevi var:

1. **Translate** — non-İngilizce Phase 1 parametrelerini İngilizce'ye sadık çeviri (English source için identity)
2. **Upgrade vague verbs** — `list`/`listele` → `render a paginated table`, `manage`/`yönet` → `expose CRUD operations`, `build`/`yap` → `implement`, vb. (14 dil için verb tablosu)

Surgical verb'lerin **standart teknik default'ları** `[default: X, changeable]` marker'larıyla annotate edilir (örn. `paginate` → `[default: cursor pagination, changeable]`). Yasak eklemeler: yeni entity, feature, NFR, auth, audit, persistence — bunlar kullanıcının açıkça mention etmesini gerektirir.

**Hallucination koruması (3 katmanlı):**
- Skill dosyasında Allowed/Forbidden boundary + 13 calibration example
- **Phase 3 Scope Changes Callout:** kullanıcı kendi dilinde tüm upgrade'leri görür ve "edit" seçeneğiyle düzeltebilir
- **Phase 4.5 Lens (e) Brief-Phase-1 Scope Drift:** implementation Phase 1 confirmed parametrelere izlenebilir mi kontrol; izlenemeyen + `[default]` marker'sız scope risk olarak surface

**Audit signal:** `engineering-brief | phase1-5 | lang=<...> skipped=<...> retries=<N> clarification=<...> upgraded=<bool> verbs_upgraded=<count>`. `upgraded=true` olduğunda Phase 3 callout ve Phase 4.5 Lens (e) zorunlu.

**Phase 5.5 simetrisi:** asimetrik kabul edildi — input upgrade (1.5), output faithful (5.5). Geri çeviride teknik kelime kaybı olabilir; spec/audit trail surgical İngilizce'de korunur.

### Phase 2 — Spec Üretimi

**Senior Engineer Spec** (7.1.x+)
Her zaman dahil edilen BASE bölümler:
- Objective, MUST/SHOULD requirements, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope

**Koşullu Bölümler** (7.3.2)
Yalnızca tetiklendiğinde eklenir, aksi hâlde tamamen omit edilir:
- **Non-functional Requirements** — performans/ölçek kısıtları belirtildiğinde
- **Failure Modes & Degradation** — dış bağımlılıklar veya async operasyonlar varsa
- **Observability** — kritik prod yolu, güvenlik audit trail, kullanıcı davranış takibi
- **Reversibility/Rollback** — DB migration, feature flag, destructive operasyon
- **Data Contract** — API yüzeyi değişiklikleri, cross-service boundary

**Collapsible Spec** (7.8.1)
Spec bloğu `<details open>` ile sarılır — Claude Code UI'da tıklayınca kapanır.

### Phase 3 — Doğrulama

**Zorunlu Yerelleştirilmiş Özet** (7.8.1)
Spec'ten sonra, AskUserQuestion'dan önce geliştiricinin dilinde 3-5 cümle özet yazılması zorunludur.

**Technical Challenge Pass** (7.3.4)
Spec onay sorusundan önce somut teknik sorun var mı kontrol eder:
- O(n²) ölçek sorunu, race condition, N+1 query, eksik auth, cascading failure
- Bulursa: `⚠️ Teknik not: [tek cümle]` — devam engellemez, bildirimdir

**AskUserQuestion Protokolü** (6.0.0+)
Tüm kapalı uçlu MCL etkileşimleri `MCL X.Y.Z | ` prefix'li native `AskUserQuestion` tool ile yapılır.

**Spec Approval Discipline** (7.9.8)
- Session başına 1 spec kuralı — spec_hash set olduktan sonra yeni spec emisyonu yasak
- Plain-text approval fallback — kullanıcı "onaylıyorum/approve/yes" yazarsa stop hook bunu algılar
- "Devam etmek için bir mesaj gönderin" ve tüm dil eşdeğerleri yasaklı
- `.mcl/hooks/*.sh` dosyaları debug amaçlı okunamaz


**Phase 3.5 Pattern Matching** (8.0.7, derinleşti 8.1.1)
Spec onayı sonrası Phase 4 başlamadan önce mevcut sibling dosyalar okunur:
- **Naming Convention**, **Error Handling Pattern**, **Test Pattern** — 3 zorunlu başlık
- 4 seviyeli cascade: sibling → proje geneli → ekosistem standardı → kullanıcıya sor
- Sonuçlar Phase 4 boyunca `PATTERN_RULES_NOTICE` olarak context'te tutulur

### Phase 4 — Kod Yazımı

**Incremental TDD** (7.3.1)
Batch TDD yerine gerçek red-green-refactor döngüsü:
1. Bir Acceptance Criterion için tek test yaz → RED verify
2. Minimum kodu yaz → GREEN verify
3. Refactor (DRY, naming, dead code temizliği) → GREEN verify
4. Sonraki criterion

**Test Komutu Çözümü** (STEP-24)
Öncelik sırası: config dosyası → auto-detect → spec'ten çıkarım → geliştirici sorusu

**Re-spec Koruması** (7.1.8)
Spec onaylandıktan sonra yeni `📋 Spec:` bloğu veya spec onay sorusu yasaktır.

**Kod Tasarım İlkeleri** (7.9.7)
Phase 4'te yazılan tüm kodda zorunlu:
- Composition over inheritance
- SOLID (Single Responsibility, Open/Closed, Liskov, Interface Segregation, Dependency Inversion)
- Extension over modification
- Design pattern yalnızca gerçek problemi çözdüğünde

**UI Build/Review Sub-Phases** (6.2.0+, auto-detect 6.5.2+)
UI surface tespit edildiğinde Phase 4 üç alt faza bölünür:
- **4a BUILD_UI** — build config dosyaları (vite/tailwind/tsconfig) önce yazılır, sonra dummy data ile çalışan frontend. `npm install && npm run dev` çalıştırılır, tarayıcı otomatik açılır.
- **4b UI_REVIEW** — geliştirici tarayıcıda UI'ı inceler, AskUserQuestion ile onaylar. Opt-in: Playwright + screenshot ile MCL kendi bakıp rapor verir.
- **4c BACKEND** — UI onayı sonrası gerçek API çağrıları, veri katmanı, async state.

**Phase 4a Build Config Fix** (7.9.6)
`vite.config.*`, `next.config.*`, `nuxt.config.*` artık backend path listesinde değil — bunlar olmadan `npm run dev` çalışmaz.

### Phase 4.5 — Risk İncelemesi

**Sıralı Diyalog**
Tüm riskler birer birer AskUserQuestion ile sunulur. Her risk için: skip / fix uygula / kural yap.

**4 Lens Kalitesi Tarama**
Eş zamanlı çalışır: (a) Code Review, (b) Simplify, (c) Performance, (d) Security. Semgrep SAST HIGH/MEDIUM bulguları otomatik uygulanır.

**Spec Compliance Pre-Check**
Phase 4 kodunun her MUST/SHOULD'u karşılayıp karşılamadığı kontrol edilir.

**TDD Re-verify + Test Coverage**
Tüm riskler çözüldükten sonra tam suite çalıştırılır.

**Root Cause Chain** (8.1.9)
Her bug fix veya davranış değişikliği için çok seviyeli kök sebep zinciri:
1. Görünür süreç — düşünce zinciri açık yazılır
2. Removal test — sebep kalkarsa üst problem çözülür mü?
3. Falsification — sebep doğruysa kontrol edilebilir X gözlemlenmeli
Her halkada uygulanır; müdahale noktası sıfır yan etki üreten halka.

**Regression Guard Smart-Skip** (8.1.5/8.1.6)
TDD green-verify GREEN + son yazımdan sonra → Regression Guard suite koşmaz.
`last_write_ts` ve `tdd_last_green` state'e yazılır; ikisi birlikte kontrol edilir.

**Session Recovery** (7.4.0)
Phase 4.5 yarıda kesilebilir. `.mcl/risk-session.md` her karar sonrası güncellenir.

**Plugin Dispatch Audit** (7.9.5)
Phase 4.5 çalışırken her turda `trace.log` kontrol edilir:
- `pr-review-toolkit:*` veya `code-review:*` sub-agent dispatch'i var mı?
- `semgrep_ran` trace eventi var mı? (stack destekleniyorsa)
- Eksik varsa `PLUGIN_MISS_NOTICE` enjekte edilir → Phase 4.6/5'e geçiş engellenir
- Dispatch gerçekleşince notice otomatik temizlenir

### Phase 4.6 — Etki Analizi

Yeni yazılan kodun projenin BAŞKA bölümlerine gerçek etkileri:
- Import eden dosyalar, shared utility davranış değişikliği, API/contract kırılması
- Schema/migration etkileri, build/toolchain/dependency değişimleri

**Plugin Çatışması — Provenance-First** (7.5.0)
İki plugin çelişen hüküm verirse `[PLUGIN CONFLICT]` formatıyla her iki gerekçe gösterilir, geliştirici karar verir.

### Phase 5 — Doğrulama Raporu

**Spec Coverage Tablosu** (7.6.0)
`| Requirement | Test | Status |` — tüm MUST/SHOULD satırları (✅/⚠️/❌).

**Automation Barriers** (7.6.0)
Call-graph tabanlı "gerçekten otomatize edilemeyen" liste. Hiçbiri tetiklenmezse omit edilir.

**Phase 5 Skip Detection** (8.2.7)
`mcl-stop.sh` her stop'ta `phase_review_state` kontrol eder. State `running` ise ve bu turda MCL prefix'li AskUserQuestion çalışmamışsa (Phase 4.5/4.6 dialog bitmiş ama Phase 5 state'i temizlememiş), audit'e `phase5-skipped-warn` yazılır. `mcl-activate.sh` bir sonraki turda `PHASE5_SKIP_NOTICE` enjekte eder — Claude'a Phase 5 raporunu çalıştırmasını söyler.

**Hook Health Check** (8.2.7)
Dört MCL hook'u (stop / activate / pre_tool / post_tool) son başarılı çalışma timestamp'ini `.mcl/hook-health.json`'a yazar. `mcl check-up` (STEP-61) eksik veya 24 saatten eski bir alan bulursa WARN üretir — hook'un kayıt dışı kaldığını veya sessizce başarısız olduğunu yakalar.

**Root Cause Chain Discipline** (8.2.8 plan-mode + 8.2.9 all-mode)
8.2.8 plan-mode tespiti: bu session içinde `.claude/plans/*.md` dosyalarından biri modify edildiyse `mcl-activate.sh`, `ROOT_CAUSE_DISCIPLINE_NOTICE` enjekte ederek 3-check zincirini zorunlu kılar (visible process / removal test / falsification). `mcl-stop.sh`, `ExitPlanMode` çağrısı yapılan son assistant turunda metin + tool input'ları üç keyword çifti için (EN/TR, case-insensitive) tarar: `removal test`/`kaldırma testi`, `falsification`/`yanlışlama`, `visible process`/`görünür süreç`. Bir çiftin ne EN ne de TR formu yoksa audit'e `root-cause-chain-skipped-warn` yazılır; bir sonraki turda `mcl-activate.sh` `ROOT_CAUSE_CHAIN_WARN_NOTICE` ile Claude'a planı yeniden emit etmesini söyler.

8.2.9 all-mode genişletme: 14 dilli (TR/EN/ES/FR/DE/JA/KO/ZH/AR/HE/HI/ID/PT/RU) heuristik trigger keyword seti (`neden`, `çalışmıyor`, `bug`, `why`, `broken`, `error`, vb.) kullanıcı prompt'unda görüldüğünde plan-mode bypass edilse bile `ROOT_CAUSE_DISCIPLINE_NOTICE` enjekte edilir (plan-mode hâlâ kazanır, çift inject yapılmaz). `mcl-stop.sh`'a always-on keyword scan eklendi — her turda son user mesajında trigger varsa son assistant cevabını 3 check için tarar; eksikse audit'e `source=all-mode missing=<list>` yazılır. False-positive riski (`fail`, `error`, `bug`, `issue` çok yaygın) kabul edilmiş gürültü; warn non-blocking.

**Plan Critique Substance Validation** (8.3.3)
8.2.10 plan critique gate yalnızca Task çağrısının **şeklini** kontrol ediyordu (`subagent_type=*general-purpose*` + `model=*sonnet*`); `Task(prompt="say hi")` bypass'a açıktı. 8.3.3 substance gate ekler: pre-tool, general-purpose+sonnet Task'ı yakaladığında transcript'i tarayıp en son `Task(subagent_type=*mcl-intent-validator*)` çağrısının JSON verdict'ini okur. `verdict=yes` → allow + `plan_critique_done=true`; `verdict=no` → `decision:block` + reason; validator hiç çağrılmamış → `decision:block` + "validator-first" talimatı; malformed JSON → fail-open + audit warn. Recursion-safe: validator subagent'ı kendi `subagent_type`'ını (mcl-intent-validator) kullandığı için pre-tool'un general-purpose gate'i tarafından yakalanmaz. Validator agent dosyası: `agents/mcl-intent-validator.md`, setup.sh ile `~/.claude/agents/` altına kopyalanır. Strict gate-keeper persona: default verdict=NO unless evidence is clear.

**Plan Critique Subagent Enforcement** (8.2.10)
Plan onayı (`ExitPlanMode`) öncesinde plan critique subagent'ının (Sonnet 4.6) çağrılmasını zorunlu kılar. State alanı `plan_critique_done` (default: `false`); session boundary'de ve `.claude/plans/*.md` dosyasına Write/Edit yapıldığında otomatik resetlenir. Pre-tool hook akışı: (1) `Task` çağrısı `subagent_type=*general-purpose*` + `model=*sonnet*` ise `plan_critique_done=true` set edilir; (2) `ExitPlanMode` çağrısı ile `plan_critique_done=false` ise `decision:block` ile reddedilir; (3) `.claude/plans/*.md` dosyasına Write/Edit/MultiEdit yapıldığında `plan_critique_done=false` resetlenir. Activate hook her turda plan dosyası varsa ve critique yapılmadıysa `PLAN_CRITIQUE_PENDING_NOTICE` enjekte eder. Stop hook ExitPlanMode tool_use bu turda var ve state hâlâ `false` ise audit'e `plan-critique-skipped-warn` yazar.

**Session Context Bridge** (8.2.11)
Cross-session bilgi köprüsü: `mcl-stop.sh` her Stop'ta `.mcl/session-context.md` yazar (trap EXIT — early-exit'lerde de fire eder, atomic tmp+rename). Markdown formatında 4-6 satır: aktif faz + spec hash, son commit SHA + subject (60 char), sıradaki adım (state-driven kural tablosu), ve varsa yarım plan / Phase 4.5 başlatılmamış uyarısı. Yeni session başında `mcl-activate.sh` dosyayı okur ve `SESSION_CONTEXT_NOTICE` olarak `additionalContext`'e enjekte eder — Claude önceki session'ın bağlamıyla devam edebilir. Aynı session içinde re-inject yok (boundary-only). Empty section omission: bilgi yoksa satır yazılmaz.

---

---

## Hook Güvenlik Katmanları (8.0.x+)

**Güvenlik Refleksleri** (8.0.8)
Write/Edit çağrıları credential ve secret taramasından geçer:
- Tier 1: `.env`, `*.pem`, `*.key`, `credentials.json` — gerçek değer içeriyorsa blok
- Tier 2: Bilinen token pattern'leri (`sk-...`, `ghp_...`, `AKIA...`, JWT vb.)
- Tier 3: Yüksek entropi assignment (Shannon ≥ 3.5, uzunluk ≥ 20)

**Scope Guard** (8.0.6)
Phase 4'te Write/Edit sadece spec'te bildirilen dosya yollarına izin verir. Glob pattern desteği (`src/auth/*.ts`).

**Scope Discipline** (8.1.2)
Her Phase 4 turunda üç kural:
- Rule 1 SPEC-ONLY: spec'in MUST/SHOULD'larında olmayan hiçbir şey yapılmaz
- Rule 2 FILE SCOPE: sadece spec'te geçen dosyalar değiştirilir
- Rule 3 ROOT CAUSE: semptomu değil sebebi düzelt

**Rollback Checkpoint** (8.0.9)
Spec onayında `git rev-parse HEAD` → `state.rollback_sha`. Her turda SHA ve `git reset --hard` komutu gösterilir (ilk tur, `/mcl-rollback` ile yeniden).

---

## Genel Mekanizmalar

### Devtime Plan Critique (8.2.4)
Plan üretildiğinde `general-purpose` subagent (claude-sonnet-4-6, extended thinking) planı 10 lens ile eleştirir: kök sebep derinliği, yan etki tahmini, boş/eksik durumlar, disambiguation eksiği, plan belirsizliği, halüsinasyon kontrolü, mevcut özelliklerle çakışma, extension/modification, kullanıcı görünürlüğü, test edilebilirlik. Sadece devtime.

### Anti-Sycophancy (7.3.4)
- **Verdict-first formatı**: Olumsuz bulgu varsa ilk cümlede söylenir
- **Proaktif firing**: Geliştirici sormadan da teknik sorun yüzeylenir
- **Pressure resistance**: Yeni kanıt yoksa pozisyon korunur
- **Self-critique loop**: Her yanıt öncesi 4 soru, maks 3 iterasyon

### `/mcl-self-q` (7.9.4, eski adı `(mcl-oz)`)
Mesaj içine yazılınca o yanıt için self-critique süreci görünür hale gelir. Per-message, kalıcı değil.

### Kural Yakalama (Rule Capture)
Geliştirici bir fix'i genel kural yapmak istediğinde kapsam seçimi + preview + onay akışı çalışır.

### Human Authority — Karar Kapanışı (8.1.4)
Geliştirici açık karar verdikten sonra (ret, seçim, risk kabulü) MCL konuyu yeniden açmaz. Pressure resistance (kanıtsız baskıya direnç) ile tamamlayıcı — biri pozisyonu korur, diğeri kararı kapatır.

### GATE Answer Coherence (7.7.0)
Mimari GATE cevabı alındıktan sonra teknik tutarlılık kontrolü. Bkz. Phase 1 bölümü.

### Proje Hafızası (7.3.0)
`.mcl/project.md` — proje bilgi tabanı. Phase 5 sonrası güncellenir.

---

## Komutlar

| Komut | Açıklama |
|---|---|
| `/mcl` | MCL'yi zorla aktive eder |
| `/mcl-version` | Kurulu sürümü gösterir |
| `/mcl-update` | MCL'yi git pull + install.sh ile günceller |
| `/mcl-restart` | Tüm faz ve spec state'ini sıfırlar; aynı session'da JIT promote'un eski askq'leri yeniden onaylamasını engellemek için `restart_turn_ts` damgası yazar (8.2.13) |
| `/mcl-finish` | Birikmiş Phase 4.6 etkilerini özetler + Semgrep taraması |
| `/mcl-doctor` | Token & maliyet raporu |
| `/mcl-checkup` | Sağlık kontrolü — tüm STEP'ler değerlendirilir |
| `/mcl-self-q` | O yanıt için self-critique sürecini görünür yapar (inline, per-message) |
| `/mcl-rollback` | Rollback checkpoint SHA'sını ve atomic commit komutunu gösterir; bir sonraki turda `ROLLBACK_NOTICE` yeniden görünür |

---

## Token & Maliyet Muhasebesi (7.8.0)

- Her tur `FULL_CONTEXT` karakter sayısı `.mcl/cost.json`'a loglanır
- `/mcl-doctor` komutu: injection overhead, cache write/read maliyet dökümü, "MCL açık vs kapalı" karşılaştırması
- Sonnet 4.6 fiyatlandırması ($3/MTok input, $0.30/MTok cache read)

---

## Session & State Yönetimi

### State Dosyası (`.mcl/state.json`)
Hook sistemi tarafından yönetilir — doğrudan Bash yazımı bloke edilir (8.0.3+).

**`mcl_get_active_phase()`** (8.2.3)
Tüm state field'larını (`current_phase`, `spec_approved`, `phase_review_state`, `ui_sub_phase`, vb.) okuyup tek bir effective phase string döndürür: `"1"`, `"2"`, `"3"`, `"3.5"`, `"4"`, `"4a"`, `"4b"`, `"4c"`, `"4.5"`, `"?"`. Hook'lardaki çift-okuma noktaları bu helper'ı kullanır.

`phase_review_state` lifecycle:
```
null → "pending" (Phase 4 kodu yazıldı, 4.5 başlamadı)
     → "running"  (Phase 4.5 AskUserQuestion ilk çağrıldı)
     → null       (Phase 4.6/5 tamamlandı)
```

### Session Log (`.mcl/log/*.md`)
Her Stop hook'unda tur özeti: `Bu tur tamamlandı. | Tur: X token | Bağlam: Y / 200.000 | Kalan: Z`

---

## Güvenlik & Sınırlama Kuralları

**Plugin Orkestrasyon**
- **Rule A**: Projede `.git/` yoksa tek seferlik onay alarak `git init`
- **Rule B**: Curated plugin'ler sessizce çalıştırılır; çatışmada provenance-first
- **Rule C**: MCP-server plugin'leri yasaklı; binary CLI araçlar (semgrep) izinli

**Hook Dominance** (8.0.x)
`mcl-pre-tool.sh` şu araç çağrılarını bloke eder:
- `superpowers:brainstorming` → MCL Phase 1-3 zaten bu rolü üstleniyor
- `TodoWrite` Phase 1-3 → MCL state.json ile yönetiyor
- `Task` → Phase 4.5/4.6/5 dispatch → bu fazlar sub-agent'a devredilemez
- `Bash` → `.mcl/state.json` yazımı → state yalnızca hook sistemine ait

**No Re-spec After Approval**
Spec onayı sonrası yeni spec bloğu veya Phase 1/2/3 yeniden çalıştırma yasaktır.

**Pasted CLI Passthrough**
Shell komutu yapıştırıldığında MCL Phase 1'i atlar. Destructive operasyonlar yine de onay alır.

---

## Bilinen Sınırlamalar / Known Limitations

### post-tool hook race — paralel tool batch (8.2.12'de dokümante edildi)

**Sorun.** Claude Code'un resmi hook lifecycle belgelerine göre:
- `PreToolUse` hook'ları **serileşik** fire eder (race yok).
- `PostToolUse` hook'ları **async, non-deterministic sırada** fire eder — Claude tek bir assistant mesajında 2+ paralel `tool_use` bloğu emit ettiğinde her tool'un `PostToolUse`'u biten sıraya göre eşzamanlı çalışabilir.
- `PostToolBatch` (TS SDK senkronizasyon noktası) **shell hook'larda mevcut değil** — MCL kullanamaz.

Kaynak: [code.claude.com/docs/en/hooks.md](https://code.claude.com/docs/en/hooks.md)

**MCL'deki etki.** `mcl-post-tool.sh` iki state alanı yazar:
- `state.last_write_ts` — Write/Edit/MultiEdit/NotebookEdit sonrası epoch
- `state.regression_block_active`, `state.regression_output` — Bash GREEN test çıktısında temizlik

`mcl-state.sh::_mcl_state_write_raw` tmp+rename atomik, ama **field-level merge yok** — tüm dosya overwrite. İki paralel `mcl-post-tool.sh` aynı snapshot'ı okuyup farklı field yazarsa, son yazar kazanır → diğer field'ın update'i kaybolur.

**Somut senaryo.** Claude tek mesajda paralel `Write` + `Bash` (test runner) çağırırsa:
1. post-tool A (Write) snapshot okur → `last_write_ts=null, regression_block_active=true`
2. post-tool B (Bash GREEN) aynı snapshot okur (eşzamanlı)
3. post-tool A yazar: `{last_write_ts=100, regression_block_active=true}`
4. post-tool B yazar: `{last_write_ts=null, regression_block_active=false}` — A'nın `last_write_ts` update'i silindi

**Etki seviyesi: düşük-orta.**
- `last_write_ts` kaybı → regression-guard smart-skip yanlış değerlendirir → gereksiz suite re-run (perf only, korrektlik etkisi yok)
- `regression_block_active=false` kaybı → Phase 4.5 BLOCK kalkmaz görünür ama `mcl-stop.sh` regression-guard'ı re-evaluate eder, sonraki turda kapanır (gecikmeli ama eventual consistency)

**Mitigasyon kasıtlı eklenmedi.** Seçenekler:
- `flock` etrafında `mcl_state_set` — ek bağımlılık (POSIX flock veya Linux/macOS fcntl), shell wrapper karmaşıklığı
- Field-level merge — `mcl-state.sh` `mcl_state_set` semantiğini değiştirir, tüm hook'larda regresyon riski
- **Kabul edilen yol:** complexity > value. Audit trail (`audit.log`) append-only olduğu için forensic olarak kayıp yok; state.json field kaybı stop hook'un re-evaluation pattern'i ile telafi edilir.

### Diğer hook'lar
- `mcl-pre-tool.sh` state yazımları **güvenli** — PreToolUse serileşik (resmi garanti).
- `mcl-activate.sh` ve `mcl-stop.sh` turda 1 kez fire eder — race yok.

---

## Kurulum (8.5.0+)

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

Wrapper, projenin realpath'inden sha1 ile stable bir key türetir, ilk çalıştırmada `~/.mcl/projects/<key>/` scaffolding'ini yaratır, hook'lar için `MCL_STATE_DIR` set'ler ve izole `--settings` + `--plugin-dir` ile `claude`'u `exec` eder. Tüm Claude Code bayrakları passthrough.

**Kaldırma:**
```bash
rm -rf ~/.mcl ~/.local/bin/mcl-claude
```
Projelerine MCL hiçbir dosya yazmadığı için proje tarafında temizlik gerekmez (8.5.0+ için).
