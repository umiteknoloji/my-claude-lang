# LLM Ajanlarında "Söz Geçmeyen" Davranış Kalıpları — MCL Referans Notu

**Amaç:** Bu dosya hook logic değildir. MCL geliştirirken (yeni özellik tasarlarken, üretim failure analizi yaparken, "bu pattern'i hangi mekanizmayla kapsadık" diye kontrol ederken) bakılacak referans tablosudur.

**Kaynak:** Üretim deneyimi + LLM araştırma literatürü (lost-in-the-middle, attention decay, prompt instruction-following ceiling).

**Genel prensip:** Her kalıbın çözümü "daha iyi prose" değil, **mekanik kısıt + kaçış valfi**. Prose ikna eder, hook zorlar; valf olmazsa model yaratıcı yollarla deforme olur.

---

## 17 anti-pattern + counter-mechanism + MCL coverage

| # | Pattern | Counter-mechanism (genel) | MCL'deki karşılığı | Status |
|---|---|---|---|---|
| 1 | **Spec'i unutma (attention decay)** — Uzun context'te kuralları "balık hafıza" gibi unutur. | JIT injection (PreToolUse hook ile o anda enjekte et) | DSI `<mcl_phase_status>` (v13.0.4) + `<mcl_active_phase_directive>` (v13.0.9 Layer A) — single-phase view her UserPromptSubmit'te dinamik enjekte | ✅ |
| 2 | **Sessiz durma** — Belirsizlikte hiçbir şey yapmamayı seçer. | Stop hook + exit criteria; "bilmiyorum" meşru ama sessiz durma yasak. | Stop hook block-on-incomplete (v13.0.6 Aşama 6, v13.0.7 Aşama 2 synthesis, v13.0.8 strict). "Bilmiyorum" valve v13.1'e | ⚠ kısmi |
| 3 | **Sahte tamamlama** — "Yaptım" der ama yapmaz, ya da yarım yapıp geçer. | Objektif validation (dosya/test/state kontrolü, model beyanı değil) | Gate engine + universal completeness loop (v13.0.0) — `*-complete` audit'leri varlık-tabanlı, model'in "tamamlandı" beyanı yetmez | ✅ |
| 4 | **Aşama atlama / paralel koşma** — Faz 1 bitmeden Faz 3'e atlar, aynı anda birden fazla iş başlatır. | Allowlist; mevcut fazın tool'u dışında her şey reddedilsin. | Layer B Phase Allowlist (v13.0.9) — gate-spec.json `allowed_tools` + `denied_paths` + PreToolUse phase enforcement | ✅ |
| 5 | **Yaratıcı bypass** — Yasakladığın yolu başka tool kombinasyonuyla taklit eder (örn. `rm` yasaksa `mv /dev/null`). | Niyet seviyesinde değil, **etki** seviyesinde validate et (post-hoc state diff). | Aşama 14 security scan (semgrep + audit) + execution-plan rule (destructive op reconfirm) | ⚠ kısmi |
| 6 | **Sycophancy / onay bias'ı** — Kullanıcı "şu doğru mu" dediğinde, yanlış olsa bile "evet" der. | Kritik kararları model onayına bağlama; deterministik kontrol koy. | self-critique loop 4-soru anti-sycophancy + AskUserQuestion gates (model kullanıcı'ya soruyor, kullanıcı karar veriyor) + honest-assessment + pressure-resistance constraints | ✅ |
| 7 | **Halüsinasyon (uydurma)** — Olmayan dosya, fonksiyon, API çağırır. | Tool çağrısından önce existence check; halüsine edilen referans = hard fail + retry. | (open) — şu an yok. Aşama 5 Pattern Matching mevcut dosyaları okur ama tool input'unun gerçekliğini doğrulamaz. | ❌ gap |
| 8 | **Context kaybolması** — Uzun konuşmada başlangıçtaki kararı unutur, çelişkili davranır. | Karar log'u state'te tutulsun, her turn başına özet enjekte edilsin. | `.mcl/session-context.md` (v8.2.11) — Stop hook her turda yazar, activate hook bir sonraki turda inject eder | ✅ |
| 9 | **Over-engineering** — Basit istekte 5 dosya, 3 abstraction yaratır. | Scope hook; izin verilen dosya sayısı/satır limiti. | Aşama 12 Simplify (premature abstraction) + scope-discipline constraint (Rule 1 SPEC-ONLY) + scope_paths file lock | ⚠ kısmi |
| 10 | **Premature optimization stop** — İlk işe yarayan çözümde durur, "daha iyi olabilir mi" diye bakmaz. | Quality gate (lint, test, type check) Stop hook'ta zorunlu. | risk_review_state + quality_review_state Stop hook enforcement (Aşama 10 + 11-18 quality+tests pipeline) | ✅ |
| 11 | **Loop'a girme** — Aynı hatayı aynı şekilde tekrar dener. | Aynı tool+input kombinasyonu N kez = block + escalate. | `_mcl_loop_breaker_count` (v10.1.7) — 3-strike fail-open per audit name. Layer B 5-strike per phase-allowlist deny. | ✅ |
| 12 | **Goal drift** — Başlangıçtaki amaçtan sapar, alakasız iş yapar. | Goal'u state'in tepesine pinle, her PreToolUse'da "bu çağrı goal'a hizmet ediyor mu" kontrolü (LLM-as-judge ile). | Aşama 4 spec emit (canonical goal in `.mcl/specs/`) + spec-drift detection (Stop hook warn-only) + scope_paths lock | ⚠ kısmi |
| 13 | **Yanlış mental model** — Kodu yanlış anladığı halde emin görünür. | Kritik aksiyondan önce "açıkla" tool'u zorunlu; açıklaması yanlışsa devam etmesin. | Aşama 1 disambiguation triage (GATE questions) + Aşama 2 precision audit (7 boyut) + Aşama 3 engineering brief (vague verb upgrade) | ✅ |
| 14 | **Permission creep** — Verdiğin yetkiyi bağlam dışında kullanır (test için verdin, prod'a uygular). | Yetki scope'u zaman/dosya/branch ile sınırlı, hook validate etsin. | scope_paths file lock + UI flow path-lock (Aşama 6 backend deny) + Layer B denied_paths (v13.0.9) | ✅ |
| 15 | **Reward hacking** — Test'i geçmek için test'i siler, type error'u `any` ile susturur. | Validation iki katmanlı: yüzeysel (test geçti mi) + semantic (test silindi mi, type weakened mı). | (open) — şu an semantic check yok. Aşama 22 completeness audit test_command result'a bakar ama test silinmiş mi denetlemez. | ❌ gap |
| 16 | **Sandbagging / az iş yapma** — Gücü yettiği halde minimum yapar. | Açık success criteria; "çalışıyor"un tanımı pre-defined olsun. | Aşama 4 spec MUST/SHOULD requirements + Aşama 20 verify report (spec coverage table — her requirement test'le bağlanır) | ✅ |
| 17 | **Context kirliliği** — Hatalı çıktıyı kendi context'ine alıp üstüne kurar. | Hata turn'leri context'ten temizle/özetle, sadece son temiz state kalsın. | (open) — Claude Code platform feature, MCL erişemez. Workaround: `/mcl-restart` state reset. | ❌ gap |

---

## Açık boşluklar (3)

- **#7 Halüsinasyon** — existence check before tool. v13.1 düşünülmeli.
- **#15 Reward hacking** — semantic validation (test silinmesi, type weakening). v13.1 düşünülmeli.
- **#17 Context kirliliği** — Claude Code platform-level feature, MCL'in erişimi yok. Workaround: `/mcl-restart`.

---

## Kullanım

Yeni özellik tasarlarken:
1. Bu tabloya bak.
2. Tasarladığın özellik hangi pattern'i kapsıyor?
3. Counter-mechanism uygulanıyor mu?
4. Kaçış valfi var mı? (her kısıt için bir tane)

Üretim failure analizi yaparken:
1. Hangi pattern (#1-17) gözlendi?
2. Mevcut MCL coverage neredeydi?
3. Eksik mekanizma + kaçış valfi → yeni release planı.

CHANGELOG drift kontrolü:
- Bu doc kod değiştikçe stale olabilir. Yeni MCL feature shipped olduğunda bu tabloya da girilmeli.
- Convention: CHANGELOG.md release entry'sinde "Updated llm-attention-failure-patterns.md row #N" satırı.

---

**Önerilen güncelleme tetikleyicileri:**
- Yeni Pattern keşfedildiğinde (üretim failure analizi)
- Mevcut Pattern coverage status değiştiğinde (❌ → ⚠ → ✅)
- v13.1 / v14 release'lerinde 3 known gap için review

**Versiyonlama:** Bu doc'un kendi version'u yok. CHANGELOG.md release entry'lerine bağlı.
