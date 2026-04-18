# CLAUDE.md

<mcl_core>
Project-scoped instructions for `my-claude-lang`. Claude Code reads this
file automatically when working in this directory.

For the MCL XML tag vocabulary used throughout this repo (hook,
skill files, captured-rules blocks), read
`skills/my-claude-lang/mcl-tag-schema.md`.
</mcl_core>

<mcl_constraint name="captured-rules-project">

## MCL-captured rules

- Always add a `For full <phase> rules, read my-claude-lang/<file>.md` pointer line in `skills/my-claude-lang.md` for every phase skill file. Never introduce a phase skill file without this pointer. <!-- loc: TR: skills/my-claude-lang.md ana dosyasına her faz skill dosyası için `For full <faz> rules, read my-claude-lang/<dosya>.md` şeklinde bir referans satırı her zaman eklenir. Referans satırı olmadan yeni faz skill dosyası tanıtılmaz. -->
- Always use hyphens (not underscores) as word separators in skill and markdown filenames under `skills/` (e.g., `phase4-5-risk-review.md`, not `phase4_5-risk-review.md`). <!-- loc: TR: `skills/` altındaki skill ve markdown dosya adlarında kelime ayırıcı olarak her zaman tire kullan, alt çizgi kullanma (örn. `phase4-5-risk-review.md`, `phase4_5-risk-review.md` değil). -->
- Always test MCL across the fixed 14-language set: Turkish, English, Arabic, German, Spanish, French, Hebrew, Hindi, Indonesian, Japanese, Korean, Portuguese, Russian, Chinese. Never substitute, reduce, or expand this set — it represents the chosen world-language coverage. <!-- loc: TR: MCL her zaman sabit 14 dillik sette test edilir: Türkçe, İngilizce, Arapça, Almanca, İspanyolca, Fransızca, İbranice, Hintçe, Endonezce, Japonca, Korece, Portekizce, Rusça, Çince. Bu set değiştirilmez, azaltılmaz, genişletilmez — seçilmiş dünya dili kapsamını temsil eder. -->

</mcl_constraint>
