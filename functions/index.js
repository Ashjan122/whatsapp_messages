const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const axios = require("axios");
const path = require("path");

if (admin.apps.length === 0) {
    admin.initializeApp();
}

const db = admin.firestore();
const storage = admin.storage();

const VERIFY_TOKEN = "Alryyan12345#";

async function uploadMediaToStorage(mediaId, folderName, dynamicToken) {
    try {
        const getUrlResponse = await axios.get(`https://graph.facebook.com/v21.0/${mediaId}`, {
            headers: { 'Authorization': `Bearer ${dynamicToken}` }
        });
        const whatsappMediaUrl = getUrlResponse.data.url;
        const mimeType = getUrlResponse.data.mime_type;
        const extension = mimeType.split('/')[1] || 'bin';

        const mediaResponse = await axios.get(whatsappMediaUrl, {
            headers: { 'Authorization': `Bearer ${dynamicToken}` },
            responseType: 'arraybuffer'
        });

        const buffer = Buffer.from(mediaResponse.data);
        const fileName = `${folderName}/${mediaId}.${extension}`;
        const file = storage.bucket().file(fileName);

        await file.save(buffer, {
            metadata: { contentType: mimeType }
        });

        const signedUrls = await file.getSignedUrl({
            action: 'read',
            expires: '03-01-2500'
        });

        return signedUrls[0];
    } catch (error) {
        console.error("❌ Error in uploadMediaToStorage:", error.message);
        return null;
    }
}

