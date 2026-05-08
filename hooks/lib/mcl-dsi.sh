#!/usr/bin/env bash
# Dynamic Status Injection — v13.0.4
#
# Reads gate-spec.json + audit.log + state.json, renders a focused
# per-turn phase status block. Read-only — never writes state.
#
# Public API:
#   _mcl_dsi_render <phase>            → stdout text (status block body)
#   _mcl_dsi_render_cli <args>         → standalone CLI for unit tests
#
# CLI mode:
#   bash mcl-dsi.sh --phase N --audit <audit.log> --spec <gate-spec.json> \
#                   [--lang tr|en] [--state <state.json>]
#
# Output language: TR by default; EN when --lang=en or MCL_LANG=en.
# All other languages fall back to EN labels (v13.1 will extend).
#
# Fail-open: any error prints a single diagnostic line; never exits non-zero.

_mcl_dsi_render() {
  local phase="$1"
  local spec_file="${MCL_GATE_SPEC:-${HOME}/.claude/skills/my-claude-lang/gate-spec.json}"
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  local state_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/state.json"
  local lang="${MCL_LANG:-tr}"

  python3 - "$spec_file" "$audit_file" "$trace_file" "$state_file" "$phase" "$lang" 2>/dev/null <<'PYEOF' || echo "DSI unavailable: helper crashed"
import json, os, re, sys

spec_path, audit_path, trace_path, state_path, phase, lang = sys.argv[1:7]

# Label tables — TR (calibration) + EN. Other 12 langs fall back to EN in v13.0.4.
L = {
    "tr": {
        "current": "Mevcut Aşama",
        "this_turn": "Bu turun zorunlu çıktısı",
        "remaining": "Bu fazda kalan",
        "next_phase": "Bir sonraki faz",
        "completed": "Tamamlandı — sonraki faza geç",
        "skip_eligible": "skip-eligible",
        "of": "/",
        "current_item": "Şu anda görüşülen",
        "items_declared_missing": "ZORUNLU: önce {audit} emit et (count=K). K bilinmeden dialog başlayamaz.",
        "ac_status": "AC {i}/{N}: red {r} green {g} refactor {x}",
        "scan_state": "Scan: {k} issue → Fixed: {m}/{k} → Rescan {rs}",
        "rescan_due": "rescan due",
        "rescan_zero": "0 (stable)",
        "yes": "evet", "no": "hayır",
        "partial_recovery": "⚠ PARTIAL SPEC RECOVERY — Spec yeniden emit edilmeli. Aşama 4'e dön.",
        "minimal_pre_spec": "Aşama {n} aktif — niyet/spec aşamasında. Tek odak: {next}.",
    },
    "en": {
        "current": "Current Phase",
        "this_turn": "This turn must produce",
        "remaining": "Remaining in this phase",
        "next_phase": "Next phase",
        "completed": "Completed — advance to next phase",
        "skip_eligible": "skip-eligible",
        "of": "/",
        "current_item": "Currently discussing",
        "items_declared_missing": "MANDATORY: emit {audit} first (count=K). Dialog cannot start without K.",
        "ac_status": "AC {i}/{N}: red {r} green {g} refactor {x}",
        "scan_state": "Scan: {k} issue → Fixed: {m}/{k} → Rescan {rs}",
        "rescan_due": "rescan due",
        "rescan_zero": "0 (stable)",
        "yes": "yes", "no": "no",
        "partial_recovery": "⚠ PARTIAL SPEC RECOVERY — Re-emit spec. Return to Aşama 4.",
        "minimal_pre_spec": "Aşama {n} active — intent/spec stage. Single focus: {next}.",
    },
}
labels = L.get(lang, L["en"])
TICK = "✓"; CROSS = "✗"

# Phase name lookup (Turkish canonical from MCL_Pipeline.md)
phase_names = {
    "1": "Niyet (gather)", "2": "Precision Audit", "3": "Engineering Brief",
    "4": "Spec + Verify", "5": "Pattern Matching", "6": "UI Build",
    "7": "UI Review", "8": "DB Design", "9": "TDD Execute",
    "10": "Risk Review", "11": "Code Review", "12": "Simplify",
    "13": "Performance", "14": "Security", "15": "Unit Tests",
    "16": "Integration Tests", "17": "E2E Tests", "18": "Load Tests",
    "19": "Impact Review", "20": "Verify Report", "21": "Localized Report",
    "22": "Completeness Audit",
}

# Session boundary
session_ts = ""
try:
    if os.path.isfile(trace_path):
        for line in open(trace_path, "r", encoding="utf-8", errors="replace"):
            if "| session_start |" in line:
                session_ts = line.split("|", 1)[0].strip()
except Exception:
    pass

audit_lines = []
try:
    if os.path.isfile(audit_path):
        for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
            ts = line.split("|", 1)[0].strip()
            if session_ts and ts < session_ts:
                continue
            audit_lines.append(line)
except Exception:
    pass

state = {}
try:
    if os.path.isfile(state_path):
        state = json.load(open(state_path, "r", encoding="utf-8"))
except Exception:
    pass

# Partial spec recovery override
if state.get("partial_spec") is True:
    print(labels["partial_recovery"])
    sys.exit(0)

try:
    spec = json.load(open(spec_path))
    pspec = spec["phases"][phase]
except Exception as e:
    print(f"DSI unavailable: spec load failed ({e})")
    sys.exit(0)

def has_audit(name):
    needle = f"| {name} |"
    return any(needle in l for l in audit_lines)

def parse_kv_last(name, key):
    needle = f"| {name} |"
    val = None
    for l in audit_lines:
        if needle in l:
            m = re.search(rf"\b{re.escape(key)}=(\d+)", l)
            if m:
                val = int(m.group(1))
    return val

def count_matching(pattern_regex):
    rx = re.compile(pattern_regex)
    return sum(1 for l in audit_lines if rx.search(l))

def distinct_indices(pattern_regex):
    rx = re.compile(pattern_regex)
    seen = set()
    for l in audit_lines:
        m = rx.search(l)
        if m:
            seen.add(int(m.group(1)))
    return seen

phase_int = int(phase)
phase_name = phase_names.get(phase, "?")
next_phase_int = phase_int + 1 if phase_int < 22 else None
next_phase_name = phase_names.get(str(next_phase_int), "—") if next_phase_int else None

# Skip-eligibility derived from gate-spec
skip_eligible = (
    "required_audits_any" in pspec
    and any("skipped" in a or "not-applicable" in a for a in pspec.get("required_audits_any", []))
)
next_skip = ""
if next_phase_int and str(next_phase_int) in spec["phases"]:
    nspec = spec["phases"][str(next_phase_int)]
    if "required_audits_any" in nspec and any(
        "skipped" in a or "not-applicable" in a for a in nspec["required_audits_any"]
    ):
        next_skip = f" ({labels['skip_eligible']})"

# Header
header = f"{labels['current']}: {phase} — {phase_name}"
print(header)

# Aşama 1-4 (pre-spec phases). Two modes:
# - Empty session (no Aşama 1 audit yet) → LOUD forbidden-list mode (v13.0.5)
# - Normal phase 2/3/4 → minimal status (cognitive overhead low)
if phase_int <= 4:
    has_any_a1 = any(
        any(marker in l for marker in (
            "| asama-1-", "| summary-confirm-approve |",
            "| asama-2-", "| asama-3-", "| asama-4-",
            "| precision-audit |", "| engineering-brief |",
        ))
        for l in audit_lines
    )
    if phase_int == 1 and not has_any_a1:
        # LOUD mode — first turn of session, no audit emitted yet.
        if lang == "tr":
            print("⛔ ASAMA 1 ZORUNLU — Henuz hicbir Asama 1 audit i emit edilmedi.")
            print("YASAK: Spec yazma. Write/Edit/MultiEdit cagirma. AskUserQuestion (Faz 4 spec onayi) acmaya kalkma.")
            print("ILK IS: Gelistiricinin niyetini anla. Tek soru sor (one-question-at-a-time)")
            print("       VEYA tum parametreler net ise SILENT-ASSUME path ile ozet uret.")
            print("Sonra: Bash mcl_audit_log ile asama-1-question-N veya summary-confirm-approve audit i emit et.")
            print("Audit i seed eden Bash + Read/Glob/Grep/LS aracilari serbest. Mutating tools KILITLI.")
        else:
            print("⛔ ASAMA 1 MANDATORY — No Aşama 1 audit emitted in this session yet.")
            print("FORBIDDEN: emitting a spec, calling Write/Edit/MultiEdit, opening AskUserQuestion (Faz 4 spec approval).")
            print("FIRST ACTION: understand developer intent. Ask one disambiguation question (one-question-at-a-time)")
            print("              OR if all parameters are clear, produce a SILENT-ASSUME summary.")
            print("Then: emit asama-1-question-N or summary-confirm-approve audit via Bash mcl_audit_log.")
            print("Audit-seed Bash + Read/Glob/Grep/LS are allowed; mutating tools are LOCKED.")
        sys.exit(0)
    # Normal minimal mode for phase 2/3/4 or phase 1 after first audit
    next_audit_hint = ""
    if "required_audits" in pspec:
        missing = [a for a in pspec["required_audits"] if not has_audit(a)]
        if missing:
            next_audit_hint = ", ".join(missing)
    if not next_audit_hint:
        next_audit_hint = "advance gate"
    print(labels["minimal_pre_spec"].format(n=phase, next=next_audit_hint))
    sys.exit(0)

t = pspec["type"]

# ── single ────────────────────────────────────────────────────────
if t == "single":
    if "required_audits_any" in pspec:
        missing = [a for a in pspec["required_audits_any"] if not has_audit(a)]
        if not missing or len(missing) < len(pspec["required_audits_any"]):
            print(labels["completed"])
            sys.exit(0)
        print(f"{labels['this_turn']}: {pspec['required_audits_any'][0]} (or any of: {', '.join(pspec['required_audits_any'])})")
    elif "required_audits" in pspec:
        missing = [a for a in pspec["required_audits"] if not has_audit(a)]
        if not missing:
            print(labels["completed"])
            sys.exit(0)
        print(f"{labels['this_turn']}: {missing[0]}")
        if len(missing) > 1:
            print(f"{labels['remaining']}: {', '.join(missing[1:])}")
    print(f"{labels['next_phase']}: {next_phase_int} — {next_phase_name}{next_skip}")
    sys.exit(0)

# ── section ───────────────────────────────────────────────────────
if t == "section":
    missing = [a for a in pspec["required_sections"] if not has_audit(a)]
    if not missing:
        print(labels["completed"])
    else:
        print(f"{labels['this_turn']}: {missing[0]}")
        if len(missing) > 1:
            print(f"{labels['remaining']}: {', '.join(missing[1:])}")
    print(f"{labels['next_phase']}: {next_phase_int} — {next_phase_name}{next_skip}")
    sys.exit(0)

# ── list (Aşama 10, 19) — KEY: unlimited-question handling ────────
if t == "list":
    declared_audit = pspec["declared_audit"]
    K = parse_kv_last(declared_audit, pspec.get("count_key", "count"))
    if K is None:
        print(labels["items_declared_missing"].format(audit=declared_audit))
        sys.exit(0)
    pat = pspec["item_audit_pattern"]
    rx_str = re.escape(pat).replace(r"\{n\}", r"(\d+)")
    resolved_indices = distinct_indices(r"\| " + rx_str + r" \|")
    M = len(resolved_indices)
    pending = K - M
    if pending <= 0:
        print(labels["completed"])
        print(f"{labels['next_phase']}: {next_phase_int} — {next_phase_name}{next_skip}")
        sys.exit(0)
    current_idx = (max(resolved_indices) + 1) if resolved_indices else 1
    print(f"{labels['remaining']}: {M}{labels['of']}{K} resolved, {pending} pending")
    print(f"{labels['current_item']}: #{current_idx}")
    next_audit = pat.replace("{n}", str(current_idx))
    print(f"{labels['this_turn']}: {next_audit}")
    sys.exit(0)

# ── iterative (11-14) ─────────────────────────────────────────────
if t == "iterative":
    scan_audit = pspec["scan_audit"]
    rescan_audit = pspec["rescan_audit"]
    K = parse_kv_last(scan_audit, "count") or 0
    if K == 0 and not has_audit(scan_audit):
        print(f"{labels['this_turn']}: {scan_audit} count=K")
        sys.exit(0)
    fix_pat = pspec["fix_audit_pattern"]
    fix_rx = re.escape(fix_pat).replace(r"\{n\}", r"(\d+)")
    M = len(distinct_indices(r"\| " + fix_rx + r" \|"))
    rescan_count = parse_kv_last(rescan_audit, "count")
    if rescan_count == 0:
        print(labels["completed"])
        print(f"{labels['next_phase']}: {next_phase_int} — {next_phase_name}{next_skip}")
        sys.exit(0)
    rs_label = labels["rescan_due"] if rescan_count is None or rescan_count > 0 else labels["rescan_zero"]
    print(labels["scan_state"].format(k=K, m=M, rs=rs_label))
    if M < K:
        next_audit = fix_pat.replace("{n}", str(M + 1))
        print(f"{labels['this_turn']}: {next_audit}")
    else:
        print(f"{labels['this_turn']}: {rescan_audit} count=<recount>")
    sys.exit(0)

# ── substep (Faz 9 — TDD) ────────────────────────────────────────
if t == "substep":
    must = parse_kv_last(pspec["ac_source_audit"], "must") or 0
    should = parse_kv_last(pspec["ac_source_audit"], "should") or 0
    total = must + should
    if total <= 0:
        print(labels["completed"])
        sys.exit(0)
    pat = pspec["audit_pattern"]
    triples = pspec["triple_audits"]
    # Per-AC status grid — render only the "current" AC (first incomplete)
    for i in range(1, total + 1):
        statuses = {}
        for tag in triples:
            audit_name = pat.replace("{i}", str(i)).replace("{tag}", tag)
            statuses[tag] = TICK if has_audit(audit_name) else CROSS
        if any(v == CROSS for v in statuses.values()):
            print(labels["ac_status"].format(
                i=i, N=total,
                r=statuses.get("red", "?"),
                g=statuses.get("green", "?"),
                x=statuses.get("refactor", "?"),
            ))
            # Next missing tag
            next_tag = next((tag for tag in triples if statuses[tag] == CROSS), None)
            if next_tag:
                next_audit = pat.replace("{i}", str(i)).replace("{tag}", next_tag)
                print(f"{labels['this_turn']}: {next_audit}")
            sys.exit(0)
    print(labels["completed"])
    print(f"{labels['next_phase']}: {next_phase_int} — {next_phase_name}{next_skip}")
    sys.exit(0)

# ── self-check (Faz 22) ───────────────────────────────────────────
if t == "self-check":
    needed = pspec["required_phases_complete"]
    missing = [n for n in needed if not has_audit(f"asama-{n}-complete")]
    if not missing:
        print(labels["completed"])
        sys.exit(0)
    print(f"{labels['remaining']}: {len(needed) - len(missing)}{labels['of']}{len(needed)} phases verified, {len(missing)} missing")
    print(f"{labels['this_turn']}: deep-dive Aşama {missing[0]} — verify completion")
    sys.exit(0)

print("DSI: unrecognized phase type")
PYEOF
}

