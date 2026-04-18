# my-claude-lang 🌐 MCL 5.4.3

### Gerçek AI çağı İngilizce konuşmuyor. Senin dilini konuşuyor.

---

Bugüne kadar dünyanın en iyi AI kodlama araçlarını kullanmak için İngilizce bilmen gerekiyordu. Artık gerekmiyor.

**my-claude-lang**, Claude Code için bir eklenti. Yazılımı kendi ana dilinde geliştirmeni sağlıyor — sıfır İngilizce bilgisiyle. Ayar yok. Dil seçimi yok. Sadece konuşmaya başla. O anlıyor.

Bu bir çevirmen değil. Çevirmenler kelimeleri çevirir. my-claude-lang **anlamı** çevirir.

### 5.0.0'dan itibaren — Evrensel Aktivasyon

my-claude-lang artık sadece İngilizce bilmeyenler için değil. MCL **her** mesajda devreye giriyor — İngilizce dahil — çünkü anlam doğrulama, kıdemli mühendis kalitesinde spec üretimi ve anti-yalakalık, kaynak dilden bağımsız olarak değerli. İngilizce bilmeyen kullanıcı için çeviri köprüsü de çalışmaya devam ediyor; İngilizce kullanıcı için çeviri katmanı identity'ye düşüyor, ama diğer tüm katmanlar (faz kapıları, öz-eleştiri, disambiguation, Faz 5 doğrulama) tamamen çalışıyor.

---

## Kimsenin Konuşmadığı Sorun

Claude Code dünyanın en güçlü AI kodlama aracı. Kıdemli bir mühendis gibi planlıyor, koddan önce test yazıyor, kendi işini inceliyor ve production-kalitesinde yazılım çıkarıyor.

Ama İngilizce düşünüyor. Ve İngilizce bilmiyorsan, tüm bunların dışındasın.

Çevirmen kullanabilirsin. Ama isteğini İngilizce'ye çevirip Claude Code'a yapıştırdığında şu oluyor:

- Niyetin düz kelimelere düşüyor
- İncelikler kayboluyor — "hızlı olsun" hıza dönüşüyor, sadeliğe değil
- Bağlam buharlaşıyor — kısıtlamaların, tercihlerin, "tabii ki şunu kastediyordum..." — hepsi gidiyor
- Teknik olarak doğru ama yanlış şeyi yapan kod alıyorsun
- Saatlerce, token'larca, sabrınla ödüyorsun

**my-claude-lang var çünkü çeviri, anlama değildir.**

---

## my-claude-lang Gerçekte Ne Yapıyor

Tek bir satır kod yazılmadan önce **beş aşamalı karşılıklı anlama döngüsü** kuruyor:

```
Sen (kendi dilinde)
  │
  ▼
Aşama 1: MCL ne istediğini anlamak için tek tek soru soruyor.
         Hiçbir belirsizlik geçemiyor. Özeti onaylıyorsun.
  │
  ▼
Aşama 2: Onaylanan niyetin, görünür bir İngilizce teknik
         spesifikasyona (📋 Spec:) dönüşüyor — 15+ yıl deneyimli
         kıdemli bir mühendis gibi yazılıyor. Görüyorsun. Onaylıyorsun.
  │
  ▼
Aşama 3: MCL spec'i sana kendi dilinde açıklıyor.
         Claude'un doğru anlayıp anlamadığını doğruluyorsun.
  │
  ▼
Aşama 4: Kod yazılıyor. Claude Code'un çalışma sırasında sana
         sorduğu her soru köprüden geçiyor — NEDEN sorduğunu
         ve hangi cevabın NE değiştireceğini açıklayarak.
  │
  ▼
Aşama 5: Sonuçlar sadece listelenmez, açıklanır.
         Ne inşa edildiğini ve neden öyle yapıldığını anlıyorsun.
```

**Hiçbir belirsizlik bu döngüden sağ çıkamaz.** Her kapıda "hayır" diyebilirsin ve MCL geri dönüp düzeltir. Senin açık "evet"in olmadan hiçbir şey ilerlemez.

Her yanıt `🌐 MCL 5.4.3` ile başlıyor — böylece köprünün aktif olduğunu her zaman biliyorsun.

---

## Kör Cevaplar Değil, Bilinçli Kararlar

Claude Code sana çalışma sırasında bir soru sorduğunda, MCL sadece çevirmekle kalmıyor. Şunları da ekliyor:

1. **Bu soru neden soruluyor** — Claude neye karar vermek istiyor
2. **Hangi cevap ne değiştirir** — cevap vermeden önce sonuçlarını biliyorsun

Asla tahmin etmiyorsun. Tam bağlamla karar veriyorsun — sanki kıdemli bir mühendis her karar noktasını senin dilinde açıklıyor.

---

## Kanıtlanmış Sonuçlar: İngilizce Yazmaktan Bile Daha İyi

