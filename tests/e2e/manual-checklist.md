# MCL E2E Manual Checklist

Companion to `tests/cases/e2e-full-pipeline.sh`. Steps that depend on
Claude Code session model behavior (AskUserQuestion turns, skill prose
Bash actually being invoked by the model, npm-driven dev server spawn)
cannot be driven from a bash test. They live here as a checklist run
once per release in a real `mcl-claude` session.

The bash file owns deterministic surface (hooks, state, helpers,
auth-check). This file owns model-behavioral surface. They evolve in
lockstep, one phase at a time.

## How to run

1. Open a fresh `mcl-claude` session in a temp directory:
   ```bash
   mkdir /tmp/mcl-e2e-manual && cd /tmp/mcl-e2e-manual
   mcl-claude
   ```
2. Paste the canonical TR prompt:
   > admin paneli yap, kullanıcıları listele, sadece adminler görsün, audit log tutsun, hızlı olsun
3. Walk the prompts through to a final commit.
4. After session ends, audit the run with:
   ```bash
   cat ~/.mcl/projects/$(echo -n "$PWD" | shasum | awk '{print $1}')/audit.log
   cat ~/.mcl/projects/$(echo -n "$PWD" | shasum | awk '{print $1}')/state.json
   ```
5. Tick each box below against observed behavior. Any unticked box is a
   regression to investigate before tagging the release.

## Coverage status

Legend: ✅ owned by bash test · 📋 manual checklist · 🚧 not yet covered

| # | Step | Owner |
|---|---|---|
| 1.A | Wrapper init — `~/.mcl/projects/<key>/` created | ✅ |
| 1.B | Phase 1 handoff Bash auth-check rejection (pre-8.17.0) | ✅ |
| 1.C | `MCL_SKILL_TOKEN` env probe (pre-8.17.0 reject) | ✅ |
| 2 | Phase 1 collect — AskUserQuestion turns, summary approval | 📋 |
| 3 | Phase 1.5 upgrade-translator — vague verb upgrade audit | 🚧 |
| 4 | Phase 1.7 GATE batching (8.16.0) — ≤ 5 turns | 📋 |
| 5 | Phase 2 spec emit + Phase 3 approval | 📋 |
| 6 | Phase 3.5 pattern matching — `project.md` codebase-scan cache | 🚧 |
| 7 | Phase 4a UI build — real `npm create vite` + install | 📋 |
| 8 | Phase 4a → 4b transition Bash — `ui_sub_phase=UI_REVIEW` | 📋 |
| 9 | Dev server auto-start — vite spawn + URL state | 📋 |
| 10 | Design loop — Edit / hot reload | 📋 |
| 11 | `/mcl-design-approve` keyword — dev_server stop | 🚧 |
| 12 | Phase 4c BACKEND — Python/SQL writes | 📋 |
| 13 | L2 incremental scans on each Edit | 🚧 |
| 14 | Phase 4.5 START — sticky-pause check, 5 gates serial | 🚧 |
| 15 | `phase4_5_high_baseline.{security,db,ui,ops,perf}` set | 🚧 |
| 16 | Phase 4.5 dialog batch-action (8.17.0) — accept_all path | 🚧 |
| 17 | Phase 4.6 impact review audit | 🚧 |
| 18 | Phase 5 verify — Spec Coverage + MUST TEST + Process Trace | 📋 |
| 19 | Phase 5 audit Bash — `phase5-verify` event emitted | 🚧 |
| 20 | Phase 5.5 localize — "Doğrulama Raporu" header | 📋 |
| 21 | Phase 6 (a) audit-trail completeness | 🚧 |
| 22 | Phase 6 (b) regression scan — HIGH=0 | 🚧 |
| 23 | Phase 6 (c) promise-vs-delivery — `phase1_intent` read (no LOW skip) | 🚧 |
| 24 | `phase6_double_check_done=true` in state | 🚧 |
| 25 | Pause-on-error trigger (mock broken scan) | 🚧 |
| 26 | `/mcl-resume` keyword — pause cleared | 🚧 |
| 27 | `/codebase-scan` keyword — `project.md` `mcl-auto` block | 🚧 |
| 28 | `/mcl-security-report` keyword + helper | 🚧 |
| 29 | `/mcl-db-report` keyword + helper | 🚧 |
| 30 | `/mcl-ui-report` keyword + helper | 🚧 |
| 31 | `/mcl-ops-report` keyword + helper | 🚧 |
| 32 | `/mcl-perf-report` keyword + helper | 🚧 |
| 33 | `/mcl-phase6-report` keyword + helper | 🚧 |

## Phase 1 manual steps (current scope)

### 2 — Phase 1 collect

- [ ] First assistant turn after the canonical prompt enters Phase 1
      (no spec emitted yet, AskUserQuestion called for clarification).
- [ ] Each clarifying question targets exactly ONE missing parameter
      (one-question-at-a-time rule).
- [ ] After all questions, assistant emits a Phase 1 summary and asks
      for approval via AskUserQuestion (approve / edit / cancel).
- [ ] On approval, audit.log gains a `precision-audit | phase1-7 | …`
      entry within the same turn (Phase 1.7 ran).

### Auth-check live observation (pairs with 1.B in bash)

After approval, immediately run:

```bash
KEY="$(echo -n "$PWD" | shasum | awk '{print $1}')"
grep -E 'set|deny-write' ~/.mcl/projects/$KEY/audit.log | tail -20
python3 -c "import json; d=json.load(open('$HOME/.mcl/projects/$KEY/state.json')); \
  print('intent=', d.get('phase1_intent')); \
  print('constraints=', d.get('phase1_constraints')); \
  print('stack=', d.get('phase1_stack_declared'))"
```

- [ ] **If `phase1_intent` / `phase1_constraints` / `phase1_stack_declared`
      are all `None`** AND the audit log shows `deny-write | bash`
      entries → **8.15.0/8.16.0 plumbing is silently failing in
      production.** Confirms the 8.17.0 fix premise.
- [ ] **If the fields are populated** → the model used a different
      invocation path (or auth-check has a hole we missed). Capture
      the exact audit lines so we can trace which caller succeeded.

This live observation is the single most important manual data point
for the 8.17.0 release. Do not skip it.

## Future phases

Each subsequent bash phase added to `e2e-full-pipeline.sh` corresponds
to rows above moving from 📋/🚧 to ✅. The `🚧 not yet covered` rows are
the work backlog for this test infrastructure.
