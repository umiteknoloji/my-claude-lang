---
name: mycl
description: MyCL (my-claude-lang) — Claude Code üstüne 22 fazlı geliştirme boru hattı dayatan anlam-doğrulama katmanı. Kullanıcı niyetinden tamlık denetimine kadar her adım: kanca + state.json + audit.log + skill dosyası ile somut. Faz atlamak imkansız; her faz çıktısı bir audit ile mühürlenir, bir sonraki faz ancak ondan sonra açılır.
---

# MyCL — Anlam Doğrulama Katmanı

MyCL **AI agent değildir, framework değildir, MCP server değildir.**
Pure Python 3 hook'larından oluşur. Claude Code'un dört olayına bağlanır
(UserPromptSubmit, PreToolUse, PostToolUse, Stop) ve her tur:

- `state.json` ile *bulunduğun fazı* hatırlar
- `audit.log` ile *ne tamamlandığını* sertifikalar
- `gate_spec.json` ile *hangi tool'un hangi fazda izinli olduğunu* dayatır
- 22 skill dosyası ile *o anda nasıl davranman gerektiğini* gösterir

## 22 Faz

Pipeline **sıralı, atlama yok**. Her faz `asama-N-complete` audit'i ile
kapanır; `asama-N-skipped` yalnızca audit'te `skip_reason` ile mümkündür.

| # | Faz | Açıklama |
|---|---|---|
| 1 | Niyet Toplama | Kullanıcının ne yapmak istediğini netleştir |
| 2 | Hassasiyet Denetimi | Niyetteki belirsizlikleri sorularla daralt |
| 3 | Mühendislik Özeti | Niyeti mühendislik diline çevir (sessiz faz) |
| 4 | Spec Yazımı + Onay | 📋 Spec bloğu — MUST/SHOULD listesi + AskUserQuestion onay |
| 5 | Desen Eşleştirme | Mevcut kodla tutarlı yazım için pattern tara (greenfield → skip) |
| 6 | UI Yapımı | Frontend dosyalarını yaz (UI yoksa skip) |
| 7 | UI İncelemesi | UI screenshot + serbest text onay (Aşama 6 atlandıysa skip) |
| 8 | Veritabanı Tasarımı | Schema + migration (DB yoksa skip) |
| 9 | TDD Yürütme | Spec MUST'larını sırayla red → yeşil → refactor |
| 10 | Risk İncelemesi | Açık risk maddelerini AskUserQuestion ile çöz (sınırsız) |
| 11 | Kod İncelemesi | İkinci-göz: bug/style/güvenlik bulguları |
| 12 | Sadeleştirme | Tekrar / fazlalık / okunabilirlik düzeltmeleri |
| 13 | Performans | Hot path + büyük O analizi |
| 14 | Güvenlik | Tüm proje semgrep + paket audit (hard secrets dahil) |
| 15 | Birim Testler | İzole fonksiyon/sınıf testleri |
| 16 | Entegrasyon Testleri | Modüller arası akış testleri |
| 17 | E2E Testler | Tam kullanıcı akışı |
| 18 | Yük Testleri | Performans/dayanım sınırı |
| 19 | Etki İncelemesi | Açık etki maddelerini AskUserQuestion ile çöz (sınırsız) |
| 20 | Doğrulama + Sahte Veri Temizliği | Spec MUST'larını commit'e karşı doğrula + dummy data temizle |
| 21 | Yerelleştirilmiş Rapor | Kullanıcının dilinde kapanış raporu (atlanabilir) |
| 22 | Tamlık Denetimi | Hook'un kendi yazdığı denetim — kapsanmamış MUST'lar yüzeye |

## Faz Skill Dosyaları

Her faz için detaylı skill dosyası `skills/mycl/asamaNN-*.md`'de.
Tek tek pointer'lar:

