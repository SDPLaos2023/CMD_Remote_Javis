# ⚡ BB_JAVIS Remote: Real-Time Zero-Dependency Remote Server & DB Management

ระบบสั่งการเซิร์ฟเวอร์ จัดการไฟล์ และคิวรีฐานข้อมูลระยะไกลประสิทธิภาพสูง ผ่านทาง Cloud Command Board ไร้ความจำเป็นในการเชื่อมต่อ VPN พร้อมระบบ **AI Autonomous Resilience (Intelligent Watchdog, Auto-Retry & In-Place Auto-Restart)** ตรวจจับและกู้คืนคำสั่งค้างอัตโนมัติ 100%

---

## 🚀 จุดเด่นของระบบ (Key Features)

* **AI Autonomous Resilience & Intelligent Watchdog:**
  * **Pending Hang Guard (>20s):** ตรวจจับคำสั่งที่ส่งไปแล้วไม่มี Agent มารับงานเกิน 20 วินาที
  * **Running Stalled Guard (>30s):** ตรวจจับกรณีสถานะ Running แต่นิ่งสนิทไร้ Heartbeat และไร้ Output ต่อเนื่องเกิน 30 วินาที
  * **Autonomous Auto-Retry:** ยกเลิกคำสั่งเดิม (Emergency Abort) และส่งคำสั่งซ้ำอัตโนมัติ (Retry 1/1) ทันทีโดยที่ผู้ใช้ไม่ต้องคอยเฝ้าหน้าจอ
  * **Heartbeat-Aware Safety:** สำหรับงานที่ใช้เวลานาน (เช่น Backup ฐานข้อมูลขนาดใหญ่) หากยังมี Heartbeat อัปเดตทุก 1.5 วินาที ระบบจะทำงานต่อเนื่องอย่างปลอดภัย **ไม่ตัดจบ**
* **In-Place Agent Auto-Restart (Self-Healing):**
  * หากคำสั่งค้างซ้ำหลัง Retry ระบบจะยกระดับส่งคำสั่งพิเศษ `__JAVIS_SYSTEM_RESTART__`
  * Agent จะทำการ In-Place Reset (เคลียร์ Runspace, Sockets, GC) ในหน้าต่างเดิมทันที ไม่เปิดหน้าต่างใหม่ให้รกหน้าจอ
  * **Keep Same PIN:** ยังคงใช้รหัส Secret Key (PIN 4 หลักเดิม) 100% เพื่อให้ทำงานต่อเนื่องได้ทันทีโดยไม่ต้องขอ PIN ใหม่
* **Enterprise Security Gateway (Cloudflare Edge WAF):** ซ่อนโครงสร้างฐานข้อมูลเบื้องหลัง 100% พร้อมระบบ Anti-Scan ป้องกันการเจาะระบบและการแอบส่องคำสั่งจากภายนอก
* **Multi-Tenant Data Isolation:** แยกพื้นที่การทำงานของแต่ละองค์กร/ทีมอย่างเด็ดขาดด้วย HMAC-SHA256 Cryptographic API Key
* **Local Machine Profile Persistence:** ระบบจดจำ API Key ลงเครื่องนั้นๆ อัตโนมัติ (`config.json`) กรอกครั้งแรกครั้งเดียว ไม่ต้องพิมพ์ซ้ำบ่อยๆ
* **Real-Time SSE Push Engine (<10ms):** ตอบสนองคำสั่งทันทีด้วยเทคโนโลยี Server-Sent Events ไม่ต้องรอรอบ Polling
* **Zero-Dependency 100%:** ขับเคลื่อนด้วย Native .NET HTTP ทำงานได้ทันทีบน Windows Server ทุกรุ่น ไม่ต้องพึ่งพาหรือดาวน์โหลด `curl.exe`
* **Zero-Touch One-Link Setup:** สั่งรันบนเซิร์ฟเวอร์ปลายทางได้ทันทีด้วย One-Link บรรทัดเดียว ปลดล็อก TLS 1.2 อัตโนมัติ
* **Self-Destruct Clean Exit & Zero-Footprint:** เมื่อกด `Ctrl+C` หรือปิดหน้าต่าง ระบบจะทำลายโหนด Session บน Cloud ทิ้งทันที (Zero Data Residue) และไม่มีไฟล์ขยะตกค้างในเครื่องเป้าหมาย
* **Universal Database & File Engine:**
  * รันสคริปต์ PowerShell / CMD แบบ Real-time Streaming
  * คิวรีฐานข้อมูล SQL Server ส่งคืนผลลัพธ์เป็น JSON ทันที
  * สำรองฐานข้อมูล (SQL Backup) พร้อมบีบอัดและส่งกลับอัตโนมัติ
  * อัปโหลด/ดาวน์โหลดไฟล์และโฟลเดอร์ข้ามเครื่องอย่างปลอดภัย
  * สั่งงาน GUI ผ่าน UI Automation (win-arm) และดูหน้าจอสดแบบ Real-Time (Live Screen Stream)

---

