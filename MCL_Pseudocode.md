MCL Kuş Bakışı — Sözde Kod

  1. Üst Seviye Mimari

  KULLANICI ←──→ MCL (anlam doğrulama katmanı) ←──→ CLAUDE CODE (model + araçlar)
                │
                ├── 4 kanca (Claude Code'un çağırdığı bash dosyaları)
                ├── state.json (faz, spec onayı, vb.)
                ├── audit.log (sadece eklenen olay kaydı)
                ├── 22 faz tanımı (gate-spec.json)
                └── her faz için skill dosyası

  2. Kancalar — Ne Zaman Çalışır, Ne Yapar

  # Her kullanıcı mesajında — turun başında
  on UserPromptSubmit:
      mcl-activate.sh çalışır:
          - state.json oku (current_phase nedir?)
          - audit.log oku (hangi audit'ler yazılmış?)
          - Bildirimler hazırla:
              * <mcl_active_phase_directive>  → şu an aktif faz, ne yazılmalı
              * <mcl_phase_status>            → ilerleme: 3/8 risk çözüldü gibi
              * <mcl_phase_allowlist_escalate> → 5+ kez reddedildiyse kullanıcıya uyarı
              * Faza özel diğer bildirimler
          - STATIC_CONTEXT (sabit kurallar) + tüm bildirimler → modele gönder


  # Her araç çağrısından ÖNCE
  on PreToolUse(tool_name, tool_input):
      mcl-pre-tool.sh çalışır:
          if tool_name in [Read, Glob, Grep, LS, WebFetch, WebSearch, Task, Skill, Bash]:
              return İZİN_VER  # araştırma + audit yazma her zaman serbest
                                # (gate-spec: _global_always_allowed_tools)
                                # NOT: Bash buradan geçer ama state-mutating
                                # komutlar (mkdir, rm, npm install, git push,
                                # vb.) plugin gate'te ayrıca filtrelenir;
                                # mutating Bash yasaktır.

          # Katman B — fazın izin verdiği araç mı?
          aktif_faz = aktif_fazi_turet(state, audit_log)
          izinli_araclar = gate_spec[aktif_faz].allowed_tools
          if tool_name not in izinli_araclar:
              return REDDET("Aşama X'te bu araç yasak")  # 5+ kez reddedilirse kullanıcıya iletilir

          # Yol kısıtı (denied_paths)
          if file_path eşleşir gate_spec[aktif_faz].denied_paths:
              return REDDET("Bu yol Aşama X'te yasak")

          # Diğer korumalar:
          # - spec_approved=false → MCL LOCK
          # - sır/kimlik bilgisi taraması
          # - yıkıcı işlem yeniden onayı (rm -rf gibi)
          # - plugin kapısı (zorunlu plugin yoksa)
          return İZİN_VER


  # Her araç çağrısından SONRA
  on PostToolUse(tool_name, tool_input, tool_output):
      mcl-post-tool.sh çalışır:
          - TDD desen tespit (yol sezgisi):
              * test yolu → audit: tdd-test-write
              * üretim yolu → audit: tdd-prod-write
          - last_write_ts state'i güncelle (regression akıllı-atlamak için)
          - Frontend dosyası yazıldıysa ui_flow_active=true yeniden değerlendir
              audit: ui-flow-reevaluated
          - Bash test çalıştırıcı YEŞİL döndüyse regression_block_active=false
              audit: regression-guard-cleared


  # Model cevabını bitirince (her turun sonu)
  on Stop:
      mcl-stop.sh çalışır:
          # 1. Spec bloğu tespit
          if "📋 Spec:" son_assistant_mesajinda:
              spec_hash hesapla, state'e yaz

          # 2. AskUserQuestion onayını işle
          if model askq açtı + kullanıcı "Onayla" seçti:
              if niyet == "spec-approve":
                  state.spec_approved = true
                  state.current_phase = 5  # Aşama 5 (Desen Eşleştirme) — sıralı

          # 3. Faza özel mercekler:
          # - Aşama 6 sunucu-tarayıcısız (sunucu başlatıldı, tarayıcı açılmadı → engelle)
          # - Aşama 2 sıfır-kapı sentezleme (precision-audit yok ama summary var → otomatik üret)
          # - Aşama 10 zorlama (Aşama 9'da kod yazıldı, risk_review_state≠complete → engelle)
          # - Aşama 11-18 kalite+test boru hattı zorlaması (quality_review_state≠complete → engelle)
          # - Spec varlık denetimi (Edit/Write var ama spec bloğu yok → spec-required-warn)

          # 4. Universal completeness loop — sıralı faz ilerletme
          for tekrar in 1..22:
              faz = state.current_phase
              karar = gate_check(faz)  # gate-spec'e göre
              if karar == "complete":
                  audit yaz(asama-{faz}-complete, "stop-auto")
                  state.current_phase += 1
                  continue  # bir sonraki fazı dene
              elif karar == "incomplete":
                  break  # burada dur, model sonraki turda devam etmeli

          # 5. session-context.md yaz (oturumlar arası hafıza)
          # 6. project.md güncelle (Aşama 20 sonrası)

  3. 22 Fazlı Boru Hattı

  ────────────────────────────────────────────────────────────────────
  Aşama 1: Niyet Toplama
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Geliştiricinin ne istediğini netleştirmek. Hiçbir belirsizlik kalmasın.

  Ne yapar:
     Belirsizlik varsa tek tek soru sorar (her turda bir soru). Tüm
     değişkenler net ise tek bir özet hazırlar ve onay ister. JWT seçilip
     server-side state gerektiren akış tarif edilirse çelişkiyi yüzeye
     çıkarır, hangisini kastettiğini sorar.

  askq:
     "MCL X.Y.Z | Faz 1 — Niyet özeti onayı"

  Çıktı:
     summary-confirm-approve

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 2: Hassasiyet Denetimi
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Niyetin tam ve doğru olduğunu 7 boyutta doğrulamak. Spec yazmadan
     önce gözden kaçan kararları yakalamak.

  Ne yapar:
     7 temel boyutu sırayla gözden geçirir:
       1. Erişim hakkı / yetki
       2. Algoritmik hata modları
       3. Kapsam dışı sınırlar
       4. Kişisel veri (PII) işleme
       5. Audit / gözlemlenebilirlik
       6. Performans SLA
       7. Idempotency / yeniden deneme
     Her boyut için karar:
       * SILENT-ASSUME → endüstri varsayımı kullan, spec'te [assumed: X] işaretle
       * SKIP-MARK    → güvenli varsayım yok, spec'te [unspecified: X] bırak
       * GATE         → mimari etkili, geliştiriciye sor

  askq:
     "MCL X.Y.Z | Faz 2 — Precision-audit niyet onayı"

  Çıktı:
     precision-audit + asama-2-complete

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 3: Mühendislik Özeti
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Onaylı niyeti İngilizce mühendislik diline çevirmek (kullanıcı dili
     → İngilizce). Sıkı çevirmen — yorum yok, ekleme yok.

  Ne yapar:
     SESSİZ faz, askq yok. Doğal dil çevriliyor; teknik terimler aynı
     kalıyor. Belirsiz fiilleri cerrahi fiillere yükseltiyor:
       * "list / listele"     → "render a paginated table"
       * "manage / yönet"     → "expose CRUD operations"
       * "build / yap"        → "implement"
     Bu üst yükseltmeler [default: X, changeable] etiketiyle işaretlenir.
     YASAK: yeni varlık, özellik, NFR, auth, persistence eklemek.

  Çıktı:
     engineering-brief + asama-3-complete

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 4: Spec Yazımı + Onay
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Onaylı niyetten görünür bir İngilizce mühendislik spesifikasyonu
     üretmek + geliştirici onayı almak. Spec, sonraki tüm fazların tek
     gerçek kaynağı.

  Ne yapar:
     15+ yıl deneyimli kıdemli mühendis kalitesinde 📋 Spec: bloğu yazar.
     Zorunlu bölümler: Objective, MUST/SHOULD, Acceptance Criteria,
     Edge Cases, Technical Approach, Out of Scope. Tetiklenirse koşullu
     bölümler: Non-functional Requirements, Failure Modes, Observability,
     Reversibility/Rollback, Data Contract.
     Spec sonrası geliştirici diliyle 3-5 cümle özet sunar. Teknik sorun
     varsa (race condition, N+1, eksik auth) tek satırlık ⚠️ uyarı koyar.
     askq ile onay istenir.

  askq:
     "MCL X.Y.Z | Faz 4 — Spec onayı"

  Çıktı:
     asama-4-complete + asama-4-ac-count must=N should=M

  ↓ (state=5'e geçer — sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 5: Desen Eşleştirme
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Mevcut kodun adlandırma/hata-yakalama/test desenlerini öğrenmek.
     Aşama 9 TDD'de yazılan kod, mevcut kodla tutarlı görünsün.

  Ne yapar:
     Spec'teki dosya yollarına benzer mevcut dosyaları okur. Üç desen
     çıkarır:
       * Naming Convention (camelCase, snake_case, dosya adlandırma)
       * Error Handling Pattern (try/catch, Result type, hata sınıfları)
       * Test Pattern (test çatısı, fixture düzeni, naming)
     PATTERN_RULES_NOTICE olarak Aşama 9 boyunca her turda hatırlatılır.

  Atlama:
     Yeni proje (greenfield) veya benzer dosya yoksa atlanır.

  Çıktı:
     pattern-summary-stored | asama-5-complete | asama-5-skipped reason=greenfield

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 6: UI Yapımı (UI yoksa atlanır)
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Kullanıcı arayüzünü gerçek API/veritabanı bağlanmadan, sahte
     verilerle hayata geçirmek. Geliştirici hemen tarayıcıda görsün,
     onay vermeden backend yazılmasın.

  Ne yapar:
     Frontend dosyalarını yazar (React/Vue/Svelte/static HTML, stack'e
     göre). Sahte veri / fixture kullanır — gerçek API çağrısı YOK.
     Build config (vite/next/nuxt/tailwind/tsconfig) önce yazılır.
     npm install + npm run dev arka planda çalıştırılır. 2 saniye
     bekleyip tarayıcıyı OTOMATİK açar (open / xdg-open / start).
     Backend yazma KESİNLİKLE yasak (denied_paths: src/api/**,
     src/server/**, prisma/**, models/**, migrations/**).

  Atlama:
     Proje UI içermiyorsa (CLI, kütüphane, backend-only).

  Çıktı (3 seçenek, en az biri):
     * asama-6-complete (UI hazır)
     * asama-6-skipped reason=no-ui-flow (UI yoksa)
     * asama-6-end server_started=true browser_opened=true
       (sunucu+tarayıcı doğrulandı, KATI mod sertifikası)

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 7: UI İncelemesi (deferred — Aşama 6'ya bağlı)
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Geliştiricinin UI'ı tarayıcıda görüp onaylaması. Yanlışsa Aşama
     6'ya geri sarma şansı — backend yazılmadan önce.

  Ne yapar (6.5.0'dan beri DEFERRED):
     Aşama 6 dev server + browser auto-open ile biter ve STOP. Aşama 7
     askq önceden AÇILMAZ — geliştiricinin bir sonraki turn'undaki
     free-form cevabı intent classification ile yorumlanır:
       * approve cue'ları (14 dilde) → asama-7-complete, Aşama 8'e geç
       * revise cue'ları → Aşama 6'ya geri dön, geri bildirimle yeniden yaz
       * cancel cue'ları → pipeline durur
       * approve + revise birlikte (örn. "güzel ama büyüt") → revise kazanır
       * boş / tek emoji / ambiguous → fallback askq açılır (4 seçenek:
         Onayla / Revize / Sen-de-bak (opt-in Playwright + screenshot +
         multimodal Claude UI'a bakar) / İptal)

  Narration kuralı (v13.0.15):
     Aşama 7 deferred ≠ skipped. Faz listesi yazılırken DAİMA görünür
     kalır: "Aşama 5 → 6 → 7 (deferred) → 8 → 9". Sadece Aşama 6
     atlandığında "(atlandı — Aşama 6)" notuyla işaretlenir.

  Atlama:
     Aşama 6 atlandıysa otomatik atlanır (asama-7-skipped reason=
     asama-6-skipped).

  Çıktı:
     asama-7-complete | asama-7-skipped

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 8: Veritabanı Tasarımı (DB yoksa atlanır)
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Veriyi normalleştirme kurallarına uygun ve ileriye dönük sorun
     çıkarmayacak şekilde tasarlamak.

  Ne yapar:
     Şema yazar (genellikle 3NF; denormalization yapılırsa gerekçe
     belgelenir). Index stratejisi: sorgu desenlerinden türetilen
     covering index'ler. Sorgu planı: beklenen sıcak sorguların erişim
     yolu. Migration dosyaları (ORM kullanılıyorsa).

  Atlama:
     Veritabanı kapsamda yoksa.

  Çıktı:
     asama-8-end tables=N indexes=M migrations=K | asama-8-not-applicable
     reason=no-db-in-scope

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 9: TDD Yürütme
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Test-First geliştirme — kod yazılmadan önce her kabul kriteri için
     test yazılır, sonra kodu geçer hale getirilir.

  Ne yapar:
     Aşama 4'te sayılan her AC için sırayla:
       1. KIRMIZI: Önce başarısız olan test yaz, çalıştır → fail görsün
       2. YEŞİL:  Testi geçirecek MİNİMUM üretim kodu yaz, çalıştır → pass
       3. REFAKTÖR: Kodu temizle (DRY, isimlendirme, ölü kod), testler
                   hâlâ yeşil
     Sonda tam test takımı yeniden çalıştırılır.
     UI flow varsa, sahte veriden gerçek API'ye geçiş bu fazda yapılır
     (UI Aşama 6'da dummy data ile yazılmıştı).

  Çıktı (her AC için 3 audit):
     asama-9-ac-{i}-red, asama-9-ac-{i}-green, asama-9-ac-{i}-refactor

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 10: Risk İncelemesi (sınırsız soru)
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Kod yazıldıktan sonra atlanmış riskleri yüzeye çıkarmak — uç
     durumlar, gerilemeler, güvenlik/performans/UX/eşzamanlılık
     boşlukları.

  Ne yapar:
     Üç adım:
       1. Spec uyum öncül kontrolü: Her MUST/SHOULD karşılandı mı?
          Spec'in güvenlik/performans kararları doğru uygulandı mı?
       2. Atlanmış risk taraması: dört mercek (Code Review, Simplify,
          Performance, Security) eş zamanlı çalışır. Semgrep SAST
          HIGH/MEDIUM bulguları otomatik uygulanır.
       3. TDD yeniden doğrulama: tüm risk düzeltmeleri sonrası tam test
          takımı çalıştırılır.
     Her risk tek tek askq ile geliştiriciye sunulur:
       * Skip   → bu riski yok say
       * Fix    → spesifik düzeltmeyi uygula
       * Rule   → bunu kalıcı kural yap (Rule Capture)

  Çıktı:
     asama-10-items-declared count=K, her risk için
     asama-10-item-{n}-resolved decision=apply|skip|rule

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 11-14: Kalite Boru Hattı (4 ardışık faz)
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Yeni veya değişen dosyalarda kalite sorunlarını otomatik bulup
     düzeltmek. Her faz aynı tara → düzelt → yeniden tara döngüsünü
     çalıştırır.

  Ne yapar (her biri):
     1. Tara: faza özgü açıdan dosyaları gözden geçir, sorunları say (K)
     2. Düzelt: her soruna otomatik fix uygula (askq YOK, dialog YOK)
     3. Yeniden tara: yeni durum kontrolü, yeni K=0 olana kadar tekrar
        (en fazla 5 yeniden tarama)
↓ (sıralı)
  Aşama 11 — Kod İncelemesi:
     Doğruluk, mantık hataları, hata yakalama eksikliği, ölü kod,
     eksik validasyon, yanlış adlandırma.
↓ (sıralı)
  Aşama 12 — Sadeleştirme:
     Erken soyutlama, gereksiz karmaşa, duplikat mantık, gereksiz
     pattern'ler, "ileride lazım olur" kodu.
↓ (sıralı)
  Aşama 13 — Performans:
     N+1 sorgular, sınırsız döngüler, bloklayan I/O, bellek sızıntısı,
     gereksiz allocation.
↓ (sıralı)
  Aşama 14 — Güvenlik (TÜM proje genelinde):
     SQL injection, auth bypass, XSS, CSRF, hardcoded secret, sızıntı.
     semgrep SAST + npm audit (veya stack equivalent) otomatik koşar.
     HIGH/MEDIUM bulgular Aşama 10 risk dialogu'na escalate edilebilir.

  Audit deseni:
     asama-N-scan count=K, asama-N-issue-{n}-fixed,
     asama-N-rescan count=0

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 15-18: Test Yazımı (4 ardışık faz)
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Yeni veya değişen dosyalar için eksik testleri yazmak. Her faz
     test takımı YEŞİL olana kadar sürer.
↓ (sıralı)
  Aşama 15 — Birim Testler:
     Her yeni fonksiyon/sınıf/modül için unit test. Aşama 9 TDD
     testlerini de doğrular.
↓ (sıralı)
  Aşama 16 — Entegrasyon Testleri:
     Modüller arası akışlar, API endpoint'leri, veritabanı katmanı.
↓ (sıralı)
  Aşama 17 — Uçtan-uca Testler (E2E):
     UI varsa Playwright/Cypress headless ile gerçek kullanıcı akışları.
↓ (sıralı)
  Aşama 18 — Yük Testleri:
     Throughput-hassas yollar için k6/locust/ab. Spec NFR hedefini
     karşıladığı doğrulanır.

  Atlama:
     Code shape uygun değilse her faz "asama-N-not-applicable
     reason=<sebep>" yazıp atlar (ama audit emit zorunlu — sessiz
     atlama yok).

  Çıktı:
     asama-N-end-green | asama-N-end-target-met (Aşama 18 için)
     | asama-N-not-applicable

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 19: Etki İncelemesi (sınırsız soru)
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Yazılan kodun projenin DİĞER yerlerine olan downstream etkilerini
     bulmak. "Bu değişiklik başka neyi kırar?" sorusunun cevabı.

  Ne yapar:
     Gerçek etkileri arar, niyet beyanı değil:
       * Çağıran dosyalar (importerlar)
       * Davranışı değişen ortak yardımcılar
       * API/contract kırılması (cross-module sözleşmeler)
       * Şema/migration etkileri (mevcut veri)
       * Konfigürasyon değişiklikleri (diğer komponentleri etkileyen)
       * Cache invalidation, shared state
       * Build/toolchain/dependency kaymaları
     YASAK: Aşama 10'da çözülmüş riskleri tekrar etmek; "sadece bu
     turda yazılan dosyalar" listesi vermek; "bir sonraki sefere
     bakacağız" notu.
     Her etki tek tek askq ile geliştiriciye sunulur (skip/fix/rule).

  Çıktı:
     asama-19-items-declared count=K, her etki için
     asama-19-item-{n}-resolved

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 20: Doğrulama Raporu + Sahte Veri Temizliği
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Spec'teki her gereksinimin (MUST/SHOULD) hangi testle kapsandığını
     gösteren tablo + projeyi sahte veriden temizlemek.

  Ne yapar:
     Spec Coverage tablosu üretir:
       | Requirement | Test                       | Status         |
       | MUST: ...   | tests/auth.test.js:42      | ✅ green       |
       | SHOULD: ... | tests/foo.test.js:18       | ⚠️ partial     |
       | MUST: ...   | —                          | ❌ test yok    |
     Otomasyon Bariyerleri bölümü: yapısal olarak otomatize edilemeyen
     testler (DOM render, third-party API, üretim env var'ı) listelenir.
     Process Trace bölümü: trace.log'dan adım adım rapor.
     Mock data temizliği: __fixtures__/, geçici sahte veri sil.

  Çıktı:
     asama-20-complete + asama-20-mock-cleanup-resolved

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 21: Yerelleştirilmiş Rapor (atlanabilir)
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Aşama 20 raporunu kullanıcının diline çevirmek. Geliştirici
     İngilizce raporu okumak zorunda kalmasın.

  Ne yapar:
     Sıkı çevirmen geçişi (EN → kullanıcı dili). Yorum yok, ekleme yok.
     Teknik token'lar olduğu gibi korunuyor (file:line, test isimleri,
     timestamp, CLI flag).

  Atlama:
     İngilizce oturumda zaten İngilizce — kimlik fonksiyonu (boşa
     çevirmek anlamsız).

  Çıktı:
     asama-21-complete

  ↓ (sıralı)
  ────────────────────────────────────────────────────────────────────
  Aşama 22: Tamlık Denetimi
  ────────────────────────────────────────────────────────────────────
  Amaç:
     Tüm pipeline'ın gerçekten uçtan-uca tamamlandığını doğrulamak.
     Atlanan adımları yüzeye çıkarmak.

  Ne yapar:
     Üç dosyayı okur:
       * .mcl/audit.log
       * .mcl/state.json
       * .mcl/trace.log
     1-21 fazlarının her birinin doğru audit'lerini kontrol eder.
     Iki zorunlu derin denetim:
       * Aşama 9 TDD: her AC için 3 audit (red/green/refactor) var mı?
                     Test komutu YEŞİL döndü mü?
       * Aşama 11-18 boru hattı: her fazın start/end/rescan audit'leri
                                  tam mı?
     Atlanan veya eksik fazlar "Açık Konular" bölümünde yüzeye çıkar.

  Çıktı:
     asama-22-complete (kanca kendi yazar, model yazmaz)

  4. Bir Turun Tam Akışı (örnek)

  KULLANICI: "backoffice projesi yapacağım..."
    │
    ▼
  [mcl-activate.sh tetiklenir]
    → state.json: current_phase=1
    → <mcl_active_phase_directive> Aşama 1 yönergesi gönderilir
    → STATIC_CONTEXT + tüm bildirimler
    │
    ▼
  [Claude modeli cevap üretir]
    Model: AskUserQuestion("MCL 13.1.0 | Faz 1 — Niyet özeti onayı: ...")
    │
    ▼
  [mcl-pre-tool.sh tetiklenir — AskUserQuestion]
    → Katman B: Aşama 1 allowed_tools = [AskUserQuestion]  ✓
    → İZİN_VER
    │
    ▼
  [askq arayüzde gösterilir, kullanıcı "Onayla" tıklar]
    │
    ▼
  [mcl-stop.sh tetiklenir]
    → askq tool_use/tool_result çiftini yakalar
    → state.current_phase = 2 (Hassasiyet Denetimi — sıralı, v13.0.11 düzeltmesi)
    → Audit: summary-confirm-approve

  Not: Eğer Stop kanca bunu kaçırırsa, bir sonraki PreToolUse'da
  pre-tool.sh'in JIT askq advance mekanizması (line ~744) yedek olarak
  aynı state ilerletmeyi yapar.
    │
    ▼
  [Sonraki kullanıcı mesajında veya devam turunda]
    → mcl-activate.sh: aktif faz=2 → Aşama 2 yönergesi gönderilir
    → Model hassasiyet denetimi yapar, asama-2-complete yazar
    → Universal completeness loop 2→3→4'e ilerletir (audit zinciri tamsa)
    → Model spec yazar + Faz 4 askq açar
    → Kullanıcı onaylar
    → state.current_phase = 5 (Desen Eşleştirme, sıralı)
    → ... böyle 22'ye kadar devam

  5. Önemli Mekanizmalar

  DSI (Dynamic Status Injection):
     Her turun başında aktif faz odağını gönderir — model "ortada kaybolma"
     yaşamasın. PHASE_META'dan aktif faz görev/emit/skip cue'ları + faz
     index tablosu render edilir.

  Persuasion Manifesto (v13.0.16):
     <mcl_core> açılışında "WHY THESE 22 PHASES — this pipeline works WITH
     you, not against you" başlıklı 8 satırlık ikna bloğu. Her atlamanın
     modele *maliyetini* (rewrite, retry) somut örneklerle anlatır. Negative
     framing yerine positive incentive — model train data'sındaki "niyet
     anlaşıldı → kod yaz" priorını dengeler. İngilizce (model ağırlıkları
     İngilizce daha güçlü çalışır).

  Katman B (Faz İzin Listesi) — v13.1.0 always-fire:
     Her fazda sadece o fazın "allowed_tools" listesi izinli. v13.1.0:
     REASON koşulu kaldırıldı — Layer B her tool çağrısında fire eder, allowlist
     ihlali pre-set REASON'ı override eder. Fail-closed: gate-spec'te
     allowed_tools field yoksa mutating tool DENY (eski varsayılan: allow,
     sızıntı kapısıydı). Debug audit her fire'da: phase-allowlist-check |
     tool=X phase=N verdict=<deny:tool|deny:path|allow>.

  Spec-Approve Audit Chain (v13.0.14 + v13.0.17 auto-fill):
     Aşama 4 spec-approve advance için audit zinciri şart:
     summary-confirm-approve + asama-2-complete + asama-3-complete. v13.0.17:
     developer "Onayla" demişse chain incomplete olsa bile MCL eksik
     audit'leri "auto-fill-spec-approve" markıyla emit eder, advance fire
     eder (deadlock kırma — model bypass'a yelteniyordu).

  Universal Completeness Loop:
     Stop kancasında gate-spec'e göre sıralı faz ilerletme
     Audit'ler tamsa otomatik ilerler, yoksa o fazda durur

  Audit-Driven Active Phase Resolver (v13.0.10):
     state.current_phase eski 7 sentinel ise audit'ten gerçek fazı türet
     v13.0.11 sonrası state hep gerçek değer tutuyor — çözücü gereksizleşti
     ama dokunulmadı (savunma yedek)

  Aşama 6 Sunucu-Tarayıcısız Merceği (v13.0.6/0.8):
     KATI — sunucu başlatıldıysa tarayıcı açma zorunlu, otomatik açılma yok

  Aşama 7 Deferred Narration Rule (v13.0.15):
     Aşama 7 deferred olsa bile faz listesinden ASLA atlanmaz. Skill +
     DSI header_directive + PHASE_META[7].narration üç katmandan enforce.
     Yasak: "Aşama 5 → 6 → 8 → 9". Doğru: "Aşama 5 → 6 → 7 (deferred) → 8".

  Spec Varlık Denetimi:
     Edit/Write/MultiEdit çağrıldı ama assistant mesajında 📋 Spec: bloğu
     yok → Stop kancası spec-required-warn audit yazar
     (uyarı amaçlı, /mcl-checkup'ta görünür)

  TDD Uyumluluk Skoru:
     Post-tool tdd-test-write + tdd-prod-write olaylarını sayar; testin
     üretim kodundan önce yazılma oranını state.tdd_compliance_score'a
     yazar (0-100). Aşama 22 denetiminde değerlendirilir.

  Devtime/Runtime REASON Split (v13.0.13):
     Hook block REASON'ları iki dilde tutulur: devtime (uzun İngilizce
     debug — MCL geliştirenler için) + runtime (kısa Türkçe — son
     kullanıcı için). _mcl_is_devtime helper CLAUDE_PROJECT_DIR'a göre
     seçer. Production session'da kırmızı "Error:" panik yumuşatılır.

  Plugin Orkestrasyon (Kural A / B / C):
     A: Yerel git deposu güvencesi (ilk açılışta git init onayı)
     B: Seçilmiş plugin'ler (feature-dev, code-review, pr-review-toolkit,
        security-guidance) sessizce çağrılır; çatışma → tek bir Aşama 10
        risk maddesi
     C: MCP-server plugin'leri yasak (.mcp.json içeren plugin seçim
        sırasında elenir)

  6. Kaçış Valfleri

  Tüm /mcl-* slash komutları mcl-activate.sh'da PROMPT_NORM dize
  eşleştirmesiyle yakalanır (ayrı komut dosyası değil, kanca-tespitli anahtar
  kelime).

  1. Audit yazma kurtarma yolu:
     bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log <ad> <çağıran> "<detay>"'
     Model askq açamadığında veya state takıldığında elle ilerletme.

  2. /mcl-restart:
     Tüm state'i sıfırla, faz=1'e dön. MCL_RESTART_MODE dalı.

  3. /mcl-update:
     git pull + setup.sh — yeni MCL sürümü. MCL_UPDATE_MODE dalı.

  4. /mcl-version:
     Kurulu MCL sürümünü göster.

  5. /mcl-doctor:
     Token & maliyet raporu (cost.json okur).

  6. Loop-breaker:
     Bazı engellerde 3 ardışık reddetme → otomatik açılma + audit uyarısı
     (eski mekanizma). v13.1.0 sonrası Katman B'de otomatik açılma YOK —
     blok kalkmaz, audit uyarısı kullanıcıya iletilir.

  7. /mcl-checkup:
     Tüm fazların durumunu salt-okunur rapor olarak göster.

  8. /mcl-finish:
     Birikmiş Aşama 19 etkilerini bir kontrol noktasında topla, proje
     düzeyinde bitirme raporu üret.

  9. Diğer slash komutları:
     /mcl-cost, /mcl-dispatch, /mcl-dsi, /mcl-log, /mcl-plugin,
     /mcl-rollback, /mcl-self, /mcl-semgrep, /mcl-stack, /mcl-state,
     /mcl-tag, /mcl-test, /mcl-trace — her biri activate hook'ta
     PROMPT_NORM string match ile yakalanır, faza özel kısa cevaplar
     veya state inceleme amaçlıdır.

  7. Tek Cümleyle MCL

  ▎ Model her turda 22 fazlı sıralı boru hattının tam olarak hangi fazında
  ▎ olduğunu bilir, fazın izinli araç listesini Katman B zorlar, faz
  ▎ tamamlanma audit-tabanlı olarak kanca tarafından otomatik yapılır,
  ▎ kaçış valfleri sıkışmaları açar.