- For full Aşama 1 rules, read mycl/asama01-niyet.md
- For full Aşama 2 rules, read mycl/asama02-hassasiyet.md
- For full Aşama 3 rules, read mycl/asama03-ozet.md
- For full Aşama 4 rules, read mycl/asama04-spec.md
- For full Aşama 5 rules, read mycl/asama05-desen.md
- For full Aşama 6 rules, read mycl/asama06-ui-yapim.md
- For full Aşama 7 rules, read mycl/asama07-ui-inceleme.md
- For full Aşama 8 rules, read mycl/asama08-db.md
- For full Aşama 9 rules, read mycl/asama09-tdd.md
- For full Aşama 10 rules, read mycl/asama10-risk.md
- For full Aşama 11 rules, read mycl/asama11-kod-inceleme.md
- For full Aşama 12 rules, read mycl/asama12-sadelestirme.md
- For full Aşama 13 rules, read mycl/asama13-performans.md
- For full Aşama 14 rules, read mycl/asama14-guvenlik.md
- For full Aşama 15 rules, read mycl/asama15-birim-test.md
- For full Aşama 16 rules, read mycl/asama16-entegrasyon-test.md
- For full Aşama 17 rules, read mycl/asama17-e2e-test.md
- For full Aşama 18 rules, read mycl/asama18-yuk-test.md
- For full Aşama 19 rules, read mycl/asama19-etki.md
- For full Aşama 20 rules, read mycl/asama20-dogrulama.md
- For full Aşama 21 rules, read mycl/asama21-yerel-rapor.md
- For full Aşama 22 rules, read mycl/asama22-tamlik.md

## Ortak Dosyalar

- For XML tag vocabulary, read mycl/ortak/tag-schema.md
- For Plugin Rule A/B/C details, read mycl/ortak/plugin-rules.md
- For audit emit reasons, read mycl/ortak/reasons.md

## Çekirdek Sözleşmeler

**Sıralı ilerleme.** `current_phase` her transition tam olarak +1.
Doğrudan setter (1→4 atlama) yasak. Hook bile bu kuralı çiğneyemez.

**Audit zinciri.** `asama-N-complete` audit yazılmadan `current_phase`
N+1'e geçmez. Universal completeness loop her tur sonu audit'leri
okuyup ilerletir.

**Audit emission kanalı.** Audit dosyaya **hook** yazar, model değil.
Model bir aşamayı tamamladığında cevap metninde `asama-N-complete`
trigger word'ünü düz yazıyla zikreder; stop hook transcript'i okur ve
**sıralı eşleşmede** (N == current_phase) `.mycl/audit.log`'a o satırı
append eder + `.mycl/state.json`'da `current_phase`'i +1 ilerletir.
Atlama denemesi (örn. cp=1'de `asama-9-complete`) reddedilir ve
`phase-skip-attempt` audit'i ile işaretlenir (görünür sinyal). Model ↔
hook kanalı **transcript metni**, dosya değil. `Write` veya `Bash` ile
audit dosyasına yazma denemesi gereksiz ve pre_tool tarafından
engellenir; manuel `phase_transition` Bash deneyi DENY.

**STRICT mode.** Fail-open YOK. Yetersiz veri = belirsizlik =
fail-closed deny. 5 strike sonrası `*-escalation-needed` audit (sinyal,
block kalır).

**Bilingual çıktı.** Tüm hook ve skill çıktıları TR + EN iki blok;
boş satır ayırır. Etiket (TR:/EN:) yok. Dosya yolları, audit isimleri,
CLI komutları çevrilmez.

**Plugin Kural A/B/C.** Detay için `mycl/ortak/plugin-rules.md`.

## Kullanıcı Arayüzü

MyCL **görünmez** çalışır. Kullanıcı:
- AskUserQuestion sorularını yanıtlar (TR + EN seçenekler)
- Her tur başı DSI'da hangi fazda olduğunu görür (ASCII pipeline)
- Faz sonu inline notification ile ilerlemeyi izler

**Ne sormaz:** "MyCL'i nasıl kapatırım?" — soruluyorsa pipeline kullanıcı
acısı veriyor demektir, hook sorununa düşülmüş; logu paylaş.
