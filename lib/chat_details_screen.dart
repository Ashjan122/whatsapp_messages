import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart'; // مكتبة الصوت
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

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
  bool isLoading = true;
  String? targetCollection;
  Map<String, dynamic>? patientData;
  bool isSearchingResult = true;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> loadSettings() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      accessToken = prefs.getString('TOKEN');
      phoneNumberId = prefs.getString('PHONE_NUMBER_ID');
      wabaId = prefs.getString('WABA_ID');
      targetCollection = prefs.getString('TARGET_COLLECTION');
      isLoading = false;
    });
    await Future.wait([searchPatientResult(), _markChatAsRead()]);
  }

  Future<void> _markChatAsRead() async {
    await FirebaseFirestore.instance
        .collection('whatsapp_config')
        .doc(widget.configId)
        .collection('chats')
        .doc(widget.phoneNumber)
        .update({'unread_count': 0})
        .catchError((_) {});
  }

  Future<String?> uploadMedia(File file) async {
    if (accessToken == null || phoneNumberId == null) return null;

    final uri = Uri.parse(
      'https://graph.facebook.com/v18.0/$phoneNumberId/media',
    );

    var request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $accessToken';

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: http.MediaType('application', 'pdf'),
      ),
    );

    request.fields['messaging_product'] = 'whatsapp';

    final response = await request.send();
    final resBody = await http.Response.fromStream(response);

    if (response.statusCode == 200) {
      final data = json.decode(resBody.body);
      return data['id']; // ده media_id
    } else {
      print(resBody.body);
      return null;
    }
  }

  Future<void> sendDocument(File file, String caption) async {
    final mediaId = await uploadMedia(file);
    if (mediaId == null) return;

    final url = Uri.parse(
      'https://graph.facebook.com/v18.0/$phoneNumberId/messages',
    );

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        "messaging_product": "whatsapp",
        "to": widget.phoneNumber,
        "type": "document",
        "document": {
          "id": mediaId,
          "caption": caption,
          "filename": "result.pdf",
        },
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final messageId = data['messages'][0]['id'];

      // ⭐ مهم: حفظ الرسالة في الشات
      await _saveMessageToFirestore(
        "تم إرسال النتيجة بنجاح",
        "sent",
        messageId,
        "document",
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("تم إرسال النتيجة بنجاح")));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("فشل إرسال النتيجة")));
    }
  }

  Future<void> searchPatientResult() async {
    if (targetCollection == null) {
      setState(() => isSearchingResult = false);
      return;
    }

    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection(targetCollection!)
              .where('patient_phone', isEqualTo: widget.phoneNumber)
              .limit(1)
              .get();

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          patientData = snapshot.docs.first.data();
        });
      }
    } catch (e) {
      print("❌ Error searching result: $e");
    }

    setState(() => isSearchingResult = false);
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "...";
    DateTime date = timestamp.toDate();
    return intl.DateFormat('h:mm a').format(date);
  }

  String _getDividerDate(Timestamp? timestamp) {
    if (timestamp == null) return "";
    DateTime date = timestamp.toDate();
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime yesterday = today.subtract(const Duration(days: 1));
    DateTime messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) return "اليوم";
    if (messageDate == yesterday) return "أمس";
    return intl.DateFormat('yyyy/MM/dd', 'ar').format(date);
  }

  Widget _buildStatusIcon(String? status) {
    switch (status) {
      case 'sent':
        return const Icon(Icons.done, size: 14, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 14, color: Colors.grey);
      case 'read':
        return const Icon(Icons.done_all, size: 14, color: Colors.blue);
      case 'pending': // الحالة الجديدة أثناء الإرسال
        return const Icon(Icons.access_time, size: 12, color: Colors.grey);
      case 'failed':
        return const Icon(Icons.error_outline, size: 14, color: Colors.red);
      default:
        return const Icon(Icons.access_time, size: 12, color: Colors.grey);
    }
  }

  Widget _buildMessageContent(Map<String, dynamic> data) {
    String type = data['message_type'] ?? 'text';
    String? mediaUrl = data['media_url'];

    if (type == 'image' && mediaUrl != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImagePreviewScreen(imageUrl: mediaUrl),
                  ),
                ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Hero(
                tag: mediaUrl,
                child: CachedNetworkImage(
                  imageUrl: mediaUrl,
                  width: 200,
                  placeholder:
                      (_, __) => Container(
                        width: 200,
                        height: 150,
                        color: Colors.grey[300],
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                  errorWidget:
                      (_, __, ___) => const Icon(Icons.broken_image, size: 50),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          if (data['message_body'] != "📷 صورة") ...[
            const SizedBox(height: 5),
            Text(data['message_body'], style: const TextStyle(fontSize: 15)),
          ],
        ],
      );
    }
    // تعديل قسم الصوت ليدعم التشغيل الفعلي
    else if ((type == 'audio' || type == 'voice') && mediaUrl != null) {
      return SizedBox(
        width: MediaQuery.of(context).size.width * 0.65, // تحديد عرض شريط الصوت
        child: VoiceMessagePlayer(url: mediaUrl),
      );
    } else {
      return Text(
        data['message_body'] ?? '',
        style: const TextStyle(fontSize: 15),
      );
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
      print("Error: $e");
    }
    return [];
  }

  Future<void> sendReply(String text) async {
    if (text.isEmpty || accessToken == null || phoneNumberId == null) return;

    final String tempMessageId =
        "temp_${DateTime.now().millisecondsSinceEpoch}";
    final String messageText = text;
    _messageController.clear(); // مسح الحقل فوراً لراحة المستخدم

    // 1. إضافة الرسالة محلياً (في Firestore) بحالة "pending" لتظهر فوراً
    await _saveMessageLocally(messageText, tempMessageId);

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
          "text": {"body": messageText},
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String officialMessageId = data['messages'][0]['id'];

        // 2. تحديث الرسالة بالمعرف الرسمي وحالة "sent" بعد نجاح الإرسال
        await _finalizeMessageStatus(
          tempMessageId,
          officialMessageId,
          messageText,
        );
      } else {
        await _updateMessageStatus(
          tempMessageId,
          'failed',
          errorReason: _parseErrorReason(response.body),
        );
      }
    } catch (e) {
      print("Error sending message: $e");
      await _updateMessageStatus(
        tempMessageId,
        'failed',
        errorReason: 'لا يوجد اتصال بالإنترنت',
      );
    }
  }

  // لحفظ الرسالة فور النقر على زر الإرسال
  Future<void> _saveMessageLocally(String body, String tempId) async {
    var chatRef = FirebaseFirestore.instance
        .collection('whatsapp_config')
        .doc(widget.configId)
        .collection('chats')
        .doc(widget.phoneNumber);

    // تحديث المحادثة الرئيسية (آخر رسالة)
    await chatRef.set({
      'last_message': body,
      'timestamp': FieldValue.serverTimestamp(),
      'sender_phone': widget.phoneNumber,
    }, SetOptions(merge: true));

    // إضافة الرسالة في المجموعة الفرعية بحالة انتظار
    await chatRef.collection('messages').doc(tempId).set({
      'message_body': body,
      'type': 'sent', // لأن المستخدم هو من أرسلها
      'message_type': 'text',
      'status': 'pending', // الحالة التي ستظهر "الساعة"
      'message_id': tempId,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // لاستبدال المعرف المؤقت بالرسمي وتحديث الحالة
  Future<void> _finalizeMessageStatus(
    String tempId,
    String officialId,
    String body,
  ) async {
    var chatRef = FirebaseFirestore.instance
        .collection('whatsapp_config')
        .doc(widget.configId)
        .collection('chats')
        .doc(widget.phoneNumber);

    // حذف الرسالة المؤقتة وإضافة الرسمية أو عمل تحديث شامل
    WriteBatch batch = FirebaseFirestore.instance.batch();

    batch.delete(chatRef.collection('messages').doc(tempId));
    batch.set(chatRef.collection('messages').doc(officialId), {
      'message_body': body,
      'type': 'sent',
      'message_type': 'text',
      'status': 'sent',
      'message_id': officialId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // لتحديث الحالة فقط (في حال الفشل مثلاً)
  Future<void> _updateMessageStatus(
    String id,
    String status, {
    String? errorReason,
  }) async {
    final Map<String, dynamic> updates = {'status': status};
    if (errorReason != null) updates['error_reason'] = errorReason;
    await FirebaseFirestore.instance
        .collection('whatsapp_config')
        .doc(widget.configId)
        .collection('chats')
        .doc(widget.phoneNumber)
        .collection('messages')
        .doc(id)
        .update(updates);
  }

  String _parseErrorReason(String responseBody) {
    try {
      final data = json.decode(responseBody);
      final error = data['error'];
      if (error != null) {
        final code = error['code'];
        if (code == 131047) return 'انتهت نافذة الـ 24 ساعة';
      }
    } catch (_) {}
    return 'فشل الإرسال';
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
      print("Error: $e");
    }
  }

  void _showSaveContactDialog() {
    final nameController = TextEditingController(text: widget.receiverName);
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("حفظ جهة الاتصال", textAlign: TextAlign.right),
            content: TextField(
              controller: nameController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(hintText: "أدخل اسم الشخص"),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "إلغاء",
                  style: TextStyle(color: Color(0xFF039105)),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  _updateDisplayName(nameController.text.trim());
                  Navigator.pop(context);
                },
                child: const Text(
                  "حفظ",
                  style: TextStyle(color: Color(0xFF039105)),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildDateDivider(Timestamp? timestamp) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blueGrey[50], // لون خفيف خلف التاريخ
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _getDividerDate(
              timestamp,
            ), // تستدعي الدالة التي ترجع "اليوم" أو "أمس"
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getAllResults() async {
    if (targetCollection == null) return [];

    final snapshot =
        await FirebaseFirestore.instance
            .collection(targetCollection!)
            .where('patient_phone', isEqualTo: widget.phoneNumber)
            .orderBy('created_at', descending: true)
            .get();

    return snapshot.docs.map((e) => e.data()).toList();
  }

  void _showResultsDialog() async {
    final phone = widget.phoneNumber;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const Center(child: CircularProgressIndicator());
      },
    );

    final results = await _getAllResults();

    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              "نتائج $phone",
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child:
                  results.isEmpty
                      ? const Text(
                        "لا توجد نتائج لهذا الرقم",
                        textAlign: TextAlign.center,
                      )
                      : ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = results[index];

                          final name = item['patient_name'] ?? "بدون اسم";
                          final url = item['result_url'];
                          final createdAt = item['created_at'] as Timestamp?;

                          String dateText = "";
                          if (createdAt != null) {
                            dateText = intl.DateFormat(
                              'yyyy/MM/dd – hh:mm a',
                            ).format(createdAt.toDate());
                          }

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              title: Text(
                                name,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                dateText,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 👁 عرض (صغير)
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.visibility,
                                        color: Colors.black87,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) =>
                                                    ResultPdfScreen(url: url),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                  const SizedBox(width: 6),

                                  // 📤 إرسال (صغير)
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF039105,
                                      ).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.send_rounded,
                                        color: Color(0xFF039105),
                                        size: 18,
                                      ),
                                      onPressed: () async {
                                        Navigator.pop(context);

                                        final response = await http.get(
                                          Uri.parse(url),
                                        );
                                        final dir =
                                            await getTemporaryDirectory();
                                        final file = File(
                                          '${dir.path}/result.pdf',
                                        );

                                        await file.writeAsBytes(
                                          response.bodyBytes,
                                        );

                                        await sendDocument(file, " result pdf");
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ),
        );
      },
    );
  }

  Future<void> sendTemplate(String templateName, String langCode) async {
    if (accessToken == null || phoneNumberId == null) return;
    setState(() => isLoading = true);
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
        final data = json.decode(response.body);
        await _saveMessageToFirestore(
          "📄 قالب: $templateName",
          'sent',
          data['messages'][0]['id'],
          'template',
        );
      }
    } catch (e) {
      print("Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _saveMessageToFirestore(
    String body,
    String type,
    String messageId,
    String messageType,
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
      'message_type': messageType,
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
              (widget.receiverName?.isNotEmpty == true)
                  ? widget.receiverName!
                  : widget.phoneNumber,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.receiverName?.isNotEmpty == true)
              Text(
                widget.phoneNumber,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          // 👇 زر النتيجة (لو موجودة)
          if (patientData != null && patientData!['result_url'] != null)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.black),
              tooltip: patientData!['patient_name'] ?? "عرض النتيجة",
              onPressed: _showResultsDialog,
            ),

          // القائمة الأساسية
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'save_contact') _showSaveContactDialog();
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'save_contact',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text("حفظ جهة الاتصال"),
                        SizedBox(width: 10),
                        Icon(Icons.person_add_alt_1, color: Color(0xFF039105)),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (isLoading)
              const LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF039105)),
                minHeight: 3,
              ),
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
                  return ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      var data = messages[index].data() as Map<String, dynamic>;
                      bool isMe = data['type'] == 'sent';
                      Timestamp? ts = data['timestamp'] as Timestamp?;

                      // --- منطق فاصل التاريخ ---
                      bool showDateDivider = false;
                      if (ts != null) {
                        if (index == messages.length - 1) {
                          // أول رسالة في المحادثة (التي تكون في نهاية القائمة لأنها الأقدم)
                          showDateDivider = true;
                        } else {
                          // قارن تاريخ الرسالة الحالية بالرسالة "السابقة" زمنياً (التي تليها في الـ index)
                          var nextData =
                              messages[index + 1].data()
                                  as Map<String, dynamic>;
                          Timestamp? nextTs =
                              nextData['timestamp'] as Timestamp?;

                          if (nextTs != null) {
                            DateTime date1 = ts.toDate();
                            DateTime date2 = nextTs.toDate();
                            // إذا كان اليوم أو الشهر أو السنة مختلفين، أظهر الفاصل
                            if (date1.year != date2.year ||
                                date1.month != date2.month ||
                                date1.day != date2.day) {
                              showDateDivider = true;
                            }
                          }
                        }
                      }

                      return Column(
                        children: [
                          if (showDateDivider)
                            _buildDateDivider(ts), // إضافة الفاصل هنا
                          Align(
                            alignment:
                                isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                            child: Container(
                              // ... (باقي كود الحاوية الخاص بالرسالة كما هو)
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isMe
                                        ? const Color(0xFFDCF8C6)
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _buildMessageContent(data),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatTime(ts),
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
                                  if (data['status'] == 'failed' &&
                                      data['error_reason'] != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      data['error_reason'],
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
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
      padding: const EdgeInsets.all(8),
      color: Colors.white,
      child: Row(
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: fetchMetaTemplates(),
            builder:
                (context, snapshot) => PopupMenuButton<Map<String, dynamic>>(
                  icon: const Icon(Icons.apps, color: Colors.blue),
                  onSelected:
                      (temp) => sendTemplate(temp['name'], temp['language']),
                  itemBuilder: (context) {
                    if (!snapshot.hasData)
                      return [
                        const PopupMenuItem(child: Text("جاري التحميل...")),
                      ];
                    return snapshot.data!
                        .map(
                          (temp) => PopupMenuItem(
                            value: temp,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  temp['name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                if (temp['body'] != null &&
                                    (temp['body'] as String).isNotEmpty)
                                  Text(
                                    temp['body'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        )
                        .toList();
                  },
                ),
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: "اكتب رسالة...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                fillColor: Colors.grey[100],
                filled: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF039105),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: () => sendReply(_messageController.text),
            ),
          ),
        ],
      ),
    );
  }
}

class ImagePreviewScreen extends StatelessWidget {
  final String imageUrl;
  const ImagePreviewScreen({super.key, required this.imageUrl});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(child: CachedNetworkImage(imageUrl: imageUrl)),
      ),
    );
  }
}

