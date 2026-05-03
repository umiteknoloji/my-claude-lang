#!/bin/bash
# Synthetic test: v10.1.10 — Aşama 13 Completeness Audit skill
# infrastructure. New phase that runs after Aşama 12 and reads
# audit.log/state.json/trace.log to render a per-phase verdict report
# with two mandatory deep dives (Aşama 7 TDD + Aşama 9 sub-steps).
#
# This test verifies the SKILL + STATIC_CONTEXT + DOCUMENTATION
# infrastructure exists. Behavioral correctness (model actually
# rendering the report on real sessions) is validated separately
# via real-world deployment audit logs.

echo "--- test-v10-1-10-asama13-completeness ---"

# === Skill file exists with required sections ===
_skill="$REPO_ROOT/skills/my-claude-lang/asama13-completeness.md"
if [ -f "$_skill" ]; then
  PASS=$((PASS+1))
  printf '  PASS: skill file exists at %s\n' "$_skill"
else
  FAIL=$((FAIL+1))
  printf '  FAIL: skill file missing at %s\n' "$_skill"
fi

if grep -q '<mcl_phase name="asama13-completeness">' "$_skill"; then
  PASS=$((PASS+1))
  printf '  PASS: skill file uses <mcl_phase name="asama13-completeness"> tag\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: mcl_phase tag missing\n'
fi

# Required deep-dive sections
for _section in "Aşama 7 Deep Dive" "Aşama 9 Deep Dive" "Phase Completion Signals" "Audit Emit on Completion"; do
  if grep -q "$_section" "$_skill"; then
    PASS=$((PASS+1))
    printf '  PASS: skill includes "%s" section\n' "$_section"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: skill missing "%s" section\n' "$_section"
  fi
done

# Verdict rules for Aşama 7 must mention all 4 outcomes
if grep -q "ANTI-TDD" "$_skill" && grep -q "GREEN" "$_skill" && grep -q "tdd_compliance_score" "$_skill"; then
  PASS=$((PASS+1))
  printf '  PASS: skill Aşama 7 verdict rules cover GREEN / partial / anti-TDD / never-ran\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: skill Aşama 7 verdict rules incomplete\n'
fi

# Aşama 9 sub-step coverage (must mention 9.1 through 9.8)
_sub_count=0
for _n in 9.1 9.2 9.3 9.4 9.5 9.6 9.7 9.8; do
  if grep -q "$_n" "$_skill"; then
    _sub_count=$((_sub_count + 1))
  fi
done
if [ "$_sub_count" = "8" ]; then
  PASS=$((PASS+1))
  printf '  PASS: skill references all 8 sub-steps (9.1–9.8)\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: skill only references %s/8 sub-steps\n' "$_sub_count"
fi

# Audit emit instruction present
if grep -q "mcl_audit_log asama-13-complete" "$_skill"; then
  PASS=$((PASS+1))
  printf '  PASS: skill mandates asama-13-complete emit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama-13-complete emit instruction missing\n'
fi

# === STATIC_CONTEXT in mcl-activate.sh includes the phase ===
_activate="$REPO_ROOT/hooks/mcl-activate.sh"
if grep -q 'mcl_phase name=\\"asama13-completeness\\"' "$_activate"; then
  PASS=$((PASS+1))
  printf '  PASS: STATIC_CONTEXT includes asama13-completeness phase\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: asama13-completeness phase missing from STATIC_CONTEXT\n'
fi

if grep -q "COMPLETENESS AUDIT (Aşama 13)" "$_activate"; then
  PASS=$((PASS+1))
  printf '  PASS: STATIC_CONTEXT carries COMPLETENESS AUDIT directive\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: COMPLETENESS AUDIT directive missing from STATIC_CONTEXT\n'
fi

# === Main skill index has pointer ===
_index="$REPO_ROOT/skills/my-claude-lang.md"
if grep -q "asama13-completeness.md" "$_index"; then
  PASS=$((PASS+1))
  printf '  PASS: main skill index points to asama13-completeness.md\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: pointer in main skill index missing\n'
fi

# === Pipeline diagram updated in user-facing docs ===
for _doc in "$REPO_ROOT/FEATURES.md" "$REPO_ROOT/README.md" "$REPO_ROOT/README.tr.md"; do
  if grep -q "Aşama 13" "$_doc"; then
    PASS=$((PASS+1))
    printf '  PASS: pipeline diagram in %s mentions Aşama 13\n' "$(basename "$_doc")"
  else
    FAIL=$((FAIL+1))
    printf '  FAIL: pipeline diagram in %s missing Aşama 13\n' "$(basename "$_doc")"
  fi
done
