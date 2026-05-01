<mcl_phase name="phase3-execute">

# Phase 3: Execution with Live Translation

Called automatically when Phase 1 (non-UI path) or Phase 2 (UI
path) approves.

## Flow Split

Phase 3 forks on `is_ui_project`:

- `is_ui_project = true`: the developer has already approved a
  visual skeleton in Phase 2. Phase 3 swaps the Phase 2 fixtures
  for real `fetch` / `axios` / DB calls and wires the data layer.
  Read `my-claude-lang/phase3-backend.md` for the UI-after-design
  backend procedure.
- `is_ui_project = false`: write code directly per the Technical
  Approach section. The default flow below runs top-to-bottom and
  exits to Phase 4 (risk gate).

State is managed by `hooks/lib/mcl-state.sh` (`current_phase=3`,
`design_approved`, `is_ui_project`). Never transition phase by
prose assertion alone — the stop hook is the only authority.

1. All code, comments, variable names, commit messages → English
2. All communication with the developer → their language
3. When Claude Code asks a question (Phase 3 mid-execution):
   - MCL applies Gate 2: verify the question is precise before translating
   - Translate the question to the developer's language
   - Add context: WHY Claude is asking this + WHAT each answer changes
     (see Gate 3 Question Context Rule)
   - Get the answer
   - MCL applies Gate 1: resolve any ambiguity in the answer
   - Translate the confirmed answer to English for Claude Code
   - Confirm: "I told Claude Code: [English version]. Is that what you meant?"
4. When Claude Code reports progress:
   - MCL applies Gate 3: explain, don't just translate
   - Translate the status update to the developer's language
   - Include key technical terms in both languages: "authentication (kimlik doğrulama)"
5. At every decision point requiring developer input:
   - Present options in the developer's language with explanations
   - After selection, confirm the English version before proceeding
6. **EXECUTION PLAN — DELETION-ONLY (since MCL 5.3.2):**
   By default MCL proceeds silently WITHOUT emitting an Execution Plan.
   The plan is required ONLY when the intended action deletes files or
   directories — specifically `rm` or `rmdir` shell commands (including
   `rm -r`, `rm -rf`, or any chained `&&`/`;` bash where `rm`/`rmdir`
   appears).

   All other actions proceed silently: Read, Grep, Glob, Write, single-
   or multi-file Edit, `git add`/`commit`/`push`/`reset`/`rebase`/
   `checkout`/`clean`/`rm` (the git subcommand, NOT shell `rm`), package
   installs (`npm install`, `pip install`, `brew install`), `WebFetch`,
   `WebSearch`, `sudo`/`chmod`/`chown`, writes under `~/.claude/` or
   system directories.

   On ambiguity (unclear whether a command deletes), default to showing
   the plan (safe side).

   When the plan IS triggered, list every action with:

   a) **What** — the exact `rm`/`rmdir` invocation and target path
   b) **Why** — one sentence: why the deletion is needed
   c) **What the harness will ask** — the permission prompt translated
      to the developer's language
   d) **What each option does** — "Yes" / "Yes, allow all" / "No"

   Example format:
   ```
   📦 Silme Planı:

   1. `rm -rf build/` komutu
      Neden: Eski derleme çıktısı temizlenecek, yeniden üretilecek
      Sistem soracak: "Do you want to run: rm -rf build/?"
      → "Yes" seçersen: sadece bu komut çalıştırılır
      → "Yes, allow all" seçersen: oturumdaki tüm rm komutlarına izin verilir
      → "No" seçersen: dizin silinmez
   ```

   After the plan, ask: "Bu plan uygun mu? Başlayayım mı?"
   Wait for confirmation before executing.

   ⛔ STOP RULE: After presenting the Execution Plan, STOP and wait
   for the developer's confirmation. Do NOT start executing.

7. When harness-level permission prompts appear during execution
   (file creation, tool approval, edit confirmation):
   - MCL translates the prompt into the developer's language with
     context explaining WHY Claude Code is asking and WHAT each
     option does (yes / yes-allow-all / no)
   - MCL does NOT produce a Permission Summary at the end of Phase 4.
     The developer already saw and approved each permission at the
     prompt — restating adds no value. (Removed in MCL 5.2.0.)
8. If the developer introduces a NEW task during Phase 3 execution
   (scope creep, "by the way also fix...", "bu arada şunu da..."):
   - Do NOT fold the new task into the current spec
   - Acknowledge it: "I noted this as a separate task."
   - Ask: "Should I finish the current task first, or pause and
     switch to this new one?"
   - If finish first → save the new task, continue current execution
   - If switch → pause current task at a safe point, run Phase 1
     (and Phase 2 if UI) for the new task
   - Either way, the new task gets its own Phase 1 cycle

<mcl_constraint name="spec-history">

## Spec History — automatic feature ledger

On every Phase 3 entry (the turn the `📋 Spec:` block is emitted),
the Stop hook writes the full spec body to
`.mcl/specs/NNNN-slug.md` with YAML frontmatter (spec_id,
approved_at, spec_hash, branch, head_at_approval,
completion_commit=null, status=active). `.mcl/specs/INDEX.md` is
regenerated as a pipe-table sorted newest-first.

This is a background mechanism — Phase 3 prose flow does NOT change.
MCL does NOT need to announce the save in every turn. Mention it only
when:

- The developer explicitly asks where specs are stored, or
- A drift-reapproval landed and the developer asks why a new file
  appeared, or
- Completion: when the developer ships the feature, remind them that
  they should update the frontmatter's `completion_commit` + `status:
  shipped` fields in the matching `NNNN-slug.md` file.

Specs dir is part of the project — it should be checked into git as
living documentation. Slug is derived from the spec's Objective line;
when derivation fails, fallback `spec-NNNN` is used. Idempotency: a
second approval of the same spec body (identical hash) is a no-op —
duplicate file is not produced.

</mcl_constraint>

</mcl_phase>
