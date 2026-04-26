# MCL Özellik Kataloğu

**Güncel sürüm:** 7.8.1

---

## Temel Mimari

### Faz Modeli
MCL her geliştirici mesajını sıralı fazlardan geçirir. Bir faz eksik parametre olmadan ilerlemez.

```
Phase 1  → Anlama (intent, constraints, success_criteria, context)
Phase 2  → Spec üretimi
Phase 3  → Spec doğrulama + geliştirici onayı
Phase 4  → Kod yazımı (TDD ile)
Phase 4.5 → Risk incelemesi
Phase 4.6 → Etki analizi
Phase 5  → Doğrulama raporu
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
| `mcl-pre-tool.sh` | Her `PreToolUse` | Phase 4.5 state advance, respec koruması |

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

**Zorunlu Türkçe Özet** (7.8.1)
Spec'ten sonra, AskUserQuestion'dan önce geliştiricinin dilinde 3-5 cümle özet yazılması zorunludur. AskUserQuestion description alanına değil, ayrı bir paragraf olarak.

**Technical Challenge Pass** (7.3.4)
Spec onay sorusundan önce somut teknik sorun var mı kontrol eder:
- O(n²) ölçek sorunu, race condition, N+1 query, eksik auth, cascading failure
- Bulursa: `⚠️ Teknik not: [tek cümle]` — devam engellemez, bildirimdir
- Vague concern → sessiz geç

**AskUserQuestion Protokolü** (6.0.0+)
Tüm kapalı uçlu MCL etkileşimleri (spec onayı, risk/etki kararları, plugin onayı) native `AskUserQuestion` tool ile yapılır. `MCL X.Y.Z | ` prefix ile. Stop hook bu prefix'i parse ederek state advance eder.

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
Spec onaylandıktan sonra yeni `📋 Spec:` bloğu veya spec onay sorusu yasaktır. Beklenmedik constraint → tek AskUserQuestion bridge sorusu (workaround/scope-trim/cancel).

### Phase 4.5 — Risk İncelemesi

**Sıralı Diyalog**
Tüm riskler bir liste olarak değil, birer birer AskUserQuestion ile sunulur. Geliştirici her risk için: skip / fix uygula / kural yap.

**4 Lens Kalitesi Tarama**
Eş zamanlı çalışır: (a) Code Review, (b) Simplify, (c) Performance, (d) Security. Semgrep SAST HIGH/MEDIUM bulguları otomatik uygulanır ve merge edilir.

**Spec Compliance Pre-Check**
Phase 4 kodunun her MUST/SHOULD'u karşılayıp karşılamadığı kontrol edilir. Eksik varsa risk olarak yüzeylenir.

**TDD Re-verify + Test Coverage**
Tüm riskler çözüldükten sonra tam suite çalıştırılır. Eksik test kategorileri tespit edilir (unit, integration, E2E, load).

**Session Recovery** (7.4.0)
Phase 4.5 yarıda kesilebilir. `.mcl/risk-session.md` her karar sonrası güncellenir:
- Session yeniden başlarsa HEAD karşılaştırması yapılır
- HEAD eşleşiyor → tamamlananlar atlanır, kaldığı yerden devam
- HEAD farklı → sıfırdan başlar (kod değişti)
- Geliştirici kesintiyi görmez

### Phase 4.6 — Etki Analizi

Yeni yazılan kodun projenin BAŞKA bölümlerine gerçek etkileri:
- Import eden dosyalar, shared utility davranış değişikliği, API/contract kırılması
- Schema/migration etkileri, build/toolchain/dependency değişimleri

Hariç tutulanlar: düzenlenen dosyaların kendisi, meta-changelog, versiyon notları, Phase 4.5'te ele alınanlar.

**Plugin Çatışması — Provenance-First** (7.5.0)
İki plugin aynı satır için çelişen hüküm verirse:
- `[PLUGIN CONFLICT]` formatıyla her iki plugin'in gerekçesi gösterilir
- Geliştirici hangi fix'in uygulanacağına karar verir
- Karar rule-capture'ı tetikler (aynı çatışma türü tekrar çıkmaz)
- Otomatik "stricter wins" kaldırıldı

### Phase 5 — Doğrulama Raporu

**Spec Coverage Tablosu** (7.6.0)
`| Requirement | Test | Status |` — tüm MUST/SHOULD satırları.
- ✅: test dosya:satır ve fonksiyon adı gösterilir
- ⚠️: kısmen veya RED
- ❌: test yazılmadı
Yalnızca TDD bu session'da hiç koşmadıysa omit edilir.

**Automation Barriers** (7.6.0)
"YOU MUST TEST THESE" listesi artık call-graph tabanlı — spec keyword'lerine değil:
1. DOM API / render() / document.* → visual layout
2. HTTP fetch / third-party SDK — test mock yok → canlı API
3. Dosya yazma test temp dir dışı → filesystem side effect
4. Shell/subprocess — mock yok → OS side effect
5. Prod-only env var → production env bağımlılığı

Hiçbiri tetiklenmezse section tamamen omit edilir.

---

## Genel Mekanizmalar

### Anti-Sycophancy (7.3.4)
- **Verdict-first formatı**: Olumsuz bulgu varsa ilk cümlede söylenir
- **Proaktif firing**: Geliştirici sormadan da teknik sorun görülürse ilk cümlede yüzeylenir
- **Pressure resistance**: Yeni kanıt yoksa pozisyon korunur, sosyal baskıyla taviz verilmez
- **Self-critique loop**: Her yanıt öncesi 4 soru (Phase 4'te 5.), maks 3 iterasyon

### Kural Yakalama (Rule Capture)
Geliştirici bir fix'i genel kural yapmak istediğinde:
- Kapsam seçimi: yalnızca bu kez / bu proje / tüm projelerim
- Preview: İngilizce direktif + yerelleştirilmiş çeviri + hedef dosya yolu
- Onay beklenir, sonra yazar
- Çakışan kurallar gösterilir: "Overwrite, keep both, or cancel?"

### GATE Answer Coherence (7.7.0)
Mimari GATE cevabı alındıktan sonra teknik tutarlılık kontrolü.
Bkz. Phase 1 bölümü.

### Proje Hafızası (7.3.0)
`.mcl/project.md` — proje bilgi tabanı:
- Phase 1'de zaten bilinen sorular atlanır (stack, mimari, konvansiyonlar)
- Phase 5 sonrası güncellenir: Mimari kararlar, Teknik Borç ([ ]/[x]), Bilinen Sorunlar
- Açık `[ ]` madde varsa Phase 5 sonunda proaktif olarak sunulur (tek madde, asla liste döküme)

---

## Komutlar

| Komut | Açıklama |
|---|---|
| `/mcl-update` | MCL'yi git pull + setup.sh ile günceller |
| `/mcl-restart` | Tüm faz ve spec state'ini sıfırlar |
| `/mcl-finish` | Birikmiş Phase 4.6 etkilerini özetler + Semgrep taraması |
| `/mcl-doctor` | Token & maliyet raporu (7.8.0+) |
| `/mcl-checkup` | Sağlık kontrolü — tüm STEP'ler değerlendirilir |

---

## Token & Maliyet Muhasebesi (7.8.0)

- Her tur `FULL_CONTEXT` karakter sayısı `.mcl/cost.json`'a loglanır
- `/mcl-doctor` komutu:
  - MCL injection overhead (karakter → tahmini token)
  - Cache write (ilk tur) / cache read (sonraki turlar) maliyet dökümü
  - "MCL açık vs kapalı" karşılaştırması
  - Session oturum token özeti (son log'dan)
  - Sonnet 4.6 fiyatlandırması ($3/MTok input, $0.30/MTok cache read)

---

## Session & State Yönetimi

### State Dosyası (`.mcl/state.json`)
`phase_review_state` lifecycle:
```
null → "pending" (Phase 4 kodu yazıldı, 4.5 başlamadı)
     → "running"  (Phase 4.5 AskUserQuestion ilk çağrıldı)
     → null       (Phase 4.6/5 tamamlandı)
