# my-claude-lang 
### Gerçek AI çağı İngilizce konuşmuyor. Senin dilini konuşuyor.

---

Bugüne kadar dünyanın en iyi AI kodlama araçlarını kullanmak için İngilizce bilmen gerekiyordu. Artık gerekmiyor.

**my-claude-lang**, Claude Code için bir eklenti. Yazılımı kendi ana dilinde geliştirmeni sağlıyor — sıfır İngilizce bilgisiyle. Ayar yok. Dil seçimi yok. Sadece konuşmaya başla. O anlıyor.

Bu bir çevirmen değil. Çevirmenler kelimeleri çevirir. my-claude-lang **anlamı** çevirir.

### 5.0.0'dan itibaren — Evrensel Aktivasyon

my-claude-lang artık sadece İngilizce bilmeyenler için değil. MCL **her** mesajda devreye giriyor — İngilizce dahil — çünkü anlam doğrulama, kıdemli mühendis kalitesinde spec üretimi ve anti-yalakalık, kaynak dilden bağımsız olarak değerli. İngilizce bilmeyen kullanıcı için çeviri köprüsü de çalışmaya devam ediyor; İngilizce kullanıcı için çeviri katmanı identity'ye düşüyor, ama diğer tüm katmanlar (aşama kapıları, öz-eleştiri, disambiguation, Aşama 11 doğrulama) tamamen çalışıyor.

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

Tek bir satır kod yazılmadan önce **on iki aşamalı karşılıklı anlama döngüsü** kuruyor:

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
Aşama 5: Pattern Matching yapılır. Proje yeni yaratılıyorsa
         atlanır.
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
Aşama 8 (Risk İncelemesi): MCL, spec'te tasarlanan güvenlik ve
         performans kararlarının doğru uygulandığını doğrular; ardından
         atlanmış riskleri tarar — uç durumlar, gerilemeler — ve her
         birini seninle tek tek konuşur. Risk düzeltmeleri bittikten
         sonra TDD testleri yeniden koşar: hepsi yeşil → geçer; kırmızı
         → ilgili kod düzeltilir; çelişki → sen karar verirsin.
  │
  ▼
Aşama 9: code review
         Simplify
         Performans
         Güvenlik
         unit test, integration test, E2E test, yük testi.
         Sırasıyla bunlar yapılır, AskUserQuestion olmadan auto-fix.
  │
  ▼
Aşama 10 (Etki İncelemesi): MCL projenin geri kalanını,
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

**Hiçbir belirsizlik bu döngüden sağ çıkamaz.** Her kapıda "hayır" diyebilirsin ve MCL geri dönüp düzeltir. Açık onayın olmadan hiçbir şey ilerlemez.

### AskUserQuestion ile Onaylar (6.0.0'dan itibaren)

Her kapalı-uçlu kapı (Aşama 1 özet, Aşama 4 spec onayı, her Aşama 8
risk, her Aşama 10 etki, plugin onayı, git-init onayı, drift çözümü,
`/mcl-update` / `/mcl-finish` / yapıştırılan-CLI onayı) yerleşik
Claude Code `AskUserQuestion` çağrısı olarak geliyor; soru başlığı
`MCL 10.0.4 | ` ile başlıyor. Kararı arayüzden tıklıyorsun — artık
"evet" yazmak veya `✅ MCL APPROVED` eklemek yok. Aşama 1'in
açık-uçlu parametre toplama kısmı ise düz metin sohbet olarak
kalıyor.

Spec drift (onaylı gövdenin mevcut emisyonla eşleşmemesi) artık
**yalnızca uyarı**: yazma araçları asla engellenmiyor, ama MCL her turda
bir drift uyarısı yayınlıyor ve AskUserQuestion ile sana yeni gövdeyi
onaylamak mı yoksa onaylı gövdeye dönmek mi istediğini soruyor.

Her yanıt `🌐 MCL 10.0.4` ile başlıyor — böylece köprünün aktif olduğunu her zaman biliyorsun.

### UI Build / Review Alt-Fazları (6.2.0'dan itibaren)

