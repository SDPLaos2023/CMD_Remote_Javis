/**
 * BB_JAVIS Enterprise Gateway & Security Firewall
 * Cloudflare Worker Reverse Proxy with HMAC API Key Verification & Multi-Tenant Isolation
 * 
 * คุณสมบัติความปลอดภัย:
 * 1. ตรวจสอบ X-Javis-Key ด้วย HMAC-SHA256 Cryptographic Signature (Zero-Database, Sub-millisecond)
 * 2. Multi-Tenant Isolation: แยกเครื่องและคำสั่งเป็นอิสระต่อกัน (/tenants/{tenant_id}/jobs/{pin})
 * 3. WAF Anti-Scan Guard: บล็อกการสแกน Root, Shallow list รวม หรือการแอบดูงานขององค์กรอื่น (403 Forbidden)
 * 4. ซ่อน URL ฐานข้อมูล Firebase RTDB และ Database Secret ไว้เบื้องหลัง 100%
 * 5. Full Real-Time Support: รองรับ Server-Sent Events (SSE) แบบสตรีมมิ่งสด (<100ms)
 */

export default {
    async fetch(request, env, ctx) {
        // จัดการ Preflight CORS
        if (request.method === "OPTIONS") {
            return new Response(null, {
                status: 204,
                headers: {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET, PUT, POST, PATCH, DELETE, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Javis-Key, Accept",
                    "Access-Control-Max-Age": "86400"
                }
            });
        }

        const url = new URL(request.url);
        const path = url.pathname;

        // 1. Health Check Endpoint (ไม่เปิดเผยข้อมูล)
        if (path === "/" || path === "/health" || path === "/api/health") {
            return new Response(JSON.stringify({
                status: "ok",
                service: "BB_JAVIS Enterprise Security Gateway",
                version: "2026.1.0",
                timestamp: new Date().toISOString()
            }), {
                status: 200,
                headers: { "Content-Type": "application/json; charset=utf-8" }
            });
        }

        // 2. ดึง API Key จาก Header หรือ Query String
        let apiKey = request.headers.get("X-Javis-Key") || "";
        if (!apiKey) {
            const authHeader = request.headers.get("Authorization") || "";
            if (authHeader.toLowerCase().startsWith("bearer ")) {
                apiKey = authHeader.substring(7).trim();
            }
        }
        if (!apiKey && url.searchParams.has("api_key")) {
            apiKey = url.searchParams.get("api_key");
        }

        // 3. ตรวจสอบความถูกต้องของ API Key ผ่าน HMAC Verification
        const masterSecret = env.JAVIS_MASTER_SECRET || "JAVIS_SECURE_ENTERPRISE_MASTER_KEY_2026";
        const authResult = await verifyJavisApiKey(apiKey, masterSecret);

        if (!authResult.valid) {
            return new Response(JSON.stringify({
                error: "Unauthorized",
                message: "API Key ของ BB_JAVIS ไม่ถูกต้องหรือไม่ได้รับอนุญาต (401 Unauthorized)",
                detail: authResult.reason
            }), {
                status: 401,
                headers: {
                    "Content-Type": "application/json; charset=utf-8",
                    "Access-Control-Allow-Origin": "*"
                }
            });
        }

        const tenantId = authResult.tenantId;

        // 4. Anti-Scan & Security Firewall (บล็อกคำขอที่อันตรายหรือพยายามสแกน Root)
        // ห้ามยิง /jobs.json หรือ /tenants.json หรือไม่มี PIN ระบุ
        const normalizedPath = path.replace(/^\/api/, "");
        
        // กฎตรวจสอบ: อนุญาตเฉพาะเส้นทาง /jobs/{pin} เท่านั้น
        const jobMatch = normalizedPath.match(/^\/jobs\/([0-9a-zA-Z_-]+)(\/.*)?$/);
        if (!jobMatch) {
            return new Response(JSON.stringify({
                error: "Forbidden",
                message: "ปฏิเสธการเข้าถึง: ไม่อนุญาตให้สแกนหรืออ่านรายการคำสั่งภาพรวม (403 Forbidden)"
            }), {
                status: 403,
                headers: {
                    "Content-Type": "application/json; charset=utf-8",
                    "Access-Control-Allow-Origin": "*"
                }
            });
        }

        const pin = jobMatch[1];
        const subPath = jobMatch[2] || "";

        // ป้องกันกรณี pin เป็นคำว่า ".json" (หมายถึงพยายามเรียก /jobs.json)
        if (pin === ".json" || pin.startsWith(".json")) {
            return new Response(JSON.stringify({
                error: "Forbidden",
                message: "ปฏิเสธการเข้าถึง: บล็อกการดึงรายการเครื่องและ PIN ทั้งหมด (Shallow Scan Blocked)"
            }), {
                status: 403,
                headers: {
                    "Content-Type": "application/json; charset=utf-8",
                    "Access-Control-Allow-Origin": "*"
                }
            });
        }

        // 5. ประกอบ URL ปลายทางสู่ Firebase RTDB ภายใต้ Tenant Namespace
        const firebaseBase = (env.FIREBASE_RTDB_URL || "https://uat-api-agent-default-rtdb.firebaseio.com").replace(/\/$/, "");
        
        // เส้นทางภายใน Firebase: /tenants/{tenantId}/jobs/{pin}{subPath}
        let targetUrl = `${firebaseBase}/tenants/${encodeURIComponent(tenantId)}/jobs/${pin}${subPath}`;
        
        // ส่งต่อ Query Parameters (เช่น ?shallow=true) พร้อมแนบ Database Auth Secret (ถ้ามี)
        const targetUrlObj = new URL(targetUrl);
        for (const [key, value] of url.searchParams.entries()) {
            if (key !== "api_key") {
                targetUrlObj.searchParams.set(key, value);
            }
        }
        if (env.FIREBASE_AUTH_SECRET) {
            targetUrlObj.searchParams.set("auth", env.FIREBASE_AUTH_SECRET);
        }

        // 6. เตรียม Forward Headers
        const forwardHeaders = new Headers();
        const copyHeaders = ["content-type", "accept", "cache-control"];
        for (const h of copyHeaders) {
            if (request.headers.has(h)) {
                forwardHeaders.set(h, request.headers.get(h));
            }
        }

        // 7. จัดการ Request Body สำหรับ PUT, POST, PATCH
        let requestBody = null;
        if (["PUT", "POST", "PATCH"].includes(request.method.toUpperCase())) {
            requestBody = await request.arrayBuffer();
        }

        // 8. Forward Request ไปยัง Firebase RTDB
        try {
            const firebaseResponse = await fetch(targetUrlObj.toString(), {
                method: request.method,
                headers: forwardHeaders,
                body: requestBody
            });

            // ตรวจสอบว่าเป็นการเชื่อมต่อ Server-Sent Events (SSE Real-time Stream) หรือไม่
            const isSSE = firebaseResponse.headers.get("content-type")?.includes("text/event-stream");

            const responseHeaders = new Headers(firebaseResponse.headers);
            responseHeaders.set("Access-Control-Allow-Origin", "*");
            responseHeaders.set("X-Javis-Tenant", tenantId);
            responseHeaders.set("X-Javis-Gateway", "Cloudflare-Edge");

            if (isSSE) {
                // ส่งต่อ Real-time Stream กลับทันที (<100ms)
                return new Response(firebaseResponse.body, {
                    status: firebaseResponse.status,
                    statusText: firebaseResponse.statusText,
                    headers: responseHeaders
                });
            }

            // คำขอแบบปกติ (GET, PUT, PATCH, DELETE)
            const respBody = await firebaseResponse.arrayBuffer();
            return new Response(respBody, {
                status: firebaseResponse.status,
                statusText: firebaseResponse.statusText,
                headers: responseHeaders
            });

        } catch (err) {
            return new Response(JSON.stringify({
                error: "Bad Gateway",
                message: "ไม่สามารถส่งคำขอไปยัง Cloud Command Board ได้",
                detail: err.message
            }), {
                status: 502,
                headers: {
                    "Content-Type": "application/json; charset=utf-8",
                    "Access-Control-Allow-Origin": "*"
                }
            });
        }
    }
};

