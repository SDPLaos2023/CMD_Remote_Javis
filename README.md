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

## 💻 วิธีเริ่มใช้งานบนเครื่องเป้าหมาย (Dual-Mode Target Agent)

ระบบรองรับ **2 รูปแบบการทำงาน** ตามความสะดวกของผู้ใช้งาน:

### 1️⃣ โหมดที่ 1: รันชั่วคราว / On-Demand (`da.gd/bbj`)
> เหมาะสำหรับเครื่องทดสอบหรืองานเฉพาะกิจ สุ่ม PIN ใน Memory ปิดหน้าต่างแล้วลบทิ้งทันที 100%

เปิด **PowerShell (Run as Administrator)** แล้ววางคำสั่งบรรทัดเดียว:
```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072; irm da.gd/bbj | iex
```

---

### 2️⃣ โหมดที่ 2: ติดตั้งถาวรเป็น Background Windows Service (`da.gd/bbj-fix`)
> เหมาะสำหรับเซิร์ฟเวอร์หลัก / POS สาขา ที่ต้องการเปิดตลอด 24 ชม. ตื่นเองอัตโนมัติเมื่อเปิดเครื่อง และจำ PIN เดิมไว้ถาวร

เปิด **PowerShell (Run as Administrator)** แล้ววางคำสั่งบรรทัดเดียว:
```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072; irm da.gd/bbj-fix | iex
```
*(หรือรันไฟล์ `install_service.bat`)*
* **ตั้งชื่อเครื่องได้ตามต้องการ (Custom Host Name / Alias):** ระบบจะขึ้นถามใน Console เช่น `ระบุชื่อเครื่อง [กด Enter เพื่อใช้ชื่อเดิม/SITTHI-VM01]:` เพื่อให้ระบุชื่อเรียกง่ายๆ เช่น `POS-Rama9`, `UAT-DB-01` (หรือตั้งล่วงหน้าผ่าน `$env:BB_JAVIS_HOST = "POS-Rama9"`)
* ติดตั้งเป็น Windows Service `BB_JAVIS_Remote` อัตโนมัติ (Zero-Dependency)
* รันเบื้องหลังระดับ SYSTEM ตลอด 24 ชั่วโมง และจำ Persistent PIN ประจำเครื่อง
* เมื่อติดตั้งเสร็จ แสดงข้อมูล PIN และสถานะ แล้วสามารถ **ปิดหน้าต่าง PowerShell ได้ทันที**

---

### 🗑️ คำสั่งถอนการติดตั้งโหมด Fix (`da.gd/bbj-unfix`)
```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072; irm da.gd/bbj-unfix | iex
```
*(หรือรัน `C:\ProgramData\BB_Javis\uninstall_service.bat`)*

---

## 🎮 วิธีสั่งการจากเครื่องควบคุม (Controller Side)

ดาวน์โหลดไฟล์ `send_remote_command.bat` แล้วสั่งงานได้ 2 รูปแบบ:

### รูปแบบที่ 1: เมนูโต้ตอบ & ตารางสถานะ Real-Time (Fleet Management)
ดับเบิลคลิกไฟล์ `send_remote_command.bat` โดยไม่ใส่ Argument ระบบจะแสดง **ตารางสถานะของอุปกรณ์ทั้งหมดในระบบ (Online/Offline)** พร้อมชื่อที่ตั้งเองและชื่อเครื่องจริง:

```text
==================================================================================================================
                           BB_JAVIS FLEET MANAGEMENT - DEVICE STATUS & PRESENCE                           
==================================================================================================================
 No.  PIN    STATUS    TYPE      COMPUTER NAME            LOCAL IP         PUBLIC IP        LAST SEEN   
------------------------------------------------------------------------------------------------------------------
 [1]  3757   ONLINE    Service   POS-Rama9 (VM-01)        192.168.1.50     183.182.195.42   Just now    
 [2]  6579   ONLINE    Service   DB-Prod (SRV-SQL)        10.10.2.14       110.164.78.12    15s ago     
 [3]  8479   OFFLINE   Service   HQ-Backup (DB-02)        192.168.1.99     183.182.195.42   2h ago (Offline)
==================================================================================================================
```
* **พิมพ์ตัวเลข [1-N]** เพื่อเลือกเครื่องนั้นทันที (ไม่ต้องจำ PIN)
* **หรือพิมพ์ชื่อเครื่องที่ตั้งเอง** (เช่น `POS-Rama9`), ชื่อเครื่องจริง หรือ **IP** เพื่อค้นหาและจับคู่อัตโนมัติ
* **หรือพิมพ์ PIN 4 หลักตรงๆ** เพื่อสั่งงานเครื่องใดๆ
* **กด [N]** เพื่อเปลี่ยนชื่อเครื่อง (Rename / Set Alias) จากระยะไกลได้ทันที
* **กด [D]** เพื่อเตะ/ลบเครื่องออกจาก Cloud | **[R]** รีเฟรชตาราง

---

### รูปแบบที่ 2: สั่งการผ่าน Command Line (CLI / Automation)

#### 1. ตรวจสอบสถานะเครื่องทั้งหมดในระบบ (Fleet List):
```cmd
send_remote_command.bat -List
```

#### 2. สั่งงานเจาะจงเครื่องด้วยชื่อเครื่อง (Target Hostname):
```cmd
send_remote_command.bat -TargetHost "SRV-UAT-01" -Mode PowerShell -SqlQuery "Get-Service w3svc"
```

#### 3. สั่งงานเจาะจงเครื่องด้วยหมายเลข IP (Target IP):
```cmd
send_remote_command.bat -TargetIp "192.168.1.50" -Mode Query -ConnectionString "Server=localhost;Database=DemoDB;Integrated Security=True;" -SqlQuery "SELECT TOP 5 ID, Name FROM Users"
```

#### 4. สั่งล้างเครื่องที่สถานะ Offline ทั้งหมด (Purge Offline):
```cmd
send_remote_command.bat -PurgeOffline
```

#### 5. สั่งสำรองข้อมูลและส่งไฟล์ .bak กลับมาเครื่องเรา:
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