Görevin bir UI yüzeyi olduğunda (her projede varsayılan), Aşama 6 üç
alt-faza ayrılıyor — böylece MCL değiştirmek istediğin bir UI'ın
üstüne backend yazarken seyretmek zorunda kalmıyorsun:

1. **Aşama 6a (BUILD_UI)** — MCL sadece dummy data ile çalıştırılabilir
   bir frontend yazıyor. Stack'ine göre React / Vue / Svelte / statik
   HTML. Çalıştırma komutu veriyor (`npm run dev` vb.); MCL
   tarayıcıyı otomatik açar, sen incelersin.
2. **Aşama 6b (UI_REVIEW)** — MCL backend'e geçmeden önce UI doğru
   mu diye soruyor. Dört seçenek: onay / revize / **sen de bak ve
   raporla** / iptal. "Sen de bak ve raporla" opt-in bir boru hattı:
   Playwright + screenshot + Claude'un multimodal görüsü ile MCL
   kendi yazdığı UI'a gerçekten bakıp ne gördüğünü anlatıyor —
   `playwright` kurulu olmasını gerektirir, asla otomatik kurmaz.
3. **Aşama 6c (BACKEND)** — ancak onayladıktan sonra MCL dummy
   fixture'ları gerçek API çağrılarına dönüştürüyor, data layer'ı
   yazıyor, error ve loading state'lerini gerçek async'e bağlıyor.

Aşama 1 özet onayında "onay, UI atlayacağız" seçersen Aşama 7
ayrılmadan çalışır (6.1.1 davranışının aynısı). UI default ON çünkü
projelerin çoğunun UI yüzeyi var; bash script'leri ve yalnızca-backend
değişiklikleri tek tıkla opt-out yapıyor.

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

### 1. Adım — Gerekli Claude Code plugin'lerini kur (MCL'DEN ÖNCE)

6.1.0'dan itibaren MCL, curated orkestrasyon plugin'i (`security-guidance`)
ve stack'ine göre tespit edilen LSP plugin'leri kurulu değilse kendini
sert-kilitler. Önce platformuna uygun installer'ı çalıştır:

```bash
# macOS / Linux
chmod +x install-claude-plugins.sh
./install-claude-plugins.sh
```

```powershell
# Windows (PowerShell)
.\install-claude-plugins.ps1
```

Script'ler önce resmi `claude-plugins-official` marketplace'ini kaydeder,
ardından curated orkestrasyon setini ve Claude Code'un desteklediği
tüm LSP plugin'lerini kurar. Her iki script de idempotent — tekrar
tekrar çalıştırabilirsin. `claude` CLI'nin PATH'te olması gerekir.

> **Neden önce bu?** Bu adımı atlarsan MCL'in PreToolUse hook'u her
> session'ın ilk mesajında `Write` / `Edit` / `MultiEdit` /
> `NotebookEdit` ve writer-Bash komutlarını (`rm`, `git commit`,
> paket kurulumu, shell yönlendirmesi, ...) reddeder; gate sadece
> yeni bir session açıldığında tekrar kontrol eder.

### 2. Adım — MCL'i kur

Klonla, tek komut çalıştır. Ayar yok. Dil seçimi yok.

```bash
git clone https://github.com/YZ-LLM/my-claude-lang.git
bash my-claude-lang/setup.sh
```

Bu her şeyi global olarak kurar:
- **Skill dosyaları** → `~/.claude/skills/my-claude-lang/` (MCL kuralları, kapılar, fazlar)
- **Otomatik aktivasyon hook'u** → `~/.claude/hooks/mcl-activate.sh` (İngilizce olmayan girdiyi algılar)
- **Hook konfigürasyonu** → `~/.claude/settings.json` (hook'u Claude Code'a bağlar)

Yeni bir Claude Code oturumu aç ve kendi dilinde yazmaya başla. Hepsi bu.

---

## Güncelleme

Güncellemek için mesaj olarak sadece `/mcl-update` yaz. MCL normal akışı (spec, fazlar) tamamen atlar ve şu komutu çalıştırır:

```
cd $MCL_REPO_PATH && git pull --ff-only && bash setup.sh
```