/**
 * ฟังก์ชันตรวจสอบความถูกต้องของ Javis API Key
 * รูปแบบของ Key: bbj_<tenant>_<timestamp>_<signature>
 * ตัวอย่าง: bbj_sdpuat_66e6b12a_9f8e7d6c5b4a3...
 */
async function verifyJavisApiKey(apiKey, masterSecret) {
    if (!apiKey || typeof apiKey !== "string") {
        return { valid: false, reason: "ไม่พบคีย์ใน Header X-Javis-Key หรือ Authorization" };
    }

    const trimmed = apiKey.trim();
    if (!trimmed.startsWith("bbj_")) {
        return { valid: false, reason: "รูปแบบ API Key ไม่ถูกต้อง (ต้องขึ้นต้นด้วย bbj_)" };
    }

    const parts = trimmed.split("_");
    if (parts.length < 4) {
        return { valid: false, reason: "โครงสร้าง API Key ไม่สมบูรณ์" };
    }

    // parts[0] = "bbj"
    // parts[1] = tenantId
    // parts[2] = timestampHex
    // parts[3] = signatureHex
    const tenantId = parts[1].toLowerCase();
    const timestampHex = parts[2];
    const signatureHex = parts[3];

    // Payload ที่นำมาเซ็นคือ "tenant:timestamp"
    const message = `${tenantId}:${timestampHex}`;
    const expectedSignature = await computeHmacSha256(message, masterSecret);

    // ตรวจสอบความถูกต้องของ Signature (เปรียบเทียบแบบป้องกัน Timing Attack)
    if (!timingSafeEqual(signatureHex.toLowerCase(), expectedSignature.toLowerCase())) {
        return { valid: false, reason: "ลายเซ็นความปลอดภัย (Signature) ไม่ถูกต้องหรือถูกแก้ไข" };
    }

    return { valid: true, tenantId: tenantId };
}

/**
 * คำนวณ HMAC-SHA256 ด้วย Web Crypto API (Sub-millisecond Performance)
 */
async function computeHmacSha256(message, secret) {
    const enc = new TextEncoder();
    const keyData = enc.encode(secret);
    const msgData = enc.encode(message);

    const cryptoKey = await crypto.subtle.importKey(
        "raw",
        keyData,
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"]
    );

    const signature = await crypto.subtle.sign("HMAC", cryptoKey, msgData);
    const hashArray = Array.from(new Uint8Array(signature));
    // ดึง 32 ตัวอักษรแรกของ Hex เพื่อความกะทัดรัดแต่ปลอดภัยสูง
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");
    return hashHex.substring(0, 32);
}

/**
 * ฟังก์ชันเปรียบเทียบสตริงแบบ Timing Safe ป้องกัน Side-Channel Attacks
 */
function timingSafeEqual(a, b) {
    if (a.length !== b.length) {
        return false;
    }
    let result = 0;
    for (let i = 0; i < a.length; i++) {
        result |= a.charCodeAt(i) ^ b.charCodeAt(i);
    }
    return result === 0;
}
