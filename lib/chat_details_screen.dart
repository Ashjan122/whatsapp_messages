import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ChatDetailScreen extends StatefulWidget {
  final String phoneNumber;
  final String configId; // أضفنا هذا المتغير لاستلام الـ ID من الصفحة السابقة

  const ChatDetailScreen({
    super.key, 
    required this.phoneNumber, 
    required this.configId,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  String? accessToken;
  String? phoneNumberId;
  String? wabaId;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  /// تحميل الإعدادات من ذاكرة الهاتف
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      accessToken = prefs.getString('TOKEN');
      phoneNumberId = prefs.getString('PHONE_NUMBER_ID');
      wabaId = prefs.getString('WABA_ID');
    });
  }

  /// جلب القوالب المعتمدة مباشرة من Meta API
  Future<List<Map<String, dynamic>>> fetchMetaTemplates() async {
    if (accessToken == null || wabaId == null) return [];

    final url = Uri.parse(
      'https://graph.facebook.com/v18.0/$wabaId/message_templates?fields=name,status,components,language',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List allTemplates = data['data'];

        return allTemplates.where((t) => t['status'] == 'APPROVED').map((t) {
          var bodyComponent = (t['components'] as List).firstWhere(
            (c) => c['type'] == 'BODY',
            orElse: () => {'text': ''},
          );
          return {
            'name': t['name'],
            'body': bodyComponent['text'],
            'language': t['language'],
          };
        }).toList();
      }
    } catch (e) {
      print("❌ Error fetching templates: $e");
    }
    return [];
  }

  /// إرسال رسالة نصية عادية
  Future<void> sendReply(String text) async {
    if (text.isEmpty || accessToken == null || phoneNumberId == null) return;

    final url = Uri.parse(
      'https://graph.facebook.com/v18.0/$phoneNumberId/messages',
    );

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          "messaging_product": "whatsapp",
          "to": widget.phoneNumber,
          "type": "text",
          "text": {"body": text},
        }),
      );

      if (response.statusCode == 200) {
        await _saveMessageToFirestore(text, 'sent');
        _messageController.clear();
      }
    } catch (e) {
      print("❌ Error sending message: $e");
    }
  }

  /// إرسال قالب (Template)
  Future<void> sendTemplate(String templateName, String langCode) async {
    if (accessToken == null || phoneNumberId == null) return;

    final url = Uri.parse(
      'https://graph.facebook.com/v18.0/$phoneNumberId/messages',
    );

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          "messaging_product": "whatsapp",
          "to": widget.phoneNumber,
          "type": "template",
          "template": {
            "name": templateName,
            "language": {"code": langCode},
          },
        }),
      );

      if (response.statusCode == 200) {
        await _saveMessageToFirestore("📄 قالب: $templateName", 'sent');
      }
    } catch (e) {
      print("❌ Error sending template: $e");
    }
  }

  /// وظيفة مساعدة لحفظ الرسالة في Firestore (تم تعديل المسار هنا)
  Future<void> _saveMessageToFirestore(String body, String type) async {
    // المسار الجديد الذي يتبع الهيكلية المعتمدة
    var chatRef = FirebaseFirestore.instance
        .collection('whatsapp_config')
        .doc(widget.configId)
        .collection('chats')
        .doc(widget.phoneNumber);

    // تحديث بيانات المحادثة (آخر رسالة)
    await chatRef.set({
      'last_message': body,
      'timestamp': FieldValue.serverTimestamp(),
      'sender_phone': widget.phoneNumber,
    }, SetOptions(merge: true));

    // إضافة الرسالة إلى المجموعة الفرعية messages
    await chatRef.collection('messages').add({
      'message_body': body,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.phoneNumber),
        backgroundColor: Colors.grey[300],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // عرض الرسائل (تم تعديل مسار الـ Stream هنا أيضاً)
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('whatsapp_config')
                    .doc(widget.configId)
                    .collection('chats')
                    .doc(widget.phoneNumber)
                    .collection('messages')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final messages = snapshot.data!.docs;

                  if (messages.isEmpty) {
                    return const Center(child: Text("لا توجد رسائل بعد"));
                  }

                  return ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      var data = messages[index].data() as Map<String, dynamic>;
                      bool isSentByMe = data['type'] == 'sent';

                      return Align(
                        alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSentByMe ? Colors.green[100] : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 2),
                            ],
                          ),
                          child: Text(data['message_body'] ?? ''),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            
            // منطقة إرسال الرسائل والقوالب
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                children: [
                  // زر القوالب
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: fetchMetaTemplates(),
                    builder: (context, snapshot) {
                      return PopupMenuButton<Map<String, dynamic>>(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.grey),
                        onSelected: (temp) => sendTemplate(temp['name'], temp['language']),
                        itemBuilder: (context) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return [const PopupMenuItem(child: Center(child: CircularProgressIndicator()))];
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return [const PopupMenuItem(child: Text("لا توجد قوالب"))];
                          }
                          return snapshot.data!.map((temp) {
                            return PopupMenuItem<Map<String, dynamic>>(
                              value: temp,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(temp['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13)),
                                  Text(temp['body'], style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const Divider(),
                                ],
                              ),
                            );
                          }).toList();
                        },
                      );
                    },
                  ),

                  // حقل النص
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: "اكتب رسالة...",
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),

                  // زر الإرسال
                  IconButton(
                    icon: const Icon(Icons.send, color: Color.fromARGB(255, 3, 145, 5)),
                    onPressed: () => sendReply(_messageController.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}