# NVDA Audit & Blindfold Test — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking. **Phases 3 and 4 are interactive and cannot be executed by a subagent — they require the human tester blindfolded with the facilitator co-present. Stop at the Phase 2 → Phase 3 boundary and hand back to the main session.**

**Goal:** Close documentation/implementation gaps on PC-01, then verify a blind student can complete every documented task end-to-end, so the build is ready for deployment to laptops #2–19.

**Architecture:** Four phases. Phase 1 is a solo paper audit producing a gap list. Phase 2 applies fixes (known + discovered) to docs/scripts/config, with both language versions kept in sync. Phase 3 is a real-time blindfold test driven by the user, facilitator logs issues. Phase 4 is collaborative triage and optional re-test of affected sections only.

**Tech Stack:** PowerShell deploy scripts, NVDA `.ini` config, Markdown guides (EN + VN), git for every fix.

**Spec:** `docs/superpowers/specs/2026-04-18-nvda-audit-blindfold-test-design.md`

---

## File Map

**Likely to be modified (discovered in Phase 1):**
- `docs/User-Guide.md` — English student guide
- `docs/Huong-Dan-Su-Dung.md` — Vietnamese student guide
- `docs/User-Guide.txt` — text mirror of EN guide
- `docs/Huong-Dan-Su-Dung.txt` — text mirror of VN guide
- `Scripts/Configure-Laptop.ps1` — desktop shortcut list, registry writes
- `Scripts/1-Install-All.ps1` — installer flow, Kiwix/GoldenDict shortcut creation
- `Scripts/3-Configure-NVDA.ps1` — NVDA auto-start, UniKey, config copy
- `Config/nvda-config/nvda.ini` — NVDA voice/layout/language

**Created this plan:**
- `docs/superpowers/plans/2026-04-18-nvda-audit-blindfold-test-gaplog.md` — written during Phase 1, consumed by Phase 2 (the audit deliverable)

---

## Phase 1 — Pre-audit (~1 hr, solo, executable)

### Task 1: Inventory live desktop state vs guide

**Files:**
- Read: `docs/User-Guide.md`, `docs/Huong-Dan-Su-Dung.md`
- Read: live desktop directory `C:\Users\Public\Desktop` and `C:\Users\Student\Desktop`
- Write: `docs/superpowers/plans/2026-04-18-nvda-audit-blindfold-test-gaplog.md`

- [ ] **Step 1: List the apps section of both guides**

Run via Grep on `docs/User-Guide.md` lines 114-132 (Desktop app list) and confirm same list appears in `Huong-Dan-Su-Dung.md` lines 114-132.

Expected outcome: a canonical list of 15–20 shortcut names the guide claims are on the desktop.

- [ ] **Step 2: List actual shortcuts on the live desktop**

Run:
```bash
ls "C:/Users/Public/Desktop" "C:/Users/Student/Desktop" 2>/dev/null
```

Expected: `.lnk` files. Capture the set.

- [ ] **Step 3: Diff the two sets into the gaplog**

Create `docs/superpowers/plans/2026-04-18-nvda-audit-blindfold-test-gaplog.md` with header:

```markdown
# Audit Gap Log — 2026-04-18

## Category (a) — Mismatch (guide says X, reality is Y)

## Category (b) — Silent implementation (reality has Z, guide silent)

## Category (c) — Missing recovery / error path

## Already-known gaps to fix regardless

- **Tab-recovery on desktop focus** — after Win+D, first-letter jump only works when focus is on the Desktop ListView. Press Tab once (NVDA announces "Desktop, list") to recover focus. Not documented in either guide. Fix location: Desktop Navigation section of both guides.
```

For each shortcut missing from desktop but in the guide → add under (a). For each shortcut on desktop but missing from the guide → add under (b).

- [ ] **Step 4: Commit the gaplog skeleton**

```bash
git add docs/superpowers/plans/2026-04-18-nvda-audit-blindfold-test-gaplog.md
git commit -m "Add audit gap log skeleton with known gaps"
```

### Task 2: Cross-check NVDA / UniKey / voice claims

**Files:**
- Read: `Config/nvda-config/nvda.ini`
- Read: `Scripts/3-Configure-NVDA.ps1`
- Append to: `docs/superpowers/plans/2026-04-18-nvda-audit-blindfold-test-gaplog.md`

