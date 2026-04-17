# NVDA + Student-Guide Audit & Blindfold Test — Design

**Date:** 2026-04-18
**Machine:** PC-01 (test bench)
**Goal:** Verify a blind student can complete every documented task end-to-end, then hand off to the remaining deployment-readiness steps for laptops #2–19.

---

## Context

PC-01 is the test-bench laptop. Its student-facing experience is documented in `docs/User-Guide.md` (EN) and `docs/Huong-Dan-Su-Dung.md` (VN). The guides describe how a blind student uses NVDA, the desktop, and the installed apps, all driven by deployment scripts in `Scripts/`.

Before rolling the build to 18 more laptops, we need to confirm three things:

1. The guides accurately describe what the laptop does.
2. The laptop actually does what the guides describe.
3. A blind user can complete the guide's tasks without getting stuck.

Known gap already identified: the "press first letter to jump to a desktop shortcut" flow depends on keyboard focus being on the desktop ListView, which is not guaranteed after `Win+D`. The Tab-recovery step is not documented. Similar gaps probably exist elsewhere.

---

## Scope

### In scope

**Tier 1 — must test:**

- Boot / login flow
- Desktop navigation (arrow keys, first-letter jump, Tab-to-list recovery)
- Word: open, type Vietnamese via UniKey, save to USB
- Readmate: open, pick a book, read
- Firefox: URL bar, caret browsing, read a page
- USB: insert, find in Explorer, safely eject

**Tier 2 — quick verification:**

- Kiwix (offline Wikipedia lookup)
- VLC (play audio)
- SumatraPDF (open a PDF)
- GoldenDict (word lookup)
- Calculator
- Language toggle (Ctrl+Shift)
- NVDA restore shortcut

### Out of scope

- Rewriting guide structure (the guides are already well-organized)
- Adding new applications
- **Tier 3 apps** (Audacity, PowerPoint, Excel, Sao Mai Typing) — launch-check only if Tier 1 + 2 finish with time to spare
- Turning the tester into a blind power user (role here is proxy tester, not student)

---

## Approach — Hybrid pre-audit + real-time blindfold test

Chosen over two alternatives:

- **Pre-audit then test** (too slow, may fix non-issues)
- **Test-first** (misses issues that don't surface in one session; rework interrupts flow)

The hybrid spends ~1 hour closing known-obvious gaps on paper before using scarce blindfold-test time on real discovery.

---

## Phases

### Phase 1 — Pre-audit (~1 hr, solo)

Walk both guides step-by-step. For each instruction, cross-check against:

- `Scripts/Configure-Laptop.ps1` (shortcut list, registry writes, file associations)
- `Scripts/1-Install-All.ps1` (installed apps, desktop shortcuts created here)
- `Scripts/3-Configure-NVDA.ps1` (NVDA auto-start, UniKey, NVDA config copy)
- `Config/nvda-config/nvda.ini` (voice, language, keyboard layout)
- Live desktop state (actual shortcut names and ordering)

Produce a gap list with three categories:

- **(a) Mismatch** — guide says X, reality is Y
- **(b) Silent implementation** — reality has Z, guide doesn't mention it
- **(c) Missing recovery** — happy path correct, but no fallback/error guidance

**Deliverable:** inline gap list in chat, no separate file.

### Phase 2 — Fix (~1 hr, scales with gap count, solo)

For each gap, decide fix location: doc (always update **both** VN and EN), script, or config. Per CLAUDE.md test-bench rule, any machine-state change must be captured in deploy scripts — no manual-only edits.

One small commit per fix, conventional message. Known inclusion: Tab-recovery step for desktop focus, added to the Desktop Navigation section of both guides.

### Phase 3 — Blindfold test (~3–4 hr Tier 1, +1–2 hr Tier 2, together)

**Setup:** tester blindfolded, headphones on, NVDA running, laptop in normal post-boot state. Facilitator has both guides open on a second screen plus a running issue log.

**Protocol per task:**

1. Tester follows the guide step-by-step (read via NVDA or from memory)
2. Tester narrates what they hear and what they are trying to do
3. If stuck more than 30 seconds, facilitator logs friction and guides recovery — do **not** abandon the task, because we want downstream signal
4. Tag each issue: **blocker** (cannot proceed), **confusion** (recovered but guide is misleading), **gap** (guide silent on what to do)

**Task order:** Tier 1 in the order listed above, then Tier 2.

### Phase 4 — Triage + optional re-test (~1–2 hr, together)

Walk the issue log. Small fixes applied now, larger ones queued. If blockers or more than 5 gaps surface, re-test only the affected sections (not the whole guide). Otherwise: done.

---

## Stopping criteria

- All Tier 1 tasks completable blindfolded with no blockers
- Every discovered gap either fixed or explicitly deferred with reason in the log
- VN and EN guides in sync
- Test-bench rule honored: every machine change reflected in deploy scripts

---

## Deployment-readiness path (after this spec completes)

This spec does **not** by itself ship the build to laptops #2–19. Sequential items that follow:

1. **Voice decision (Task #11 in handover)** — finalize NVDA voice: Thanh Vi vs Vi-Vu vs Minh Du / Mai Dung / Thu An / Microsoft An
2. **Voice cleanup (Task #12)** — if Vi-Vu is rejected, uninstall the 5 staged MSIs (Vi-Vu + RHVoice + 4 data packages) and remove from deploy scripts
3. **Commit the prior session's pending edits** — ~20 modified files visible in `git status` at session start
4. **Sync USB D: and E:** to match repo + installer set (per CLAUDE.md USB rule)
5. **Fresh-laptop bootstrap dry-run** — reset or blank laptop, run `Scripts/Bootstrap-Laptop.ps1`, verify resulting state matches PC-01. This is the ultimate test-bench-rule validation; our blindfold test verifies PC-01's current state but not that scripts reproduce it on a clean machine.

Only after item 5 passes is the build deployment-ready for laptops #2–19.

---

## Risks & notes

- **Tester fatigue:** blindfold + narration is cognitively heavy. Break every 60–90 min.
- **Focus recovery is the likely theme:** most screen-reader friction on Windows comes from keyboard focus drifting off expected controls. Expect several gaps of type (c).
- **VN/EN drift:** fixes applied to one guide and not the other will cause confusion for the Vietnamese teacher who shipped the laptops. Every doc fix must touch both files.
- **Git commit style:** per CLAUDE.md, commits are authored as the developer; no Co-Authored-By lines, no Claude mentions.
