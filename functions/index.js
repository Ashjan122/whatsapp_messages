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

            if (body.object === "whatsapp_business_account" && 
                body.entry?.[0]?.changes?.[0]?.value?.messages?.[0]) {
                
                const value = body.entry[0].changes[0].value;
                const message = value.messages[0];
                const contact = value.contacts[0];
                const metadata = value.metadata;

                const senderPhone = message.from; 
                const incomingPhoneNumberId = metadata.phone_number_id; 
                
                // متغيرات لاستخراج المحتوى ورقم البحث
                let messageText = "";
                let resultNumber = "";

                // --- استخراج البيانات بناءً على نوع الرسالة ---
                if (message.type === "text") {
                    messageText = message.text.body.trim();
                    // إذا كان النص أرقاماً فقط، نعتبره رقم نتيجة
                    if (/^\d+$/.test(messageText)) {
                        resultNumber = messageText;
                    }
                } 
                else if (message.type === "button") {
                    messageText = message.button.text; // نص الزر ليظهر في سجل المحادثات
                    try {
                        // قراءة الـ visitId من الـ payload المرسل في القالب
                        const payloadData = JSON.parse(message.button.payload);
                        resultNumber = String(payloadData.visitId);
                    } catch (e) {
                        console.error("❌ Error parsing payload:", e);
                    }
                }

                // البحث عن إعدادات الواتساب لتحديد المستند الرئيسي
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

                // حفظ الرسالة المستلمة في Firestore
                await chatRef.set({
                    'last_message': messageText || "📄 وسائط",
                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                    'sender_phone': senderPhone,
                    'sender_name': contact.profile.name || "Unknown"
                }, { merge: true });

                await chatRef.collection("messages").add({
                    'message_body': messageText || "📄 وسائط",
                    'type': 'received',
                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                });

                // --- تنفيذ البحث إذا توفر رقم نتيجة (من نص أو زر) ---
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

                                await axios.post(
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

                                const successMsg = `تم إرسال ملف النتائج رقم: ${resultNumber}`;
                                await chatRef.collection("messages").add({
                                    'message_body': successMsg,
                                    'type': 'sent', 
                                    'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                                    'is_bot': true 
                                });
                                await chatRef.update({ 'last_message': successMsg });
                            }
                        } else {
                            // إرسال رد "لا توجد نتيجة"
                            const errorMsg = `عذراً، لا توجد نتيجة مسجلة بالرقم: ${resultNumber}`;
                            
                            await axios.post(
                                `https://graph.facebook.com/v25.0/${incomingPhoneNumberId}/messages`,
                                {
                                    "messaging_product": "whatsapp",
                                    "to": senderPhone,
                                    "type": "text",
                                    "text": { "body": errorMsg }
                                },
                                { headers: { 'Authorization': `Bearer ${WHATSAPP_TOKEN}` } }
                            );

                            await chatRef.collection("messages").add({
                                'message_body': errorMsg,
                                'type': 'sent', 
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