## 💻 วิธีเริ่มใช้งานบนเครื่องเป้าหมาย (Target Agent Side)

### 🔒 คำสั่งมาตรฐานทางเดียวของ JAVIS (Universal One-Link — รองรับทุกเครื่อง 100%)
เพื่อความปลอดภัยสูงสุดและป้องกันการเจาะระบบ ระบบบังคับใช้คำสั่งทางการของ **JAVIS ช่องทางเดียวเท่านั้น** โดยมีตัวเปิด TLS 1.2 ในตัว จึงสามารถใช้งานได้ทันที **100% บนทุกเครื่อง ทุกเวอร์ชัน** (ครอบคลุมทั้ง Windows Server 2012 R2, 2016, 2019, 2022, Windows 10 และ 11):

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
หน้าจอจะแสดงรหัส **Remote Secret Key (PIN 4 หลัก)** เช่น `1012` ให้นำรหัสนี้ไปให้ผู้ควบคุมเพื่อเริ่มสั่งงาน:
```text
======================================================================
              BB_JAVIS ENTERPRISE REMOTE EXECUTION AGENT              
======================================================================
  -> Remote Secret Key : [ 1012 ] (ACTIVE)
  -> Tenant Workspace  : [SDPUAT]
  -> API Key Security  : bbj_sdpuat_6...65ca (Persistent)
  -> Connection Status : Real-Time SSE Connected (<10ms In-Memory Turbo)
  -> Engine Type       : Hybrid Turbo C2 (In-Memory Runspace + Dual-Engine)
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

#### 1. ตรวจสอบสเปกเครื่องเป้าหมาย (System Spec & Health Check):
```cmd
send_remote_command.bat -SecretKey "1012" -Mode PowerShell -SqlQuery "$os=Get-CimInstance Win32_OperatingSystem;$cpu=Get-CimInstance Win32_Processor;$ram=[Math]::Round($os.TotalVisibleMemorySize/1MB,1);Write-Output \"Host: $env:COMPUTERNAME | OS: $($os.Caption) | CPU: $($cpu.Name) | RAM: ${ram}GB\""
```

#### 2. สั่งรันคำสั่ง PowerShell ทั่วไป:
```cmd
send_remote_command.bat -SecretKey "1012" -Mode PowerShell -SqlQuery "Get-Service w3svc"
```

#### 3. สั่งคิวรี SQL Server (ได้ผลลัพธ์เป็น JSON Compact):
```cmd
send_remote_command.bat -SecretKey "1012" -Mode Query -ConnectionString "Server=localhost;Database=DemoDB;Integrated Security=True;" -SqlQuery "SELECT TOP 5 ID, Name FROM Users"
```

#### 4. สั่งสำรองข้อมูลและส่งไฟล์ .bak กลับมาเครื่องเรา:
```cmd
send_remote_command.bat -SecretKey "1012" -Mode Backup -ConnectionString "Server=localhost;Database=DemoDB;Integrated Security=True;" -DbName "DemoDB" -OutputDir "D:\Backups"
```

#### 5. ดาวน์โหลดไฟล์/โฟลเดอร์จากเครื่องปลายทาง:
```cmd
send_remote_command.bat -SecretKey "1012" -Mode Download -RemotePath "C:\App\appsettings.json" -OutputDir "D:\Downloads"
```

#### 6. อัปโหลดไฟล์/โฟลเดอร์ไปยังเครื่องปลายทาง:
```cmd
send_remote_command.bat -SecretKey "1012" -Mode Upload -LocalPath "D:\Configs\appsettings.json" -RemotePath "C:\App\appsettings.json"
```

#### 7. สั่งยกเลิกงานฉุกเฉิน (Emergency Cancel / Abort):
```cmd
send_remote_command.bat -SecretKey "1012" -Mode Cancel
```
*(หรือกด `Ctrl+C` ที่หน้าจอของตัวส่งขณะรอ ระบบจะส่งสัญญาณ Abort ไปสั่งหยุดคำสั่งบนเครื่องปลายทางทันที)*

#### 8. สั่งการความเร็วสูง (Fast CLI) และการถ่ายทอดสดหน้าจอสด (Live Screen Streaming):
ยิงคำสั่งระดับ Sub-Second (1.7 - 1.9s) และดูหน้าจอสดแบบ Real-Time (5-10 FPS):

```cmd
# สั่งการด่วนผ่าน Fast CLI
send_fast.bat 1012 "whoami; Get-Date"

