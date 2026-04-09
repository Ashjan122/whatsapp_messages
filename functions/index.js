const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const axios = require("axios");

if (admin.apps.length === 0) {
    admin.initializeApp();
}

const db = admin.firestore();

const VERIFY_TOKEN = "Alryyan12345#"; 
const WHATSAPP_TOKEN = "EAAapSj9k2sABRIVNLKtomho0lxjbXkH9JXm1Asgzosmz0x3nsOAlDdzRauNcJOgYNwUfXzRz5xCetT0SqgKZAeJZAD2h92NaUnrXWDOiFyjdZAaStoF1d36EPgwzAxZC6UmihhYyGZCyx2JdlDIBvpl2JTTvNFdTPYi215N0GiS2XhmoHULg9F6WK6iwd7ZBklXgZDZD"; 

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

            // --- أولاً: معالجة تحديثات حالة الرسائل (علامات الصح) ---
            if (value.statuses && value.statuses[0]) {
                const statusUpdate = value.statuses[0];
                const messageId = statusUpdate.id; // wamid...
                const newStatus = statusUpdate.status; // delivered, read, etc.
                const recipientId = statusUpdate.recipient_id;

                // البحث عن المحادثة لتحديث حالة الرسالة بداخلها
                // ملاحظة: نحتاج configId، لذا سنبحث باستخدام الـ phone_number_id الخاص بـ Metadata
                const incomingPhoneNumberId = value.metadata.phone_number_id;
                const configQuery = await db.collection("whatsapp_config")
                    .where("PHONE_NUMBER_ID", "==", incomingPhoneNumberId)
                    .limit(1)
                    .get();

                if (!configQuery.empty) {
                    const configDocId = configQuery.docs[0].id;
                    await db.collection("whatsapp_config")
                        .doc(configDocId)
                        .collection("chats")
                        .doc(recipientId)
                        .collection("messages")
                        .doc(messageId) // نستخدم المعرف كـ Document ID
                        .update({ status: newStatus })
                        .catch(err => console.log("Message doc not found for status update, skipping."));
                }
            }

            // --- ثانياً: معالجة الرسائل الواردة (المنطق الحالي) ---
            if (value.messages && value.messages[0]) {
                const message = value.messages[0];
                const contact = value.contacts?.[0];
                const metadata = value.metadata;

                const senderPhone = message.from; 
                const incomingPhoneNumberId = metadata.phone_number_id; 
                
                let messageText = "";
                let resultNumber = "";

                if (message.type === "text") {
                    messageText = message.text.body.trim();
                    if (/^\d+$/.test(messageText)) {
                        resultNumber = messageText;
                    }
                } 
                else if (message.type === "button") {
                    messageText = message.button.text; 
                    try {
                        const payloadData = JSON.parse(message.button.payload);
                        resultNumber = String(payloadData.visitId);
                    } catch (e) {
                        console.error("❌ Error parsing payload:", e);
                    }
                }

                const configQuery = await db.collection("whatsapp_config")
                    .where("PHONE_NUMBER_ID", "==", incomingPhoneNumberId)
                    .limit(1)
                    .get();

                if (configQuery.empty) return res.sendStatus(200);

                const configDocId = configQuery.docs[0].id; 
                const chatRef = db.collection("whatsapp_config")
                    .doc(configDocId)
                    .collection("chats")
                    .doc(senderPhone);

                await chatRef.set({
                    'last_message': messageText || "📄 وسائط",
                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                    'sender_phone': senderPhone,
                    'sender_name': (contact && contact.profile) ? contact.profile.name : "Unknown"
                }, { merge: true });

                // حفظ الرسالة المستلمة (باستخدام ID واتساب للرسالة الواردة أيضاً)
                await chatRef.collection("messages").doc(message.id).set({
                    'message_body': messageText || "📄 وسائط",
                    'type': 'received',
                    'message_id': message.id,
                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                });

                if (resultNumber !== "") {
                    let targetCollection = "";
                    if (incomingPhoneNumberId === "1151556284697196") {
                        targetCollection = "alroomi";
                    } else if (incomingPhoneNumberId === "1114284988426114") {
                        targetCollection = "altohami";
                    }

                    if (targetCollection !== "") {
                        const careDoc = await db.collection(targetCollection).doc(resultNumber).get();

                        if (careDoc.exists) {
                            const data = careDoc.data();
                            if (data.result_url) {
                                const pdfUrl = data.result_url;

                                const fbResponse = await axios.post(
                                    `https://graph.facebook.com/v25.0/${incomingPhoneNumberId}/messages`,
                                    {
                                        "messaging_product": "whatsapp",
                                        "to": senderPhone,
                                        "type": "document",
                                        "document": {
                                            "link": pdfUrl,
                                            "filename": `Result_${resultNumber}.pdf`
                                        }
                                    },
                                    { headers: { 'Authorization': `Bearer ${WHATSAPP_TOKEN}` } }
                                );

                                // حفظ رد البوت التلقائي مع المعرف الخاص به لتتبع حالته
                                const botMsgId = fbResponse.data.messages[0].id;
                                const successMsg = `تم إرسال ملف النتائج رقم: ${resultNumber}`;
                                
                                await chatRef.collection("messages").doc(botMsgId).set({
                                    'message_body': successMsg,
                                    'type': 'sent', 
                                    'status': 'sent',
                                    'message_id': botMsgId,
                                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                                    'is_bot': true 
                                });
                                await chatRef.update({ 'last_message': successMsg });
                            }
                        } else {
                            const errorMsg = `عذراً، لا توجد نتيجة مسجلة بالرقم: ${resultNumber}`;
                            
                            const fbResponse = await axios.post(
                                `https://graph.facebook.com/v25.0/${incomingPhoneNumberId}/messages`,
                                {
                                    "messaging_product": "whatsapp",
                                    "to": senderPhone,
                                    "type": "text",
                                    "text": { "body": errorMsg }
                                },
                                { headers: { 'Authorization': `Bearer ${WHATSAPP_TOKEN}` } }
                            );

                            const botMsgId = fbResponse.data.messages[0].id;
                            await chatRef.collection("messages").doc(botMsgId).set({
                                'message_body': errorMsg,
                                'type': 'sent', 
                                'status': 'sent',
                                'message_id': botMsgId,
                                'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                                'is_bot': true 
                            });
                            await chatRef.update({ 'last_message': errorMsg });
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