MCL'yi 13 dilde test ettik ve sonuçları 15+ yıl deneyimli kıdemli bir İngilizce mühendise aynı isteği doğrudan İngilizce yazdırdığımızdaki çıktıyla karşılaştırdık.

**Sonuç: 2 EŞIT, 11 MCL DAHA İYİ.**

MCL sadece İngilizce mühendis kalitesine yetişmiyor — 13 dilin 11'inde **daha iyi** spec üretiyor.

| # | Dil | Kıdemli Mühendise Karşı | Neden |
|---|-----|------------------------|-------|
| 1 | 🇹🇷 Türkçe | EŞIT | Optimize edilmiş — MCL Türkçe üzerinde geliştirildi |
| 2 | 🇯🇵 Japonca | EŞIT | Japonca zaten kesin ve yapılandırılmış |
| 3 | 🇩🇪 Almanca | **MCL DAHA İYİ** | Daha fazla edge case yakalıyor |
| 4 | 🇨🇳 Çince | **MCL DAHA İYİ** | Analojileri somut spec'lere kırıyor |
| 5 | 🇰🇷 Korece | **MCL DAHA İYİ** | Kültürel ifadeleri koruyor |
| 6 | 🇪🇸 İspanyolca | **MCL DAHA İYİ** | Olumsuzlamayı pozitif spec'e çeviriyor |
| 7 | 🇫🇷 Fransızca | **MCL DAHA İYİ** | Başkalarının kaçırdığı belirsizliği fark ediyor |
| 8 | 🇮🇩 Endonezyaca | **MCL DAHA İYİ** | Belirsiz terimleri çalıştırmadan önce çözüyor |
| 9 | 🇸🇦 Arapça | **MCL DAHA İYİ** | Eksik detayları tamamlıyor |
| 10 | 🇧🇷 Portekizce | **MCL DAHA İYİ** | Teknik homonimleri + denetim izini yakalıyor |
| 11 | 🇷🇺 Rusça | **MCL DAHA İYİ** | Gizli alt görevleri parçalıyor |
| 12 | 🇮🇳 Hintçe | **MCL DAHA İYİ** | Belirsiz isteklerde gizlilik endişelerini işaretliyor |
| 13 | 🇮🇱 İbranice | **MCL DAHA İYİ** | Yetkilendirme modellerini netleştiriyor |

### Neden Bu 13 Dil?

Bu diller dünyanın ana yazı sistemi ailelerini temsil etmek için seçildi:

- **Latin** — Türkçe, Almanca, İspanyolca, Fransızca, Endonezyaca, Portekizce
- **CJK** — Çince (Hanzi), Japonca (Kanji + Hiragana + Katakana), Korece (Hangul)
- **Kiril** — Rusça
- **Devanagari** — Hintçe
- **Arap yazısı (sağdan sola)** — Arapça
- **İbrani yazısı (sağdan sola)** — İbranice

Bu, dünyanın geliştiricilerinin büyük çoğunluğunun kullandığı yazı sistemi ailelerini kapsıyor — soldan sağa, sağdan sola, karakter tabanlı ve hece tabanlı sistemler. MCL bunların hepsinde çalışıyorsa, senin dilinde de çalışır.

### MCL Neden İngilizce'yi Geçiyor?

Çünkü avantaj dilsel değil — **prosedürel**.

Kıdemli bir mühendis İngilizce "Build a notification system" yazıyor ve Claude kodlamaya başlıyor. Belki Claude netleştirici sorular soruyor. Belki sormuyor. **Garantisi yok.**

MCL belirsizlik çözmeyi **zorunlu** kılıyor, opsiyonel değil:
- Her belirsiz terim sorgulanıyor
- Her gizli alt görev yüzeye çıkarılıyor
- Her kültürel ifade çözümleniyor
- Tek bir satır kod yazılmadan önce her varsayım doğrulanıyor

**MCL, Claude'a senin dilini öğretmiyor. Claude'a mühendislik disiplini dayatıyor. Ve bu, tek başına İngilizce'den daha iyi sonuç üretiyor.**

---

## Kurulum

Klonla, tek komut çalıştır. Bitti. Ayar yok. Dil seçimi yok.

```bash
git clone https://github.com/umiteknoloji/my-claude-lang.git
bash my-claude-lang/setup.sh
```

Bu her şeyi global olarak kurar:
- **Skill dosyaları** → `~/.claude/skills/my-claude-lang/` (MCL kuralları, kapılar, fazlar)
- **Otomatik aktivasyon hook'u** → `~/.claude/hooks/mcl-activate.sh` (İngilizce olmayan girdiyi algılar)
- **Hook konfigürasyonu** → `~/.claude/settings.json` (hook'u Claude Code'a bağlar)

