# Laptop Checkout System Design

**Date:** 2026-03-04
**Status:** Approved

## Problem

19 laptops will sometimes be loaned out to students overnight or for multiple days. We need accountability tracking — knowing who has which laptop and when it's due back.

## Decision

Google Form + Google Sheet with a paper backup. No code changes to existing scripts.

## Design

### Google Form: "Hệ Thống Mượn Máy Tính - Vietnam Lab"

Vietnamese-language form with 5 fields:

| # | Field | Vietnamese Label | Type | Values |
|---|-------|-----------------|------|--------|
| 1 | Action | Hành động | Dropdown (required) | Mượn máy / Trả máy |
| 2 | PC Number | Số máy tính | Dropdown (required) | PC-01 through PC-19 |
| 3 | Student ID | Mã học sinh | Short text (required) | STU-XXX format (regex: `STU-\d{3}`) |
| 4 | Student Name | Tên học sinh | Short text (required) | Student's full Vietnamese name |
| 5 | Notes | Ghi chú | Long text (optional) | Return date, condition, reason |

System identifiers (PC-01, STU-XXX) keep their existing format — they are not translated.

### Google Sheet: Two Tabs

**Tab 1: "Phản hồi" (Responses)**

Auto-populated by Google Forms. Each submission = one row with automatic timestamp. This is the permanent audit trail.

| Dấu thời gian | Hành động | Số máy tính | Mã học sinh | Tên học sinh | Ghi chú |
|---------------|-----------|-------------|-------------|-------------|---------|
| 2026-04-15 10:30 | Mượn máy | PC-02 | STU-003 | Nguyễn Văn Minh | Trả thứ Sáu |
| 2026-04-18 08:15 | Trả máy | PC-02 | STU-003 | Nguyễn Văn Minh | |

**Tab 2: "Bảng theo dõi" (Dashboard)**

19 rows (one per PC), formula-driven, showing current state at a glance:

| Máy tính | Trạng thái | Mã học sinh | Tên học sinh | Ngày mượn | Ghi chú |
|----------|-----------|-------------|-------------|-----------|---------|
| PC-01 | Sẵn sàng | — | — | — | — |
| PC-02 | Đang mượn | STU-003 | Nguyễn Văn Minh | 15/04/2026 | Trả thứ Sáu |
| PC-03 | Sẵn sàng | — | — | — | — |

Dashboard formulas scan the Responses tab for the most recent entry per PC:
- Last action = "Mượn máy" → status = **Đang mượn** (checked out), show student info
- Last action = "Trả máy" → status = **Sẵn sàng** (available)

### Paper Backup

A printed grid taped to the lab wall with columns: Ngày (Date), Số máy (PC#), Mã HS (Student ID), Tên HS (Name), Mượn/Trả (Out/In), Ghi chú (Notes).

Used when internet is down. Staff enters paper entries into the Google Form later when connectivity returns.

### Student Name Mapping

The form builds a name-to-STU-number roster organically over time. No need to know student names upfront when preparing USBs — the `4-Prepare-Student-USB.ps1` script stays unchanged (STU-XXX only). Names are captured at first checkout.

## What Changes

- **New file:** `Documentation/Laptop-Checkout-System.md` — setup guide with form creation steps, dashboard formulas, and printable paper template

## What Doesn't Change

- No modifications to any PowerShell scripts
- No changes to USB preparation or backup workflows
- No changes to Configure-Laptop.ps1 or deployment pipeline
- No new scheduled tasks or software installs

## Constraints

- **Operator:** Sighted lab staff only (no screen-reader accessibility required for the form)
- **Internet:** Form requires internet to submit; paper backup covers offline periods
- **Language:** All form and sheet labels in Vietnamese; system identifiers (PC-XX, STU-XXX) unchanged
- **Remote visibility:** Not required — local staff use only (Andrew can ask staff if needed)

## Alternatives Considered

1. **PowerShell script on a lab PC** — rejected: more friction than a phone form, tied to one machine, more code to maintain
2. **Paper log only** — rejected: no digital record, not searchable, no dashboard view