class VoiceMessagePlayer extends StatefulWidget {
  final String url;
  const VoiceMessagePlayer({super.key, required this.url});

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool isPlaying = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => isPlaying = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((newDuration) {
      if (mounted) setState(() => duration = newDuration);
    });
    _player.onPositionChanged.listen((newPosition) {
      if (mounted) setState(() => position = newPosition);
    });
    _player.onPlayerComplete.listen((event) {
      if (mounted)
        setState(() {
          position = Duration.zero;
          isPlaying = false;
        });
    });
  }

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double maxValue = duration.inMilliseconds.toDouble();
    double currentValue = position.inMilliseconds.toDouble();
    if (maxValue <= 0) maxValue = 1.0;
    if (currentValue > maxValue) currentValue = maxValue;

    return Container(
      // تحديد عرض ثابت وصغير للفقاعة
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // زر التشغيل - تم تصغيره
          GestureDetector(
            onTap: () async {
              if (isPlaying) {
                await _player.pause();
              } else {
                await _player.play(UrlSource(widget.url));
              }
            },
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 28, // حجم أصغر قليلاً
              color: const Color(0xFF039105),
            ),
          ),
          const SizedBox(width: 4), // مسافة بسيطة بين الزر والشريط
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.0, // جعل الخط نحيفاً جداً
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 4.0,
                    ), // تصغير دائرة السحب
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 8.0,
                    ), // تصغير هالة الضغط
                    // إزالة المسافات الافتراضية من اليمين واليسار
                    trackShape: const RectangularSliderTrackShape(),
                  ),
                  child: SizedBox(
                    height:
                        20, // تحديد ارتفاع صغير جداً للشريط لضغط المسافة الرأسية
                    child: Slider(
                      min: 0.0,
                      max: maxValue,
                      value: currentValue,
                      activeColor: const Color(0xFF039105),
                      inactiveColor: Colors.grey[300],
                      onChanged: (value) async {
                        await _player.seek(
                          Duration(milliseconds: value.toInt()),
                        );
                      },
                    ),
                  ),
                ),
                // عرض التوقيت بشكل مدمج وأنيق
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    "${_formatDuration(position)} / ${_formatDuration(duration)}",
                    style: TextStyle(
                      fontSize: 8, // تصغير الخط جداً
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    return "${d.inMinutes.remainder(60)}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";
  }
}

