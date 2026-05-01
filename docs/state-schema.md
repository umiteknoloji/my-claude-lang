# MCL State Schema

`.mcl/state.json` — per-project, one file per working directory.
Written atomically (tmp + mv). Schema version: **3** (MCL 10.0.0).

## Canonical v3 example

```json
{
  "schema_version": 3,
  "current_phase": 1,
  "phase_name": "INTENT",
  "is_ui_project": false,
  "design_approved": false,
  "spec_hash": null,
  "ui_flow_active": false,
  "ui_sub_phase": null,
  "ui_build_hash": null,
  "ui_reviewed": false,
  "scope_paths": [],
  "pattern_scan_due": false,
  "pattern_files": [],
  "rollback_sha": null,
  "rollback_notice_shown": false,
  "pattern_summary": null,
  "tdd_last_green": null,
  "last_write_ts": null,
  "pattern_level": null,
  "pattern_ask_pending": false,
  "plan_critique_done": false,
  "restart_turn_ts": null,
  "phase4_security_scan_done": false,
  "phase4_db_scan_done": false,
  "phase4_ui_scan_done": false,
  "phase4_high_baseline": {"security": 0, "db": 0, "ui": 0, "ops": 0, "perf": 0},
  "phase4_ops_scan_done": false,
  "phase4_perf_scan_done": false,
  "phase1_ops": {},
  "phase1_perf": {},
  "phase6_double_check_done": false,
  "phase4_batch_decision": null,
  "phase1_turn_count": 0,
  "phase1_intent": null,
  "phase1_constraints": null,
  "paused_on_error": {"active": false},
  "dev_server": {"active": false},
  "spec_format_warn_count": 0,
  "last_update": 1746086400
}
```

## Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `schema_version` | int | 3 | Schema version. v3 introduced in MCL 10.0.0. |
| `current_phase` | int | 1 | 1=INTENT, 2=DESIGN_REVIEW, 3=IMPLEMENTATION, 4=RISK_GATE, 5=VERIFICATION, 6=FINAL_REVIEW |
| `phase_name` | string | `"INTENT"` | Human-readable phase label aligned with `current_phase` |
| `is_ui_project` | bool | `false` | Set by Phase 1 brief parse (intent keywords + stack tags + project file hints). Drives whether Phase 2 DESIGN_REVIEW runs. Default `true` if signals are ambiguous. |
| `design_approved` | bool | `false` | Phase 2 → Phase 3 gate. Set true on `/mcl-design-approve` or askq approval. For non-UI projects (`is_ui_project=false`), this is implicitly true and Phase 2 is skipped. |
| `spec_hash` | null/string | `null` | SHA256 of last emitted Phase 3 `📋 Spec:` block. Documentation-only — no longer state-gating in v3. |
| `ui_flow_active` | bool | `false` | UI surface detected at runtime (alias kept for hook back-compat) |
| `ui_sub_phase` | null/string | `null` | Phase 2 sub-state: `BUILD_UI` / `UI_REVIEW` / null |
| `ui_build_hash` | null/string | `null` | SHA256 of last UI skeleton build |
| `ui_reviewed` | bool | `false` | Mirror of `design_approved` for legacy reads |
| `scope_paths` | array | `[]` | Glob patterns from Phase 3 spec's Technical Approach. Scope guard reads this. |
| `pattern_scan_due` | bool | `false` | Phase 3 pattern matching pending |
| `pattern_files` | array | `[]` | Sibling files used for pattern extraction |
| `rollback_sha` | null/string | `null` | `git rev-parse HEAD` at Phase 1 approval |
| `rollback_notice_shown` | bool | `false` | Whether the rollback notice has been surfaced this session |
| `pattern_summary` | null/string | `null` | Cached pattern matching summary |
| `tdd_last_green` | null/int | `null` | Epoch of last TDD green-verify |
| `last_write_ts` | null/int | `null` | Epoch of last Write/Edit/MultiEdit/NotebookEdit |
| `pattern_level` | null/string | `null` | Cascade resolution level: `sibling` / `project` / `ecosystem` / `asked` |
| `pattern_ask_pending` | bool | `false` | Pattern matching escalated to user question |
| `plan_critique_done` | bool | `false` | Devtime plan critique subagent dispatch flag |
| `restart_turn_ts` | null/int | `null` | Epoch stamped by `/mcl-restart` to invalidate stale askq's |
| `phase4_security_scan_done` | bool | `false` | Phase 4 security gate completed |
| `phase4_db_scan_done` | bool | `false` | Phase 4 DB gate completed |
| `phase4_ui_scan_done` | bool | `false` | Phase 4 UI gate completed |
| `phase4_ops_scan_done` | bool | `false` | Phase 4 ops gate completed |
| `phase4_perf_scan_done` | bool | `false` | Phase 4 perf gate completed |
| `phase4_high_baseline` | object | `{"security":0,"db":0,"ui":0,"ops":0,"perf":0}` | HIGH counts captured at Phase 4 START. Phase 6 (b) compares post-fix counts against this baseline. |
| `phase4_batch_decision` | null/string | `null` | Last batched dialog decision (`apply-fix` / `override`) |
| `phase1_turn_count` | int | `0` | Number of Phase 1 turns spent (for clarification budget) |
| `phase1_intent` | null/string | `null` | Brief parser output: confirmed intent statement |
| `phase1_constraints` | null/array | `null` | Brief parser output: confirmed constraints (negations land here for Phase 4 intent-violation check) |
| `phase1_ops` | object | `{}` | Industry-default ops dimensions filled by hook |
| `phase1_perf` | object | `{}` | Industry-default perf dimensions filled by hook |
| `phase6_double_check_done` | bool | `false` | Phase 6 audit + regression + promise-vs-delivery completion gate |
| `paused_on_error` | object | `{"active": false}` | Pause-on-error state. When `active=true`, all subsequent tools return `decision:deny`. |
| `dev_server` | object | `{"active": false}` | Phase 2 dev server state (PID, port, URL, log path) |
| `spec_format_warn_count` | int | `0` | Tally of `spec-format-warn` audits across turns. ≥3 → Phase 6 LOW soft fail. |
| `last_update` | int | epoch | Unix timestamp of last write |

