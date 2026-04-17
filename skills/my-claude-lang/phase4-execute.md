# Phase 4: Execution with Live Translation

Called automatically when Phase 3 is confirmed.

1. All code, comments, variable names, commit messages → English
2. All communication with the developer → their language
3. When Claude Code asks a question:
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
6. **EXECUTION PLAN — MANDATORY BEFORE ANY TOOL CALL:**
   After spec is confirmed but BEFORE any code is written, MCL presents
   an "Execution Plan" (Uygulama Planı) in the developer's language.
   This plan lists EVERY file and tool action that will happen, with:

   For EACH action:
   a) **What** — file name and operation (create/edit/command)
   b) **Why** — one sentence: why this is needed
   c) **What the harness will ask** — the exact options translated
      to the developer's language (e.g., "Sistem sana şunu soracak:
      'config.ts dosyasını oluşturmak istiyor musun?'")
   d) **What each option does** — explain every choice:
      - "Yes" → sadece bu dosya için izin verir
      - "Yes, allow all" → bu oturumdaki tüm düzenlemelere izin verir
      - "No" → bu işlemi reddeder, dosya oluşturulmaz

   Example format:
   ```
   📦 Uygulama Planı:

   1. `mock-data.ts` düzenleme
      Neden: Category tipi ve örnek veriler eklenecek
      Sistem soracak: "Do you want to edit mock-data.ts?"
      → "Yes" seçersen: sadece bu dosya düzenlenir
      → "Yes, allow all" seçersen: bundan sonraki tüm düzenlemelere otomatik izin verilir
      → "No" seçersen: bu dosya düzenlenmez, kategori verileri eklenmez

   2. `categories/page.tsx` oluşturma
      Neden: Kategori yönetim sayfasının ana dosyası
      Sistem soracak: "Do you want to create categories/page.tsx?"
      → "Yes" seçersen: sadece bu dosya oluşturulur
      → "No" seçersen: sayfa oluşturulmaz
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
8. If the developer introduces a NEW task during Phase 4 execution
   (scope creep, "by the way also fix...", "bu arada şunu da..."):
   - Do NOT fold the new task into the current spec
   - Acknowledge it: "I noted this as a separate task."
   - Ask: "Should I finish the current task first, or pause and
     switch to this new one?"
   - If finish first → save the new task, continue current execution
   - If switch → pause current task at a safe point, run Phase 1-3
     for the new task
   - Either way, the new task gets its own Phase 1-3 cycle
