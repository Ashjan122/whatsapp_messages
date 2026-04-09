import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatDetailScreen extends StatefulWidget {
  final String phoneNumber;
  final String configId;
  final String? receiverName;

  const ChatDetailScreen({
    super.key,
    required this.phoneNumber,
    required this.configId,
    this.receiverName,
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

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      accessToken = prefs.getString('TOKEN');
      phoneNumberId = prefs.getString('PHONE_NUMBER_ID');
      wabaId = prefs.getString('WABA_ID');
    });
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "...";
    DateTime date = timestamp.toDate();
    return DateFormat('h:mm a').format(date);
  }

  Widget _buildStatusIcon(String? status) {
    switch (status) {
      case 'sent':
        return const Icon(Icons.done, size: 14, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 14, color: Colors.grey);
      case 'read':
        return const Icon(Icons.done_all, size: 14, color: Colors.blue);
      default:
        return const Icon(Icons.access_time, size: 12, color: Colors.grey);
    }
  }

  Future<List<Map<String, dynamic>>> fetchMetaTemplates() async {
    if (accessToken == null || wabaId == null) return [];
    final url = Uri.parse(
      'https://graph.facebook.com/v18.0/$wabaId/message_templates?fields=name,status,components,language',
    );
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List allTemplates = data['data'];
        return allTemplates.where((t) => t['status'] == 'APPROVED').map((t) {
          var body = (t['components'] as List).firstWhere(
            (c) => c['type'] == 'BODY',
            orElse: () => {'text': ''},
          );
          return {
            'name': t['name'],
            'body': body['text'],
            'language': t['language'],
          };
        }).toList();
      }
    } catch (e) {
      print("❌ Error fetching templates: $e");
    }
    return [];
  }

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
        final responseData = json.decode(response.body);
        final String messageId = responseData['messages'][0]['id'];

        await _saveMessageToFirestore(text, 'sent', messageId);
        _messageController.clear();
      }
    } catch (e) {
      print("❌ Error sending message: $e");
    }
  }

  Future<void> _updateDisplayName(String newName) async {
    if (newName.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('whatsapp_config')
          .doc(widget.configId)
          .collection('chats')
          .doc(widget.phoneNumber)
          .update({'display_name': newName});

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("تم حفظ الاسم بنجاح")));
    } catch (e) {
      print("❌ Error updating name: $e");
    }
  }

  void _showSaveContactDialog() {
    final TextEditingController nameController = TextEditingController(
      text: widget.receiverName,
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("حفظ جهة الاتصال", textAlign: TextAlign.right),
          content: TextField(
            controller: nameController,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(hintText: "أدخل اسم الشخص"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "إلغاء",
                style: TextStyle(color: Color.fromARGB(255, 3, 145, 5)),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _updateDisplayName(nameController.text.trim());
                Navigator.pop(context);
              },
              child: const Text(
                "حفظ",
                style: TextStyle(color: Color.fromARGB(255, 3, 145, 5)),
              ),
            ),
          ],
        );
      },
    );
  }

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
        final responseData = json.decode(response.body);
        final String messageId = responseData['messages'][0]['id'];
        await _saveMessageToFirestore(
          "📄 قالب: $templateName",
          'sent',
          messageId,
        );
      }
    } catch (e) {
      print("❌ Error sending template: $e");
    }
  }

  Future<void> _saveMessageToFirestore(
    String body,
    String type,
    String messageId,
  ) async {
    var chatRef = FirebaseFirestore.instance
        .collection('whatsapp_config')
        .doc(widget.configId)
        .collection('chats')
        .doc(widget.phoneNumber);

    await chatRef.set({
      'last_message': body,
      'timestamp': FieldValue.serverTimestamp(),
      'sender_phone': widget.phoneNumber,
    }, SetOptions(merge: true));

    await chatRef.collection('messages').doc(messageId).set({
      'message_body': body,
      'type': type,
      'status': 'sent',
      'message_id': messageId,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (widget.receiverName != null && widget.receiverName!.isNotEmpty)
                  ? widget.receiverName!
                  : widget.phoneNumber,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.receiverName != null && widget.receiverName!.isNotEmpty)
              Text(
                widget.phoneNumber,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'save_contact') {
                _showSaveContactDialog();
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem<String>(
                  value: 'save_contact',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text("حفظ جهة الاتصال"),
                      SizedBox(width: 10),
                      Icon(
                        Icons.person_add_alt_1,
                        color: Color.fromARGB(255, 3, 145, 5),
                      ),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    FirebaseFirestore.instance
                        .collection('whatsapp_config')
                        .doc(widget.configId)
                        .collection('chats')
                        .doc(widget.phoneNumber)
                        .collection('messages')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final messages = snapshot.data!.docs;
                  if (messages.isEmpty)
                    return const Center(child: Text("لا توجد رسائل بعد"));

                  return ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      var data = messages[index].data() as Map<String, dynamic>;
                      bool isMe = data['type'] == 'sent';

                      return Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isMe ? const Color(0xFFDCF8C6) : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft:
                                  isMe
                                      ? const Radius.circular(12)
                                      : const Radius.circular(0),
                              bottomRight:
                                  isMe
                                      ? const Radius.circular(0)
                                      : const Radius.circular(12),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                data['message_body'] ?? '',
                                style: const TextStyle(fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatTime(
                                      data['timestamp'] as Timestamp?,
                                    ),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    _buildStatusIcon(data['status']),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: fetchMetaTemplates(),
            builder: (context, snapshot) {
              return PopupMenuButton<Map<String, dynamic>>(
                icon: const Icon(Icons.apps, color: Colors.blue),
                onSelected:
                    (temp) => sendTemplate(temp['name'], temp['language']),
                itemBuilder: (context) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return [
                      const PopupMenuItem(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ];
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return [const PopupMenuItem(child: Text("لا توجد قوالب"))];
                  }
                  return snapshot.data!
                      .map(
                        (temp) => PopupMenuItem<Map<String, dynamic>>(
                          value: temp,
                          child: ListTile(
                            title: Text(
                              temp['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              temp['body'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      )
                      .toList();
                },
              );
            },
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(25),
              ),
              child: TextField(
                controller: _messageController,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: "اكتب رسالة...",
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color.fromARGB(255, 3, 145, 5),
            radius: 22,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: () => sendReply(_messageController.text),
            ),
          ),
        ],
      ),
    );
  }
}
