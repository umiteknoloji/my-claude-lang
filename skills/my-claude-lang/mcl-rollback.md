<mcl_constraint name="mcl-rollback">

# `/mcl-rollback` — Rollback Checkpoint Display

When the developer types `/mcl-rollback`, perform these steps in order:

1. Run: `bash -c "source ~/.claude/hooks/lib/mcl-state.sh 2>/dev/null; mcl_state_set rollback_notice_shown false >/dev/null 2>&1; echo ok"` to reset the display flag.

2. Read `.mcl/state.json` and extract `rollback_sha`, `scope_paths`, and `spec_hash`.

3. If `rollback_sha` is null or missing, respond in the developer's detected language:
   > (TR) Rollback checkpoint yok. Spec henüz onaylanmamış veya git repo mevcut değil.
   > (EN) No rollback checkpoint. Spec not yet approved or no git repo present.
   Render the message in the developer's language, not hardcoded Turkish.

4. If `rollback_sha` is set, display the following in the developer's detected language:

   ```
   🔙 Rollback Checkpoint
   SHA:      <full sha>
   Short:    <sha[:12]>

   To revert all Aşama 7 changes:
     git reset --hard <full sha>

   ⚠️  This does NOT delete files — it only moves HEAD back.
       Protect current work first with git stash or a commit.

   Atomic commit (after Aşama 11):
     git add <scope_paths or ".">
     git commit -m "feat: <spec objective>"
   ```

   Translate all prose labels into the developer's language. Technical tokens
   (git commands, SHA, `scope_paths`) stay in English.

5. Do NOT run `git reset` automatically. Show only — the developer decides.

After this turn the `ROLLBACK_NOTICE` will re-appear in context (the flag was reset in step 1).

</mcl_constraint>
