```
Sen (kendi dilinde)
  │
  ▼
Aşama 1: MCL ne istediğini anlamak için tek tek soru soruyor.
         Hiçbir belirsizlik geçemiyor. Özeti onaylıyorsun.
         MCL aynı zamanda mimari cevaplarını da sorgulayabilir:
         "JWT" deyip sunucu tarafı oturum akışı tarif edersen,
         MCL çelişkiyi yüzeye çıkarır ve spec yazmadan önce
         hangisini kastettiğini sorar.
  │
  ▼
Aşama 2: 7 boyutlu precision audit + hard enforcement ile
         niyetin doğruluğunu ve tamlığını doğrular.
  │
  ▼    
Aşama 3: Onaylanan niyetin katı bir çevirmen
         geçişinden (kullanıcı dili → EN) geçiyor. Yorum yok,
         ekleme yok — sadece doğal dil çevriliyor; teknik terimler
         olduğu gibi kalıyor. Ortaya çıkan İngilizce Engineering
         Brief, spec üretiminin tek girdisi oluyor.
  │
  ▼
Aşama 4: Onaylanan niyetin, görünür bir İngilizce teknik
           spesifikasyona (📋 Spec:) dönüşüyor — 15+ yıl deneyimli
           kıdemli bir mühendis gibi yazılıyor — ve MCL spec'i
           sana kendi dilinde açıklıyor; ikisi aynı turda, tek
           AskUserQuestion onayıyla. Spec bloğu daraltılabilir —
           okuduktan sonra tıklayarak küçültebilirsin.

  │
  ▼
Aşama 5: Pattern Matching yapılır. proje yeni yaratılıyorsa atlanır.
  │
  ▼
Aşama 6: UI yüzeyi tespit edildiğinde (varsayılan: ON), Aşama 6 üçe bölünür:
              ├─ 6a BUILD_UI  — sadece dummy data ile çalışır frontend.
              │                 Çalıştırma komutu verilir; MCL tarayıcıyı açar.
              ├─ 6b UI_REVIEW — backend başlamadan önce UI'ı onaylarsın.
              │                 Opt-in Playwright görsel incelemesi mevcut.
              └─ 6c BACKEND   — gerçek API çağrıları, data layer, async bağlantı.
                                Yalnızca UI onayından sonra çalışır.
  │
  ▼                           
Aşama 7: Kod yazılıyor. Bu aşamanın içinde kademeli TDD
         çalışıyor — her kabul kriteri için: bir failing test
         (RED), onu geçecek minimum kod (GREEN), ardından refactor.
         Döngü her kriter için tekrar eder; sonda tam suite tekrar
         koşulur.

  │
  ▼
Aşama 8: (Risk İncelemesi): MCL, spec'te tasarlanan güvenlik ve
         performans kararlarının doğru uygulandığını doğrular; ardından
         atlanmış riskleri tarar — uç durumlar, gerilemeler — ve her
         birini seninle tek tek konuşur. Risk düzeltmeleri bittikten
         sonra TDD testleri yeniden koşar: hepsi yeşil → geçer; kırmızı
         → ilgili kod düzeltilir; çelişki → sen karar verirsin.
  │
  ▼
Aşama 9:  code review
          Simplify
          Performans
          Güvenlik
          unit test, integration test, E2E test, yük testi. 
          sırasıyla bunlar yapılır.
  │
  ▼
Aşama 10: (Etki İncelemesi): MCL projenin geri kalanını,
         değişikliğin gerçek downstream etkileri için tarıyor —
         çağıranlar, ortak yardımcılar, şema/API kaymaları — ve
         her birini senin kararın için önüne koyuyor.
  │
  ▼
Aşama 11: Doğrulama Raporu — Spec Kapsama tablosu (her MUST/SHOULD
         gereksinimi, onu kapsayan teste bağlı: ✅ dosya:satır ile,
         ⚠️ kısmi, ❌ test yazılmamış).
  │
  ▼
Aşama 12: Tam İngilizce rapor, katı çevirmen geçişiyle (EN →
         kullanıcı dili) senin diline çevriliyor — yorum yok,
         ekleme yok. Teknik tokenlar (dosya:satır, test isimleri)
         olduğu gibi korunuyor.
```