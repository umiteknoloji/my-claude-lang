#!/bin/bash
# v13.0.15 — Aşama 7 deferred narration rule görünür mü.
# Header directive (TR + EN) ve PHASE_META[7] narration field
# render edilmiş çıktıda olmalı; aksi halde model deferred=skipped
# yorumuyla narration'dan düşürebilir.

echo "--- test-v1315-asama7-narration-rule ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"

_render_tr() {
  MCL_LANG=tr MCL_STATE_DIR="$_dir/.mcl" \
    bash -c "source $REPO_ROOT/hooks/lib/mcl-dsi.sh; _mcl_dsi_render_active_phase $1" 2>&1
}

_render_en() {
  MCL_LANG=en MCL_STATE_DIR="$_dir/.mcl" \
    bash -c "source $REPO_ROOT/hooks/lib/mcl-dsi.sh; _mcl_dsi_render_active_phase $1" 2>&1
}

_assert_contains() {
  local label="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    PASS=$((PASS+1)); printf '  PASS: %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '  FAIL: %s\n         needle: %s\n' "$label" "$needle"
  fi
}

# ════════ T1: Phase 7 aktifken header_directive NARRATION RULE içerir (TR) ════════
out_tr_7="$(_render_tr 7)"
_assert_contains "T1: TR header NARRATION RULE" "$out_tr_7" "NARRATION RULE"
_assert_contains "T2: TR header 'Deferred ≠ skipped'" "$out_tr_7" "Deferred ≠ skipped"
_assert_contains "T3: TR header yasak örnek '5 → 6 → 8 → 9'" "$out_tr_7" "Aşama 5 → 6 → 8 → 9"
_assert_contains "T4: TR header doğru örnek '7 (deferred)'" "$out_tr_7" "7 (deferred)"

# ════════ T5-T7: PHASE_META[7] narration_tr aktif faz block'unda render edilir ════════
_assert_contains "T5: TR narration_tr 'Aşama 6 dev server sonrası'" "$out_tr_7" "Aşama 6 dev server sonrası"
_assert_contains "T6: TR narration_tr 'Sessizce düşürmek yasak'" "$out_tr_7" "Sessizce düşürmek yasak"
_assert_contains "T7: TR narration_tr '(atlandı — Aşama 6)'" "$out_tr_7" "(atlandı — Aşama 6)"

# ════════ T8-T11: EN render aynı kuralı içerir ════════
out_en_7="$(_render_en 7)"
_assert_contains "T8: EN header NARRATION RULE" "$out_en_7" "NARRATION RULE"
_assert_contains "T9: EN header 'Deferred ≠ skipped'" "$out_en_7" "Deferred ≠ skipped"
_assert_contains "T10: EN narration_en 'developer's reply after Aşama 6'" "$out_en_7" "developer's reply after Aşama 6"
_assert_contains "T11: EN narration_en 'Silent omission forbidden'" "$out_en_7" "Silent omission forbidden"

# ════════ T12: Phase 6 aktifken de header NARRATION RULE görünür (cross-phase reminder) ════════
out_tr_6="$(_render_tr 6)"
_assert_contains "T12: Phase 6 aktif iken header'da NARRATION RULE" "$out_tr_6" "NARRATION RULE"

# ════════ T13: Phase 4 aktifken de NARRATION RULE görünür (spec onayı turn'ünde model phase listesi yazar) ════════
out_tr_4="$(_render_tr 4)"
_assert_contains "T13: Phase 4 aktif iken header'da NARRATION RULE" "$out_tr_4" "NARRATION RULE"

# ════════ T14: PHASE_META'da narration_tr field'ı SADECE phase 7'de — diğer faz aktif iken active block'unda 📋 satır olmaz ════════
# (Header'daki 📋 NARRATION RULE her zaman var; active phase block'undaki 📋 narration sadece phase 7'de)
# Phase 8 aktif iken active block'unda "Deferred — Aşama 6 dev server sonrası" SATIRI olmamalı
out_tr_8="$(_render_tr 8)"
if [[ "$out_tr_8" != *"Aşama 6 dev server sonrası"* ]]; then
  PASS=$((PASS+1)); printf '  PASS: T14: Phase 8 aktif iken active block narration cue YOK\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL: T14: Phase 8 aktif iken phase 7 narration cue sızdı\n'
fi

cleanup_test_dir "$_dir"