class ResultPdfScreen extends StatefulWidget {
  final String url;

  const ResultPdfScreen({super.key, required this.url});

  @override
  State<ResultPdfScreen> createState() => _ResultPdfScreenState();
}

class _ResultPdfScreenState extends State<ResultPdfScreen> {
  bool isLoading = true;
  String? localPath;

  @override
  void initState() {
    super.initState();
    _downloadPdf();
  }

  Future<void> _downloadPdf() async {
    try {
      final response = await http.get(Uri.parse(widget.url));

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/result.pdf');

      await file.writeAsBytes(response.bodyBytes);

      setState(() {
        localPath = file.path;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _downloadToDevice() async {
    try {
      final response = await http.get(Uri.parse(widget.url));

      final dir = await getExternalStorageDirectory();
      final file = File(
        '${dir!.path}/result_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      await file.writeAsBytes(response.bodyBytes);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("تم تحميل الملف")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("فشل التحميل")));
    }
  }

  Future<void> _sharePdf() async {
    if (localPath == null) return;
    await Share.shareXFiles([XFile(localPath!, mimeType: 'application/pdf')]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("عرض النتيجة"),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: _sharePdf),
        ],
      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : localPath == null
              ? const Center(child: Text("فشل تحميل الملف"))
              : SfPdfViewer.file(File(localPath!)),
    );
  }
}
