# Root Cause Discipline — Kararlar

MCL'de kök sebep bulma ve müdahale ile ilgili tüm kararların özeti.
Bu doküman hem CLAUDE.md (devtime) hem Phase 4 Root Cause Chain
(runtime) için referanstır.

---

## 1. Temel düstur

Bir sorunu çözerken yüzeyde kalma. "Bu neden böyle?" sorusunu sor.
Cevap geldiğinde tekrar sor: "Peki bu neden böyle?" En derine kadar git.
Bazen en alttaki sebebi çözmek tüm ağı çözer.

Bu hem geliştirme sırasında (sen + Claude Code), hem MCL kullanıcısının
projelerinde (Phase 4 Root Cause Chain) uygulanır. Atlanması yasak —
anti-sycophancy seviyesinde temel mekanizma.

---

## 2. Zincir nasıl ilerler

Tek seviyeli sebep arama yetmez. Çok seviyeli zincir kurulur:

- İlk sebep bulunur
- "Bu sebebin de kök sebebi var mı?" diye sorgulanır
- Yapısal alt tabana inene kadar devam edilir
- Her halka, bir sonrakine geçmeden önce doğrulanır

---

## 3. Her halka doğrulama — üç check, sıralı

Bir halkadan sonrakine geçmeden önce üç check **sıralı** uygulanır.
Paralel değil. Bir önceki geçmeden sonrakine geçilmez.

### 3.1 Görünür süreç
Hangi adımları izleyerek bu halkaya geldin? Açıkça yaz, gizli kalmasın.
Düşünce zinciri görünür olmalı.

### 3.2 Removal test
"Bu sebep ortadan kalksa, üst halkadaki problem çözülür mü?"
Cevap "evet" değilse, sebep yanlış — geri dön, başka yol dene.

### 3.3 Falsification
"Bu sebep doğruysa, başka şu da gözlemlenmeli."
Bekleneni kontrol et. Gözlemlenmiyorsa, sebep yanlış — geri dön.

**Önemli kısıt:** Falsification'da "X gözlemlenmeli" cümlesindeki X
**kontrol edilebilir** olmalı: kodda görünür, log'da görünür, davranışta
görünür, dosyada görünür. Soyut "X olmalı" yetmez. Eğer X kontrol
edilemezse, falsification check'i geçersiz, halka şüpheli sayılır.

---

## 4. Halka geçişi sonucu

Üç check'in sonucuna göre:

- **Üçü de geçti** → zincir bir adım daha derine inebilir
- **Biri fail etti** → ya yanlış halkadayız (geri dön ve farklı yol dene),
  ya da kök sebep zaten bu (zincir burada biter)

Erken yakalama ilkesi: bu üç check **zincirin sonunda değil, her halkada**
uygulanır. Sondaki tek kontrol labirentte sapmayı geç fark eder; her
halka kontrolü erken yakalar.

---

## 5. Edge case — zincir tıkandığında

Pratikte zincir 2-3 halkada biter. Ama nadiren ciddi bir sıkıntı çıkar:
zincir uzuyor ama netleşmiyor, alternatif sebepler tükeniyor, kontrol
alanı dışına çıkılıyor.

Bu durumda MCL kullanıcıya **açık, net, kısa** anlatır. Soyut çözüm
üretmez, halüsine etmez. Örnek: "Kök sebep şu noktaya kadar takip
edildi, ötesi şu sebeple belirsiz."

Over-engineer edilmiş çıkış koşulları, geri dönüş protokolleri kurulmaz.
Sıkıntı çıkarsa şeffaflık yeterli.

---

## 6. Müdahale noktası seçimi — en kritik kural

Zincir sonunda kök sebep bulunduğunda, **hemen değiştirme**.

Önce müdahalenin tüm etkilerini tahmin et — Phase 4 (impact lens) mantığıyla:
- Bu sebebi import eden dosyalar
- Shared utility davranış değişikliği
- API/contract kırılması
- Schema/migration etkileri
- Downstream tüketiciler
- Build/toolchain/dependency değişimleri

### Kural: sıfır yan etki halkası

Eğer **bir tek** etki başka yere dokunuyorsa, o halka müdahale noktası
değil. Bir üst halkaya çık, oranın etkilerini tahmin et. Hiç etki
yaratmayan halkaya kadar yukarı çık.

**Müdahale noktası:** kök sebebe en yakın, sıfır yan etki üreten halka.
Temiz iş bu olur.

### Mantık

Bir işi yaparken diğerine etki etmemek gerekiyor. Kök sebep her zaman
doğru müdahale noktası değil — en alttaki sebebi düzeltmek tüm sistemi
kıracak yan etkilere yol açabilir. Phase 4 (impact lens)'nın felsefesi (yan etki
tahmini) kök sebep zincirine de uygulanıyor; ikisi aynı disiplin.

---

## 7. Kök sebep + çözüm raporu

Müdahale noktası belirlendiğinde, hem **kök sebep** hem **önerilen
çözüm** raporlanır. Tek başına kök sebep yetmez — kullanıcı "tamam
anladım" der ama düzeltme yapılmaz.

Çözüm ayrı bir doğrulama gerektirir: "bu çözüm uygulanırsa kök sebep
ortadan kalkar mı?" — yes/no kontrolü.

Phase 4 risk item'ı olarak ikisi birlikte sunulur:
- Yüzeysel semptom değil, en derin yapısal sebep (veya seçilen müdahale
  halkası)
- Önerilen çözüm
- Çözüm doğrulama sonucu

---

## 8. Kapsam

Hem **devtime** (sen + Claude Code arası MCL geliştirme), hem **runtime**
(Phase 4 Root Cause Chain — MCL kullanıcısının projelerinde) bu
disiplin uygulanır.

Atlanması yasak. Anti-sycophancy ile aynı seviyede temel mekanizma.

---

## 9. Özet — tek paragraf

Bir sorun bulunduğunda, kök sebep zinciri kurulur. Her halka üç
check'ten geçer (görünür süreç → removal test → falsification);
sıralı, paralel değil. Üçü geçerse derine inilir, biri fail ederse
geri dönülür. Zincir tıkanırsa kullanıcıya açıkça söylenir, halüsine
edilmez. Kök sebep bulunduğunda hemen değiştirilmez — etkileri tahmin
edilir. Bir tek etki başka yere dokunuyorsa, üst halkaya çıkılır.
Müdahale noktası: sıfır yan etki üreten halka. Sonra kök sebep ve
çözüm birlikte raporlanır.
