# MCL v13.0.0 — Universal Deterministic Gate Protocol
## Implementation Brief for Claude Code

**Repo:** `https://github.com/YZ-LLM/my-claude-lang`
**Current version:** 12.0.0
**Target version:** 13.0.0

---

## Hedef

Repo şu an **yarı-geçiş** durumunda — `state.schema` ve `mcl-activate.sh` 22 fazlık şemayı anlatıyor ama `mcl-stop.sh` hâlâ v11 (12 fazlık) mantığında. Bu brief geçişi tamamlar **ve** her fazı deterministik gate ile sertleştirir: model `*-complete` emit yetkisinden çıkarılır, hook her fazın gate tipine göre completeness'i kendisi doğrular ve auto-emit eder.

---

## Mevcut tutarsızlıkların envanteri

Repo'yu tarayarak doğrulanmış gerçekler:

| Bileşen | Durum |
|---|---|
| `hooks/lib/mcl-state.sh:113` | `1 <= current_phase <= 22` validation — **22 fazlık** |
| `hooks/mcl-activate.sh:217` | Skill prompt'u Aşama 1...22 listeliyor — **22 fazlık** |
| `MCL_Pipeline.md` | 12 fazlık eski döküman — **eski** |
| `hooks/mcl-stop.sh:892` | `range(10, 18)` quality scan — **v11 numaralandırması** |
| `hooks/mcl-stop.sh:1054` | `phase_transition 12 done` — **v11 numaralandırması** |
| `hooks/mcl-state.sh:66-67` | `risk_review_state`, `quality_review_state` — eski isimler |
| `skills/my-claude-lang/asama11-..asama18-*.md` | **VAR** — 22 fazlık skill dosyaları |
| `skills/my-claude-lang/asama10-risk-review.md` | Audit format `h_count=N m_count=M l_count=K resolved=R` |
| `skills/my-claude-lang/asama19-impact-review.md` | Audit format `impacts=N resolved=R` |
| `VERSION` | `12.0.0` |
| `README.md` | banner `MCL 6.2.1` — çok eski, açıklama 7 fazlık |

---

## v13.0 hedef şema

22 faz, gate tipleri:

| # | Faz | Tip | Gate şartı |
|---|---|---|---|
| 1 | Gathering | single | `summary-confirm-approve` |
| 2 | Precision Audit | single | `asama-2-complete` (mevcut) |
| 3 | Translator (TR→EN) | single | `asama-3-complete` |
| 4 | Spec emit + approval | single | `asama-4-complete` (mevcut) |
| 5 | Pattern Matching | single-or-skip | `asama-5-complete` veya `asama-5-skipped` |
| 6 | UI Build (6a/6b/6c) | section | `asama-6a-complete` + `asama-6b-approved` + `asama-6c-complete` |
| 7 | UI Review | (6b içinde, ayrı faz değil) | — |
| 8 | DB Design | single-or-skip | `asama-8-end` veya `asama-8-not-applicable` |
| 9 | TDD execute | substep | her AC için RED+GREEN+REFACTOR triple |
| 10 | Risk Review | **list** | `items-declared` → her item resolved |
| 11 | Code Review | **iterative** | scan → fix → rescan=0 |
| 12 | Simplify | iterative | aynı |
| 13 | Performance | iterative | aynı |
| 14 | Security | iterative | aynı |
| 15 | Unit + TDD test | section | `asama-15-end green=true` |
| 16 | Integration test | section | `asama-16-end green=true` |
| 17 | E2E test | section | `asama-17-end green=true` |
| 18 | Load test | section | `asama-18-end met_target=true` |
| 19 | Impact Review | **list** | `items-declared` → her item resolved |
| 20 | Verification Report | section | `asama-20-complete` + `asama-20-mock-cleanup-end` |
| 21 | Localized Report | single | `asama-21-complete` |
| 22 | Completeness Audit | self-check | hook 1-21 *-complete kayıtlarını doğrular |

**Not:** Pipeline'da Faz 7 (UI Review) ayrı top-level değil — Aşama 6'nın 6b alt-fazı. Yani **görünen 22 numara, 22 ayrı gate**: 6'nın 3 alt-fazı (6a/6b/6c) tek section gate'in 3 required section'ı, 7 numarası boş.

