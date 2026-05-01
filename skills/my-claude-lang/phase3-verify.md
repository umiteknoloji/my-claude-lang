<mcl_phase name="phase3-verify">

# Phase 3: Claude Code Understanding Verification

**`superpowers` (tier-A, ambient):** active throughout this phase — no explicit dispatch point; its methodology layer applies as a behavioral prior.

Called automatically when spec is generated.

1. Claude Code must summarize its understanding in English
2. Format: "I understand the task as: [summary]. I will: [action plan]. Is this correct?"
3. MCL applies Gate 2: check Claude Code's summary for vague terms or
   implicit assumptions. Challenge if found. Only proceed when Claude Code's
   understanding is precise.
4. MCL applies Gate 3: translate Claude Code's verified summary to the
   developer's language. Explain technical concepts, don't just translate words.
5. Present the translated summary and action plan as plain text:

```
[DEVELOPER'S LANGUAGE]
━━━━━━━━━━━━━━━━━━━━━
Claude Code understood it this way:

[translated summary of Claude Code's interpretation]

[translated action plan]
━━━━━━━━━━━━━━━━━━━━━
```

5.5. **Technical Challenge Pass** — Before calling AskUserQuestion, silently
   ask yourself: "Does this spec have a concrete, specific technical problem?"

   Qualifying problems (specific and actionable, not vague):
   - Algorithmic scale issue (e.g., O(n²) on a large dataset)
   - Race condition in shared state or concurrent access
   - N+1 query with no index on the join path
   - Missing auth check or unescaped input on a trust boundary
   - Unhandled cascading failure mode
   - Contradiction with loaded project memory (`.mcl/project.md` patterns)

   **If a concrete problem is found:** add ONE localized line to the response
   AFTER the translated summary and BEFORE the AskUserQuestion call:
   - Turkish: `⚠️ Teknik not: [tek cümle spesifik sorun]. Devam edebilirsiniz — onaylamadan önce bu riski değerlendirin.`
   - English: `⚠️ Technical note: [one sentence specific issue]. You can proceed — evaluate this risk before approving.`
   Localize to the developer's detected language. One line, one problem, no list.

   **If no concrete problem or only a vague concern:** skip silently. Do NOT
   add "potential risks" or hedge language — only concrete findings surface.

   This is NOT a gate. The developer can approve even with the note.

6. Then call (since 6.0.0):
```
AskUserQuestion({
  question: "MCL {version} | <localized 'Approve this spec?' — e.g.
    Turkish: Bu spec'i onaylıyor musun?; English: Approve this spec?>",
  options: [
    { label: "<approve-verb-only>", description: "<free-form context>" },
    { label: "<edit-verb>",         description: "<free-form context>" },
    { label: "<cancel-verb>",       description: "<free-form context>" }
  ]
})
```

   **Label Discipline (since 6.4.1 — MANDATORY).** The approve option's
   `label` is the BARE VERB in the developer's detected language — NO
   descriptive suffix. Use the canonical 14-language set from
   [askuserquestion-protocol.md:32](my-claude-lang/askuserquestion-protocol.md):

   | Locale | Approve label |
   | ------ | ------------- |
   | TR     | Onayla        |
   | EN     | Approve       |
   | ES     | Aprobar       |
   | FR     | Approuver     |
   | DE     | Genehmigen    |
   | JA     | 承認           |
   | KO     | 승인           |
   | ZH     | 批准           |
   | AR     | موافق          |
   | HE     | אשר           |
   | HI     | स्वीकार        |
   | ID     | Setujui       |
   | PT     | Aprovar       |
   | RU     | Одобрить      |

   FORBIDDEN approve labels (examples of drift): `Onayla, kodu yaz`,
   `Approve and proceed`, `Approve, write code`, `Aprobar y continuar`,
   `承認して実装へ`, `승인하고 코드 작성`, `Genehmigen und codieren`.
   Any descriptive context belongs in the option's `description` field,
   NOT in `label`.

   The `edit` and `cancel` labels stay free-form localized verbs
   (`Düzenle` / `İptal` / `Edit` / `Cancel` / etc.) — this rule
   restricts the approve label only.

   Do NOT emit the legacy `✅ MCL APPROVED` marker — dead in 6.0.0.

7. If developer picks a non-approve option → ask "What did I get
   wrong?", fix the English spec, repeat Phase 3.