## Phase transition rules

```
INTENT (1)
  │  summary-confirm askq approved
  │  ├─ is_ui_project=true  → DESIGN_REVIEW (2)
  │  └─ is_ui_project=false → IMPLEMENTATION (3)
  ▼
DESIGN_REVIEW (2)         ──design_approved=true──▶ IMPLEMENTATION (3)
IMPLEMENTATION (3)        ──spec emitted + writes──▶ RISK_GATE (4)
RISK_GATE (4)             ──HIGH=0 + dialog done──▶ VERIFICATION (5)
VERIFICATION (5)          ──phase5-verify audit──▶ FINAL_REVIEW (6)
FINAL_REVIEW (6)          ──phase6_double_check_done=true──▶ session close
```

Phase 4 may loop back into itself when fixes generate new HIGH findings (regression block). Phase 6 (b) regression block returns control to Phase 4 with the offending diff highlighted.

## Migration v2 → v3

`mcl-activate.sh` runs the migration on the first activate after install when `schema_version < 3`. A backup is written to `.mcl/state.json.backup.pre-v3` and an audit event `state-migrated-10.0.0` is emitted.

Migration rules:

| v2 field / value | v3 result |
|---|---|
| `schema_version: 1` or `2` | `schema_version: 3` |
| `current_phase: 2` (SPEC_REVIEW, deleted) | `current_phase: 3`, `phase_name: "IMPLEMENTATION"` |
| `current_phase: 3` (USER_VERIFY, deleted) | `current_phase: 3`, `phase_name: "IMPLEMENTATION"` |
| `current_phase: 4` (EXECUTE, renamed) | `current_phase: 3`, `phase_name: "IMPLEMENTATION"` |
| `current_phase: 4.5` (RISK_REVIEW, renumbered) | `current_phase: 4`, `phase_name: "RISK_GATE"` |
| `current_phase: 5` (DELIVER) | `current_phase: 5`, `phase_name: "VERIFICATION"` |
| `current_phase: 6` (DOUBLE_CHECK) | `current_phase: 6`, `phase_name: "FINAL_REVIEW"` |
| `spec_approved: true` | `design_approved: true` (preserves prior approval — UI review askq does not re-trigger) |
| `spec_approved: false` | `design_approved: false` |
| `phase4_5_security_scan_done` (and all other `phase4_5_*`) | renamed to `phase4_security_scan_done` (`phase4_*`) |
| `phase4_5_high_baseline` | `phase4_high_baseline` |
| `precision_audit_block_count` | dropped |
| `precision_audit_skipped` | dropped |
| `phase_review_state` | dropped (state machine collapsed into `current_phase` + `phase4_*_scan_done`) |
| `partial_spec`, `partial_spec_body_sha` | dropped (spec is documentation; no recovery state needed) |
| `plugin_gate_active`, `plugin_gate_missing`, `plugin_gate_session` | dropped (Rule C plugin filter is curation-time, not runtime state) |

For projects already past their UI review in v2 (`spec_approved=true`), the migration sets both `is_ui_project=true` and `design_approved=true` so the Phase 2 askq does not re-fire on already-completed work. Projects fresh-installing on 10.0.0 start with `is_ui_project=false` until Phase 1 brief parse runs.

## Pause-on-error semantics

When `paused_on_error.active=true`, every subsequent tool call returns `decision:deny` with the captured error context, suggested fix, and last-known phase. Resume with `/mcl-resume <resolution>` (free-form natural-language argument). Sticky across session boundaries — paused state survives Claude Code restarts.

## File path

`${MCL_STATE_DIR}/state.json` (with `MCL_STATE_DIR=~/.mcl/projects/<sha1(realpath)>/`).

Write authority: `mcl-activate.sh`, `mcl-stop.sh`, `mcl-pre-tool.sh`, `mcl-post-tool.sh` only. Direct `Bash` writes are blocked by the pre-tool hook.
