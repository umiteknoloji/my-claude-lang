<mcl_phase name="asama7-ui-review">

# Aşama 7: UI_REVIEW — Developer-Verified Before Backend

## Entry Condition

Aşama 7 is **deferred** since 6.5.0. Aşama 6 now auto-starts the dev
server and opens the browser, then STOPS. Aşama 7 only begins when
the developer returns on their own — i.e. on the developer's NEXT
turn after the browser-open, carrying a free-form reply in their own
words. There is no preemptive `AskUserQuestion`.

The state flags are unchanged (`ui_sub_phase = "BUILD_UI"`,
`ui_reviewed = false`) until the developer's reply is interpreted
and acted on.

## Core Intent

Block every backend write (`mcl-pre-tool.sh` UI-BUILD lock is still
active) until the developer has opened the UI in their browser and
explicitly approved moving to backend integration. This is the
second spec-approval kapısı in UI flows — it exists because spec
approval at Aşama 4 cannot fully verify visual intent.

## Sub-Topic Files

For the opt-in "MCL sees its own UI" pipeline (Playwright + screenshot
+ Read multimodal), read `my-claude-lang/asama7-ui-review/visual-inspect.md`.

## Interpreting the Developer's Free-Form Reply

When the developer's next turn arrives after Aşama 6's browser-open,
MCL reads their message and classifies it into one of three intents
**before** calling any tool. No `AskUserQuestion` is emitted up front —
the reply itself is the decision.

Intent classification (match against 14-language token sets; case-
insensitive, substring match, any-match wins):

| Intent          | Turkish cues                       | English cues                              |
| --------------- | ---------------------------------- | ----------------------------------------- |
| `approve`       | "beğendim", "güzel olmuş", "onay", "tamam devam", "backend'e geç" | "looks good", "approve", "ship it", "go backend", "proceed" |
| `revise`        | "şunu değiştir", "büyüt", "renk", "yanlış", "olmamış", "revize", free-form critique | "change", "fix", "smaller", "color", "wrong", "revise"   |
| `cancel`        | "iptal", "vazgeç", "durdur"        | "cancel", "stop", "abandon"               |

Full 14-language token sets live in `hooks/mcl-stop.sh` under
`UI_REVIEW_TOKENS` and must stay in sync.

**Tie-breakers:**
- Approve + revise tokens together → `revise` wins (e.g. "güzel ama
  butonu büyüt" is critique-bearing, not an approval).
- No recognised tokens and the reply is pure feedback prose → treat
  as `revise` with the whole message as the feedback payload.
- Ambiguous one-word reply in a non-cue form → fall back to the
  explicit `AskUserQuestion` below.

## Confirmation AskUserQuestion (fallback only)

If intent classification is genuinely ambiguous (empty reply, a
single emoji, a question back at MCL, etc.), and only then, emit:

```
AskUserQuestion({
  question: "MCL 6.5.0 | <localized: UI reviewed? proceed to backend?>",
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
| Approve             | `ui-review-approve`  | `ui_reviewed=true`, `ui_sub_phase="BACKEND"` | Aşama 6c (`asama6c-backend.md`) |
| Revise              | `ui-review-revise`   | no state change                              | Re-enter Aşama 6 with feedback |
| Visual inspect      | `ui-vision-request`  | no state change                              | Run visual-inspect sub-skill    |
| Cancel              | `ui-review-cancel`   | state cleared (ui flags reset)               | Abort                          |

The stop hook detects these intents by matching option-label tokens
against the 14-language token sets defined in `hooks/mcl-stop.sh`
(`UI_REVIEW_TOKENS`, `_mcl_is_ui_skip_option`,
`_mcl_is_vision_request_option`).

## Revise Loop

When Revise is chosen, the developer's free-text feedback is the input
for the next Aşama 6 turn. Treat feedback as parameters for the
existing spec — do NOT re-run Aşama 1/4. The spec is still
canonical; only the visual realization is being tweaked.

If the feedback contradicts the approved spec ("change the primary
button to a signup form instead"), that is scope creep — treat it
exactly like the "Yes but..." rule (see `asama1-gather.md`): run a
fresh Aşama 1-4 cycle for the delta, do not quietly rewrite.

## Visual-Inspect Loop

When "See it yourself" is chosen, run the pipeline in
`asama7-ui-review/visual-inspect.md`, emit the observation report,
then re-call this same review `AskUserQuestion` so the developer can
still choose approve / revise / cancel. Visual-inspect is
informational — it never auto-advances to Aşama 6c.

## Cancel

Cancel clears the UI state flags via stop-hook and aborts the task
entirely. The `.mcl/specs/NNNN-slug.md` entry is marked
`status: cancelled` (handled by stop-hook spec-history extension).

## Exit

Only "Approve" exits Aşama 7. On approve, the next turn starts
Aşama 6c; the UI-BUILD pre-tool lock is lifted (because
`ui_sub_phase = "BACKEND"` now).

</mcl_phase>