# v13.0.9 — Active phase directive renderer.
# Replaces the static 22-block PHASE SCRIPT in mcl-activate.sh with a
# dynamic single-phase view (attention-decay mitigation: lost-in-the-middle).
# Output: directive block for the CURRENT phase only + compact phase index
# + next-phase preview. ~10x smaller than the old 22-block PHASE SCRIPT.
#
# Public API:
#   _mcl_dsi_render_active_phase <phase>  → stdout text
#
# Used by mcl-activate.sh to inject `<mcl_active_phase_directive>` block.
_mcl_dsi_render_active_phase() {
  local phase="$1"
  local spec_file="${MCL_GATE_SPEC:-${HOME}/.claude/skills/my-claude-lang/gate-spec.json}"
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  local lang="${MCL_LANG:-tr}"

  python3 - "$spec_file" "$audit_file" "$trace_file" "$phase" "$lang" 2>/dev/null <<'PYEOF' || echo "AKTIF FAZ DIRECTIVE: helper crashed"
import json, os, re, sys

spec_path, audit_path, trace_path, phase, lang = sys.argv[1:6]

# Phase metadata: name + skill file + 1-2 line task + emit pattern + skip cond
# Source: MCL_Pipeline.md (canonical 22-phase architecture).
PHASE_META = {
    "1":  {"name_tr": "Niyet (Gather)",          "name_en": "Intent (Gather)",      "skill": "asama1-gather.md",          "task_tr": "Geliştirici niyetini anla. Tek soru sor (one-question-at-a-time) VEYA tum parametreler net ise SILENT-ASSUME path ile özet üret.", "emit_tr": "asama-1-question-N | summary-confirm-approve (closing askq sonrası)", "skip_tr": ""},
    "2":  {"name_tr": "Precision Audit",         "name_en": "Precision Audit",      "skill": "asama2-precision-audit.md", "task_tr": "7 boyutluk precision audit (permission, failure modes, out-of-scope, PII, audit, perf SLA, idempotency) + stack add-on. Her boyut SILENT-ASSUME / SKIP-MARK / GATE classification.", "emit_tr": "precision-audit core_gates=N stack_gates=M | closing askq sonrası asama-2-complete", "skip_tr": "İngilizce session'da skipped=true"},
    "3":  {"name_tr": "Engineering Brief",       "name_en": "Engineering Brief",    "skill": "asama3-translator.md",      "task_tr": "Onaylanan parametreleri İngilizce engineering brief'e çevir. Vague verb upgrade (list → fetch+paginate, manage → expose CRUD).", "emit_tr": "engineering-brief | asama-3-complete", "skip_tr": "İngilizce session'da identity"},
    "4":  {"name_tr": "Spec + Verify",           "name_en": "Spec + Verify",        "skill": "asama4-spec.md",            "task_tr": "📋 Spec: bloğu emit et (Objective, MUST/SHOULD, AC, Edge Cases, Technical Approach, Out of Scope). Geliştirici diline özet. AskUserQuestion ile onay. asama-4-ac-count must=N should=M emit ZORUNLU.", "emit_tr": "asama-4-ac-count must=N should=M | asama-4-complete (askq onayı sonrası)", "skip_tr": ""},
    "5":  {"name_tr": "Pattern Matching",        "name_en": "Pattern Matching",     "skill": "asama5-pattern-matching.md","task_tr": "Mevcut sibling dosyaları oku, naming + error handling + test pattern çıkar. Greenfield ise atla.", "emit_tr": "pattern-summary-stored | asama-5-complete | asama-5-skipped reason=greenfield", "skip_tr": "Greenfield veya empty+no-stack"},
    "6":  {"name_tr": "UI Build",                "name_en": "UI Build",             "skill": "asama6-ui-build.md",        "task_tr": "Frontend dummy data ile yaz, npm install + npm run dev (run_in_background:true), sleep + tarayıcıyı OTOMATİK aç. denied_paths: backend (src/api/**, prisma/**, ...).", "emit_tr": "asama-6-end server_started=true browser_opened=true | asama-6-skipped reason=no-ui-flow", "skip_tr": "UI flow yoksa"},
    "7":  {"name_tr": "UI Review",               "name_en": "UI Review",            "skill": "asama7-ui-review.md",       "task_tr": "AskUserQuestion ile geliştirici UI onayı. Options: Onayla / Revize / Sen de bak ve raporla / İptal.", "emit_tr": "asama-7-complete (askq onayı sonrası) | asama-7-skipped (Aşama 6 atlandıysa)", "skip_tr": "Aşama 6 atlandıysa", "narration_tr": "Deferred — Aşama 6 dev server sonrası geliştirici cevabıyla başlar. Faz listesinde DAİMA görünür kalır: '... → 6 → 7 (deferred) → 8 ...'. Sessizce düşürmek yasak; sadece Aşama 6 atlanırsa '(atlandı — Aşama 6)' notuyla işaretle.", "narration_en": "Deferred — starts on developer's reply after Aşama 6 dev server. ALWAYS visible in phase list: '... → 6 → 7 (deferred) → 8 ...'. Silent omission forbidden; only when Aşama 6 is skipped, mark '(skipped — Aşama 6)'."},
    "8":  {"name_tr": "DB Design",               "name_en": "DB Design",            "skill": "asama8-db-design.md",       "task_tr": "Schema (3NF), index strategy, query plan. Migration files yaz.", "emit_tr": "asama-8-end | asama-8-not-applicable reason=no-db-in-scope", "skip_tr": "DB scope yoksa"},
    "9":  {"name_tr": "TDD Execute",             "name_en": "TDD Execute",          "skill": "asama9-tdd.md",             "task_tr": "Her AC için RED (failing test) → GREEN (minimum kod) → REFACTOR. asama-4-ac-count'tan must+should toplamı kadar üçlü.", "emit_tr": "asama-9-ac-{i}-red, asama-9-ac-{i}-green, asama-9-ac-{i}-refactor (her AC için)", "skip_tr": ""},
    "10": {"name_tr": "Risk Review",             "name_en": "Risk Review",          "skill": "asama10-risk-review.md",    "task_tr": "Spec compliance pre-check + missed-risk scan. asama-10-items-declared count=K emit ZORUNLU. Sonra her risk için sıralı AskUserQuestion (skip / fix / rule).", "emit_tr": "asama-10-items-declared count=K | her item için asama-10-item-{n}-resolved", "skip_tr": ""},
    "11": {"name_tr": "Code Review",             "name_en": "Code Review",          "skill": "asama11-code-review.md",    "task_tr": "Yeni/değişen dosyalarda code review. Scan → fix → rescan loop, otomatik fix.", "emit_tr": "asama-11-scan count=K | asama-11-issue-{n}-fixed | asama-11-rescan count=0 (stable)", "skip_tr": ""},
    "12": {"name_tr": "Simplify",                "name_en": "Simplify",             "skill": "asama12-simplify.md",       "task_tr": "Yeni/değişen dosyalarda simplify. Premature abstraction, duplicate logic.", "emit_tr": "asama-12-scan / issue-fixed / rescan", "skip_tr": ""},
    "13": {"name_tr": "Performance",             "name_en": "Performance",          "skill": "asama13-performance.md",    "task_tr": "N+1, unbounded loops, blocking calls.", "emit_tr": "asama-13-scan / issue-fixed / rescan", "skip_tr": ""},
    "14": {"name_tr": "Security",                "name_en": "Security",             "skill": "asama14-security.md",       "task_tr": "Whole-project semgrep + injection / auth / CSRF / secrets.", "emit_tr": "asama-14-scan / issue-fixed / rescan", "skip_tr": ""},
    "15": {"name_tr": "Unit Tests",              "name_en": "Unit Tests",           "skill": "asama15-unit-tests.md",     "task_tr": "Yeni function/class/module için unit test + TDD verify.", "emit_tr": "asama-15-end-green", "skip_tr": "Code shape not applicable"},
    "16": {"name_tr": "Integration Tests",       "name_en": "Integration Tests",    "skill": "asama16-integration-tests.md","task_tr": "Cross-module, API endpoints, DB.", "emit_tr": "asama-16-end-green", "skip_tr": ""},
    "17": {"name_tr": "E2E Tests",               "name_en": "E2E Tests",            "skill": "asama17-e2e-tests.md",      "task_tr": "UI active + new user flows.", "emit_tr": "asama-17-end-green", "skip_tr": ""},
    "18": {"name_tr": "Load Tests",              "name_en": "Load Tests",           "skill": "asama18-load-tests.md",     "task_tr": "Throughput-sensitive paths.", "emit_tr": "asama-18-end-target-met", "skip_tr": ""},
    "19": {"name_tr": "Impact Review",           "name_en": "Impact Review",        "skill": "asama19-impact-review.md",  "task_tr": "Downstream impact scan. asama-19-items-declared count=K emit ZORUNLU. Her impact için sıralı AskUserQuestion.", "emit_tr": "asama-19-items-declared count=K | asama-19-item-{n}-resolved", "skip_tr": ""},
    "20": {"name_tr": "Verify Report",           "name_en": "Verify Report",        "skill": "asama20-verify-report.md",  "task_tr": "Spec coverage table + mock cleanup.", "emit_tr": "asama-20-complete + asama-20-mock-cleanup-resolved", "skip_tr": ""},
    "21": {"name_tr": "Localized Report",        "name_en": "Localized Report",     "skill": "asama21-localized-report.md","task_tr": "EN → geliştirici diline strict çeviri.", "emit_tr": "asama-21-complete", "skip_tr": "İngilizce session'da identity"},
    "22": {"name_tr": "Completeness Audit",      "name_en": "Completeness Audit",   "skill": "asama22-completeness.md",   "task_tr": "audit.log okunup 1-21 fazlarının tamamlandığını doğrula. Hook self-emit eder.", "emit_tr": "asama-22-complete (hook auto-emit)", "skip_tr": ""},
}

L = {
    "tr": {
        "active_label": "AKTİF FAZ",
        "skill_label": "Skill",
        "task_label": "Görev",
        "emit_label": "Emit",
        "skip_label": "Skip koşulu",
        "next_label": "SONRAKİ FAZ",
        "auto_advance": "audit emit edilince auto-advance",
        "phase_index_label": "TÜM FAZLAR",
        "current_marker": "← AKTİF",
        "skip_marker": "(skip-eligible)",
        "unknown_phase": "AKTİF FAZ: bilinmiyor",
        "header_directive": "🛑 NO MID-PIPELINE STOP RULE — Aşama 4 spec onayından sonra Aşama 22 tamamlanana kadar pipeline ortasında durmak yasak. Bu turun sonunda mevcut fazın audit'i emit edilmeli + bir sonraki fazın başlangıcı yapılmalı. Yalnızca AskUserQuestion gate'lerinde dur (Faz 7, 10-her-risk, 19-her-impact). 'Kod yazdım, bitti' diyerek faz ortasında durmak yasak.\n📋 NARRATION RULE — Faz listesi yazarken (örn. 'Aşama 5 → 6 → ...') Aşama 7 DAİMA görünür kalır. Deferred ≠ skipped: Aşama 7 deferred olsa bile (Aşama 6 dev-server sonrası geliştirici cevabıyla başlar) listeden ASLA düşürülmez. Yasak: 'Aşama 5 → 6 → 8 → 9'. Doğru: 'Aşama 5 → 6 → 7 (deferred) → 8 → 9'. Sadece Aşama 6 atlandıysa '(atlandı — Aşama 6)' notuyla.",
    },
    "en": {
        "active_label": "ACTIVE PHASE",
        "skill_label": "Skill",
        "task_label": "Task",
        "emit_label": "Emit",
        "skip_label": "Skip condition",
        "next_label": "NEXT PHASE",
        "auto_advance": "auto-advance on audit emit",
        "phase_index_label": "ALL PHASES",
        "current_marker": "← ACTIVE",
        "skip_marker": "(skip-eligible)",
        "unknown_phase": "ACTIVE PHASE: unknown",
        "header_directive": "🛑 NO MID-PIPELINE STOP RULE — Between Aşama 4 spec approval and Aşama 22 completion, mid-pipeline stops are forbidden. End of every turn must emit current phase's audit + start the next phase. Only AskUserQuestion gates pause (Faz 7, 10 per-risk, 19 per-impact). 'Wrote code, done' mid-phase = forbidden.\n📋 NARRATION RULE — When writing phase lists (e.g. 'Aşama 5 → 6 → ...') Aşama 7 ALWAYS stays visible. Deferred ≠ skipped: even when Aşama 7 is deferred (starts on developer's reply after Aşama 6 dev-server), it is NEVER dropped from the list. Forbidden: 'Aşama 5 → 6 → 8 → 9'. Correct: 'Aşama 5 → 6 → 7 (deferred) → 8 → 9'. Only when Aşama 6 is skipped, mark '(skipped — Aşama 6)'.",
    },
}
labels = L.get(lang, L["en"])
name_key = "name_tr" if lang == "tr" else "name_en"
task_key = "task_tr"  # tasks always TR for now (calibration); skill files have full multilingual content
emit_key = "emit_tr"
skip_key = "skip_tr"
narration_key = "narration_tr" if lang == "tr" else "narration_en"

if phase not in PHASE_META:
    print(labels["unknown_phase"])
    sys.exit(0)

meta = PHASE_META[phase]
phase_int = int(phase)

# Header directive (ONE line, top of injection)
print(labels["header_directive"])
print()

# Active phase block
print(f"━━━ {labels['active_label']}: Aşama {phase} — {meta[name_key]} ━━━")
print(f"{labels['skill_label']}: ~/.claude/skills/my-claude-lang/{meta['skill']}")
print(f"{labels['task_label']}: {meta[task_key]}")
print(f"{labels['emit_label']}: {meta[emit_key]}")
if meta.get(skip_key):
    print(f"{labels['skip_label']}: {meta[skip_key]}")
if meta.get(narration_key):
    print(f"📋 {meta[narration_key]}")

# Next phase preview
if phase_int < 22:
    next_p = str(phase_int + 1)
    next_meta = PHASE_META.get(next_p)
    if next_meta:
        print()
        print(f"{labels['next_label']}: Aşama {next_p} — {next_meta[name_key]} ({labels['auto_advance']})")

# Compact phase index — all 22 phases on a few lines for global awareness
print()
print(f"{labels['phase_index_label']}:")
groups = [
    ("1-4 Niyet→Spec",  ["1", "2", "3", "4"]),
    ("5-8 Hazırlık",    ["5", "6", "7", "8"]),
    ("9 TDD + 10 Risk", ["9", "10"]),
    ("11-14 Quality",   ["11", "12", "13", "14"]),
    ("15-18 Tests",     ["15", "16", "17", "18"]),
    ("19-22 Kapanış",   ["19", "20", "21", "22"]),
]
for grp_label, phases in groups:
    parts = []
    for p in phases:
        m = PHASE_META.get(p, {})
        nm = m.get(name_key, "?")
        marker = f" {labels['current_marker']}" if p == phase else ""
        parts.append(f"{p} {nm}{marker}")
    print(f"  {grp_label}: " + " · ".join(parts))
PYEOF
}

# CLI entrypoint for unit tests
if [ "${1:-}" = "--cli" ] || [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  _PHASE=""; _AUDIT=""; _SPEC=""; _STATE=""; _LANG="tr"; _MODE="status"
  shift 2>/dev/null  # consume --cli if present
  while [ $# -gt 0 ]; do
    case "$1" in
      --phase) _PHASE="$2"; shift 2;;
      --audit) _AUDIT="$2"; shift 2;;
      --spec)  _SPEC="$2";  shift 2;;
      --state) _STATE="$2"; shift 2;;
      --lang)  _LANG="$2";  shift 2;;
      --mode)  _MODE="$2";  shift 2;;
      *) shift;;
    esac
  done
  [ -n "$_AUDIT" ] && export MCL_STATE_DIR="$(dirname "$_AUDIT")"
  [ -n "$_SPEC" ] && export MCL_GATE_SPEC="$_SPEC"
  export MCL_LANG="$_LANG"
  case "$_MODE" in
    active) _mcl_dsi_render_active_phase "$_PHASE" ;;
    *)      _mcl_dsi_render "$_PHASE" ;;
  esac
fi
