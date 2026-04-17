# Audit Gap Log — 2026-04-18

Produced during Phase 1 of `2026-04-18-nvda-audit-blindfold-test.md`. Consumed by Phase 2 to generate per-gap fix tasks.

---

## Category (a) — Mismatch (guide says X, reality is Y)

*(Populated during Tasks 1–3. Empty entries = no mismatch found in that task.)*

- **Task 1 findings:** None. Guide claims 16 desktop shortcuts; all 16 present (15 on Public Desktop, 1 — NVDA — on Student Desktop). Split across two desktop folders is transparent to the user since Windows merges them visually.

---

## Category (b) — Silent implementation (reality has Z, guide silent)

*(Populated during Tasks 1–3.)*

- **Task 1 findings:** None from desktop inventory.

---

## Category (c) — Missing recovery / error path

*(Populated during Tasks 1–3.)*

---

## Already-known gaps to fix regardless

- **Tab-recovery on desktop focus** — After `Win+D`, first-letter jump only works when keyboard focus is on the Desktop ListView. If a letter does nothing, press Tab once — NVDA should announce "Desktop, list". Press Tab again if it lands on taskbar/tray. Alternatively any arrow key forces focus onto the icon grid. Type-ahead buffer resets after ~1 second, so press letters quickly or wait 2 seconds between jumps.
  - **Fix location:** Desktop Navigation section of both `docs/User-Guide.md` and `docs/Huong-Dan-Su-Dung.md` (plus the `.txt` mirrors).
  - **Status:** 🔧 Queued for Task 4.

---

## Deployment-readiness notes (not audit gaps, tracked separately)

- **NVDA voice decision open (handover Task #11).** `Config/nvda-config/nvda.ini` currently specifies Microsoft An (`MSTTS_V110_viVN_An`), but handover state says live NVDA is using Thanh Vi (Sao Mai). Either repo config is stale vs. live, or handover wording was imprecise. Task 2 will confirm. This is a decision/cleanup item, not a guide-vs-reality mismatch a blind student would hit.
