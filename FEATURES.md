# MCL Özellik Kataloğu

**Güncel sürüm:** 8.2.9

---

## Temel Mimari

### Faz Modeli
MCL her geliştirici mesajını sıralı fazlardan geçirir. Bir faz eksik parametre olmadan ilerlemez.

```
Phase 1   → Anlama (intent, constraints, success_criteria, context)
Phase 1.5 → Engineering Brief (kullanıcı dili → EN çevirisi, yorumsuz)
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
| `/mcl-update` | MCL'yi git pull + setup.sh ile günceller |
| `/mcl-restart` | Tüm faz ve spec state'ini sıfırlar |
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

## Kurulum

```bash
git clone https://github.com/YZ-LLM/my-claude-lang.git ~/my-claude-lang
cd ~/my-claude-lang && bash setup.sh
```

`setup.sh` her çalışmada:
**Kaldırma:**
```bash
bash uninstall.sh
```
`uninstall.sh`: settings.json'dan hook kayıtlarını çıkarır, skill ve hook dosyalarını siler. Per-project `.mcl/` elle temizlenir.

`setup.sh` her çalışmada:
- Skill dosyalarını `~/.claude/skills/` altına kopyalar
- Hook'ları `~/.claude/hooks/` altına kopyalar
- `settings.json`'a hook kayıtlarını ekler
- README, skill, hook, **FEATURES.md** ve **CHANGELOG.md**'deki versiyon string'lerini otomatik sync eder