`MCL_REPO_PATH` varsayılan olarak `$HOME/my-claude-lang`. Klonun başka bir yerdeyse environment variable ile ayarla. Güncellenen hook ve skill dosyaları her prompt'ta yeniden okunduğu için aynı oturumdaki bir sonraki mesajın yeni kuralları kullanır — oturum yeniden başlatmaya gerek yok.

---

## Parçalı Spec Kurtarma — Rate-Limit Kesinti Savunması

Uzun spec'ler rate-limit, ağ kesintisi veya süreç kill ile yarıda kesilebilir. 5.15.0 öncesi, sonraki turda senden gelen bir `evet` bu yarıda kalmış spec'i sessizce EXECUTE fazına geçiriyordu — çünkü MCL'in state makinesi sadece approval token'ına bakıyordu, spec body'nin yapısal tamlığına bakmıyordu. Gereksinimlerinin yarısı eksik onaylanmış bir spec ile kalıyordun ve tek çıkış yolu manuel `rm .mcl/state.json` idi.

5.15.0 ile MCL bu kesintiyi Stop-hook katmanında tespit ediyor: bir `📋 Spec:` bloğu yedi zorunlu bölümden (Objective, MUST, SHOULD, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope) herhangi birini kapsamıyorsa, state'e `partial_spec=true` bayrağı yazılır. Bir sonraki aktivasyon Claude'a spec'i tam olarak yeniden yayınlamasını söyler — ve bayrak temiz spec ile sıfırlanana kadar hiçbir approval token'ı dinlenmez. Kesintiyi fark etmek zorunda değilsin; MCL senin için fark eder.

---

## Token & Maliyet Muhasebesi — `/mcl-doctor`

MCL her turda context injection boyutunu loglar. `/mcl-doctor` yazarak şunları görebilirsin:

- **MCL injection overhead** tur başına (karakter → tahmini token)
- **Cache write ve cache read** maliyeti (Sonnet 4.6 fiyatlandırması)
- **MCL açık vs kapalı karşılaştırması** — bu session'da MCL'nin net maliyeti
- **Session token özeti** gerçek session log'undan

Fiyatlar tahmini. Gerçek fatura için Claude Console'u kontrol et.
Sayacı sıfırlamak için: `rm .mcl/cost.json`

---

## Oturumlar Arası Bitirme Modu — `/mcl-finish`

Aşama 10 execution sırasında downstream etkileri teker teker yüzeye çıkarır. Bu etkilerin çoğu "haftaya bir kontrol edeyim" türünden gerçek maddelerdir — tek bir oturuma sığmayan, ileri tarihli kontroller.

`/mcl-finish` bu maddeleri oturumlar arasında taşıyan checkpoint mekanizmasıdır.

Her Aşama 11 Doğrulama Raporu, bu komuta işaret eden senin dilinde bir hatırlatıcı satırla biter. Hazır olduğunda mesaj olarak sadece `/mcl-finish` yaz ve MCL şunları yapar:

1. Son checkpoint'ten bu yana `.mcl/impact/` dizinine yazılmış tüm Aşama 10 etkilerini toplar
2. Desteklenen stack'lerde full-project Semgrep taraması çalıştırır (desteklenmeyenlerde sessizce atlanır)
3. Senin dilinde proje seviyesi bir bitirme raporu emit eder
4. `.mcl/finish/NNNN-YYYY-MM-DD.md` olarak yeni bir checkpoint yazar

Bir sonraki `/mcl-finish` bu checkpoint'ten itibaren yeni bir pencere açar — kapanan etkiler arşivde kalır, yeniler bir sonraki pass için birikmeye başlar. Git commit yok, remote push yok, external reporting yok — tamamen yerel state.

Aşama 8 riskleri biriktirilmez: onlar oturum içinde çözülür.

---

## Kullanım

İki yol var:

### 1. Manuel (önerilen)

Mesajının başına `/mcl` veya `/mcl` yaz:

```
/mcl bir login sayfası yap
/mcl hızlı bir dashboard lazım
bu API'yi düzelt
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