→ **Karar:** Ya 7'yi 6b ile birleştirip kanon 21 fazlı yapıyoruz, ya da Faz 7'yi **bağımsız UI review faz** haline getiriyoruz (6c'den önce). Brief'in bu sürümü ikincisini varsayar (skill dosyaları zaten ayrı: `asama6-ui-build.md` + `asama7-ui-review.md`).

---

## Universal protokol

### Model'in YENİ yetkileri (sınırlı)
- `asama-N-entry`
- `asama-N-items-declared count=K [breakdown]` — sadece list-gate
- `asama-N-section-X-emitted` — section-gate
- `asama-N-item-M-resolved` — list-gate per-item
- `asama-N-issue-M-fixed` — iterative-gate per-issue
- `asama-N-scan count=K` — iterative-gate scan
- `asama-N-rescan count=R` — iterative-gate rescan
- `asama-N-skipped reason=...` — skip-eligible fazlar (5, 8)
- `asama-9-ac-i-red`, `asama-9-ac-i-green`, `asama-9-ac-i-refactor` — Faz 9 substep
- **Faz 4 ek zorunluluk:** `asama-4-ac-count must=N should=M` (Faz 9'un kaynağı)

### Model'in YASAK emit'leri (PreToolUse deny)
- `asama-N-complete` (her N için)
- `phase_transition N M`
- `asama-N-progression-from-emit`

İhlal durumunda: `asama-N-illegal-emit-attempt` audit + tool denied.

### Hook'un YENİ yetkileri
- Stop hook her turn sonu aktif fazı `gate-spec.json`'dan oku → tipine göre completeness check → auto-emit `complete` + `phase_transition` + `state.current_phase++`

---

## Yeni dosyalar

### 1. `skills/my-claude-lang/gate-spec.json`

```json
{
  "version": "13.0.0",
  "phases": {
    "1":  {"type": "single", "required_audits": ["summary-confirm-approve"]},
    "2":  {"type": "single", "required_audits": ["asama-2-complete"]},
    "3":  {"type": "single", "required_audits": ["asama-3-complete"]},
    "4":  {"type": "single", "required_audits": ["asama-4-complete", "asama-4-ac-count"]},
    "5":  {"type": "single", "required_audits_any": ["asama-5-complete", "asama-5-skipped"]},
    "6":  {"type": "section", "required_sections": ["asama-6a-complete", "asama-6b-approved", "asama-6c-complete"]},
    "7":  {"type": "single", "required_audits": ["asama-7-complete"]},
    "8":  {"type": "single", "required_audits_any": ["asama-8-end", "asama-8-not-applicable"]},
    "9":  {"type": "substep", "ac_source_audit": "asama-4-ac-count", "ac_keys": ["must", "should"], "triple_audits": ["red", "green", "refactor"], "audit_pattern": "asama-9-ac-{i}-{tag}"},
    "10": {"type": "list", "declared_audit": "asama-10-items-declared", "item_audit_pattern": "asama-10-item-{n}-resolved", "count_key": "count"},
    "11": {"type": "iterative", "scan_audit": "asama-11-scan", "fix_audit_pattern": "asama-11-issue-{n}-fixed", "rescan_audit": "asama-11-rescan", "completion_when": "rescan_count_eq_zero"},
    "12": {"type": "iterative", "scan_audit": "asama-12-scan", "fix_audit_pattern": "asama-12-issue-{n}-fixed", "rescan_audit": "asama-12-rescan", "completion_when": "rescan_count_eq_zero"},
    "13": {"type": "iterative", "scan_audit": "asama-13-scan", "fix_audit_pattern": "asama-13-issue-{n}-fixed", "rescan_audit": "asama-13-rescan", "completion_when": "rescan_count_eq_zero"},
    "14": {"type": "iterative", "scan_audit": "asama-14-scan", "fix_audit_pattern": "asama-14-issue-{n}-fixed", "rescan_audit": "asama-14-rescan", "completion_when": "rescan_count_eq_zero"},
    "15": {"type": "section", "required_sections": ["asama-15-end-green"]},
    "16": {"type": "section", "required_sections": ["asama-16-end-green"]},
    "17": {"type": "section", "required_sections": ["asama-17-end-green"]},
    "18": {"type": "section", "required_sections": ["asama-18-end-target-met"]},
    "19": {"type": "list", "declared_audit": "asama-19-items-declared", "item_audit_pattern": "asama-19-item-{n}-resolved", "count_key": "count"},
    "20": {"type": "section", "required_sections": ["asama-20-complete", "asama-20-mock-cleanup-resolved"]},
    "21": {"type": "single", "required_audits": ["asama-21-complete"]},
    "22": {"type": "self-check", "required_phases_complete": [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21]}
  }
}
```

### 2. `hooks/lib/mcl-gate.sh`

Universal gate engine. Public API: `_mcl_gate_check <phase>` → stdout `complete|incomplete|skipped`.

```bash
#!/usr/bin/env bash
# Universal gate engine — v13.0.0
# Reads gate-spec.json and audit.log, decides if a phase is complete.
# Side effect: caller is responsible for auto-emit + state advance.

_MCL_GATE_SPEC="${MCL_GATE_SPEC:-$HOME/.claude/skills/my-claude-lang/gate-spec.json}"

_mcl_gate_check() {
  local phase="$1"
  [ -z "$phase" ] && echo "incomplete" && return
  [ ! -f "$_MCL_GATE_SPEC" ] && echo "incomplete" && return
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"

  python3 - "$_MCL_GATE_SPEC" "$audit_file" "$trace_file" "$phase" 2>/dev/null <<'PYEOF' || echo "incomplete"
import json, os, re, sys
spec_path, audit_path, trace_path, phase = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# session boundary
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

try:
    spec = json.load(open(spec_path))
    pspec = spec["phases"][phase]
except Exception:
    print("incomplete"); sys.exit(0)

def has_audit(name):
    needle = f"| {name} |"
    return any(needle in l for l in audit_lines)

def parse_kv(name, key):
    needle = f"| {name} |"
    for l in audit_lines:
        if needle in l:
            m = re.search(rf"\b{re.escape(key)}=(\d+)", l)
            if m: return int(m.group(1))
    return None

def parse_kv_last(name, key):
    needle = f"| {name} |"
    val = None
    for l in audit_lines:
        if needle in l:
            m = re.search(rf"\b{re.escape(key)}=(\d+)", l)
            if m: val = int(m.group(1))
    return val

def count_pattern(pattern):
    rx = re.compile(re.escape(pattern).replace(r"\{n\}", r"\d+").replace(r"\{i\}", r"\d+").replace(r"\{tag\}", r"\w+"))
    return sum(1 for l in audit_lines if rx.search(l))

t = pspec["type"]

if t == "single":
    if "required_audits_any" in pspec:
        if any(has_audit(n) for n in pspec["required_audits_any"]):
            print("complete"); sys.exit(0)
    elif "required_audits" in pspec:
        if all(has_audit(n) for n in pspec["required_audits"]):
            print("complete"); sys.exit(0)
    print("incomplete"); sys.exit(0)

if t == "section":
    if all(has_audit(n) for n in pspec["required_sections"]):
        print("complete"); sys.exit(0)
    print("incomplete"); sys.exit(0)

if t == "list":
    declared = parse_kv_last(pspec["declared_audit"], pspec.get("count_key", "count"))
    if declared is None or declared <= 0:
        print("incomplete"); sys.exit(0)
    pat = pspec["item_audit_pattern"]
    rx = re.compile(r"\| " + re.escape(pat).replace(r"\{n\}", r"\d+") + r" \|")
    resolved = sum(1 for l in audit_lines if rx.search(l))
    print("complete" if resolved >= declared else "incomplete"); sys.exit(0)

if t == "iterative":
    rescan = parse_kv_last(pspec["rescan_audit"], "count")
    if rescan is not None and rescan == 0:
        print("complete"); sys.exit(0)
    print("incomplete"); sys.exit(0)

if t == "substep":
    must = parse_kv(pspec["ac_source_audit"], "must")
    should = parse_kv(pspec["ac_source_audit"], "should")
    if must is None or should is None:
        print("incomplete"); sys.exit(0)
    total = must + should
    if total <= 0:
        print("complete"); sys.exit(0)  # nothing to TDD against
    pat = pspec["audit_pattern"]
    needed = total * len(pspec["triple_audits"])
    rx = re.compile(r"\| " + re.escape(pat).replace(r"\{i\}", r"\d+").replace(r"\{tag\}", r"(red|green|refactor)") + r" \|")
    seen = sum(1 for l in audit_lines if rx.search(l))
    print("complete" if seen >= needed else "incomplete"); sys.exit(0)

if t == "self-check":
    needed = pspec["required_phases_complete"]
    for n in needed:
        if not has_audit(f"asama-{n}-complete"):
            print("incomplete"); sys.exit(0)
    print("complete"); sys.exit(0)

print("incomplete")
PYEOF
}
```

---

## Hook entegrasyonu

### `hooks/mcl-pre-tool.sh` — universal deny

Mevcut Aşama 2 SKIP-BLOCK bloğundan (line ~895) hemen önce, JIT classifier sonrasında ekle:

```bash
# v13.0 — Universal model emit denylist
# Model artık asama-N-complete / phase_transition / asama-N-progression-from-emit
# emit edemez. Hook bunları kendisi yazar.
_TOOL_DETAIL="$(printf '%s' "$TOOL_INPUT" 2>/dev/null)"
_DENY_PATTERN='(asama-[0-9]+-complete|phase_transition[[:space:]]+[0-9]+[[:space:]]+[0-9]+|asama-[0-9]+-progression-from-emit)'
if echo "$_TOOL_DETAIL" | grep -qE "$_DENY_PATTERN"; then
  _BAD_TOKEN="$(echo "$_TOOL_DETAIL" | grep -oE "$_DENY_PATTERN" | head -1)"
  _DENY_PHASE="$(echo "$_BAD_TOKEN" | grep -oE '[0-9]+' | head -1)"
  mcl_audit_log "asama-${_DENY_PHASE:-?}-illegal-emit-attempt" "pre-tool" "token=$_BAD_TOKEN tool=$TOOL_NAME"
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"v13.0 deterministic gate: \`$_BAD_TOKEN\` is hook-emitted only. Model must emit *-entry / *-items-declared / *-item-M-resolved / *-scan / *-rescan / *-issue-M-fixed / *-section-X-emitted / *-skipped / asama-9-ac-i-{red,green,refactor} only. Phase completion auto-fires when gate criteria are met."}}
JSON
  exit 0
fi
```

### `hooks/mcl-stop.sh` — universal completeness loop

Source `mcl-gate.sh`'ı ekle (dosyanın başındaki diğer source'larla):

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/mcl-gate.sh" 2>/dev/null || true
```

Mevcut Aşama 8/9/10/11/12 hard-coded progression bloklarını (line 864-1055) **TAMAMEN SİL**. Yerine universal loop:

```bash
# === v13.0 — Universal phase completion loop ===
# Replaces hardcoded asama-8/9/10/11/12 blocks (v11/v12 era).
# Reads gate-spec.json, checks each phase from current_phase forward,
# auto-emits *-complete + phase_transition for each gate that passes.
# Loop bound: max 22 iterations (defensive cap, never reached in practice).

_V13_CUR="$(mcl_state_get current_phase 2>/dev/null || echo 1)"
_V13_ITER=0
while [ "$_V13_ITER" -lt 22 ]; do
  _V13_ITER=$((_V13_ITER + 1))
  _V13_PHASE="$_V13_CUR"
  _V13_RESULT="$(_mcl_gate_check "$_V13_PHASE" 2>/dev/null || echo incomplete)"
  if [ "$_V13_RESULT" != "complete" ]; then
    break
  fi
  # Idempotency: skip if asama-N-complete already in audit this session
  if _mcl_audit_emitted_in_session "asama-${_V13_PHASE}-complete" "" 2>/dev/null | grep -q '^1$'; then
    : # already emitted — just advance
  else
    mcl_audit_log "asama-${_V13_PHASE}-complete" "stop-auto" "gate=passed"
  fi
  _V13_NEXT=$((_V13_PHASE + 1))
  if [ "$_V13_NEXT" -gt 22 ]; then
    mcl_trace_append phase_transition "$_V13_PHASE" "done"
    break
  fi
  mcl_trace_append phase_transition "$_V13_PHASE" "$_V13_NEXT"
  mcl_state_set current_phase "$_V13_NEXT" >/dev/null 2>&1 || true
  _V13_CUR="$_V13_NEXT"
done
```

### `hooks/lib/mcl-state.sh` — schema temizliği

`_mcl_state_default()` içindeki eski state field'ları temizle/yeniden adlandır:

```bash
# ESKİ → YENİ
"risk_review_state": null,        →  KALDIRİLACAK (gate-spec ile yer değiştirir)
"quality_review_state": null,     →  KALDIRİLACAK
"open_severity_count": 0,         →  KALSIN (Aşama 14 severity gate hâlâ kullanıyor)
"tdd_compliance_score": null,     →  KALSIN
```

`mcl_get_active_phase()` helper'ındaki eski coarse-bucket mapping'i (`current_phase == 1, 4, 7, 11`) **kaldır** — artık `current_phase` 1..22 fine-grained.

---

## Skill MD güncellemeleri (24 dosya)

### Genel kural — her `asamaN-*.md` dosyasında

**ÇIKAR:**
- `mcl_audit_log asama-N-complete ...` (her form: ` mcl-stop`, `stop`, doğrudan emit)
- `phase_transition N M` referansları model komutu olarak

**EKLE (gate tipine göre):**

#### Faz 4 (`asama4-spec.md`) — özel
Aşama 4 emit zorunluluğuna ek satır:
```bash
# v13.0 zorunlu: AC count audit (Faz 9 substep gate'inin kaynağı)
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log "asama-4-ac-count" "model" "must=<MUST_COUNT> should=<SHOULD_COUNT>"'
```

#### Faz 9 (`asama9-tdd.md`) — substep
Model her acceptance criterion için 3 audit emit eder:
```bash
mcl_audit_log "asama-9-ac-${i}-red"      "model" "ac_index=${i} test_file=<path>"
mcl_audit_log "asama-9-ac-${i}-green"    "model" "ac_index=${i} prod_file=<path>"
mcl_audit_log "asama-9-ac-${i}-refactor" "model" "ac_index=${i}"
```
**Refactor zorunlu** — "skip if not needed" yok. Refactor gerekmiyorsa boş audit (`reason=no-changes-needed`) emit edilir ama atlamak yasak.

#### Faz 10 (`asama10-risk-review.md`) — list
Mevcut emit:
```
mcl_audit_log asama-10-complete mcl-stop "h_count=N m_count=M l_count=K resolved=R"
```
**SİL.** Yerine, Aşama 10 girişinde:
```bash
# Risk listesi tamamlandığında (her risk surface edilmiş ama henüz konuşulmamış)
mcl_audit_log "asama-10-items-declared" "model" "count=<N> h_count=<H> m_count=<M> l_count=<L>"
```
Her risk dialog kapanışında (kullanıcı AskUserQuestion'a cevap verdiğinde):
```bash
mcl_audit_log "asama-10-item-${idx}-resolved" "model" "decision=<apply|skip|rule> severity=<H|M|L>"
```
**LOW severity item'lar resolved sayılır mı?** count'a dahil edildiyse evet, dahil değilse hayır. Default: H+M sayılır, L declared count'a eklenmez.

#### Faz 11-14 (`asama11-..asama14-*.md`) — iterative
Mevcut emit (`asama-11-start`, `asama-11-end findings=N fixes=M skipped=K`) — **DEĞİŞTİR:**
```bash
# Scan: tarama tamamlandığında
mcl_audit_log "asama-11-scan" "model" "count=<K> categories=<list>"

# Her issue fix'lendikten sonra
mcl_audit_log "asama-11-issue-${idx}-fixed" "model" "rule=<id> file=<f>:<l>"

# Rescan: tüm fix'ler bittikten sonra yeniden tara
mcl_audit_log "asama-11-rescan" "model" "count=<R>"
# Eğer count > 0 ise loop devam eder (model tekrar fix yapar, tekrar rescan eder)
# Eğer count == 0 ise hook auto-emit asama-11-complete
```

Faz 14 (security) için bonus: `asama-14-resolved` ve `asama-14-autofix` mevcut audit'leri **kalır**, ek olarak `scan/rescan` pattern'i devreye girer.

#### Faz 19 (`asama19-impact-review.md`) — list
Faz 10 ile birebir aynı pattern:
```bash
mcl_audit_log "asama-19-items-declared" "model" "count=<N>"
mcl_audit_log "asama-19-item-${idx}-resolved" "model" "decision=<apply|skip|rule>"
```

#### Faz 22 (`asama22-completeness.md`) — self-check
Bu skill **rapor üretmeye devam eder** ama `asama-22-complete` audit'i **model değil hook** emit eder. Skill'den:
```bash
mcl_audit_log asama-22-complete mcl-stop "phases_done=N phases_missing=M"
```
**SİL.** Hook gate-check geçtiğinde otomatik yazar.

### `skills/my-claude-lang.md` — banner ve sürüm
- `🌐 MCL 12.0.0` → `🌐 MCL 13.0.0` (her yerde)
- "v12.0.0" → "v13.0.0"
- Aşama 5+ açıklamasındaki "_was Aşama 8 in v11_, _was Aşama 9 in v11_" parantezleri sil — kanon artık 22.

### `mcl-activate.sh` STATIC_CONTEXT
Line 217'deki büyük prompt bloğu içinde:
- `🌐 MCL 12.0.0` → `🌐 MCL 13.0.0` (3 yerde geçer)
- `MCL 12.0.0 |` askq prefix → `MCL 13.0.0 |`
- "Aşama 5+" cümlesinin parantez listesinde hâlâ "_was Aşama 8 in v11_" var — temizle

---

## Backward compatibility

### Aktif v12.0.0 oturumları
v12 oturumda model `asama-N-complete` emit etmiş ve audit'e yazılmışsa, v13'e upgrade ettiğinde:
- `_mcl_gate_check` o audit'i göremez (gate-spec yeni audit isimlerini bekler)
- Hook complete diyemez → kullanıcı stuck

**Mitigation: legacy emit detection (1 release window):**

`hooks/lib/mcl-gate.sh` içine ekle, her phase check'inde önce çalışır:
```python
# Legacy v12 emit fallback (warn-once, sunset v13.1)
if has_audit(f"asama-{phase}-complete"):
    # Eski format zaten var — geç
    print("complete"); sys.exit(0)
```

Bu fallback sadece v13.0'da olacak. v13.1'de **kaldırılır** ve hard cutover olur. CHANGELOG'da bu açıkça belirtilir.

### v12 state.json
`risk_review_state` ve `quality_review_state` field'ları silinince eski state.json `_mcl_state_valid` kontrolünden geçemez (zaten validation katı). Kullanıcı oturumu açtığında state otomatik default'a sıfırlanır — bu **kabul edilebilir** çünkü v12'den v13'e geçişte zaten pipeline ortasında olamaz (her oturum yeni başlar).

---

## Migration script — `tools/migrate-v12-to-v13.sh`

Sadece skill MD dosyalarını otomatik dönüştürmek için. 22 dosya × manuel düzenleme = hata kaynağı:

```bash
#!/usr/bin/env bash
# v12 → v13 skill MD migrator
# Replaces audit emit patterns in skill files based on gate-spec.json types.
# Idempotent: re-run yields no diff.
set -euo pipefail

SKILLS_DIR="${1:-skills/my-claude-lang}"

# Per-phase find/replace rules
declare -A REPLACEMENTS=(
  # list-gate phases
  ["asama10-risk-review.md|asama-10-complete"]="asama-10-items-declared"
  ["asama19-impact-review.md|asama-19-complete"]="asama-19-items-declared"
  # iterative phases — keep start/end as scan/rescan
  ["asama11-code-review.md|asama-11-start"]="asama-11-scan"
  ["asama11-code-review.md|asama-11-end"]="asama-11-rescan"
  ["asama12-simplify.md|asama-12-start"]="asama-12-scan"
  ["asama12-simplify.md|asama-12-end"]="asama-12-rescan"
  ["asama13-performance.md|asama-13-start"]="asama-13-scan"
  ["asama13-performance.md|asama-13-end"]="asama-13-rescan"
  ["asama14-security.md|asama-14-start"]="asama-14-scan"
  ["asama14-security.md|asama-14-end"]="asama-14-rescan"
)
# (run in dry-run mode first; show diffs; require explicit --apply)
```

**Manuel onay zorunlu** — migrator dry-run default, `--apply` flag ile yazar.

---

## Test stratejisi

### Yeni dosya: `tests/test-v13-gate-spec.sh`

Her gate tipi için synthetic audit log üret + `_mcl_gate_check` döndürdüğü değeri assert et:

```bash
# === single-gate ===
seed_audit "summary-confirm-approve | model |"
assert_eq "$(_mcl_gate_check 1)" "complete"

# === substep-gate (Faz 9) ===
seed_audit "asama-4-ac-count | model | must=2 should=1"
# Henüz hiç triple yok
assert_eq "$(_mcl_gate_check 9)" "incomplete"
# 3 AC × 3 triple = 9 audit
for i in 1 2 3; do
  for tag in red green refactor; do
    seed_audit "asama-9-ac-${i}-${tag} | model |"
  done
done
assert_eq "$(_mcl_gate_check 9)" "complete"

# === list-gate (Faz 10) ===
seed_audit "asama-10-items-declared | model | count=3"
assert_eq "$(_mcl_gate_check 10)" "incomplete"
seed_audit "asama-10-item-1-resolved | model |"
seed_audit "asama-10-item-2-resolved | model |"
assert_eq "$(_mcl_gate_check 10)" "incomplete"
seed_audit "asama-10-item-3-resolved | model |"
assert_eq "$(_mcl_gate_check 10)" "complete"

# === iterative-gate (Faz 11) ===
seed_audit "asama-11-scan | model | count=2"
seed_audit "asama-11-issue-1-fixed | model |"
seed_audit "asama-11-issue-2-fixed | model |"
seed_audit "asama-11-rescan | model | count=1"
assert_eq "$(_mcl_gate_check 11)" "incomplete"
seed_audit "asama-11-issue-3-fixed | model |"
seed_audit "asama-11-rescan | model | count=0"
assert_eq "$(_mcl_gate_check 11)" "complete"

# === self-check (Faz 22) ===
# Faz 1-21 tüm complete'leri seed et
for n in $(seq 1 21); do seed_audit "asama-${n}-complete | stop-auto |"; done
assert_eq "$(_mcl_gate_check 22)" "complete"

# === legacy fallback ===
seed_audit "asama-10-complete | model | h_count=3 m_count=1 resolved=4"  # v12 format
assert_eq "$(_mcl_gate_check 10)" "complete"  # legacy fallback fires
```

### Pre-existing test suite
`bash tests/run-tests.sh` — baseline 270/24/2 ile karşılaştır. v13 değişiklikleri bazı testleri bozar (eski audit isimleri arayan testler). **Beklenen:** ~30-50 test güncelleme gerekir, separate cleanup release'inde.

### Manuel smoke
22 fazlık tam pipeline'ı 1 dilde uçtan uca koş:
1. "bir todo listesi uygulaması yap" → Aşama 1 başla
2. Her gate'te beklenen davranışı doğrula:
   - Model `asama-N-complete` emit etmeyi denerse PreToolUse deny
   - Model doğru per-item / per-section / scan-rescan emit ederse hook auto-complete
   - state.current_phase her gate'te doğru artıyor
3. trace.log'da `phase_transition 1 2 ... 21 22 done` zinciri eksiksiz olsun

---

## Sürüm + banner güncellemeleri

| Dosya | Değişiklik |
|---|---|
| `VERSION` | `12.0.0` → `13.0.0` |
| `README.md` | "MCL 6.2.1" başlık + 7 fazlık akış → "MCL 13.0.0" + 22 fazlık akış (MCL_Pipeline.md'den çek) |
| `README.tr.md` | aynı |
| `MCL_Pipeline.md` | 12 fazlık → 22 fazlık güncelle (skill MD'lerle senkron) |
| `FEATURES.md` | sürüm referansı |
| `CHANGELOG.md` | v13.0.0 entry — universal gate protocol + breaking change bildirimi |
| `hooks/mcl-activate.sh` | `MCL 12.0.0` → `MCL 13.0.0` (3+ yer) |
| `skills/my-claude-lang.md` | `v12.0.0` → `v13.0.0` |
| `skills/my-claude-lang/*.md` | banner ref'leri (varsa) |

---

## Risk ve dikkat noktaları

### 1. AC count Faz 9 zinciri zorunlu
Eğer Aşama 4'te `asama-4-ac-count` audit'i **emit edilmezse**, Faz 9 substep gate çalışamaz → kullanıcı stuck.

**Mitigation:** Aşama 4 skill MD'sinde audit emit'i en yüksek önceliğe yaz, ÖRNEK kod blokları ekle, Aşama 4 PreToolUse'una `asama-4-complete` görüldüğünde `asama-4-ac-count` da var mı kontrolü ekle (yoksa block + warn).

### 2. PreToolUse deny kapsamı
Universal denylist `phase_transition` regex'i çok geniş. Eğer model log mesajına yazıyorsa (örn. error stack içinde "phase_transition 4 5") yanlış pozitif. **Mitigation:** Sadece `mcl_audit_log` veya `mcl_trace_append` tool çağrılarında çalışsın — TOOL_NAME=Bash AND command body içinde.

### 3. Iterative phase sonsuz loop
Model `asama-11-rescan count=5` → fix → rescan=4 → fix → rescan=3 ... eğer model gerçekten fix yapamayıp aynı issue sayısında kalırsa loop sonsuz. **Mitigation:** Hook tarafında 5 rescan üst limiti — 5'e ulaşınca `asama-11-give-up` audit + complete olarak işaretle (warn-only).

### 4. Faz 7 (UI Review) ayrı mı, 6b içinde mi
Skill dosyaları ayrı (`asama7-ui-review.md` var) ama mevcut 6a→6b→6c flow'u skill ortak. Brief 7'yi bağımsız faz kabul ediyor. **Karar gerekli:** ya 7'yi 6'nın 6b'siyle birleştir (21 gerçek gate), ya da 6 ve 7'yi ayır (`asama-6-complete` = 6a+6c, 7 = 6b).

### 5. README v22 update
README hâlâ 6.2.1, açıklama 7 fazlık. Bu **breaking documentation gap** — v13 release notunda README'nin tam yeniden yazıldığı not düşülsün.

### 6. Test suite kırılır
Mevcut testler eski audit isimleri arıyor. v13.0'da ~30-50 test kırılacak. **Karar:** ya v13.0 ile birlikte testleri de güncelle (büyük PR), ya v13.0 ship et + v13.0.1 test cleanup release'i hemen ardından.

---

## Çalışma sırası (Claude Code için)

### Phase A — Hazırlık (read-only)
1. `git status` clean mi kontrol et, değilse durdur
2. `bash tests/run-tests.sh` baseline al, sonuçları kaydet
3. `git checkout -b v13.0-universal-gates` feature branch
4. `git tag pre-v13` rollback tag'i

### Phase B — Yeni dosyalar
5. `skills/my-claude-lang/gate-spec.json` oluştur
6. `hooks/lib/mcl-gate.sh` oluştur, `bash -n` syntax check
7. `tests/test-v13-gate-spec.sh` oluştur ve **önce çalıştır** — gate engine düzgün mü?

### Phase C — Hook entegrasyon
8. `hooks/mcl-pre-tool.sh` universal deny block'unu ekle (line ~895 öncesine)
9. `hooks/mcl-stop.sh` eski Aşama 8/9/10/11/12 progression bloklarını sil (line 864-1055)
10. `hooks/mcl-stop.sh` universal completeness loop'u ekle
11. `hooks/lib/mcl-state.sh` `risk_review_state` ve `quality_review_state` field'larını kaldır, `mcl_get_active_phase()` coarse-bucket mapping'ini sil
12. `bash -n` her dosyada

### Phase D — Skill MD'ler
13. `tools/migrate-v12-to-v13.sh` migrator script'i yaz
14. **Dry-run** çalıştır, diff'leri incele
15. `--apply` ile skill MD'leri dönüştür
16. Faz 4 ve Faz 9 için **manuel ek düzenleme** (AC count, refactor zorunluluğu)
17. `mcl-activate.sh` STATIC_CONTEXT içindeki sürüm referanslarını güncelle

### Phase E — Sürüm + dokümantasyon
18. `VERSION` 12.0.0 → 13.0.0
19. `MCL_Pipeline.md` 22 fazlık şemaya yeniden yaz (skill MD'lerle senkron)
20. `README.md` ve `README.tr.md` tam yeniden yazım — 22 fazlık akış
21. `CHANGELOG.md` v13.0.0 entry: breaking change + universal gate + legacy fallback notice
22. `FEATURES.md` güncellemesi
23. Banner ref'leri (`MCL 13.0.0`) tüm dosyalarda grep ile doğrula

### Phase F — Doğrulama
24. `bash -n hooks/*.sh hooks/lib/*.sh tools/*.sh` tümü temiz
25. `python3 -c "import json; json.load(open('skills/my-claude-lang/gate-spec.json'))"` JSON valid
26. `bash tests/test-v13-gate-spec.sh` — yeni testler geçmeli
27. `bash tests/run-tests.sh` — baseline'dan kırılan testleri listele, beklenen kırılmalar mı kontrol et
28. Manuel smoke: 1 dilde tam 22 fazlık pipeline koş, trace.log'u incele

### Phase G — Commit + tag
29. Atomik commit'ler:
    - `feat(gate): add gate-spec.json and mcl-gate.sh universal engine`
    - `feat(hooks): universal phase completion loop in mcl-stop`
    - `feat(hooks): universal model emit denylist in mcl-pre-tool`
    - `refactor(state): remove v11 risk_review_state and quality_review_state fields`
    - `feat(skills): convert all phase skill MDs to v13 emit protocol`
    - `feat(version): bump to 13.0.0 with banner and doc updates`
    - `test(gate): add test-v13-gate-spec.sh covering all gate types`
30. Push branch, açık PR aç
31. Tüm CI yeşil olunca main'e merge, `v13.0.0` tag

---

## Out of scope (v13.0'da yapılmayacak)

- Test suite v13 audit name güncellemeleri (~30-50 test) → **v13.0.1**
- Legacy v12 emit fallback'in kaldırılması → **v13.1.0**
- README'nin diğer dillere çevrilmesi (TR ve EN dışında) → topluluk
- Faz 7'nin 6b ile resmi birleştirilmesi (eğer karar 21 gate'e dönerse) → ayrı RFC
- `mcl_get_active_phase` helper'ının tamamen kaldırılması → v13.2

---

## Uygulama öncesi onay gereken kararlar

Bu brief'i Claude Code'a vermeden önce sen onayla:

**A. Faz 7 status:** Faz 7 (UI Review) bağımsız top-level mi (skill ayrı dosya), yoksa Aşama 6'nın 6b'si mi (mevcut hook flow)? Brief A varsayar.

**B. LOW severity Faz 10 sayım:** `items-declared count=K`'da LOW severity item'lar dahil mi? Brief default: H+M.

**C. Faz 9 refactor:** Refactor audit zorunlu (her AC için 3'lü) mi, yoksa "değişiklik yoksa atla" mı? Brief: zorunlu (sen söyledin "amaç proje sağlamlığı").

**D. Iterative loop üst limit:** 5 rescan, sonra fail-open + warn → kabul mü?

**E. Test suite cleanup:** v13.0 ile aynı PR'da mı, ayrı v13.0.1 mi? Brief: ayrı.

Onaylar gelince Claude Code'a verebilirsin.
