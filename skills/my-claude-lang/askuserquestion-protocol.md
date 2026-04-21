# AskUserQuestion Protocol (since MCL 6.0.0)

Every CLOSED-ENDED MCL interaction uses Claude Code's native
`AskUserQuestion` tool. The legacy `✅ MCL APPROVED` text marker is
REMOVED — Claude must never emit it; it carries no state effect.

## Question format contract

Every MCL-initiated `AskUserQuestion` call MUST set `question` beginning
with the literal prefix `MCL 6.0.0 | ` followed by the localized question
body in the developer's detected language. Version tracks the banner.

```
AskUserQuestion({
  question: "MCL 6.0.0 | <localized question body>",
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
| 1 | Phase 1 summary confirmation | After parameter gathering is complete | "Evet, doğru" / "Yes, correct" / "Sí, correcto" / … |
| 2 | Phase 3 spec approval | Immediately after the `📋 Spec:` block and its localized explanation | "Onayla" / "Approve" / "Aprobar" / … |
| 3 | Rule A git-init consent | First MCL activation per project when no `.git/` exists | "Evet, git init çalıştır" / "Yes, run git init" / … |
| 4 | Plugin suggestion (per plugin) | First-message plugin-install suggestion block; one AskUserQuestion per suggested plugin | "Kur" / "Install" / "Instalar" / … |
| 5 | Stack auto-detect fallback | Phase 1 if `mcl-stack-detect.sh` returns empty but developer started a concrete task | "Python" / "Node" / "Go" / … (stack options) |
| 6 | Phase 4.5 risk walkthrough (per risk) | Each detected risk — one AskUserQuestion per risk | "Kabul et" / "Düzelt" / "Atla" — with "Kural yap" as a fourth option when generalizable |
| 7 | Phase 4.6 impact walkthrough (per impact) | Each detected impact — one AskUserQuestion per impact | Same as Phase 4.5 |
| 8 | Partial-spec recovery | When `partial_spec=true` state was set by the Stop hook on the prior turn | "Bu spec'i onayla" / "Approve this spec" — note: tool_result is IGNORED by Stop hook while `partial_spec=true`; Claude must first re-emit a complete spec |
| 9 | `mcl-update` confirmation | After status report, before running `git pull && bash setup.sh` | "Güncelle" / "Update" / … |
| 10 | `mcl-finish` confirmation | Before writing the checkpoint file | "Finalize et" / "Finalize" / … |
| 11 | Pasted-CLI passthrough | When pasted command hits a genuinely ambiguous parameter beyond defaults | Surgical option list for the specific parameter |
| 12 | Drift resolution | When `drift_detected=true` in state (activate hook emits DRIFT_NOTICE) | Two-path options: "Yeni spec'i onayla" (re-approve) OR "Onaylı spec'e geri dön" (revert) |

## Does NOT apply to (stay as plain text)

- Phase 1 OPEN-ENDED gathering ("What do you want to build?", "What are the
  constraints?", "Which database?")
- Spec body itself — the `📋 Spec:` block is plain markdown
- Phase 3 language explanation (prose that precedes the approval
  AskUserQuestion call)
- Phase 4 code writing (Edit/Write/MultiEdit tool calls, not developer
  questions)
- Phase 5 Verification Report (prose output)

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
- Classifies semantic intent (`spec-approve`, `summary-confirm`, `other`)
  by substring matching the question body against a fixed token table.
- Extracts the selected option from the tool_result by matching against
  `tool_use.input.options` first, then falling back to raw tool_result
  text.
- For `spec-approve` + approve-family option → sets
  `spec_approved=true`, `current_phase=4`, emits
  `approve-via-askuserquestion` audit entry. While `partial_spec=true`
  the tool_result is IGNORED (`askq-ignored-partial-spec` audit).
- For drift re-approval (previous state had `drift_detected=true`),
  clears drift with `drift-reapproved | via=askuserquestion` audit.
- Never transitions on a text-only `yes` without the paired tool_result.

## Malformed-prefix handling

If Claude emits an AskUserQuestion with a prefix that does not match
`^MCL \d+\.\d+\.\d+ \| ` (e.g., `MCL 6 |`, `MCL | `, or no prefix at
all), the Stop hook skips it silently (logs `askq-ignored-wrong-phase`
/ `askq-ignored-no-spec` depending on state). No state transition
occurs. Claude must re-issue the question with the correct prefix.
