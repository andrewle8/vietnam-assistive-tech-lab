# Audit Gap Log — 2026-04-18

Produced during Phase 1 of `2026-04-18-nvda-audit-blindfold-test.md`. Consumed by Phase 2 to generate per-gap fix tasks.

---

## Category (a) — Mismatch (guide says X, reality is Y)

*(Populated during Tasks 1–3. Empty entries = no mismatch found in that task.)*

- **Task 1 findings:** None. Guide claims 16 desktop shortcuts; all 16 present (15 on Public Desktop, 1 — NVDA — on Student Desktop). Split across two desktop folders is transparent to the user since Windows merges them visually.

- **Task 2 finding — NVDA voice drift between live and repo:** Live `C:\Users\Student\AppData\Roaming\nvda\nvda.ini` has `voice = HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\Thanh Vi`. Repo `Config/nvda-config/nvda.ini` still has `voice = HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\MSTTS_V110_viVN_An` (Microsoft An). A fresh laptop bootstrap would get Microsoft An, not Thanh Vi — violates test-bench rule. All other keys match between live and repo.
  - **Fix location:** `Config/nvda-config/nvda.ini` — update voice field to match live.
  - **Caveat:** This fix is conditional on Task #11 voice decision (handover). If Thanh Vi is the chosen voice, sync repo to live. If a different voice wins, set repo + live to that voice together.
  - **Status:** 🔧 Queued for Task 5.

---

## Category (b) — Silent implementation (reality has Z, guide silent)

*(Populated during Tasks 1–3.)*

- **Task 1 findings:** None from desktop inventory.

- **Task 2 finding — LabVolumeReset in startup, not mentioned in guide:** `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\LabVolumeReset.lnk` is a silent background startup item (likely resets volume to 70% each login per handover / `Configure-Laptop.ps1` Step 9). Students never see or interact with it.
  - **Fix location:** No fix needed — this is an implementation detail below the student's awareness. Guide silence is correct. Logging for completeness.
  - **Status:** ✅ No action.

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