Yeni bir Claude Code oturumu aç ve kendi dilinde yazmaya başla. Hepsi bu.

---

## Güncelleme

MCL, pasif bir güncelleme kontrolü ve tek kelimeyle self-update özelliğiyle gelir.

Hook, 24 saatte bir arka planda repodaki `VERSION` dosyasını çeker. Yeni sürüm varsa, her yanıttaki banner'ın yanında senin dilinde lokalize bir uyarı belirir, örneğin:

```
🌐 MCL 5.4.1 (⚠️ 5.4.2 mevcut — mcl-update yaz)
```

Güncellemek için mesaj olarak sadece `mcl-update` yaz. MCL normal akışı (spec, fazlar) tamamen atlar ve şu komutu çalıştırır:

```
cd $MCL_REPO_PATH && git pull --ff-only && bash setup.sh
```

`MCL_REPO_PATH` varsayılan olarak `$HOME/my-claude-lang`. Klonun başka bir yerdeyse environment variable ile ayarla. Güncelleme bitince yeni bir Claude Code oturumu aç — güncellenen hook ancak yeni oturumda devreye girer.

---

## Kullanım

İki yol var:

### 1. Manuel (önerilen)

Mesajının başına `/mcl` veya `@mcl` yaz:

```
/mcl bir login sayfası yap
/mcl hızlı bir dashboard lazım
@mcl bu API'yi düzelt
```

Bu **garanti** aktivasyon. Bir kere yaz, konuşma boyunca aktif kalır.

### 2. Otomatik (hook ile)

Sadece kendi dilinde yaz. Hook kuruluysa, MCL her İngilizce olmayan mesajda otomatik devreye girer — prefix gerekmez. Hook kurulu değilse, `/mcl` yazarak aktive et.

---

## Çeviriden Farkı Ne

Bir çevirmen şunu görür:

> "kullanıcı giriş yaptıktan sonra ana sayfaya yönlendirilsin"

Ve şunu üretir:

> "redirect user to main page after login"

my-claude-lang aynı cümleyi görür ve sana şunları sorar:

- Hangi kimlik doğrulama yöntemi? Session mı? JWT mi? OAuth mı?
- Yönlendirme client tarafında mı yoksa sunucu tarafında mı?
- Yönlendirme sırasında oturum süresi dolarsa ne olacak?
- "Beni hatırla" seçeneği olacak mı?
- Başarısız giriş nereye yönlendirecek?
- Yükleniyor durumu nasıl görünecek?

Sonra tüm bu soruları sana çeviriyor — her sorunun neden sorulduğunu ve cevabının ne değiştireceğini açıklayarak. Cevaplarını alıyor, İngilizce'ye çeviriyor ve ANCAK O ZAMAN Claude Code'un inşa etmeye başlamasına izin veriyor.

**Bu çeviri değil. Bu senin dilini konuşan bir kıdemli mühendis.**

---

## Teknik Terimler Nasıl Çalışıyor

- Evrensel terimler İngilizce kalıyor: API, REST, GraphQL, Docker, Git, database
- Yarı teknik terimler iki dilde veriliyor: "endpoint (erişim noktası)"
- Kavramsal terimler senin dilinde tam açıklanıyor, ilk kullanımda İngilizce parantez içinde
- Dilinde karşılığı olmayan terimler İngilizce kalıyor — uydurma çeviri yok

---

## Her Şeyle Çalışıyor

my-claude-lang tüm Claude Code ekosistemine entegre:

- **Superpowers** — beyin fırtınası ve planlama soruları köprüden geçiyor
- **Local-Review** — kod inceleme sonuçları sadece çevrilmiyor, açıklanıyor
- **Claude-Mem** — oturum hafızası köprüyle birlikte çalışıyor
- **Seninle konuşan her plugin** — tüm iletişim my-claude-lang üzerinden yönlendiriliyor

---

## Desteklenen Diller

Claude'un desteklediği her dil. Otomatik algılama. Ayar yok.

---

## Gerçek AI Çağı

Yıllarca AI kodlama araçlarının görünmez bir kapısı vardı: İngilizce bilmek.

İstanbul'da, São Paulo'da, Tokyo'da, Kahire'de veya Seul'de büyüdüysen — ve yol boyunca İngilizce öğrenmediysen — dünyanın en güçlü geliştirme araçları tırmanamayacağın bir duvarın arkasındaydı.

my-claude-lang o duvarı kaldırıyor.

Sana İngilizce öğreterek değil. Araçları basitleştirerek değil. Senin niyetinin, inceliklerinin, uzmanlığının her zerresini koruyan ve Claude Code'a en iyi düşündüğü dilde ileten bir köprü kurarak.

**Gerçek AI çağı, İngilizce çalışan araçların çağı değil. Senin dilinde çalışan araçların çağı.**

---

## Lisans

MIT — özgürce kullan, değiştir ve dağıt.
