# คู่มือการติดตั้ง BB_JAVIS Enterprise Gateway บน Cloudflare Workers (ฟรี 100%)

เอกสารนี้อธิบายขั้นตอนการนำโค้ด `worker.js` ขึ้นไปทำงานเป็น Gateway รักษาความปลอดภัยบน Cloudflare Workers เพื่อซ่อนฐานข้อมูล Firebase และคุมสิทธิ์ด้วย API Key

---

## 🚀 วิธีที่ 1: ติดตั้งผ่านหน้าเว็บ Cloudflare Dashboard (ง่ายที่สุด ไม่ต้องลงโปรแกรมใดๆ)

1. **สมัคร/เข้าสู่ระบบ:** ไปที่ [https://dash.cloudflare.com/](https://dash.cloudflare.com/)
2. **สร้าง Worker:**
   - เมนูด้านซ้ายคลิก **Compute (Workers & Pages)** -> **Workers & Pages**
   - คลิกปุ่ม **Create Application** -> เลือกแท็บ **Workers** -> คลิก **Create Worker**
   - ตั้งชื่อ เช่น `bb-javis-gateway` แล้วคลิก **Deploy**
3. **วางโค้ด Worker:**
   - ในหน้ารายละเอียด Worker ให้คลิก **Edit code**
   - ลบโค้ดเดิมทั้งหมดออก แล้วคัดลอกโค้ดจากไฟล์ `scripts/cloudflare_worker/worker.js` ทั้งหมดไปวางแทน
   - คลิกปุ่ม **Deploy** (มุมขวาบน)
4. **ตั้งค่า Environment Variables (ความลับของระบบ):**
   - กลับมาที่หน้าตั้งค่า Worker -> เลือกแท็บ **Settings** -> เมนูย่อย **Variables and Secrets**
   - คลิก **Add** เพื่อเพิ่มตัวแปรดังนี้:
     - `FIREBASE_RTDB_URL`: `https://uat-api-agent-default-rtdb.firebaseio.com`
     - `JAVIS_MASTER_SECRET`: ใส่ Secret เดียวกับที่ใช้ในสคริปต์ Gen Key (ค่าเริ่มต้น: `JAVIS_SECURE_ENTERPRISE_MASTER_KEY_2026` หรือตั้งเองใหม่)
   - คลิก **Save and Deploy**
5. **รับ URL ใช้งาน:**
   - คุณจะได้ URL ประจำ Worker เช่น `https://bb-javis-gateway.<your-account>.workers.dev`
   - สามารถนำ URL นี้ไประบุในตัวแปร `$GatewayUrl` ของ Agent และ Sender ได้ทันที!

---

## ⚡ วิธีที่ 2: ติดตั้งผ่าน Command-Line (Wrangler CLI)

หากเครื่องของคุณมี Node.js และ npm ติดตั้งอยู่แล้ว:

1. เปิด Terminal ในโฟลเดอร์นี้:
   ```bash
   cd scripts/cloudflare_worker
   ```
2. ล็อกอินเข้า Cloudflare:
   ```bash
   npx wrangler login
   ```
3. สั่ง Deploy ขึ้น Cloudflare ทันที:
   ```bash
   npx wrangler deploy
   ```
4. ตั้งค่า Secret อย่างปลอดภัย:
   ```bash
   npx wrangler secret put JAVIS_MASTER_SECRET
   ```

---

## 🔑 การสร้างและแจกจ่าย API Key

เมื่อติดตั้ง Gateway เสร็จแล้ว สามารถสั่งสร้าง API Key ให้ทีมงานหรือใส่ในเครื่องเป้าหมายได้ง่ายๆ ผ่าน `gen_key.bat`:

```cmd
# สร้างคีย์สำหรับ Tenant "sdpuat" และบันทึกจำไว้ในเครื่องนี้ทันที
.\gen_key.bat -Tenant "sdpuat" -SaveToThisMachine

# หรือสร้างคีย์สำหรับเครื่องของลูกค้า / ทีมอื่น
.\gen_key.bat -Tenant "customer_a"
```
