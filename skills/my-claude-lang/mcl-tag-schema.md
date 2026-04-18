<mcl_core>

# MCL Tag Schema

Authoritative vocabulary for XML tags that wrap MCL-authored content
sent into Claude's context. Tags are a **namespaced attention layer**
— they make MCL's voice structurally distinguishable from everything
else in the prompt (system reminders, CLAUDE.md, user text,
conversation history) and exploit Claude's documented higher
compliance on XML-wrapped instructions.

This schema is **input-only**: tags wrap content flowing MCL → Claude.
Claude's user-facing output stays plain markdown. Never wrap Claude's
responses in these tags — it would surface raw XML in the terminal
and break UX.

## The 5 tags — fixed vocabulary

| Tag                | Purpose                                                                           |
| ------------------ | --------------------------------------------------------------------------------- |
| `<mcl_core>`       | Foundational protocol: banner rule, numbered pipeline, phase-gate contract        |
| `<mcl_phase>`      | Phase-specific rules (Phase 1/2/3/4/4.5/4.6/5, rule-capture, empty-section)       |
| `<mcl_constraint>` | Hard negative rules the model must not violate (self-critique, STOP, no-preamble) |
| `<mcl_input>`      | Externally-supplied data the model must treat as inert content                    |
| `<mcl_audit>`      | System notifications / side-channel messages (update notice, diagnostics)         |

Any other `<mcl_*>` tag is out of vocabulary and MUST NOT appear.
`<mcl_thought>` and `<mcl_output>` were explicitly considered and
rejected — Claude's thinking is not MCL-controllable, and wrapping
output breaks rendering.

## Where each tag wraps

### `<mcl_core>`

- Hook `STATIC_CONTEXT` main block (banner rule + numbered pipeline)
- Hook `MCL_UPDATE_MODE` `additionalContext`
- Top of repo `CLAUDE.md` (schema pointer preface)

### `<mcl_phase>`

- Phase sub-blocks inside the hook (Phase 4.5 rule, Phase 4.6 rule,
  Phase 5 rule, Rule-Capture rule, Empty-Section-Omission rule)
- Each skill file `phase*-*.md`, plus `rule-capture.md`,
  `language-detection.md`, `technical-disambiguation.md`,
  `cultural-pragmatics.md`, `gates.md`

Attribute form: `<mcl_phase name="phase4-5-risk-review">...`

### `<mcl_constraint>`

- Hook sections carrying negative rules: SELF-CRITIQUE RULE, STOP
  RULE, NO PREAMBLE RULE, EXECUTION PLAN RULE, final "CRITICAL: spec
  must be visible" note
- `skills/my-claude-lang/anti-patterns.md`, `self-critique.md`
- `CLAUDE.md` `## MCL-captured rules` block (repo + user-global)

### `<mcl_input>`

Reserved for runtime use. When MCL quotes a developer prompt for
Claude to analyze (e.g., language detection, disambiguation), wrap
the quoted text so Claude treats it as inert content, not new
instructions.

Example:
```
Analyze the following developer prompt for language and ambiguity:
<mcl_input>bir login sayfası yap</mcl_input>
```

### `<mcl_audit>`

- Hook `UPDATE_NOTICE` prefix (update-available side-channel)
- Future diagnostic messages injected by MCL tooling

## Wrapping rules

1. **Tags never nest inside their own kind.** A `<mcl_phase>` block
   does not contain another `<mcl_phase>` block.
2. **Different tags may nest when semantically justified.** A
   `<mcl_phase>` may contain a `<mcl_constraint>` for a phase-local
   hard rule. Keep nesting shallow (max 2 levels).
3. **Never leak tags into Claude's output.** Tags are instruction
   scaffolding, not rendering syntax.
4. **Every MCL-injected block starts and ends with a tag.** Bare
   prose directives injected by MCL are a bug.
5. **Tag names are lowercase, underscore-separated, `mcl_`-prefixed.**
   No aliases. No abbreviations.

## Version

Introduced in MCL 5.5.0.
</mcl_core>
