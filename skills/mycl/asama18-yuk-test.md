---
name: mycl-asama18-yuk-test
description: MyCL Aşama 18 — Yük Testleri (Test Pipeline 4/4). Throughput-hassas yollar için k6/locust/ab. Spec NFR hedefini karşıladığı doğrulanır. Spec'te NFR yoksa atlanır. Çıktı asama-18-end-target-met | asama-18-not-applicable.
---

# Aşama 18 — Yük Testleri (Test Pipeline 4/4)

## Amaç

**Throughput-hassas yollar** için yük testi → spec'teki NFR (latency,
throughput) **hedefini karşıladığı doğrulanır**.

## Spec NFR koşulu

Aşama 4 spec'inde NFR yoksa Aşama 18 atlanır:
```
asama-18-not-applicable reason=no-nfr-in-spec
```

NFR varsa örnekler:
- p99 latency < 50ms
- 1000 req/s throughput
- 5MB memory peak per request

## Tercih edilen araçlar

| Senaryo | Tool |
|---|---|
| HTTP API | k6 (önerilen), wrk, ab, vegeta |
| WebSocket | k6 (k6/ws), Artillery |
| GraphQL | k6 (with GraphQL helpers), easygraphql-load-tester |
| Genel | Locust (Python, dağıtık) |

## Pipeline (4-step)

1. **NFR oku** → spec'ten hedef metric'leri çıkar
2. **Senaryo yaz** → k6 script veya locustfile
3. **Çalıştır** → CI değil, dedicated runner / local
4. **Karşılaştır** → ölçüm vs hedef:
   - Karşılıyor → `asama-18-end-target-met`
   - Karşılamıyor → Aşama 13 performans'a geri dön (regression)

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (audit)

```
asama-18-scan count=K (yük testi senaryo sayısı)
asama-18-scenario-N-passed metric=p99 target=50ms actual=42ms
asama-18-end-target-met
asama-18-not-applicable reason=no-nfr-in-spec
asama-18-target-missed metric=p99 actual=120ms target=50ms
  → Aşama 13 reentry
```

## Anti-pattern

- ❌ NFR uydurma — spec'te yoksa Aşama 18 atlanır, NFR uydurmak
  Aşama 4'ün işidir
- ❌ Tek seferlik run → ortalama yetmez (variance), k6 → 5x run
- ❌ Lokal ölçümü production garantisi sayma — production hardware,
  network, traffic farkı; "lokal hedefi geçti, prod geçer" varsayımı
  yanlış (proxy sinyal kabul; Aşama 19 etki incelemesinde işle)

---

# Phase 18 — Load Tests (Test Pipeline 4/4)

## Goal

Validate spec NFRs (latency, throughput, memory) on
throughput-sensitive paths.

## NFR-gated

`asama-18-not-applicable reason=no-nfr-in-spec` when no NFR in spec.

## Tools

k6 (preferred), wrk/ab (HTTP), Artillery (WS), Locust (Python
distributed).

## Pipeline

Read NFRs → write scenario (k6/locustfile) → run on dedicated runner
→ compare measurement to target. Fail → re-enter Phase 13.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

`asama-18-scan count=K` → `asama-18-scenario-N-passed metric=...
target=... actual=...` → `asama-18-end-target-met` |
`asama-18-not-applicable` | `asama-18-target-missed → Phase 13`.

## Anti-patterns

- Inventing NFRs (Phase 4's job).
- Single-shot run (use 5x for variance).
- Treating local measurement as production guarantee (proxy signal
  only; address in Phase 19 impact review).