- [ ] **Step 1: Verify guide claims about NVDA behaviour**

Guide (EN line 137) claims: *"keyboard layout: Laptop. NVDA key = Insert (right Insert or Insert on numpad)."*

Check `Config/nvda-config/nvda.ini`:
- `keyboardLayout = laptop` ✓ expected
- `NVDAModifierKeys = 6` → decode: 2=numpad Insert, 4=extended Insert, 1=CapsLock. `6` = `2|4` = both Inserts, no CapsLock.

Guide says CapsLock is not an NVDA key, which matches `6`. But the 2026-04-18 handover state mentions "Insert+CapsLock as NVDA keys." If CapsLock should be added: `NVDAModifierKeys = 7`. Log as category (a) if a mismatch, else skip.

- [ ] **Step 2: Verify guide claims about Vietnamese voice**

Guide does not specify which voice; handover says "Thanh Vi (Sao Mai, Southern)". `nvda.ini` says `voice = HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\MSTTS_V110_viVN_An` — that's Microsoft An, not Thanh Vi.

This is an active-decision item (Task #11 in handover), not an audit gap. Log as a **deployment-readiness note**, not a (a)/(b)/(c) gap.

- [ ] **Step 3: Verify UniKey auto-start + VN-default behaviour**

Guide (EN line 174): *"UniKey auto-runs on startup. Default input method is Telex. Toggle EN/VN with Ctrl+Shift."*

Check `Scripts/3-Configure-NVDA.ps1:179-213` creates a startup shortcut for UniKey. Confirm it exists at `C:/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/UniKey.lnk`. If missing, log as (a).

- [ ] **Step 4: Verify NVDA restore script exists**

Guide (EN line 222-230) tells students to use "Khoi Phuc NVDA" / "Restore NVDA" shortcut. Check it exists on the live desktop and points to `C:\LabTools\restore-nvda.ps1`. If missing or broken, log as (a).

- [ ] **Step 5: Commit the appended findings**

```bash
git add docs/superpowers/plans/2026-04-18-nvda-audit-blindfold-test-gaplog.md
git commit -m "Add NVDA/UniKey/voice audit findings to gap log"
```

### Task 3: Walk the guide procedurally end-to-end

**Files:**
- Read: `docs/User-Guide.md` (EN is canonical for audit)
- Append to: gap log

- [ ] **Step 1: Section-by-section walkthrough**

For each heading in the EN guide, mentally trace the steps and mark any of the following as gaps:
- References to keys/shortcuts that do not exist (category a)
- References to apps that are not actually installed / actually on desktop (category a)
- Flows that assume focus is on a specific control without saying how to recover if it isn't (category c)
- Features that exist on the laptop but are never mentioned (category b — e.g., Magnifier Win+Plus, High Contrast shortcut)

Sections to walk: Bat Dau / Getting Started, Cac Cong Ket Noi / Ports, Tai Nghe / Headphones, USB Cua Ban / Your USB, Dieu Huong Tren Desktop / Desktop Navigation, Phim Tat NVDA / NVDA Shortcuts, Go Tieng Viet / Vietnamese Input, Phim Tat Windows / Windows Shortcuts, Doc Sach Giao Khoa / Textbooks, Khi NVDA Bi Loi / NVDA Recovery, Luu Y / Notes.

- [ ] **Step 2: Log each gap under the right category**

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-04-18-nvda-audit-blindfold-test-gaplog.md
git commit -m "Complete procedural walkthrough of student guide"
```

---

## Phase 2 — Apply fixes (scales with gap count, solo, executable)

### Task 4: Add Tab-recovery step to Desktop Navigation (known fix)

**Files:**
- Modify: `docs/User-Guide.md` (Desktop Navigation section, around line 104-112)
- Modify: `docs/Huong-Dan-Su-Dung.md` (Dieu Huong Tren Desktop section, around line 104-112)
- Modify: `docs/User-Guide.txt` and `docs/Huong-Dan-Su-Dung.txt` — mirror the same change

- [ ] **Step 1: Add the recovery paragraph to EN guide**

After the "Tip: Press the first letter..." paragraph in `docs/User-Guide.md`, insert:

```markdown
If pressing a letter does nothing, keyboard focus has drifted off the desktop. Press Tab once — NVDA should announce "Desktop, list". Now first-letter jump works. If Tab lands on the taskbar or system tray, press Tab again to cycle into the desktop list. Alternatively, press any arrow key to force focus onto the icon grid.

Between jumps, press the next letter within about one second, or wait two seconds for the type-ahead buffer to reset. Pausing mid-word (e.g., "F" then pause then "W") can make Windows interpret it as the prefix "FW" and jump to nothing.
```

- [ ] **Step 2: Add the Vietnamese equivalent to VN guide**

After the corresponding "Meo: Nhan chu cai dau..." paragraph in `docs/Huong-Dan-Su-Dung.md`, insert:

```markdown
Neu nhan chu cai khong co phan ung, tieu diem ban phim da roi khoi Desktop. Nhan phim Tab mot lan — NVDA se thong bao "Desktop, danh sach". Bay gio nhan chu cai de nhay se hoat dong. Neu Tab chuyen den thanh tac vu hoac khay he thong, nhan Tab them mot lan de quay lai danh sach Desktop. Hoac nhan mot phim mui ten bat ky de ep tieu dieu len bieu tuong.

Giua cac lan nhay, nhan chu cai tiep theo trong vong khoang mot giay, hoac doi hai giay de bo dem "go chu" reset. Tam dung giua hai chu (vi du: "F" roi tam dung roi "W") co the khien Windows hieu la tien to "FW" va khong tim thay gi.
```

- [ ] **Step 3: Mirror both edits into the `.txt` files**

Re-apply the same paragraphs in the matching sections of `docs/User-Guide.txt` and `docs/Huong-Dan-Su-Dung.txt`.

- [ ] **Step 4: Verify all four files are in sync**

```bash
grep -c "first-letter jump" docs/User-Guide.md docs/User-Guide.txt
grep -c "nhay se hoat dong" docs/Huong-Dan-Su-Dung.md docs/Huong-Dan-Su-Dung.txt
```

Expected: 1 in each file.

- [ ] **Step 5: Commit**

```bash
git add docs/User-Guide.md docs/Huong-Dan-Su-Dung.md docs/User-Guide.txt docs/Huong-Dan-Su-Dung.txt
git commit -m "Document Tab-recovery step for desktop focus (VN + EN)"
```

### Task 5–N: Apply each discovered gap-fix (one commit per fix)

One task per entry in the gap log. For each:

- [ ] **Step 1: Decide fix location**

Doc-only (both VN + EN), script-only, config-only, or combination. Record decision in the gap log next to the entry.

- [ ] **Step 2: Apply the fix**

If doc: update `.md` **and** `.txt` in both languages.
If script: update the script file; then re-run the relevant portion on PC-01 to make the live state match (test-bench rule — no manual-only changes). Capture what command was run.
If config: update the file under `Config/`; copy to the live target path; re-apply.

- [ ] **Step 3: Verify the fix**

For doc changes: re-read the modified section, confirm it reads naturally for a screen reader (no complex markdown, short sentences).
For script/config changes: confirm live state now matches what the script would produce on a blank laptop.

- [ ] **Step 4: Commit**

```bash
git add <changed-files>
git commit -m "<conventional message describing the fix>"
```

### Task N+1: Phase 2 sign-off

- [ ] **Step 1: Verify gap log is fully resolved**

Every entry in the gap log is either marked ✅ fixed, or explicitly marked deferred with a one-line reason (e.g., "defer: out-of-scope Tier 3 app").

- [ ] **Step 2: Verify VN/EN parity**

```bash
diff <(grep -c "^##" docs/User-Guide.md) <(grep -c "^##" docs/Huong-Dan-Su-Dung.md)
```

Expected: same section count.

- [ ] **Step 3: Commit the resolved gap log**

```bash
git add docs/superpowers/plans/2026-04-18-nvda-audit-blindfold-test-gaplog.md
git commit -m "Finalize audit gap log — all entries resolved or deferred"
```

---

## Phase 3 — Blindfold test (interactive, co-present, NOT auto-executable)

> **STOP for agentic workers:** Do not proceed past this line. Return control to the main session. The human tester must perform these steps blindfolded, in real time, with the facilitator co-present.

### Protocol

**Setup:**
- Tester blindfolded, seated at PC-01, headphones on
- NVDA running, laptop freshly booted (no open apps)
- Facilitator has both guides open on a second screen and a running issue log

**Per-task protocol:**
1. Tester follows the guide step-by-step (from memory or NVDA-read)
2. Tester narrates only when something surprises them (wrong announcement, unexpected focus, silence)
3. If stuck, tester says "next" and facilitator logs a **blocker** without guided recovery
4. Otherwise, each friction point → one-line log entry tagged **blocker** / **confusion** / **gap**

**Issue log file:** `docs/superpowers/plans/2026-04-18-nvda-audit-blindfold-test-sessionlog.md` (facilitator creates live during session)

### Tier 1 — must complete

- [ ] T1-A: Boot → login → hear NVDA welcome → confirm landed on Desktop
- [ ] T1-B: Desktop navigation — arrow keys, first-letter jump (F=Firefox, W=Word, R=Readmate), Tab-recovery after drift
- [ ] T1-C: Word — open, type a Vietnamese sentence via UniKey Telex, save to USB
- [ ] T1-D: Readmate — open, select a book, read a page, close
- [ ] T1-E: Firefox — open, focus URL bar (Ctrl+L), navigate to a page, use caret browsing to read
- [ ] T1-F: USB — insert, find drive in Explorer, safely eject (Shift+F10 → Eject)

### Tier 2 — quick verification (launch + one core action each)

- [ ] T2-A: Kiwix — open, search a Wikipedia article, read first paragraph
- [ ] T2-B: VLC — play a test audio file, pause, quit
- [ ] T2-C: SumatraPDF — open a PDF, navigate one page
- [ ] T2-D: GoldenDict — look up one English word, hear the Vietnamese definition
- [ ] T2-E: Calculator — open, perform 2+2, hear result
- [ ] T2-F: Language toggle — press Ctrl+Shift, hear UniKey mode switch
- [ ] T2-G: NVDA restore — navigate to Khoi Phuc NVDA shortcut, trigger it, confirm NVDA reloads

### Tier 3 — only if time remains, launch-check only

- [ ] T3-A: Audacity launches and announces main window
- [ ] T3-B: PowerPoint launches
- [ ] T3-C: Excel launches
- [ ] T3-D: Sao Mai Typing Tutor launches

---

## Phase 4 — Triage + optional re-test (interactive)

- [ ] **Step 1: Walk the session log together**

Review every logged issue. For each, decide:
- **Fix now** (small, clear, low-risk)
- **Queue** (larger, needs its own plan/session)
- **Accept / won't fix** (edge case that does not block deployment)

- [ ] **Step 2: Apply fix-now items using the Phase 2 task template**

Same pattern as Tasks 5–N above: one commit per fix, doc changes touch both VN + EN `.md` and `.txt`.

- [ ] **Step 3: Decide on re-test**

If any blocker was fixed, re-test only the affected task(s) from Tier 1/2 (not the whole guide). If all fixes were confusion/gap tier, skip re-test.

- [ ] **Step 4: Mark the session log complete**

Append a final summary block to the session log:

```markdown
## Summary
- Total issues: N
- Blockers: X (all fixed / N deferred)
- Confusion: Y
- Gaps: Z
- Re-test performed: yes / no, scope: <tasks>
- Outcome: stopping criteria met / not met
```

- [ ] **Step 5: Commit the final session log**

```bash
git add docs/superpowers/plans/2026-04-18-nvda-audit-blindfold-test-sessionlog.md
git commit -m "Finalize blindfold test session log"
```

---

## Stopping criteria (copied from spec, for reference during execution)

- All Tier 1 tasks completable blindfolded with no blockers
- Every discovered gap either fixed or explicitly deferred with reason
- VN + EN guides in sync
- Test-bench rule honored: every machine change reflected in deploy scripts

## After this plan completes

Not part of this plan, but required before deployment to laptops #2–19 (per spec):

1. Voice decision (handover Task #11)
2. Voice cleanup (handover Task #12)
3. Commit the pending ~20 modified files from the prior session
4. Sync USB D: and E: to match repo + installers
5. Fresh-laptop bootstrap dry-run to verify scripts reproduce PC-01 state on a blank machine
