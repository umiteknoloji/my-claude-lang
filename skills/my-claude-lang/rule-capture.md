<mcl_phase name="rule-capture">

# Rule Capture

MCL can persist user-approved general rules to the appropriate `CLAUDE.md`
layer so Claude honors them in future sessions without the user restating
them. Rules are written only after explicit preview approval. Rules are
written in precise, imperative English (Claude reads English); a
sibling-comment localization is kept next to each rule for the user to
verify.

## When Rule Capture Triggers

The capture flow may trigger in two situations:

1. **During the Phase 4.5 Post-Code Risk Review dialog**: when the user
   says "make this a general rule" for a risk being discussed. (Before
   MCL 5.3.0 this dialog lived inside Phase 5; it is now its own phase.)
2. **Anywhere MCL detects a generalizable pattern**: if during normal
   work MCL notices a recurring preference ("don't use try/catch
   fallback", "always use pnpm, not npm"), it may ask the user:
   *"Should I always do it this way?"* (rendered in the user's language).

If the user declines, nothing happens. Silence is a valid answer.

## Scope Selection

When the user accepts, MCL asks for scope with exactly three options,
phrased in the user's language:

- **Once only** → no storage, applies just to this case
- **This project** → write to `<CWD>/CLAUDE.md`
- **All my projects** → write to `~/.claude/CLAUDE.md`

`<CWD>` means the current working directory the session was opened in
(the developer's actual project, not the MCL plugin repo). MCL never
writes rules to the MCL plugin repo unless the user is actively
developing MCL itself and explicitly chooses project scope there.

## Scope Sanity Check

Before writing, MCL assesses whether the rule suits the chosen scope.
If MCL judges it inappropriate (e.g., a React-specific rule tagged
"all projects" when the user also has Go or Python projects), MCL asks
**exactly one** follow-up question citing the specific concern:

> *"This rule looks React-specific; apply it to all your projects anyway?"*

If the user confirms, MCL proceeds silently. No second warning — one
challenge is enough. The user's final decision stands.

Inverse case: if the user picks "this project" for something clearly
universal (e.g., "never hardcode secrets"), MCL may also flag once:

> *"This rule reads as universal; apply it to all your projects instead?"*

Same rule: one challenge, then defer.

## Rule Preview — MANDATORY Before Writing

MCL NEVER writes to `CLAUDE.md` without showing the exact text first.
Preview shows both versions:

```
Proposed rule:

EN (what Claude will read):
  Never use try/catch fallback patterns that silently swallow errors;
  let errors propagate.

TR (for your review):
  Try/catch fallback kullanma — hatayı sessizce yutan kalıplar yasak,
  hata yukarı fırlatılsın.

Scope: This project → /path/to/project/CLAUDE.md

Approve this exact text? (yes / edit / cancel)
```

- **yes** → MCL writes the rule
- **edit** → the user dictates changes; MCL re-shows the preview
- **cancel** → nothing is written; flow continues

The English version is what matters for Claude's behavior. The
user-language version is informational.

## English Rule Format

Rules MUST be imperative and unambiguous. Preferred templates:

- `Never <action>; <reason or alternative>.`
- `Always <action>.`
- `Prefer <X> over <Y> for <context>.`
- `Do not <action> unless <specific condition>.`

Forbidden in rule text:
- Vague modifiers: "generally", "usually", "maybe", "try to"
- Subjective descriptors: "nice", "clean", "modern"
- Unscoped negatives: "don't do bad things"

If MCL cannot phrase the user's intent precisely, it asks clarifying
questions before showing the preview — never writes a vague rule just
because the user was vague.

## Write Format

Each rule is appended under an `## MCL-captured rules` heading in the
target `CLAUDE.md`. If the heading does not exist, MCL creates it. If
`CLAUDE.md` itself does not exist, MCL creates a minimal file:

```markdown
# Project rules

## MCL-captured rules

- Never use try/catch fallback patterns that silently swallow errors; let errors propagate. <!-- loc: TR: Try/catch fallback kullanma — hatayı sessizce yutan kalıplar yasak, hata yukarı fırlatılsın. -->
- Always use pnpm, never npm or yarn. <!-- loc: TR: Her zaman pnpm kullan — npm veya yarn kullanma. -->
```

The HTML comment format `<!-- loc: <LANG-CODE>: <translation> -->` keeps
Claude parsing only the English directive while preserving the user's
localized version for later display. Use ISO-like language codes: `TR`,
`EN`, `ES`, `FR`, `JA`, `KO`, `AR`, etc.

## Conflict Detection

Before writing, MCL scans the target `CLAUDE.md`'s `## MCL-captured rules`
section for semantically-overlapping rules. Overlap signals:

- Same subject (e.g., "fallback", "pnpm")
- Same verb polarity (both positive or both negative)
- One contradicts or supersedes the other

On match, MCL shows both rules side-by-side in the user's language and
asks: *"Rule X already exists. Overwrite, keep both, or cancel?"*

- **Overwrite** → old rule is deleted, new rule is appended
- **Keep both** → both coexist; MCL does not de-duplicate silently
- **Cancel** → nothing is written

## Rule Query

When the user asks a question like *"what rules did we set?"*, *"hangi
kurallar var?"*, *"¿qué reglas hay?"* — in any language — MCL:

1. Reads `<CWD>/CLAUDE.md` (if present) and extracts the
   `## MCL-captured rules` section.
2. Reads `~/.claude/CLAUDE.md` (if present) and extracts the
   `## MCL-captured rules` section.
3. Displays both groups separately in the user's language, using the
   `<!-- loc: -->` translations where available; falls back to the
   English text when no localization exists.

Example response (Turkish user):

```
Bu projede tanımlı kurallar (/path/to/project/CLAUDE.md):
- Try/catch fallback kullanma — hatayı sessizce yutan kalıplar yasak.

Tüm projelerinde tanımlı kurallar (~/.claude/CLAUDE.md):
- Her zaman pnpm kullan — npm veya yarn kullanma.
```

If both files are absent or empty, MCL replies plainly: *"No rules
captured yet."* in the user's language.

## Edge Cases

- **CWD is not a project root (no git, no package.json, no pyproject.toml)**
  → project scope is unavailable. MCL offers only "once only" and
  "all my projects" and explains why project scope is hidden.
- **User cancels during preview** → nothing is written; flow continues
  to the next open topic (next missed risk, or normal work).
- **Conflict, user chooses "keep both"** → both rules persist verbatim;
  MCL does not merge or re-word them.
- **User edits the proposed rule text** → MCL re-runs the preview with
  the new text; preview approval restarts.
- **User rule is ambiguous even after editing** → MCL asks one more
  clarifying question; never writes a vague rule.
- **Missed Risks dialog interrupted by a new topic** → the open risk is
  marked skipped; MCL does not re-raise it unless the user asks.
- **Rule query while user is outside any project (home directory,
  random tmp dir)** → MCL can only read `~/.claude/CLAUDE.md`; it
  tells the user project-scoped rules cannot be read here.
- **User asks for rules in a non-Turkish language not covered by a
  stored `<!-- loc: -->` tag** → MCL shows the English directive as-is
  with a brief note that no translation exists for that rule.

## What Rule Capture Is NOT

- Not silent — nothing is written without the user seeing the exact text.
- Not automatic — MCL offers; the user decides.
- Not a general memory system — rule capture is strictly about durable
  directives Claude must follow in future sessions. Other context
  (project notes, user profile) belongs elsewhere.
- Not irreversible — captured rules live in plain `CLAUDE.md` files.
  The user can edit or delete them with any text editor at any time.

## Integration with Phase 4.5

During the Phase 4.5 Post-Code Risk Review interactive dialog, when the
user picks "make this a general rule" for a risk, MCL:

1. Triggers the rule capture flow immediately for that risk.
2. After the flow completes (rule saved, saved+user-level, or cancelled),
   MCL moves to the next missed risk.
3. If the user picks "skip" or "apply specific fix", the risk is
   resolved locally with no rule capture.

## Anti-Sycophancy in Rule Capture

When the user insists on a scope MCL disagrees with, MCL does NOT
soften the sanity-check question. One clear, direct challenge is
allowed; then MCL defers. MCL never adds "great rule!" or "nice
choice!" after approval. The rule is written silently once confirmed.

</mcl_phase>
