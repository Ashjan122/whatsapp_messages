const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const axios = require("axios"); // لإرسال طلبات الـ API لميتا

if (admin.apps.length === 0) {
    admin.initializeApp();
}

const db = admin.firestore();

const VERIFY_TOKEN ="Alryyan12345#"; 
const WHATSAPP_TOKEN ="EAAapSj9k2sABRIVNLKtomho0lxjbXkH9JXm1Asgzosmz0x3nsOAlDdzRauNcJOgYNwUfXzRz5xCetT0SqgKZAeJZAD2h92NaUnrXWDOiFyjdZAaStoF1d36EPgwzAxZC6UmihhYyGZCyx2JdlDIBvpl2JTTvNFdTPYi215N0GiS2XhmoHULg9F6WK6iwd7ZBklXgZDZD"; // Permanent Access Token

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
                const phoneNumberId = metadata.phone_number_id; // معرف رقمك الرسمي
                const messageText = message.text ? message.text.body.trim() : "";

                const chatRef = db.collection("chats").doc(senderPhone);

                // 1️⃣ حفظ رسالة العميل في الفايرستور (كما هي في كودك)
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

                // 2️⃣ ذكاء البوت: البحث عن ملف PDF إذا كان النص المرسل عبارة عن رقم (ID)
                if (messageText !== "") {
                    const careDoc = await db.collection("one_care").doc(messageText).get();

                    if (careDoc.exists) {
                        const data = careDoc.data();
                        if (data.result_url) {
                            const pdfUrl = data.result_url;

                            // أ- إرسال الملف للعميل على واتساب
                            await axios.post(
                                `https://graph.facebook.com/v18.0/${phoneNumberId}/messages`,
                                {
                                    "messaging_product": "whatsapp",
                                    "to": senderPhone,
                                    "type": "document",
                                    "document": {
                                        "link": pdfUrl,
                                        "filename": `Result_${messageText}.pdf`
                                    }
                                },
                                { headers: { 'Authorization': `Bearer ${WHATSAPP_TOKEN}` } }
                            );

                            // ب- تسجيل أن البوت أرسل ملف في محادثات التطبيق (ليراها الموظف)
                            const replyText = `📄 تم إرسال ملف النتائج رقم: ${messageText}`;
                            await chatRef.collection("messages").add({
                                'message_body': replyText,
                                'type': 'sent', // ستظهر باللون الأخضر في تطبيقك كأنها رد
                                'timestamp': admin.firestore.FieldValue.serverTimestamp(),
                                'is_bot': true // علامة اختيارية لتعرف أن البوت هو من أرسل
                            });

                            await chatRef.update({ 'last_message': replyText });
                        }
                    }
                }
            }
            return res.sendStatus(200);
        } catch (error) {
            console.error("❌ Error:", error);
            return res.sendStatus(200); // نرسل 200 دائماً لميتا لتجنب تكرار المحاولة
        }
    }
    res.sendStatus(405);
});