# MCL Faz Eşleme Tablosu (Kanonik Kaynak)

Bu dosya 22 aşamanın tek doğruluk kaynağıdır. Numara, kanonik ad, slug,
çıktı audit ve skill dosyası adı buradan üretilir.

**Build-time normalizasyon:** Skill dosyaları doğrudan yazılmaz. `_templates/`
altındaki template'lerde `{{tdd_phase_no}}` gibi placeholder'lar kullanılır.
Mapping bu dosyadan okunur, build script (`scripts/build-skills.py`)
template'leri process eder, gerçek skill dosyaları üretilir.

**Değişiklik kuralı:** Numara değiştirilecekse SADECE bu dosya güncellenir,
sonra `bash scripts/build-skills.sh` çalıştırılır. Tüm skill dosyaları
ve referansları otomatik yeni numbering'e geçer.

---

## Faz Tablosu

| Numara | Slug | Kanonik Ad | Çıktı Audit | Skill Dosyası |
|--------|------|------------|-------------|---------------|
| 1 | gather | Niyet Toplama | summary-confirm-approve | asama1-gather.md |
| 2 | precision-audit | Hassasiyet Denetimi | precision-audit + asama-2-complete | asama2-precision-audit.md |
| 3 | translator | Mühendislik Özeti | engineering-brief + asama-3-complete | asama3-translator.md |
| 4 | spec | Spec Yazımı + Onay | asama-4-complete + asama-4-ac-count | asama4-spec.md |
| 5 | pattern-matching | Desen Eşleştirme | asama-5-complete | asama5-pattern-matching.md |
| 6 | ui-build | UI Yapımı | asama-6-end | asama6-ui-build.md |
| 7 | ui-review | UI İncelemesi | asama-7-complete | asama7-ui-review.md |
| 8 | db-design | Veritabanı Tasarımı | asama-8-end | asama8-db-design.md |
| 9 | tdd | TDD Yürütme | asama-9-ac-{i}-red, green, refactor | asama9-tdd.md |
| 10 | risk-review | Risk İncelemesi | asama-10-items-declared + asama-10-item-{n}-resolved | asama10-risk-review.md |
| 11 | code-review | Kod İncelemesi | asama-11-scan / issue-fixed / rescan | asama11-code-review.md |
| 12 | simplify | Sadeleştirme | asama-12-scan / issue-fixed / rescan | asama12-simplify.md |
| 13 | performance | Performans | asama-13-scan / issue-fixed / rescan | asama13-performance.md |
| 14 | security | Güvenlik | asama-14-scan / issue-fixed / rescan | asama14-security.md |
| 15 | unit-tests | Birim Testler | asama-15-end-green | asama15-unit-tests.md |
| 16 | integration-tests | Entegrasyon Testleri | asama-16-end-green | asama16-integration-tests.md |
| 17 | e2e-tests | Uçtan-Uca Testler | asama-17-end-green | asama17-e2e-tests.md |
| 18 | load-tests | Yük Testleri | asama-18-end-target-met | asama18-load-tests.md |
| 19 | impact-review | Etki İncelemesi | asama-19-items-declared + asama-19-item-{n}-resolved | asama19-impact-review.md |
| 20 | verify-report | Doğrulama Raporu | asama-20-complete + asama-20-mock-cleanup-resolved | asama20-verify-report.md |
| 21 | localized-report | Yerelleştirilmiş Rapor | asama-21-complete | asama21-localized-report.md |
| 22 | completeness | Tamlık Denetimi | asama-22-complete (kanca yazar) | asama22-completeness.md |

---

## Atlama Koşulları

| Numara | Atlanabilir mi? | Şart |
|--------|-----------------|------|
| 1 | Hayır | — |
| 2 | Hayır (İngilizce session'da scan skipped, askq yine zorunlu) | İngilizce session |
| 3 | Hayır (İngilizce session'da identity) | İngilizce session |
| 4 | Hayır | — |
| 5 | Evet | Greenfield veya benzer dosya yok |
| 6 | Evet | UI flow yok |
| 7 | Evet | Aşama 6 atlandıysa otomatik (cascade-skip) |
| 8 | Evet | DB scope yok |
| 9 | Hayır | — |
| 10 | Hayır | — |
| 11-14 | Hayır (auto-fix loop) | — |
| 15-18 | Soft-skip | Code shape uygun değilse `asama-N-not-applicable` audit zorunlu |
| 19 | Hayır | — |
| 20 | Hayır | — |
| 21 | Evet | İngilizce session — identity |
| 22 | Hayır | — |

---

## Placeholder Konvansiyonu

Template'lerde kullanılacak placeholder formatı:

- `{{phase_no:slug}}` → Aşama numarasını döndürür (örn: `{{phase_no:tdd}}` → `9`)
- `{{phase_name:slug}}` → Kanonik adı döndürür (örn: `{{phase_name:tdd}}` → `TDD Yürütme`)
- `{{phase_audit:slug}}` → Çıktı audit'i döndürür
- `{{phase_file:slug}}` → Skill dosya adını döndürür

Slug, tablodaki "Slug" sütunu ile eşleşir.

---

## Versiyon

Bu mapping v13 numbering'i temsil eder. Numara/sıra değişikliği MCL'in
fundamental refactor'unu gerektirir; rastgele yapılmaz.

Son güncelleme: 2026-05-09
