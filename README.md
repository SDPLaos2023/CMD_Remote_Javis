# ⚡ BB_JAVIS Remote: Real-Time Zero-Dependency Remote Server & DB Management

ระบบสั่งการเซิร์ฟเวอร์ จัดการไฟล์ และคิวรีฐานข้อมูลระยะไกลประสิทธิภาพสูง ผ่านทาง Cloud Command Board ไร้ความจำเป็นในการต่อ VPN

---

## 🚀 จุดเด่นของระบบ (Key Features)

* **Real-Time SSE Push Engine (<100ms):** ตอบสนองคำสั่งทันทีด้วยเทคโนโลยี Server-Sent Events ไม่ต้องรอรอบ Polling 5 วินาที
* **Zero-Dependency 100%:** ขับเคลื่อนด้วย Native .NET HTTP ทำงานได้ทันทีบน Windows Server ทุกรุ่น ไม่ต้องพึ่งพาหรือดาวน์โหลด `curl.exe`
* **Zero-Touch One-Link Setup:** สั่งรันบนเซิร์ฟเวอร์ปลายทางได้ทันทีด้วย One-Link บรรทัดเดียว
* **Emergency Abort & Hard Timeout:** สามารถส่งสัญญาณยกเลิกงานที่ค้างได้ทันที พร้อมระบบตัดจบคำสั่งอัตโนมัติหากเกินเวลา
* **Self-Destruct Clean Exit:** เมื่อกด `Ctrl+C` หรือปิดหน้าต่าง ระบบจะทำลายโหนด Session บน Cloud ทิ้งทันที (Zero Data Residue)
* **Zero-Footprint:** ไม่บันทึก Log ค้างไว้ในเครื่องเป้าหมาย และลบไฟล์ชั่วคราวทั้งหมดทันทีหลังรันเสร็จ
* **Universal Database & File Engine:**
  * รันสคริปต์ Windows PowerShell / CMD แบบ Real-time Streaming
  * คิวรีฐานข้อมูล SQL Server ส่งคืนผลลัพธ์เป็น JSON ทันที
  * สำรองฐานข้อมูล (SQL Backup) พร้อมบีบอัดและส่งกลับอัตโนมัติ
  * อัปโหลด/ดาวน์โหลดไฟล์และโฟลเดอร์ข้ามเครื่องอย่างปลอดภัย

---

## 💻 วิธีเริ่มใช้งานบนเครื่องเป้าหมาย (Target Agent Side)

### 🔒 คำสั่งมาตรฐานทางเดียวของ JAVIS (Universal One-Link — รองรับทุกเครื่อง 100%)
เพื่อความปลอดภัยสูงสุดและป้องกันการเจาะระบบ ระบบบังคับใช้คำสั่งทางการของ **JAVIS ช่องทางเดียวเท่านั้น** โดยมีตัวเปิด TLS 1.2 ในตัว จึงสามารถใช้งานได้ทันที **100% บนทุกเครื่อง ทุกเวอร์ชัน** (ทั้ง Windows Server 2012 R2, 2016, 2019, 2022, Windows 10 และ 11):

เปิด **PowerShell (Run as Administrator)** แล้ววางคำสั่งบรรทัดเดียว:

```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072; irm da.gd/bbj | iex
```

> [!IMPORTANT]
> **ระบบความปลอดภัยช่องทางเดียว (Single-Channel JAVIS Lockdown):**
> * บังคับผ่าน One-Link ทางการ `da.gd/bbj` เพียงทางเดียว ปิดกั้นทุกลิงก์ตรงและลิงก์ภายนอกทั้งหมด ป้องกันการสแกนหรือพยายามเจาะระบบจากภายนอก 100%
> * รันตรงในหน่วยความจำ (In-Memory Runspace) ทันที ไม่ต้องติดตั้งโปรแกรมเพิ่ม และไม่ทิ้งไฟล์ตกค้างใดๆ ในระบบ (Zero-Footprint)

---

### 🔑 เมื่อเปิดทำงานสำเร็จ:
หน้าจอจะแสดงรหัส **Remote Secret Key (PIN 4 หลัก)** เช่น `3757` ให้นำรหัสนี้ไปให้ผู้ควบคุมเพื่อเริ่มสั่งงาน:
```text
======================================================================
                    BB_JAVIS REMOTE (ZERO-TOUCH C2)                   
======================================================================
  -> Remote Secret Key : [ 3757 ] (ACTIVE)
  -> Connection Status : Real-Time SSE Connected (<100ms)
  -> Engine Type       : Native .NET (Zero-Dependency)
  -> One-Link URL      : da.gd/bbj
----------------------------------------------------------------------
   * Give the Remote Secret Key above to your controller
======================================================================
  Ready for incoming commands. Press Ctrl+C to stop.
======================================================================
```

