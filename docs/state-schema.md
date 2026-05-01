# MCL State Schema

`.mcl/state.json` — per-project, one file per working directory.
Written atomically (tmp + mv). Schema version: 2.

## Fields

| Field | Type | Default | Description |
|---|---|---|---|
| schema_version | int | 2 | Schema version for migration |
| current_phase | int | 1 | 1=COLLECT 2=SPEC_REVIEW 4=EXECUTE 5=DELIVER |
| phase_name | string | "COLLECT" | Human-readable phase label |
| spec_approved | bool | false | Phase 3→4 gate |
| spec_hash | null/string | null | SHA256 of approved spec body |
| plugin_gate_active | bool | false | Missing plugin/binary gate |
| plugin_gate_missing | array | [] | [{kind, name, plugin}] objects |
| ui_flow_active | bool | false | UI surface detected |
| ui_sub_phase | null/string | null | BUILD_UI / REVIEW / BACKEND |
| ui_build_hash | null/string | null | SHA256 of last UI build |
| ui_reviewed | bool | false | Phase 4b UI approved |
| phase_review_state | null/string | null | null / "pending" / "running" |
| plugin_gate_session | null/string | null | Session ID of last gate check |
| partial_spec | bool | false | Spec was truncated (recovery) |
| partial_spec_body_sha | null/string | null | SHA of partial spec for dedup |
| last_update | int | epoch | Unix timestamp of last write |

## `phase_review_state` Lifecycle

```
null
  │  (Phase 4 code written, Phase 4.5 not yet started)
  ▼
"pending"
  │  (Phase 4.5 AskUserQuestion first called — mcl-pre-tool.sh)
  ▼
"running"
  │  (Phase 4.5 fully resolved)
  ▼
null
```

- **null → pending**: set by `mcl-stop.sh` when Phase 4 code is written and `phase_review_state` is null.
- **pending → running**: set by `mcl-pre-tool.sh` on first `AskUserQuestion` call in Phase 4.5.
- **running → null**: set by `mcl-stop.sh` when Phase 4.6/5 completes.

## Recovery

When `phase_review_state = "running"`, the next `UserPromptSubmit` injects a `phase-review-recovery` audit block. Claude reads `.mcl/risk-session.md` to determine which risks were already reviewed and resumes from the first unreviewed risk.

## File Path

`${CLAUDE_PROJECT_DIR}/.mcl/state.json`

Write authority: `mcl-activate.sh`, `mcl-stop.sh`, `mcl-pre-tool.sh` only.