```
Bkz. `docs/state-schema.md` — tüm field tablosu.

### Session Log (`.mcl/log/*.md`)
Her Stop hook'unda tur özeti eklenir:
`Bu tur tamamlandı. | Tur: X token | Bağlam: Y / 200.000 | Kalan: Z`

### Phase 4.5 Session Recovery (`.mcl/risk-session.md`)
Her risk kararı sonrası yazılır, phase tamamlanınca silinir.

---

## Güvenlik & Sınırlama Kuralları

**Plugin Orkestrasyon**
- **Rule A**: Projede `.git/` yoksa tek seferlik onay alarak `git init`
- **Rule B**: Curated plugin'ler sessizce çalıştırılır; çatışmada provenance-first
- **Rule C**: MCP-server plugin'leri yasaklı; binary CLI araçlar (semgrep) izinli

**Execution Plan**
Yalnızca geri döndürülemez operasyonlarda (`rm -rf`, `git push --force`, `DROP TABLE` vb.) plan gösterilir. Diğer tüm operasyonlar sessiz ilerler.

**No Re-spec After Approval**
Spec onayı alındıktan sonra yeni spec bloğu veya Phase 1/2/3 yeniden çalıştırma yasaktır.

**Pasted CLI Passthrough**
Doğrudan shell komutu (`git clone URL`, `bash setup.sh`) yapıştırıldığında MCL Phase 1'i atlar, komutu doğrudan yürütür. Destructive operasyonlar yine de onay alır.

---

## Kurulum

```bash
git clone https://github.com/YZ-LLM/my-claude-lang.git ~/my-claude-lang
cd ~/my-claude-lang && bash setup.sh
```

`setup.sh` her çalışmada:
- Skill dosyalarını `~/.claude/skills/` altına kopyalar
- Hook'ları `~/.claude/hooks/` altına kopyalar
- `settings.json`'a hook kayıtlarını ekler
- README + skill + hook'lardaki versiyon string'lerini otomatik sync eder
