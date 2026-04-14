# Language Detection Rules

## Auto-Detection

The developer's language is detected automatically from their first message.
If uncertain, ask: "[detected language]: Is this your preferred language?"

## Mixed Language Detection

If the message contains both languages, determine the dominant language
by sentence structure and grammar, not by word count.

- If the MAJORITY of sentence structures (subject-verb-object patterns,
  verb conjugations, grammatical suffixes) belong to a non-English language
  → ACTIVATE
- If the MAJORITY of sentence structures are English with scattered
  non-English words → DO NOT ACTIVATE
- Determine dominant language by analyzing grammatical structure, NOT by
  counting English vs non-English words. Every language has unique signals:
  verb conjugations, case markers, particles, postpositions, word order
  patterns, and morphological suffixes. If the sentence grammar belongs
  to a non-English language — regardless of how many English technical
  terms are embedded — the developer is speaking that language.
  English words inside non-English grammar = non-English speaker.
  Non-English words inside English grammar = English speaker.
- When genuinely uncertain (true 50/50) → ask the developer:
  "Which language would you prefer to work in?"

## Mid-Conversation Language Switch

If the developer switches to a different language during a conversation:
- Ask: "I noticed you switched to [new language]. Would you prefer to
  continue in [new language]?"
- If "yes" → switch all communication to the new language, continue the
  current phase
- If "no" → continue in the original language
