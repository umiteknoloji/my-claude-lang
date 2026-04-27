<mcl_constraint name="mcl-rollback">

# `/mcl-rollback` — Rollback Checkpoint Display

When the developer types `/mcl-rollback`, perform these steps in order:

1. Run: `bash -c "source ~/.claude/hooks/lib/mcl-state.sh 2>/dev/null; mcl_state_set rollback_notice_shown false >/dev/null 2>&1; echo ok"` to reset the display flag.

2. Read `.mcl/state.json` and extract `rollback_sha`, `scope_paths`, and `spec_hash`.

3. If `rollback_sha` is null or missing, respond:
   > Rollback checkpoint yok. Spec henüz onaylanmamış veya git repo mevcut değil.

4. If `rollback_sha` is set, display in the developer's language:

   ```
   🔙 Rollback Checkpoint
   SHA:      <full sha>
   Kısa:     <sha[:12]>

   Tüm Phase 4 değişikliklerini geri almak için:
     git reset --hard <full sha>

   ⚠️  Bu komut dosyaları silmez — sadece HEAD'i geri taşır.
       Önce git stash veya commit ile mevcut çalışmayı koruyun.

   Atomic commit (Phase 5 sonrası):
     git add <scope_paths veya ".">
     git commit -m "feat: <spec objective>"
   ```

5. Do NOT run `git reset` automatically. Show only — the developer decides.

After this turn the `ROLLBACK_NOTICE` will re-appear in context (the flag was reset in step 1).

</mcl_constraint>