# เปิดดูหน้าจอสดผ่านเว็บเบราว์เซอร์ได้ทันที (Zero-Install Web Viewer):
http://127.0.0.1:5999/live?key=1012
```

#### 9. ควบคุมหน้าจอและ GUI อัตโนมัติ (Windows UI Automation via win-arm):
```cmd
# สั่งคลิกปุ่ม สลับแท็บ หรือกรอกข้อความในโปรแกรมบนเครื่องปลายทางผ่าน UIA Engine (ความเร็ว <50ms ไม่แย่งเมาส์)
send_remote_command.bat -SecretKey "1012" -Mode PowerShell -SqlQuery "python win_arm\win_arm.py -Mode Click -TargetTitle 'POS' -ControlName 'ปิดกะ'"
send_remote_command.bat -SecretKey "1012" -Mode PowerShell -SqlQuery "python win_arm\win_arm.py -Mode Screenshot -TargetTitle 'POS' -Base64"
```

---

## 🐧 การรองรับระบบปฏิบัติการ Linux (Cross-Platform Architecture)

เนื่องจากแกนกลางของ **BB_JAVIS** ใช้สถาปัตยกรรม **Cloud Command Board + HTTPS + Server-Sent Events (SSE) + JSON** ซึ่งเป็นมาตรฐานสากล จึงรองรับเครื่องเซิร์ฟเวอร์ปลายทางที่เป็น **Linux (Ubuntu, Debian, CentOS, RHEL)** ได้เช่นเดียวกัน:

| โครงสร้างระบบ | ฝั่ง Windows | ฝั่ง Linux |
| :--- | :--- | :--- |
| **Command Engine** | PowerShell / CMD | Bash Shell (`/bin/bash`) |
| **HTTP Transport** | Native .NET `HttpWebRequest` | Native `curl` (Zero-Dependency) |
| **System Diagnostics** | WMI / CIM (`Get-CimInstance`) | Linux Procfs (`/proc/cpuinfo`, `free -m`, `df -h`) |
| **Auto-Start Service** | Windows Task Scheduler | `systemd service` (Auto-start on boot) |
| **Resource Usage** | RAM ~30–50 MB | RAM **< 5 MB** (Ultra-lightweight) |

*(สคริปต์ Agent สำหรับ Linux สามารถสั่งรันผ่าน `curl -sSL https://da.gd/bbj-linux | bash` เพื่อเชื่อมต่อเข้า Command Board เดียวกันได้ทันที)*

---

## 🛡️ มาตรฐานความปลอดภัยระดับองค์กร (Enterprise Security Architecture)

### 1. ระบบรักษาความปลอดภัยด้วย Gateway และ Tenant API Key
* **Cloudflare Edge Reverse Proxy:** สคริปต์เชื่อมต่อผ่าน Cloudflare Worker Gateway แทนการเชื่อมต่อฐานข้อมูลคลาวด์โดยตรง ป้องกันการแกะดู URL หรือสิทธิ์ภายในองค์กร 100%
* **HMAC-SHA256 Cryptographic API Key:** คีย์ความปลอดภัยมาตรฐานสากล คำนวณความถูกต้องในระดับ Sub-millisecond ป้องกันการปลอมแปลงและไม่ต้องพึ่งพาฐานข้อมูลจัดเก็บ Key
* **Multi-Tenant Isolation:** แยกข้อมูลและคำสั่งระหว่างองค์กรอย่างเด็ดขาด (`/tenants/{tenant_id}/jobs/{pin}`) ผู้ใช้จากภายนอกไม่มีสิทธิ์มองเห็นหรือสั่งงานเครื่องของเราได้
* **WAF Anti-Scan Guard:** ระบบตัดการเชื่อมต่อและตอบกลับ `403 Forbidden` ทันทีเมื่อตรวจพบความพยายามสแกนโหนดรวม (Shallow List) หรือพยายามเดา PIN
* **Strict Secret Key Matching:** คำสั่งทุกคำสั่งต้องมีรหัส PIN ตรงกับหน้าจอเครื่องเป้าหมายเท่านั้น
* **Ephemeral Lifecycle & Self-Destruct:** ลบ Payload ทันทีหลังทำงานเสร็จ และลบ Session บน Cloud ทันทีที่ปิดหน้าต่าง
* **Zero-Footprint:** ไม่มีไฟล์ขยะหรือ Log ตกค้างในเครื่องเป้าหมาย

---

## 🔑 การสร้างและจัดการ API Key (API Key Generation)

ผู้ดูแลระบบสามารถสร้าง API Key ประจำทีมหรือเครื่องได้ง่ายๆ ผ่าน `gen_key.bat`:

```cmd
# 1. สั่งสร้าง Key สำหรับ Tenant "sdpuat" และบันทึกจำไว้ในเครื่องนี้ทันที:
gen_key.bat -Tenant "sdpuat" -SaveToThisMachine

# 2. สร้าง Key ให้ทีมอื่นหรือลูกค้า (พร้อมคัดลอกลง Clipboard):
gen_key.bat -Tenant "client_a" -CopyToClipboard
```

> [!TIP]
> **ระบบจดจำคีย์อัตโนมัติ (Local Machine Persistence):**
> เมื่อท่านระบุ API Key ในเครื่องครั้งแรก สคริปต์จะบันทึกจำไว้ใน `$env:LOCALAPPDATA\BB_Javis\config.json` อัตโนมัติ ทำให้การรันในครั้งต่อไปทำงานได้ทันทีแบบ 1-Click โดยไม่ต้องพิมพ์ซ้ำ!
