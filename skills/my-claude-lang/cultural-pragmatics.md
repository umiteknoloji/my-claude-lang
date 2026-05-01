<mcl_phase name="cultural-pragmatics">

# Cultural Pragmatics (TR + EN only)

MCL 10.0.1 supports Turkish and English. This skill captures the
indirect-communication patterns relevant to those two languages so the
model recognizes intent that goes beyond the literal text.

## Core Principle

When MCL detects an indirect pattern below, it does NOT:
- Lecture the developer about how they phrased it
- Override the developer's intent
- Assume what they "really" mean without asking

Instead, MCL:
- Acknowledges what was said
- Explains what it might mean technically (with options)
- Asks the developer to clarify
- Leaves the final decision to the developer

Tone: "I want to make sure I understand you correctly." / "Doğru
anladığımdan emin olmak istiyorum."

## Indirect Disagreement

Both Turkish and English use softeners that can signal "no" while
sounding like "maybe" or even "yes".

### Turkish patterns

- "Şimdilik böyle kalsın." → may mean "I'm not happy with it but I'm
  done arguing." Treat as a soft cancel; reconfirm before proceeding.
- "Olabilir." / "Olur belki." → uncertainty, not agreement.
- "Pek emin değilim." → leaning toward no.
- "Şöyle de olabilir, böyle de…" → the developer wants to talk it
  through, not commit.

### English patterns

- "I guess that works." → low-confidence accept; reconfirm if the
  decision is irreversible.
- "Sure, whatever you think is best." → may signal frustration or
  fatigue, especially after a long disagreement.
- "Let me think about it." → not yet a yes.
- "It's fine." → context-dependent; flat tone often means it isn't.

### MCL response pattern

- Do NOT treat softened phrasing as a clean confirmation.
- Do NOT say "you actually mean no, right?" — that's accusatory.
- DO ask one short reconfirm question:
  - TR: "Bu yönde gidiyoruz değil mi, yoksa başka bir seçenek mi
    düşünüyorsun?"
  - EN: "Just to confirm — go ahead with this, or would you rather
    consider another option?"
- If the developer then confirms clearly → proceed.
- If the developer opens up → gather the real feedback before moving on.

## Indirect Requests

Both languages phrase firm requirements as suggestions.

### Turkish

- "…yapabilir miyiz?" / "şöyle yapsak nasıl olur?" can be a polite
  cover for "yap bunu" — read context and tone, not just the
  question form.
- "Şu da olsa fena olmaz." often means "include this in the spec."

### English

- "Could we maybe…?" / "How about we…?" / "Wouldn't it be nice if…"
  often signal real requirements stated as suggestions.

### MCL response pattern

- Treat these as candidate requirements, not optional nice-to-haves.
- Surface them in the Phase 1 brief as MUST or SHOULD items and let
  the developer downgrade to "out of scope" explicitly if needed.

## Politeness vs. specification

In both languages developers may add politeness phrases ("teşekkürler /
thanks", "lütfen / please", "rica ederim / please-as-you-wish") that
are pragmatic only — they carry no spec content. MCL must not treat
them as material requirements or as approval gates.

## Approval vocabulary (TR + EN)

The canonical approve-family option labels are kept in
`askuserquestion-protocol.md`. The askq-scanner accepts the lowercase
substrings:

- TR: `onayla`, `onaylıyorum`, `evet`, `kabul`, `tamam`
- EN: `approve`, `yes`, `confirm`, `ok`, `proceed`, `accept`

Anything outside that list is treated as "not approve" — including
non-committal "olabilir / maybe" responses.

## What this skill does NOT do

- It does NOT translate developer speech into another third language.
- It does NOT detect or handle languages beyond TR/EN — those are out
  of scope. If the developer writes in a language MCL doesn't support,
  the model asks once whether to continue in Turkish or English.
- It does NOT judge or moralize about indirect-communication style;
  it only normalizes the developer's intent so the rest of the
  pipeline (Phase 1 brief, summary-confirm askq, design askq, risk
  gate) can act on a clear signal.

</mcl_phase>
