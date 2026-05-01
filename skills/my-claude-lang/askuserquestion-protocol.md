# AskUserQuestion Protocol (since MCL 6.0.0)

Every CLOSED-ENDED MCL interaction uses Claude Code's native
`AskUserQuestion` tool. The legacy `✅ MCL APPROVED` text marker is
REMOVED — Claude must never emit it; it carries no state effect.

## Question format contract

Every MCL-initiated `AskUserQuestion` call MUST set `question` beginning
with the literal prefix `MCL {{MCL_VERSION}} | ` followed by the localized question
body in the developer's detected language. Version tracks the banner.

```
AskUserQuestion({
  question: "MCL {{MCL_VERSION}} | <localized question body>",
  options: ["<approve-family-in-language>", "<edit-option>", "<cancel-option>"]
})
```

The Stop hook parses the most-recent `AskUserQuestion` tool_use /
tool_result pair with the `MCL {version} | ` prefix and transitions state
based on the selected option.

## The 12 closed-ended moments

Every one of these MUST use `AskUserQuestion`. Plain-text "reply yes/no"
prompts are forbidden for these moments.

| # | Moment | Where it fires | Approve-family option |
|---|--------|----------------|-----------------------|
| 1 | Phase 1 clarifying questions (multi-option choice) | When developer's prompt is ambiguous and requires picking from a limited set | n/a — open-ended choice questions, not approve/reject |
| 2 | Phase 1 summary confirmation | After parameter gathering is complete | "Evet, doğru" / "Yes, correct" / "Sí, correcto" / … |
| 3 | Phase 1.7 GATE questions (precision-audit) | When a precision dimension has architectural impact requiring developer decision | n/a — surgical option list per dimension |
| 4 | Rule A git-init consent | First MCL activation per project when no `.git/` exists | "Evet, git init çalıştır" / "Yes, run git init" / … |
| 5 | Plugin suggestion (per plugin) | First-message plugin-install suggestion block | "Kur" / "Install" / "Instalar" / … |
| 6 | Stack auto-detect fallback | Phase 1 if `mcl-stack-detect.sh` returns empty | "Python" / "Node" / "Go" / … (stack options) |
| 7 | Phase 4.5 risk walkthrough (per risk) | Each detected risk — one AskUserQuestion per risk | "Kabul et" / "Düzelt" / "Atla" / "Kural yap" |
| 8 | Phase 4.6 impact walkthrough (per impact) | Each detected impact | Same as Phase 4.5 |
| 9 | Phase 4b UI review | When ui_sub_phase=REVIEW and developer must approve UI before backend | "Onayla" / "Düzenle" / "Sen de bak" |
| 10 | `mcl-update` confirmation | After status report, before running `git pull && bash install.sh` | "Güncelle" / "Update" / … |
| 11 | `mcl-finish` confirmation | Before writing the checkpoint file | "Finalize et" / "Finalize" / … |
| 12 | Pasted-CLI passthrough | When pasted command hits a genuinely ambiguous parameter | Surgical option list for the parameter |

**REMOVED from this list (since 9.2.1):**
- ~~Phase 3 spec approval~~ — auto-approve on spec emit (hook-driven). Do NOT call AskUserQuestion after the `📋 Spec:` block.
- ~~Partial-spec recovery askq~~ — model re-emits spec inline when hook returns `decision:block`; no askq involved.

## Does NOT apply to (stay as plain text)

- Phase 1 OPEN-ENDED gathering ("What do you want to build?", "What are the
  constraints?") — these go through prose, not askq
- Spec body itself — the `📋 Spec:` block is plain markdown
- Phase 3 spec language explanation (prose that precedes auto-approve)
- Phase 4 code writing (Edit/Write/MultiEdit tool calls, not developer
  questions)
- Phase 5 Verification Report (prose output)
- **Spec approval (since 9.2.1)** — auto-approve on spec emit, no askq

**Phase 1 questions ARE askq-driven for multi-choice.** When the
developer's intent has 2-5 valid interpretations, present them via
AskUserQuestion with surgical options ("E-ticaret", "SaaS admin",
"İçerik yönetimi", "Diğer") rather than open prose.

## Approve family — 14-language token whitelist

The Stop hook's `_mcl_is_approve_option()` matches the selected option
via case-insensitive substring against the following token set. Claude
should always include one option containing one of these tokens so the
Stop hook can deterministically detect approval.

| Language   | Approve tokens (substring match, case-insensitive)              |
|------------|-----------------------------------------------------------------|
| Turkish    | onayla, onaylıyorum, evet, kabul, tamam                         |
| English    | approve, yes, confirm, ok, proceed, accept                      |
| Spanish    | aprobar, sí / si, confirmar                                     |
| French     | approuver, oui, confirmer                                       |
| German     | genehmigen, bestätigen, ja                                      |
| Japanese   | 承認, はい, 確認, 了解                                           |
| Korean     | 승인, 네, 확인, 예                                               |
| Chinese    | 批准, 是, 确认                                                   |
| Arabic     | موافق, نعم, تأكيد                                               |
| Hebrew     | אשר, כן, אישור                                                  |
| Hindi      | स्वीकार, हाँ / हां                                                |
| Indonesian | setujui, ya, konfirmasi                                         |
| Portuguese | aprovar, sim, confirmar                                         |
| Russian    | одобрить, да, подтвердить                                       |

Non-approve options (edit, cancel, skip, reject, change) are free-form
in the developer's language — the Stop hook simply treats any
non-approve option as a "do not advance state" signal and logs
`askq-non-approve`.

## Stop-hook behavior summary

- Scans the transcript for all `tool_use` blocks with
  `name=="AskUserQuestion"` and pairs each with its `tool_result` by
  `tool_use_id`.
- Filters by the `^MCL \d+\.\d+\.\d+ \| (.+)$` prefix regex.
- Classifies semantic intent (`summary-confirm`, `ui-review`, `other`)
  by substring matching the question body against a fixed token table.
  **Note:** `spec-approve` intent is no longer transition-driving since
  9.2.1; the scanner still detects it as a diagnostic but no state
  changes — spec auto-approve happens on spec emit, not askq response.
- Extracts the selected option from the tool_result by matching against
  `tool_use.input.options` first, then raw tool_result text.

- Never transitions on a text-only `yes` without the paired tool_result.

## Malformed-prefix handling

If Claude emits an AskUserQuestion with a prefix that does not match
`^MCL \d+\.\d+\.\d+ \| ` (e.g., `MCL 6 |`, `MCL | `, or no prefix at
all), the Stop hook skips it silently (logs `askq-ignored-wrong-phase`
/ `askq-ignored-no-spec` depending on state). No state transition
occurs. Claude must re-issue the question with the correct prefix.
