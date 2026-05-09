---
name: mycl-reasons
description: MyCL hook'larının emit ettiği audit/decision REASON metinleri için referans. Devtime (sen + CC) için iç dil; runtime (kullanıcı projesi) için kullanıcı diline çeviri kuralları. Reason yazarken kısa ol — bilingual mesaj key'i kullan, hard-coded prose'tan kaçın.
---

# REASON Metinleri — Devtime/Runtime Ayrımı

Hook'ların emit ettiği `permissionDecisionReason`, audit `detail`,
askq option label, error mesajı — hepsi REASON metni. İki bağlam:

## Devtime — MyCL geliştirme oturumu

Sen + Claude Code MyCL'i geliştiriyorsunuz. Reason metni:
- Sade Türkçe (CLAUDE.md kuralı)
- Code identifier'lar yalnızca somut artefakt referansında
  (`hooks/pre_tool.py:120`, commit `abc1234`)
- Kalan her şey kodun ne YAPTIĞINI anlatır, ne ADLANDIĞINI değil

Örnek:
- ❌ "askq-advance-jit branch failed"
- ✅ "kullanıcı askq onaylayınca state'i ileri taşıyan kod parçası
  başarısız oldu"

## Runtime — Kullanıcı projesi oturumu

MyCL yüklü, kullanıcı kendi işini yapıyor. Reason metni:
- Bilingual (TR + EN, boş satır ayrılı, etiketsiz)
- Tek noktadan render: `bilingual.render(key, **kwargs)`
- Hard-coded prose **yasak** — `data/bilingual_messages.json`'a key ekle

Örnek:
```python
# YASAK — hard-coded prose
return _deny("Spec onayı yok; Write engellendi.")

# DOĞRU — bilingual key
return _deny(bilingual.render("spec_approval_block", tool="Write"))
```

Eksik key durumunda hook fail-safe: render `[missing-key:foo]` dönerse
hard-coded TR + EN fallback kullanılır (pre_tool.py paterni).

## REASON Sözleşmeleri

1. **Kısa.** Tek paragraf yeter; kullanıcı iki dilde okuyacak.
2. **Eylem önerisi.** "Engellendi" yetmez — "ne yap?" söyle. Örn:
   "Önce Aşama 1 → 2 → 3 → 4 sırasıyla ilerleyin."
3. **Recovery yolu varsa göster.** Legitim emit komutu, manuel
   audit injection, rollback adımı — kullanıcı koridor görsün.
4. **Suçlama yok.** "Modeli bypass'a çalıştın" değil; "spec onayı yok,
   şu adımı izle" yeterli. Anti-sycophancy ≠ anti-clarity.
5. **Code identifier minimum.** REASON'da dosya yolu vs. teknik
   detay yalnızca developer-facing audit log'a gider; kullanıcı görür
   reason'da kullanılmaz.

## Audit `detail` Alanı

Audit log formatı: `<UTC ISO8601> | name | caller | detail`. Detail
kısa yapılandırılmış metin — debug için, kullanıcı görmez:

```
2026-05-09T20:00:00Z | spec-approval-block | pre_tool.py | tool=Write
2026-05-09T20:00:01Z | spec-approval-block-escalation-needed | pre_tool.py | strike=5 developer-intervention-required
2026-05-09T20:00:02Z | spec-hash-stored | stop.py | hash=a1b2c3d4e5f6 must_count=3
```

Detail'da `=` ile key=value pattern; sözel değil. Audit sorgu
script'leri bu formata güvenir.

---

# REASON texts — devtime / runtime split

Hook-emitted `permissionDecisionReason`, audit `detail`, askq option
label, error message — all REASON text. Two contexts:

## Devtime (you + Claude Code building MyCL)

Plain Turkish prose; code identifiers only when referencing concrete
artifacts (file paths, commit SHAs).

## Runtime (user project session)

Bilingual TR + EN, blank-line separated, no labels. Single render
point: `bilingual.render(key, **kwargs)`. Hard-coded prose forbidden —
add a key to `data/bilingual_messages.json` instead.

## REASON contracts

- Short — one paragraph max.
- Action recommendation — "blocked" insufficient; tell the user what
  to do.
- Show recovery if any (legit emit command, manual audit injection).
- No blame — anti-sycophancy ≠ anti-clarity.
- Minimum code identifiers in REASON.

## Audit `detail` field

Format: `<UTC ISO8601> | name | caller | detail`. Detail = short
structured text (key=value), not prose. Audit query scripts rely on
this format.
