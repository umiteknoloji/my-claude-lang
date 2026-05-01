# Root Cause Discipline — Decisions

Summary of all decisions related to root cause identification and intervention in MCL.
This document is the reference for both CLAUDE.md (devtime) and Phase 4 Root Cause Chain (runtime).

---

## 1. Core principle

When solving a problem, do not stay at the surface. Ask "Why is this the case?"
When an answer comes, ask again: "And why is that?" If the root cause you found
is not sufficient, look for its root cause. Go all the way down.
Sometimes fixing the deepest cause resolves the entire network.

This applies both during development (you + Claude Code) and in the developer's
projects (Phase 4 Root Cause Chain). Skipping it is forbidden — same standing
as anti-sycophancy.

---

## 2. How the chain advances

A single-level cause search is not enough. A multi-level chain is built:

- The first cause is identified
- It is queried: "Does this cause have a deeper root cause?"
- The descent continues until the structural bottom is reached
- Each ring is verified before moving to the next

---

## 3. Per-ring validation — three checks, in order

Before moving from one ring to the next, three checks are applied **in order**.
Not in parallel. The next check does not begin until the previous one passes.

### 3.1 Visible process
What steps did you follow to arrive at this ring? Write them out explicitly —
do not leave the reasoning hidden. The chain of thought must be visible.

### 3.2 Removal test
"If this cause were eliminated, would the problem in the parent ring be resolved?"
If the answer is not "yes", the cause is wrong — backtrack and try a different path.

### 3.3 Falsification
"If this cause is correct, the following should also be observable."
Verify the expectation. If it is not observed, the cause is wrong — backtrack.

**Critical constraint:** The X in "X should be observable" must be
**verifiable**: visible in code, logs, behavior, or files. An abstract
"X should be the case" is not sufficient. If X cannot be checked,
the falsification check is invalid and the ring is considered suspect.

---

## 4. Ring transition result

Based on the three checks:

- **All three pass** → the chain can descend one level deeper
- **One fails** → either we are at the wrong ring (backtrack and try a
  different path), or this is already the root cause (chain ends here)

Early-catch principle: these three checks are applied **at every ring, not
only at the end of the chain**. A single check at the end catches deviations
late; per-ring checks catch them early.

---

## 5. Edge case — when the chain gets stuck

In practice the chain ends in 2–3 rings. But occasionally a serious difficulty
arises: the chain keeps going without clarifying, alternative causes are
exhausted, the investigation moves outside the controllable scope.

In this situation MCL tells the developer **clearly, plainly, briefly**.
It does not produce abstract solutions; it does not hallucinate. Example:
"The root cause was traced to this point; beyond that it is unclear because of X."

No over-engineered exit conditions or fallback protocols are constructed.
When stuck, transparency is sufficient.

---

## 6. Intervention point selection — the most critical rule

When the root cause is found at the end of the chain, **do not change it immediately**.

First estimate all effects of the intervention — following Phase 4 (impact lens) logic:
- Files that import the changed cause
- Shared utility behavior changes
- API/contract breakage
- Schema/migration effects
- Downstream consumers
- Build/toolchain/dependency changes

### Rule: zero-side-effect ring

If **even a single** effect touches something else, that ring is not the
intervention point. Move up one ring and estimate its effects. Keep moving
up until you reach a ring that produces no side effects on other parts of
the system.

**Intervention point:** the ring closest to the root cause that produces
zero side effects. That is the clean place to work.

### Rationale

One piece of work must not affect another. The root cause is not always
the correct intervention point — fixing the deepest cause can produce
system-breaking side effects. Phase 4 (impact lens)'s philosophy (side-effect estimation)
applies to the root cause chain as well; they are the same discipline.

---

## 7. Root cause + fix report

When the intervention point is determined, both the **root cause** and the
**proposed fix** are reported. The root cause alone is not sufficient —
the developer says "understood" but no correction is applied.

The fix requires a separate verification: "If this fix is applied, does
the root cause disappear?" — a yes/no check.

Both are presented together as a Phase 4 risk item:
- Not the surface symptom, but the deepest structural cause (or the selected
  intervention ring)
- The proposed fix
- The fix verification result

---

## 8. Scope

Both **devtime** (MCL development between you and Claude Code) and **runtime**
(Phase 4 Root Cause Chain — in the developer's projects) apply this discipline.

Skipping it is forbidden. Same standing as anti-sycophancy as a core mechanism.

---

## 9. Summary — single paragraph

When a problem is found, a root cause chain is built. Each ring passes three
checks (visible process → removal test → falsification); in order, not in
parallel. If all three pass, descend deeper; if one fails, backtrack.
If the chain gets stuck, tell the developer plainly — do not hallucinate.
When the root cause is found, do not change it immediately — estimate its
effects. If even one effect touches something else, move up one ring.
Intervention point: the ring that produces zero side effects. Then root
cause and fix are reported together.
