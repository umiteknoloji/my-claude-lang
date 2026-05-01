<mcl_phase name="language-detection">

# Language Detection Rules

**Purpose**: Select the **response language**. MCL 10.0.1 supports
**Turkish (TR)** and **English (EN)** only — these are the two languages
section headers, audit messages, and skill prose are localized for.

## Auto-Detection

The developer's language is detected automatically from their first
message. If the message is unambiguously Turkish → respond in Turkish.
If unambiguously English → respond in English. If genuinely uncertain →
default to **Turkish** (the calibration language). Ask only when a
mixed-language message creates real doubt.

## Mixed Language Detection

If the message contains both languages, determine the dominant language
by sentence structure and grammar, not by word count.

- Turkish grammar (subject-object-verb order, vowel-harmony suffixes,
  agglutinative verb endings, particles like `mı/mi/mu/mü`) → respond
  in Turkish, even when English technical terms are embedded.
- English grammar (subject-verb-object order, articles, prepositional
  phrases) → respond in English, even when Turkish words appear inline.
- True 50/50 → default to Turkish.

## Mid-Conversation Language Switch

If the developer switches language mid-conversation:
- Ask once: "I noticed you switched to [new language]. Continue in
  [new language]?"
- If yes → switch all communication; continue the current phase.
- If no → continue in the original language.

Other languages are out of scope. Respond in Turkish (or English when
the developer is clearly writing in English) — never improvise prose
in a third language even if the developer's input is in one.

</mcl_phase>
