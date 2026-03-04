# Laptop Checkout System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a setup guide for a Google Form + Sheet laptop checkout system with Vietnamese labels, dashboard formulas, and a printable paper backup template.

**Architecture:** Single documentation file (`Documentation/Laptop-Checkout-System.md`) containing step-by-step Google Form/Sheet setup instructions, copy-paste-ready dashboard formulas, and an ASCII paper log template. No code changes.

**Tech Stack:** Google Forms, Google Sheets (FILTER/SORT/IF formulas), Markdown documentation

---

### Task 1: Create the Laptop Checkout System documentation file

**Files:**
- Create: `Documentation/Laptop-Checkout-System.md`

**Step 1: Write the documentation file**

The file has 5 sections:

**Section 1 — Overview** (Vietnamese + English)
- Purpose: track laptop loans for accountability
- Components: Google Form, Google Sheet with dashboard, paper backup

**Section 2 — Google Form Setup** (step-by-step with screenshots description)

Exact steps to create the form in Google Forms:

1. Go to forms.google.com, create new form
2. Set form title: `Hệ Thống Mượn Máy Tính - Vietnam Lab`
3. Set form description: `Biểu mẫu theo dõi mượn/trả máy tính xách tay`
4. Add field 1 — "Hành động": Dropdown, required, options: `Mượn máy`, `Trả máy`
5. Add field 2 — "Số máy tính": Dropdown, required, options: `PC-01` through `PC-19` (all 19 listed)
6. Add field 3 — "Mã học sinh": Short answer, required, response validation regex: `STU-\d{3}`, error text: `Vui lòng nhập đúng định dạng STU-XXX (ví dụ: STU-001)`
7. Add field 4 — "Tên học sinh": Short answer, required
8. Add field 5 — "Ghi chú": Paragraph, optional
9. Link to Google Sheet (Responses tab → green Sheet icon)

**Section 3 — Dashboard Tab Setup** (step-by-step)

1. In the linked Google Sheet, rename the auto-created tab to `Phản hồi`
2. Note the column layout: A=Timestamp, B=Hành động, C=Số máy tính, D=Mã học sinh, E=Tên học sinh, F=Ghi chú
3. Create new tab called `Bảng theo dõi`
4. Row 1 headers: `Máy tính | Trạng thái | Mã học sinh | Tên học sinh | Ngày mượn | Ghi chú`
5. Column A rows 2-20: `PC-01` through `PC-19` (hardcoded)
6. Column B (Trạng thái) formula for cell B2, drag down to B20:

```
=IF(COUNTIF('Phản hồi'!C:C,A2)=0,"Sẵn sàng",IF(INDEX(SORT(FILTER('Phản hồi'!B:B,'Phản hồi'!C:C=A2),FILTER('Phản hồi'!A:A,'Phản hồi'!C:C=A2),FALSE),1,1)="Mượn máy","Đang mượn","Sẵn sàng"))
```

7. Column C (Mã học sinh) formula for cell C2, drag down to C20:

```
=IF(B2="Đang mượn",INDEX(SORT(FILTER('Phản hồi'!D:D,'Phản hồi'!C:C=A2),FILTER('Phản hồi'!A:A,'Phản hồi'!C:C=A2),FALSE),1,1),"—")
```

8. Column D (Tên học sinh) formula for cell D2, drag down to D20:

```
=IF(B2="Đang mượn",INDEX(SORT(FILTER('Phản hồi'!E:E,'Phản hồi'!C:C=A2),FILTER('Phản hồi'!A:A,'Phản hồi'!C:C=A2),FALSE),1,1),"—")
```

9. Column E (Ngày mượn) formula for cell E2, drag down to E20:

```
=IF(B2="Đang mượn",TEXT(INDEX(SORT(FILTER('Phản hồi'!A:A,'Phản hồi'!C:C=A2),FILTER('Phản hồi'!A:A,'Phản hồi'!C:C=A2),FALSE),1,1),"DD/MM/YYYY"),"—")
```

10. Column F (Ghi chú) formula for cell F2, drag down to F20:

```
=IF(B2="Đang mượn",INDEX(SORT(FILTER('Phản hồi'!F:F,'Phản hồi'!C:C=A2),FILTER('Phản hồi'!A:A,'Phản hồi'!C:C=A2),FALSE),1,1),"—")
```

11. Conditional formatting: highlight rows where B = "Đang mượn" in light red

**Section 4 — Paper Backup Template**

A printable ASCII grid:

```
╔══════════╦═══════╦═════════╦══════════════════╦═══════════╦══════════════╗
║ Ngày     ║ Số máy║ Mã HS   ║ Tên HS           ║ Mượn/Trả  ║ Ghi chú      ║
╠══════════╬═══════╬═════════╬══════════════════╬═══════════╬══════════════╣
║          ║       ║         ║                  ║           ║              ║
╠══════════╬═══════╬═════════╬══════════════════╬═══════════╬══════════════╣
║          ║       ║         ║                  ║           ║              ║
╚══════════╩═══════╩═════════╩══════════════════╩═══════════╩══════════════╝
```

(Repeat for ~20 rows, enough for 1-2 weeks of loans)

**Section 5 — Usage Instructions** (Vietnamese)

Brief instructions for staff:
- Khi học sinh mượn máy: fill out form with "Mượn máy"
- Khi học sinh trả máy: fill out form with "Trả máy"
- Không có internet: write on paper log, enter into form later
- Kiểm tra máy đang mượn: open Dashboard tab

**Step 2: Commit**

```bash
git add Documentation/Laptop-Checkout-System.md
git commit -m "Add laptop checkout system setup guide with Vietnamese form, dashboard formulas, and paper template"
```

---

### Task 2: Verify the documentation

**Step 1: Review the doc for completeness**

Check that:
- All 19 PC numbers are listed in the dropdown instructions
- All formulas reference correct column letters matching the Responses tab layout
- Vietnamese text has correct diacritics (Mượn, Trả, Sẵn sàng, Đang mượn)
- Paper template renders correctly in markdown
- Usage instructions are clear for non-technical Vietnamese staff

**Step 2: Done**

No tests to run — this is documentation only.
