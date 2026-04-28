# Değişiklik Günlüğü

[Keep a Changelog](https://keepachangelog.com) formatı. Her yeni sürümde
`[Unreleased]` bölümü `[X.Y.Z] - YYYY-MM-DD`'ye dönüştürülür.

---

## [Unreleased]

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
