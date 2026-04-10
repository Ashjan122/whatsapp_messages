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
const WHATSAPP_TOKEN = "EAAapSj9k2sABRIVNLKtomho0lxjbXkH9JXm1Asgzosmz0x3nsOAlDdzRauNcJOgYNwUfXzRz5xCetT0SqgKZAeJZAD2h92NaUnrXWDOiFyjdZAaStoF1d36EPgwzAxZC6UmihhYyGZCyx2JdlDIBvpl2JTTvNFdTPYi215N0GiS2XhmoHULg9F6WK6iwd7ZBklXgZDZD"; 

/**
 * دالة لتحميل الوسائط من واتساب ورفعها إلى Firebase Storage
 */
async function uploadMediaToStorage(mediaId, folderName) {
    try {
        const getUrlResponse = await axios.get(`https://graph.facebook.com/v21.0/${mediaId}`, {
            headers: { 'Authorization': `Bearer ${WHATSAPP_TOKEN}` }
        });
        const whatsappMediaUrl = getUrlResponse.data.url;
        const mimeType = getUrlResponse.data.mime_type;
        const extension = mimeType.split('/')[1] || 'bin';

        const mediaResponse = await axios.get(whatsappMediaUrl, {
            headers: { 'Authorization': `Bearer ${WHATSAPP_TOKEN}` },
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

            // --- معالجة تحديثات الحالة ---
            if (value.statuses && value.statuses[0]) {
                const statusUpdate = value.statuses[0];
                const messageId = statusUpdate.id;
                const newStatus = statusUpdate.status;
                const recipientId = statusUpdate.recipient_id;

                const incomingPhoneNumberId = value.metadata.phone_number_id;
                const configQuery = await db.collection("whatsapp_config")
                    .where("PHONE_NUMBER_ID", "==", incomingPhoneNumberId)
                    .limit(1).get();

                if (!configQuery.empty) {
                    const configDocId = configQuery.docs[0].id;
                    await db.collection("whatsapp_config").doc(configDocId)
                        .collection("chats").doc(recipientId)
                        .collection("messages").doc(messageId)
                        .update({ status: newStatus })
                        .catch(() => {});
                }
            }

            // --- معالجة الرسائل الواردة ---
            if (value.messages && value.messages[0]) {
                const message = value.messages[0];
                const contact = value.contacts?.[0];
                const senderPhone = message.from; 
                const incomingPhoneNumberId = value.metadata.phone_number_id; 
                
                let messageText = "";
                let resultNumber = "";
                let mediaUrl = null;
                let messageType = message.type;

                if (message.type === "text") {
                    messageText = message.text.body.trim();
                    if (/^\d+$/.test(messageText)) resultNumber = messageText;
                } 
                else if (message.type === "button") {
                    messageText = message.button.text; 
                    try {
                        const payloadData = JSON.parse(message.button.payload);
                        resultNumber = String(payloadData.visitId);
                    } catch (e) {}
                }
                else if (message.type === "image") {
                    messageText = "📷 صورة";
                    mediaUrl = await uploadMediaToStorage(message.image.id, "whatsapp_images");
                }
                else if (message.type === "audio" || message.type === "voice") {
                    messageText = "🎤 رسالة صوتية";
                    mediaUrl = await uploadMediaToStorage(message.audio.id, "whatsapp_audio");
                }

                const configQuery = await db.collection("whatsapp_config")
                    .where("PHONE_NUMBER_ID", "==", incomingPhoneNumberId)
                    .limit(1).get();

                if (configQuery.empty) return res.sendStatus(200);

                const configDocId = configQuery.docs[0].id; 
                const chatRef = db.collection("whatsapp_config").doc(configDocId)
                    .collection("chats").doc(senderPhone);

                // حفظ رسالة المستخدم وتحديث last_message للمستلم
                await chatRef.set({
                    'last_message': messageText,
                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                    'sender_phone': senderPhone,
                    'sender_name': (contact && contact.profile) ? contact.profile.name : "Unknown"
                }, { merge: true });

                await chatRef.collection("messages").doc(message.id).set({
                    'message_body': messageText,
                    'type': 'received',
                    'message_type': messageType,
                    'media_url': mediaUrl,
                    'message_id': message.id,
                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                });

                // --- منطق إرسال النتائج تلقائياً وتحديث "لاست مسج" ---
                if (resultNumber !== "") {
                    let targetCollection = "";
                    if (incomingPhoneNumberId === "1151556284697196") targetCollection = "alroomi";
                    else if (incomingPhoneNumberId === "1114284988426114") targetCollection = "altohami";

                    if (targetCollection !== "") {
                        const careDoc = await db.collection(targetCollection).doc(resultNumber).get();
                        if (careDoc.exists) {
                            const data = careDoc.data();
                            if (data.result_url) {
                                const fbResponse = await axios.post(
                                    `https://graph.facebook.com/v21.0/${incomingPhoneNumberId}/messages`,
                                    {
                                        "messaging_product": "whatsapp",
                                        "to": senderPhone,
                                        "type": "document",
                                        "document": { "link": data.result_url, "filename": `Result_${resultNumber}.pdf` }
                                    },
                                    { headers: { 'Authorization': `Bearer ${WHATSAPP_TOKEN}` } }
                                );

                                const botMsgId = fbResponse.data.messages[0].id;
                                const botMsgBody = `تم إرسال ملف النتائج رقم: ${resultNumber}`;

                                // 1. حفظ في مجموعة الرسائل
                                await chatRef.collection("messages").doc(botMsgId).set({
                                    'message_body': botMsgBody,
                                    'type': 'sent', 
                                    'status': 'sent', 
                                    'message_id': botMsgId,
                                    'timestamp': admin.firestore.FieldValue.serverTimestamp(), 
                                    'is_bot': true 
                                });

                                // 2. تحديث المستند الرئيسي (لاست مسج)
                                await chatRef.update({
                                    'last_message': botMsgBody,
                                    'timestamp': admin.firestore.FieldValue.serverTimestamp()
                                });
                            }
                        }
                    }
                }
            }
            return res.sendStatus(200);
        } catch (error) {
            console.error("❌ Error:", error.message);
            return res.sendStatus(200); 
        }
    }
    res.sendStatus(405);
});