exports.whatsappWebhook = onRequest({
    region: "us-central1",
    invoker: "public"
}, async (req, res) => {

    if (req.method === "GET") {
        const mode = req.query["hub.mode"];
        const token = req.query["hub.verify_token"];
        const challenge = req.query["hub.challenge"];

        if (mode === "subscribe" && token === VERIFY_TOKEN) {
            return res.status(200).send(challenge);
        } else {
            return res.sendStatus(403);
        }
    }

    if (req.method === "POST") {
        try {
            const body = req.body;
            const entry = body.entry?.[0];
            const changes = entry?.changes?.[0];
            const value = changes?.value;

            if (!value) return res.sendStatus(200);

            const incomingPhoneNumberId = value.metadata.phone_number_id;

            // --- 1. جلب الإعدادات ديناميكياً بناءً على الرقم المستلم ---
            const configQuery = await db.collection("whatsapp_config")
                .where("PHONE_NUMBER_ID", "==", incomingPhoneNumberId)
                .limit(1).get();

            if (configQuery.empty) {
                console.log(`⚠️ No config found for Phone ID: ${incomingPhoneNumberId}`);
                return res.sendStatus(200);
            }

            const configDoc = configQuery.docs[0];
            const configData = configDoc.data();
            const actualConfigId = configDoc.id; // المعرف الصحيح (مثلاً alroomi_branch أو altamayoz_branch)
            const currentToken = configData.TOKEN;

            // مرجع المستند الحالي للفرع المستلم
            const currentConfigRef = db.collection("whatsapp_config").doc(actualConfigId);

            // --- 2. تحديثات الحالة (في الفرع الصحيح) ---
            if (value.statuses && value.statuses[0]) {
                const statusUpdate = value.statuses[0];
                await currentConfigRef.collection("chats").doc(statusUpdate.recipient_id)
                    .collection("messages").doc(statusUpdate.id)
                    .update({ status: statusUpdate.status })
                    .catch(() => {});
            }

            // --- 3. معالجة الرسائل الواردة ---
            if (value.messages && value.messages[0]) {
                const message = value.messages[0];
                const contact = value.contacts?.[0];
                const senderPhone = message.from;
                const senderName = (contact && contact.profile) ? contact.profile.name : "Unknown";

                let messageText = "";
                let resultNumber = "";
                let mediaUrl = null;
                let messageType = message.type;
                let shiftReportType = null; // "sales" | "sold_items"
                let shiftNumber = null;

                // تحليل الرسالة
                if (message.type === "text") {
                    messageText = message.text.body.trim();
                    if (/^\d+$/.test(messageText)) resultNumber = messageText;
                }
                else if (message.type === "interactive" && message.interactive.type === "button_reply") {
                    messageText = message.interactive.button_reply.title.trim();
                    console.log("🔘 interactive button_reply title:", messageText);
                    console.log("🔘 interactive button_reply id:", message.interactive.button_reply.id);
                    if (messageText.includes("تقرير مبيعات اليوم")) shiftReportType = "sales";
                    else if (messageText.includes("تقرير الاصناف المباعه")) shiftReportType = "sold_items";
                    try {
                        const payloadData = JSON.parse(message.interactive.button_reply.id);
                        console.log("🔘 interactive parsed payload:", payloadData);
                        if (payloadData.shift_id) shiftNumber = String(payloadData.shift_id);
                    } catch (e) {
                        console.log("🔘 interactive button_reply id is not JSON:", e.message);
                    }
                }
                else if (message.type === "button") {
                    messageText = message.button.text.trim();
                    console.log("🔘 button text:", messageText);
                    console.log("🔘 button payload raw:", message.button.payload);
                    if (messageText.includes("تقرير مبيعات اليوم")) shiftReportType = "sales";
                    else if (messageText.includes("تقرير الاصناف المباعه")) shiftReportType = "sold_items";
                    try {
                        const payloadData = JSON.parse(message.button.payload);
                        console.log("🔘 button parsed payload:", payloadData);
                        if (payloadData.visitId) resultNumber = String(payloadData.visitId);
                        if (payloadData.shift_id) shiftNumber = String(payloadData.shift_id);
                    } catch (e) {
                        const raw = message.button.payload;
                        const match = /(\d+)$/.exec(raw);
                        if (match) shiftNumber = match[1];
                        console.log("🔘 button payload plain string:", raw, "→ shiftNumber:", shiftNumber);
                    }
                }
                else if (message.type === "image") {
                    messageText = "📷 صورة";
                    mediaUrl = await uploadMediaToStorage(message.image.id, "whatsapp_images", currentToken);
                }
                else if (message.type === "audio" || message.type === "voice") {
                    messageText = "🎤 رسالة صوتية";
                    mediaUrl = await uploadMediaToStorage(message.audio.id, "whatsapp_audio", currentToken);
                }

                // مرجع الدردشة (في مجلد الفرع المستلم فعلياً)
                const chatRef = currentConfigRef.collection("chats").doc(senderPhone);

                // حفظ بيانات الدردشة العامة في الفرع الصحيح (الرومي أو التميز)
                await chatRef.set({
                    'last_message': messageText || messageType,
                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                    'sender_phone': senderPhone,
                    'sender_name': senderName,
                    'unread_count': admin.firestore.FieldValue.increment(1)
                }, { merge: true });

                await chatRef.collection("messages").doc(message.id).set({
                    'message_body': messageText,
                    'type': 'received',
                    'message_type': messageType,
                    'media_url': mediaUrl,
                    'message_id': message.id,
                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                });

                // --- 4. إرسال النتائج والقالب الإضافي ---
                if (resultNumber !== "") {
                    const targetCollection = configData.target_collection;

                    if (targetCollection) {
                        const careDoc = await db.collection(targetCollection).doc(resultNumber).get();

                        if (careDoc.exists && careDoc.data().result_url) {
                            const data = careDoc.data();
                            try {
                                // إرسال ملف النتيجة (يخرج من نفس الرقم الذي استقبل الرسالة)
                                const fbResponse = await axios.post(
                                    `https://graph.facebook.com/v21.0/${incomingPhoneNumberId}/messages`,
                                    {
                                        "messaging_product": "whatsapp",
                                        "to": senderPhone,
                                        "type": "document",
                                        "document": { "link": data.result_url, "filename": `Result_${resultNumber}.pdf` }
                                    },
                                    { headers: { 'Authorization': `Bearer ${currentToken}` } }
                                );

                                const botMsgId = fbResponse.data.messages[0].id;
                                const botMsgBody = `تم إرسال ملف النتائج رقم: ${resultNumber}`;

                                await chatRef.collection("messages").doc(botMsgId).set({
                                    'message_body': botMsgBody,
                                    'type': 'sent',
                                    'message_id': botMsgId,
                                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                                    'is_bot': true
                                });

                                await chatRef.update({
                                    'last_message': botMsgBody,
                                    'timestamp': admin.firestore.FieldValue.serverTimestamp()
                                });

                            } catch (err) {
                                console.error("❌ Send Error:", err.response?.data || err.message);
                            }
                        }
                    }
                }
                // --- 5. إرسال تقارير الوردية ---
                console.log("📊 shiftReportType:", shiftReportType, "| shiftNumber:", shiftNumber);
                if (shiftReportType && shiftNumber) {
                    try {
                        const shiftDoc = await db.collection("pharmacies").doc("lifcare")
                            .collection("shifts").doc(shiftNumber).get();
                        console.log("📊 shiftDoc exists:", shiftDoc.exists);

                        if (shiftDoc.exists) {
                            const shiftData = shiftDoc.data();
                            const pdfField = shiftReportType === "sales" ? "pdf_url" : "sold_items_pdf_url";
                            const pdfUrl = shiftData[pdfField];

                            if (pdfUrl) {
                                const reportName = shiftReportType === "sales"
                                    ? `sales_shift_${shiftNumber}.pdf`
                                    : `sold_items_shift_${shiftNumber}.pdf`;

                                const fbResponse = await axios.post(
                                    `https://graph.facebook.com/v21.0/${incomingPhoneNumberId}/messages`,
                                    {
                                        "messaging_product": "whatsapp",
                                        "to": senderPhone,
                                        "type": "document",
                                        "document": { "link": pdfUrl, "filename": reportName }
                                    },
                                    { headers: { 'Authorization': `Bearer ${currentToken}` } }
                                );

                                const botMsgId = fbResponse.data.messages[0].id;
                                const botMsgBody = shiftReportType === "sales"
                                    ? `📊 تم إرسال تقرير مبيعات الوردية رقم: ${shiftNumber}`
                                    : `📋 تم إرسال تقرير الأصناف المباعة للوردية رقم: ${shiftNumber}`;

                                await chatRef.collection("messages").doc(botMsgId).set({
                                    'message_body': botMsgBody,
                                    'type': 'sent',
                                    'message_id': botMsgId,
                                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                                    'is_bot': true
                                });

                                await chatRef.update({
                                    'last_message': botMsgBody,
                                    'timestamp': admin.firestore.FieldValue.serverTimestamp()
                                });
                            } else {
                                console.log(`⚠️ Field ${pdfField} not found in shift ${shiftNumber}`);
                            }
                        } else {
                            console.log(`⚠️ Shift document ${shiftNumber} not found`);
                        }
                    } catch (err) {
                        console.error("❌ Shift Report Error:", err.response?.data || err.message);
                    }
                }
            }
            return res.sendStatus(200);
        } catch (error) {
            console.error("❌ Global Error:", error.message);
            return res.sendStatus(200);
        }
    }
    res.sendStatus(405);
});