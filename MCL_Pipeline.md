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
Aşama 5: Pattern Matching yapılır. Proje yeni yaratılıyorsa
         atlanır.
  │
  ▼
Aşama 6: Front-end dummy data ile yapılır. Proje ve tüm bağımlılıkları ayağa kaldırılır. Proje otomatik olarak tarayıcıda açılır.
  │
  ▼
Aşama 7: UI'ı incelersin. Güncelleme gerekiyorsa MCL'e söylersin.
         Opt-in Playwright görsel incelemesi mevcut. İstersen onu da yaptırabilirsin ama maliyetlidir.
  │
  ▼
Aşama 8: DB yi normalizasyon kurallarına uygun ve ileriye dönük sorun çıkarmayacak şekilde tasarlar. index strategy ve query plan gibi gerekli bütün adımları uygular.
  │
  ▼
Aşama 9: Test-first geliştirme (TDD). Her kabul kriteri için
         ÖNCE failing test yazılıyor (RED), SONRA onu geçecek
         minimum production kod (GREEN), ardından refactor. Döngü
         her kriter için tekrar eder; sonda tam suite tekrar
         koşulur. Test her zaman production kodun önünde gelir —
         "kod yaz sonra test ekle" değil, gerçek TDD.
  │
  ▼
Aşama 10: (Risk İncelemesi): MCL, spec'te tasarlanan güvenlik ve
         performans kararlarının doğru uygulandığını doğrular; ardından
         atlanmış riskleri tarar — uç durumlar, gerilemeler — ve her
         birini seninle tek tek konuşur. Risk düzeltmeleri bittikten
         sonra TDD testleri yeniden koşar: hepsi yeşil → geçer; kırmızı
         → ilgili kod düzeltilir; çelişki → sen karar verirsin.
  │
  ▼
Aşama 11: Yeni ya da değişen dosyalara code review yapılır. bulunan sorunlar otomatik düzeltilir.
  │
  ▼
Aşama 12: Yeni ya da değişen dosyalara Simplify yapılır. bulunan sorunlar otomatik düzeltilir.
  │
  ▼
Aşama 13: Yeni ya da değişen dosyalara performans kontrolü yapılır. bulunan sorunlar otomatik düzeltilir.
  │
  ▼
Aşama 14: Tüm projeye güvenlik kontrolü (security vulnerability check) yapılır. bulunan sorunlar otomatik düzeltilir.
  │
  ▼
Aşama 15: Yeni ya da değişen dosyalara unit test ve TDD testleri yapılır. bulunan sorunlar otomatik düzeltilir.
  │
  ▼
Aşama 16: Yeni ya da değişen dosyalara integration test yapılır. bulunan sorunlar otomatik düzeltilir.
  │
  ▼
Aşama 17: Yeni ya da değişen dosyalara E2E testi yapılır. bulunan sorunlar otomatik düzeltilir.
  │
  ▼
Aşama 18: Yeni ya da değişen dosyalara yük testi yapılır. bulunan sorunlar otomatik düzeltilir.
  │
  ▼
Aşama 19: (Etki İncelemesi): MCL projenin geri kalanını,
         değişikliğin gerçek downstream etkileri için tarıyor —
         çağıranlar, ortak yardımcılar, şema/API kaymaları — ve
         her birini senin kararın için önüne koyuyor.
  │
  ▼
Aşama 20: Doğrulama Raporu — Spec Kapsama tablosu (her MUST/SHOULD
          gereksinimi, onu kapsayan teste bağlı: ✅ dosya:satır ile,
          ⚠️ kısmi, ❌ test yazılmamış).  Mock data projeden silinir.
  │
  ▼
Aşama 21: Tam İngilizce rapor, katı çevirmen geçişiyle (EN →
          kullanıcı dili) senin diline çevriliyor — yorum yok,
          ekleme yok. Teknik tokenlar (dosya:satır, test isimleri)
          olduğu gibi korunuyor.
  │
  ▼
Aşama 22: Tamlık Denetimi — `.mcl/audit.log` okunup her fazın
          1-21 gerçekten uçtan uca tamamlandığı doğrulanır. Açık Konular bölümü pipeline'ın
          atladığı boşlukları yüzeye çıkarır.