---

## 🎮 วิธีสั่งการจากเครื่องควบคุม (Controller Side)

ดาวน์โหลดไฟล์ `send_remote_command.bat` แล้วสั่งงานได้ 2 รูปแบบ:

### รูปแบบที่ 1: เมนูโต้ตอบ (Interactive Mode)
ดับเบิลคลิกไฟล์ `send_remote_command.bat` เพื่อเลือกโหมดทำงาน [1-6] ผ่านเมนู

### รูปแบบที่ 2: สั่งการผ่าน Command Line (CLI / Automation)

#### 1. สั่งรันคำสั่ง PowerShell ทั่วไป:
```cmd
send_remote_command.bat -SecretKey "3757" -Mode PowerShell -SqlQuery "Get-Service w3svc"
```

#### 2. สั่งคิวรี SQL Server (ได้ผลลัพธ์เป็น JSON Compact):
```cmd
send_remote_command.bat -SecretKey "3757" -Mode Query -ConnectionString "Server=localhost;Database=DemoDB;Integrated Security=True;" -SqlQuery "SELECT TOP 5 ID, Name FROM Users"
```

#### 3. สั่งสำรองข้อมูลและส่งไฟล์ .bak กลับมาเครื่องเรา:
```cmd
send_remote_command.bat -SecretKey "3757" -Mode Backup -ConnectionString "Server=localhost;Database=DemoDB;Integrated Security=True;" -DbName "DemoDB" -OutputDir "D:\Backups"
```

#### 4. ดาวน์โหลดไฟล์จากเครื่องปลายทาง:
```cmd
send_remote_command.bat -SecretKey "3757" -Mode Download -RemotePath "C:\App\appsettings.json" -OutputDir "D:\Downloads"
```

#### 5. อัปโหลดไฟล์ไปยังเครื่องปลายทาง:
```cmd
send_remote_command.bat -SecretKey "3757" -Mode Upload -LocalPath "D:\Configs\appsettings.json" -RemotePath "C:\App\appsettings.json"
```

#### 6. สั่งยกเลิกงานฉุกเฉิน (Emergency Cancel / Abort):
```cmd
send_remote_command.bat -SecretKey "3757" -Mode Cancel
```
*(หรือกด `Ctrl+C` ที่หน้าจอของตัวส่งขณะรอ ระบบจะส่งสัญญาณ Abort ไปสั่งหยุดคำสั่งบนเครื่องปลายทางทันที)*

#### 7. ควบคุมหน้าจอและ GUI อัตโนมัติ (Windows UI Automation via win-arm):
```cmd
# สั่งคลิกปุ่ม สลับแท็บ หรือกรอกข้อความในโปรแกรมบนเครื่องปลายทางผ่าน UIA Engine (ความเร็ว <50ms ไม่แย่งเมาส์)
send_remote_command.bat -SecretKey "3757" -Mode PowerShell -SqlQuery "python win_arm\win_arm.py -Mode Click -TargetTitle 'POS' -ControlName 'ปิดกะ'"
send_remote_command.bat -SecretKey "3757" -Mode PowerShell -SqlQuery "python win_arm\win_arm.py -Mode Screenshot -TargetTitle 'POS' -Base64"
```

#### 8. สั่งการความเร็วสูง (Fast CLI) และการถ่ายทอดสดหน้าจอสด (Live Screen Streaming):
ยิงคำสั่งระดับ Sub-Second (1.7 - 1.9s) และดูหน้าจอสดแบบ Real-Time (5-10 FPS):

```cmd
# สั่งการด่วนผ่าน Fast CLI
send_fast.bat 2944 "whoami; Get-Date"

# เปิดดูหน้าจอสดผ่านเว็บเบราว์เซอร์ได้ทันที (Zero-Install Web Viewer):
http://127.0.0.1:5999/live?key=2944
```
*(เปลี่ยน `2944` เป็น Remote Secret Key ของเครื่องเป้าหมาย)*

---

## 🛡️ มาตรฐานความปลอดภัย (Security Architecture)
* **Anti-Collision Protection:** สุ่ม PIN พร้อมตรวจสอบสถานะกับระบบคลาวด์ ป้องกันการชนกันของรหัสเชื่อมต่อ
* **Strict Secret Key Matching:** คำสั่งทุกคำสั่งต้องมีรหัส PIN ตรงกับหน้าจอเครื่องเป้าหมายเท่านั้น
* **Ephemeral Lifecycle & Self-Destruct:** ลบ Payload ทันทีหลังทำงานเสร็จ และลบ Session บน Cloud ทันทีที่ปิดหน้าต่าง
* **Zero-Footprint:** ไม่มีไฟล์ขยะหรือ Log ตกค้างในเครื่องเป้าหมาย
