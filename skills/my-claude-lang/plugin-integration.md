# Plugin Integration — Bridge Scope

MCL is a cross-cutting bridge, not a workflow monopolist. Other Claude
Code plugins (`/feature-dev`, `/pr-review`, `/code-simplifier`,
`/skill-creator`, and any future third-party slash command) run their
own workflows with their own prompts. This file defines how MCL's bridge
behaves when such a plugin is driving.

## The rule

When a third-party slash-command plugin is invoked and runs its own
workflow, MCL's language bridge still applies unconditionally: every
developer-facing question, report, decision prompt, progress update,
and summary produced by that plugin's workflow is rendered in the
developer's detected language — exactly as if MCL itself wrote it.

**Bridge scope is defined by the reader, not by the producer.** It does
not matter which plugin emitted the text. If the developer reads it, it
goes through the bridge.

## What "bridge applies" means concretely

- Clarifying questions asked by `/feature-dev` Aşama 4 → rendered in
  the developer's language, with MCL's standard "WHY it's asking +
  WHAT each answer changes" context layer.
- Architecture-option summaries and recommendations from
  `/feature-dev` Aşama 7 → section headers, verdicts, trade-off
  labels all localized per the `MCL-captured rules` on header
  localization.
- Code-review findings from `/pr-review` or `/code-review` → severity
  labels, rationale text, and fix suggestions localized; file paths,
  line numbers, code identifiers stay verbatim.
- Progress updates, "waiting for approval" prompts, and final
  summaries from any plugin → localized.

## What stays unchanged

- The plugin's **internal instructions** to Claude (its command
  markdown, its agent prompts) remain in English — they are
  producer-facing, not developer-facing.
- **Agent-to-agent dispatch text** (e.g., `/feature-dev` launching
  `code-explorer` agents in parallel) stays in English; only the
  agent's **results, summarized back to the developer**, go through
  the bridge.
- **Fixed technical tokens**: file paths, line numbers, CLI flags,
  code identifiers, MUST/SHOULD, English-native technical terms (API,
  REST, OAuth, JWT, etc.) remain verbatim.
- The plugin's **workflow structure** (its own phases, its own
  approval gates, its own agent launches) — MCL does not override
  these. The bridge is language-only.

## Anti-sycophancy still applies

MCL's anti-sycophancy filter applies to third-party plugin output as
well. Unearned praise, softening qualifiers, closing flourishes, and
balancing hedges in a plugin's output are filtered the same way they
are in MCL's own output.

## Out of scope (this file)

- **Workflow ownership conflicts.** If MCL is mid-Aşama 1
  (clarifying-question dialog) and the developer types
  `/feature-dev ...`, who owns the workflow from that turn forward?
  That question is not answered here. Default assumption: the
  explicitly-invoked slash command becomes the active workflow; MCL's
  implicit universal-activation workflow defers. But the bridge rule
  above applies regardless of who owns the workflow.
- **Spec history auto-save.** Third-party plugins do not produce
  MCL `📋 Spec:` blocks, so `.mcl/specs/` writes do not fire for
  their workflows. Whether they should is a separate design
  question.
- **Plugin discovery / auto-install.** Covered by
  `plugin-suggestions.md` (LSP plugins only, at first developer
  message). No auto-install of workflow plugins.

## Example walkthrough — `/feature-dev`

Turkish developer types:

> `/feature-dev login sayfası ekle`

feature-dev's command prompt activates and runs its Aşama 1
(Discovery). MCL's bridge intercepts every developer-facing emission:

- feature-dev's "What problem are you solving?" →
  "Hangi sorunu çözüyorsun?"
- feature-dev's "I've designed 3 approaches: ..." →
  section headers localized ("3 yaklaşım tasarladım: ..."), the
  approaches themselves rendered in Turkish, file paths and
  identifiers untouched.
- feature-dev's Phase 6 review findings → severity labels localized
  ("Yüksek Öncelikli Sorunlar", "Orta Öncelikli"), rationale in
  Turkish, code citations verbatim.

The developer sees feature-dev's 7-phase workflow fully, in Turkish,
without ever noticing a language seam. Bridge scope held.
