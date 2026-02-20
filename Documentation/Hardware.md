# Hardware
**Requirements:** x86-64 CPU: NVDA-compatible

## - **Dell Latitude 5420 Laptop:**
**$307.53/unit** from Dell Refurbished (**Grade A**) — 19 units purchased 2026-02-13.
**Status:** 5 of 19 received (2026-02-19). Remaining 14 in transit.
(Product ID: dell-latitude-5420-000402, Order #U1301960)

| Spec | Detail |
|------|--------|
| **CPU** | i5-1145G7 (11th gen, 4C/8T, 4.4 GHz) — (NVDA screen reader is Intel-optimized) |
| **RAM** | 8GB DDR4-3200 (2 slots, upgradeable) |
| **Storage** | 256GB NVMe SSD |
| **Build** | Carbon-fiber, MIL-STD-810G |
| **Ports** | 2x Thunderbolt 4, 2x USB 3.2, RJ-45 Ethernet |
| **Keyboard** | 1.5 mm key travel (Tactile keyboard feel is crucial), spill-resistant, full-size arrow keys|
| **Webcam** | Privacy shutter |
| **Microphone** | Dual-array noise-reducing |
| **Wi-Fi / BT** | Wi-Fi 6 AX201 (802.11ax, 2x2) — Bluetooth 5.1 |
| **Display** | 14" FHD IPS (Irrelevant) |
| **Weight** | 3.03 lbs |
| **OS** | Windows 10 Pro (free upgrade to 11) |
| **Warranty** | 100-day included, 1-year extended for $49 |

Serviceability (Latitude is built for easy service): 
- Replacement keyboards $15-25
- Replacement batteries $30-50.

Upgradeability: $18-25 for additional stick of 8GB DDR4-3200 SO-DIMM RAM. Extensive availability for at least 10 years. Still available long after.

Meets all Win11 Upgrade requirements:
- i5-1145G7 (11th gen Intel)
- TPM 2.0 built-in
- UEFI + Secure Boot capable

### 19x Laptop Purchase

| | |
|---|---|
| List price | $459.00/unit |
| Promo (LOVE33, 33% off) | -$151.47/unit |
| **Effective per unit** | **$307.53** |
| **Per unit with tax** | **$345.87** |
| Subtotal (19 units) | $5,843.07 |
| Tax | $728.40 |
| **Grand Total** | **$6,571.47** |

#### Serial Numbers
7FP31J3, 7YB71J3, 82DJ0J3, 88X63F3, 9GGW2F3, 9PH41J3, B4JR2F3, C5MJ0J3, CQ6H1J3, CTDJ2F3, DC861J3, DDYJ6J3, DFS91J3, DT1M6J3, FNDP0J3, FSRH0J3, G2X61J3, HQKJ0J3, 6C541J3

### x86-x64 vs ARM

ARM/Snapdragon laptops run NVDA, Sao Mai VNVoice, Microsoft Office, and LEAP Games through **emulation**, adding latency to speech output. Not suitable for screen reader users.

---

## - Headphones: Audio-Technica ATH-M40x

Audio-Technica ATH-M40x — 21 units pending via Sweetwater sales engineer (nonprofit pricing TBD).

### For Blind Users, Headphones = SINGLE Computer Output
Screen reader audio is 100% of the interface.

Used at:
- Perkins School for the Blind computer labs
- National Federation of the Blind recommended
- JAWS/NVDA training centers
  
Flat Freq. response (clear at critical speech range 2000-8000 Hz). Critical for NVDA speech at fast rates.

### Detachable Cable
Cable breaks → Replace $15 cable instead of $79 headphone. Only failure point.

### Replacement Earpads
Replace after heavy use ~3 years. $15-$30 simple installation.

### Closed-Back
Required for classrooms. 10 screen readers running simultaneously need sound isolation.

### ATHM40x vs M20x
Detachable cable, better clarity, build quality and comfort are worth the $30 difference for a long term deployment.


### Specs

- Type: Closed-back over-ear
- Drivers: 40mm neodymium
- Frequency: 15-24,000 Hz (flat)
- Impedance: 35Ω (laptop compatible)
- Cable: Detachable 3.5mm (2 included)
- Weight: 240g
- Warranty: 1 year

### 21x Headphone Purchase (Sweetwater — pending)

| Item | Qty | Cost | Total |
|------|-----|------|-------|
| ATH-M40x | 21 | TBD | TBD |
| Spare cables | 5 | TBD | TBD |
| Replacement earpads | 4 | TBD | TBD |
| **Total** | | | **TBD** |

---
## - Personal Student USB Drives

**EASTBULL 100-Pack 16GB USB 2.0** with lanyards and labels — purchased 2026-02-13. **Received.**

| | |
|---|---|
| Subtotal | $231.88 |
| Tax | $17.97 |
| Gift card | -$1.31 |
| **Grand Total** | **$248.54** |
| **Per unit with tax** | **$2.49** |

| Spec | Detail |
|------|--------|
| **Capacity** | 16GB |
| **Interface** | USB 2.0 (~20-30 MB/s read) |
| **Design** | Swivel, capless (no cap to lose) |
| **Included** | 50 lanyards, 50 labels |
| **Qty** | 100 |

- Each USB drive is assigned an Asset Number (STU-001, etc.) via `4-Prepare-Student-USB.ps1`
  - Asset number labeled in both print and 3D-printed Braille tag (see `Documentation/USB-Braille-Tags.md`)
  - Braille tag clips onto drive keyring loop, lanyard attaches to tag
- Pre-created folders (Documents, Audio, Schoolwork)
- Optional Google Drive backup via rclone syncs every 15 minutes if internet is available
- Asset numbers also stored as hidden `.student-id` file on USB drive

---

## Total Cost Summary

| Item | Per Station (with tax) | Total (19 stations) |
|------|----------------------|---------------------|
| Dell Latitude 5420 | $345.87 | $6,571.47 |
| ATH-M40x headphone | TBD (~$92-107) | TBD |
| **Estimated Per Station** | **~$438-453** | **~$8,300-8,600** |

USB drives purchased separately: 100x EASTBULL 16GB — $248.54

---

# Conclusion
Enterprise laptop durability and professional headphone clarity is best for an accessible deployment.