8. Only when the tool_result returns an approve-family option → Stop
   hook flips state to Phase 4 (`approve-via-askuserquestion` audit).
9. After the tool_result returns an approve-family option — and BEFORE
   Phase 4 code writing begins — resolve the test command (STEP-24).
   Resolution priority (first non-empty result wins):

   a. Check config: `bash ~/.claude/hooks/lib/mcl-config.sh get test_command`.
      Non-empty → resolved, proceed to Phase 4.
   b. Auto-detect: `bash ~/.claude/hooks/lib/mcl-test-runner.sh detect`.
      Non-empty → resolved, proceed to Phase 4.
   c. Infer from the approved spec's Technical Approach section.
      Read the stack/framework named there and map to a canonical test command:
      - Node.js + Jest → `npx jest`
      - Node.js + Vitest → `npx vitest run`
      - Node.js (no explicit runner) → `npm test`
      - Python + pytest → `pytest`
      - Python + unittest → `python -m unittest`
      - Go → `go test ./...`
      - Ruby / Rails → `bundle exec rspec`
      - PHP + PHPUnit → `./vendor/bin/phpunit`
      - Java + Maven → `mvn test`
      - Java + Gradle → `./gradlew test`
      - Rust → `cargo test`
      - Swift → `swift test`
      If a confident single mapping exists → use it silently, proceed to Phase 4.
      If the spec names a stack with multiple valid runner options → fall through to d.
   d. Still unresolved → ask the developer ONE question in their language:

      > Turkish: *TDD her Phase 4'te çalışıyor. Bu projede testler
      > hangi komutla koşuyor? ('yok' dersen TDD bu session için
      > atlanır.)*
      >
      > English: *TDD runs on every Phase 4. What command runs the
      > tests in this project? (type 'none' to skip TDD for this
      > session.)*

      - Non-empty reply → offer to persist as `test_command` in
        `.mcl/config.json`. Either way, the command is used for this session.
      - `none` / equivalent → session-scoped skip flag set; TDD overlay
        silently falls through to non-TDD execution.

   Skip this step entirely when:
   - Config, auto-detect, or spec inference already resolved the command.
   - Mid-session (Phase 4 / 4.5 / 4.6 / 5) is already in progress.

## Scope Changes Callout (since 8.4.0)

Phase 1.5 became upgrade-translator in 8.4.0 — vague verbs in the
developer's prompt are upgraded to surgical English in the brief, and
verb-implied standard patterns are annotated as
`[default: X, changeable]`. Phase 3 spec verification MUST surface
these upgrades back to the developer in their language so they can
correct anything that was added without their explicit ask.

**Trigger:** the session's `engineering-brief` audit emits
`upgraded=true` (one or more vague verbs were transformed).

**Skip:** `upgraded=false` (no upgrades; no callout needed).

**Format:** include a "Scope Changes" section in Phase 3 prose
**before** the AskUserQuestion spec-approval call. Render in the
developer's detected language. Each upgrade is one bullet:

```
**Spec'e eklenen mühendislik standartları:**
- Pagination [listele verbinden çıkarıldı, varsayılan: cursor-based — değiştirilebilir]
- Empty/loading/error UI states [render verbinden çıkarıldı, UI bağlamında]
- HTTP CRUD endpoints [yönet verbinden çıkarıldı, varsayılan: GET/POST/PUT/DELETE — değiştirilebilir]

İstemediğin bir ekleme varsa "düzenle" seç ve hangi maddeyi
kaldırmak istediğini belirt.
```

Localize per detected language (Turkish above; English / Spanish /
Japanese / 14 supported languages get the same structure with
translated section title and bullet wording).

**Source for each bullet:** the brief's "Verb upgrades" line lists
`<vague> → <surgical>` mappings; each surgical verb's `[default: X,
changeable]` markers in the spec become the callout bullets. Phase 3
prose author's job is purely to surface these — no judgment call,
no editing of the underlying upgrades.

**Why this exists:** developer reads Phase 3 spec via reverse
translation; without an explicit callout, invisible scope additions
look like part of the original intent. The callout makes the
upgrade-translator's work auditable to the very person it's supposed
to serve. Combined with Phase 4.5 Lens (e), it gives the developer
both pre-implementation visibility (Phase 3) and post-implementation
verification (Phase 4.5).

</mcl_phase>
