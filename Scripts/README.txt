==========================================
VIETNAM LAB DEPLOYMENT - SCRIPTS GUIDE
==========================================

Language: English & Vietnamese / Tiếng Anh & Tiếng Việt
Version: 1.0
Date: February 2026

==========================================
ENGLISH INSTRUCTIONS
==========================================

These PowerShell scripts automate the deployment of the Vietnam Assistive Technology Lab.

PREREQUISITES:
--------------
✓ Windows 11 PCs (pre-updated, disconnected from internet)
✓ USB drive with all installers downloaded
✓ Administrator access to each PC
✓ 30-60 minutes per PC for full deployment

DEPLOYMENT ORDER:
-----------------

0. Run: 0-Download-Installers.ps1 (FIRST TIME ONLY - on your main PC)
   → Downloads most software automatically
   → Sao Mai software must be downloaded manually
   → Run this BEFORE going to Vietnam

1. Run: 1-Install-All.ps1
   → Installs all software silently (15-20 minutes)
   → NVDA, VNVoice, Typing Tutor, LibreOffice, Firefox, VLC, LEAP Games
   → Creates installation.log file

2. Run: 2-Verify-Installation.ps1
   → Checks all software installed correctly
   → Reports critical failures
   → Creates verification.log file

3. Run: 3-Configure-NVDA.ps1
   → Applies Vietnamese NVDA profile
   → Enables auto-start on login
   → Configures Orbit Reader 20 settings
   → Creates configuration.log file

HOW TO RUN:
-----------
1. Insert USB drive into PC
2. Right-click Windows Start button
3. Select "Windows PowerShell (Admin)" or "Terminal (Admin)"
4. Navigate to scripts folder:
   cd X:\Scripts
   (Replace X: with your USB drive letter)

5. Run first script:
   .\1-Install-All.ps1

6. Follow prompts for remaining scripts

TROUBLESHOOTING:
----------------
If scripts won't run due to "Execution Policy":

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Then run scripts normally.

LOGS:
-----
All scripts create log files in the Scripts folder:
- installation.log
- verification.log
- configuration.log

Review logs if any issues occur.

SUPPORT:
--------
For technical support, contact:
- Sao Mai Center: https://saomaicenter.org/en/contact
- Project Lead: [Contact info]

==========================================
HƯỚNG DẪN TIẾNG VIỆT
==========================================

Các tập lệnh PowerShell này tự động hóa việc triển khai Phòng Lab Công Nghệ Hỗ Trợ Việt Nam.

YÊU CẦU TRƯỚC KHI BẮT ĐẦU:
--------------------------
✓ Máy tính Windows 11 (đã cập nhật, ngắt kết nối internet)
✓ USB chứa tất cả các tập tin cài đặt
✓ Quyền quản trị viên (Administrator) trên mỗi máy
✓ 30-60 phút cho mỗi máy tính

THỨ TỰ TRIỂN KHAI:
------------------

1. Chạy: 1-Install-All.ps1
   → Cài đặt tất cả phần mềm tự động (15-20 phút)
   → NVDA, VNVoice, Chương trình luyện gõ, LibreOffice, Firefox, VLC, LEAP Games
   → Tạo tập tin installation.log

2. Chạy: 2-Verify-Installation.ps1
   → Kiểm tra tất cả phần mềm đã cài đúng
   → Báo cáo lỗi nghiêm trọng
   → Tạo tập tin verification.log

3. Chạy: 3-Configure-NVDA.ps1
   → Áp dụng cấu hình NVDA tiếng Việt
   → Cài đặt các add-on NVDA (VLC accessibility)
   → Bật tự động khởi động khi đăng nhập
   → Cấu hình cài đặt Orbit Reader 20
   → Tạo tập tin configuration.log

CÁCH CHẠY:
----------
1. Cắm USB vào máy tính
2. Nhấp chuột phải vào nút Start của Windows
3. Chọn "Windows PowerShell (Admin)" hoặc "Terminal (Admin)"
4. Di chuyển đến thư mục scripts:
   cd X:\Scripts
   (Thay X: bằng ký tự ổ USB của bạn)

5. Chạy tập lệnh đầu tiên:
   .\1-Install-All.ps1

6. Làm theo hướng dẫn cho các tập lệnh còn lại

KHẮC PHỤC SỰ CỐ:
----------------
Nếu tập lệnh không chạy được do "Execution Policy":

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Sau đó chạy tập lệnh bình thường.

TẬP TIN GHI CHÚ (LOG):
----------------------
Tất cả tập lệnh tạo tập tin ghi chú trong thư mục Scripts:
- installation.log
- verification.log
- configuration.log

Xem lại các tập tin này nếu có vấn đề.

HỖ TRỢ KỸ THUẬT:
----------------
Để được hỗ trợ kỹ thuật, liên hệ:
- Trung tâm Sao Mai: https://saomaicenter.org/en/contact
- Trưởng dự án: [Thông tin liên hệ]

==========================================
© 2026 - Vietnam Assistive Tech Lab Project
==========================================
