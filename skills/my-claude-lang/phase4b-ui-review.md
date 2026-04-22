<mcl_phase name="phase4b-ui-review">

# Phase 4b: UI_REVIEW — Developer-Verified Before Backend

**`superpowers` (tier-A, ambient):** active throughout this phase.

## Entry Condition

Phase 4b starts the moment Phase 4a emits its final "run it" snippet.
No state flag flip — it is a direct call from Phase 4a procedure step 6.

## Core Intent

Block every backend write (`mcl-pre-tool.sh` UI-BUILD lock is still
active) until the developer has opened the UI in their browser and
explicitly approved moving to backend integration. This is the
second spec-approval kapısı in UI flows — it exists because spec
approval at Phase 3 cannot fully verify visual intent.

## Sub-Topic Files

For the opt-in "MCL sees its own UI" pipeline (Playwright + screenshot
+ Read multimodal), read `my-claude-lang/phase4b-ui-review/visual-inspect.md`.

## Review AskUserQuestion

After Phase 4a emits the run snippet, call:

```
AskUserQuestion({
  question: "MCL 6.2.0 | <localized: UI reviewed? proceed to backend?>",
  options: [
    "<approve-family: approve, proceed to backend>",
    "<revise: rewrite the UI>",
    "<visual-inspect: MCL look at it and report>",
    "<cancel>"
  ]
})
```

Option labels MUST be in the developer's language (all 14 supported
locales). Reference labels:

| Locale | Approve                    | Revise                        | Visual inspect                      | Cancel    |
| ------ | -------------------------- | ----------------------------- | ----------------------------------- | --------- |
| TR     | Onay — backend'e geç       | Revize — şunu değiştir        | Sen de bak ve raporla               | İptal     |
| EN     | Approve — proceed to backend | Revise — change this        | See it yourself and report          | Cancel    |
| JA     | 承認 — バックエンドへ進む  | 修正 — ここを変える           | 自分で確認して報告                  | キャンセル |
| KO     | 승인 — 백엔드로 진행       | 수정 — 여기를 바꿔라          | 직접 확인하고 보고해                | 취소      |
| ZH     | 批准 — 进入后端             | 修改 — 改这里                 | 你自己看看并报告                    | 取消      |
| AR     | موافق — انتقل إلى الخلفية   | مراجعة — غيّر هذا             | شاهد بنفسك وقدّم تقريراً            | إلغاء     |
| HE     | אישור — עבור לבקאנד        | תיקון — שנה את זה             | בדוק בעצמך ודווח                   | ביטול    |
| DE     | Genehmigen — weiter zum Backend | Überarbeiten — das ändern | Sieh es dir selbst an und berichte | Abbrechen |
| ES     | Aprobar — pasar al backend | Revisar — cambiar esto        | Mira tú mismo e informa             | Cancelar  |
| FR     | Approuver — passer au backend | Réviser — changer ceci     | Regarde toi-même et rapporte        | Annuler   |
| HI     | स्वीकृति — बैकएंड पर जाएं  | संशोधन — इसे बदलें            | खुद देखें और रिपोर्ट करें          | रद्द करें |
| ID     | Setuju — lanjut ke backend | Revisi — ubah ini             | Lihat sendiri dan laporkan          | Batal     |
| PT     | Aprovar — seguir para o backend | Revisar — mudar isto     | Veja você mesmo e reporte           | Cancelar  |
| RU     | Одобрить — перейти к бэкенду | Доработать — изменить это  | Посмотри сам и сообщи               | Отмена    |

## Dispatch Table (result of AskUserQuestion)

| Option chosen       | Stop-hook intent     | State transition                             | Next MCL step                  |
| ------------------- | -------------------- | -------------------------------------------- | ------------------------------ |
| Approve             | `ui-review-approve`  | `ui_reviewed=true`, `ui_sub_phase="BACKEND"` | Phase 4c (`phase4c-backend.md`) |
| Revise              | `ui-review-revise`   | no state change                              | Re-enter Phase 4a with feedback |
| Visual inspect      | `ui-vision-request`  | no state change                              | Run visual-inspect sub-skill    |
| Cancel              | `ui-review-cancel`   | state cleared (ui flags reset)               | Abort                          |

The stop hook detects these intents by matching option-label tokens
against the 14-language token sets defined in `hooks/mcl-stop.sh`
(`UI_REVIEW_TOKENS`, `_mcl_is_ui_skip_option`,
`_mcl_is_vision_request_option`).

## Revise Loop

When Revise is chosen, the developer's free-text feedback is the input
for the next Phase 4a turn. Treat feedback as parameters for the
existing spec — do NOT re-run Phase 1/2/3. The spec is still
canonical; only the visual realization is being tweaked.

If the feedback contradicts the approved spec ("change the primary
button to a signup form instead"), that is scope creep — treat it
exactly like the "Yes but..." rule (see `phase1-rules.md`): run a
fresh Phase 1-3 cycle for the delta, do not quietly rewrite.

## Visual-Inspect Loop

When "See it yourself" is chosen, run the pipeline in
`phase4b-ui-review/visual-inspect.md`, emit the observation report,
then re-call this same review `AskUserQuestion` so the developer can
still choose approve / revise / cancel. Visual-inspect is
informational — it never auto-advances to Phase 4c.

## Cancel

Cancel clears the UI state flags via stop-hook and aborts the task
entirely. The `.mcl/specs/NNNN-slug.md` entry is marked
`status: cancelled` (handled by stop-hook spec-history extension).

## Exit

Only "Approve" exits Phase 4b. On approve, the next turn starts
Phase 4c; the UI-BUILD pre-tool lock is lifted (because
`ui_sub_phase = "BACKEND"` now).

</mcl_phase>
