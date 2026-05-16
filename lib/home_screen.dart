import 'dart:convert';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_messages/chat_details_screen.dart';
import 'package:whatsapp_messages/phone_contact_screen.dart';
import 'package:whatsapp_messages/setting_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String? selectedConfigId;

  final GlobalKey<ConversationsScreenState> _convKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    loadHeaderConfig();
  }

  Future<void> loadHeaderConfig() async {
    final prefs = await SharedPreferences.getInstance();

    String? savedId = prefs.getString('selectedConfigId');

    if (savedId == null) {
      savedId = "altohami";
      await prefs.setString('selectedConfigId', savedId);
    }

    setState(() {
      selectedConfigId = savedId;
    });
  }

  List<Widget> get _pages => [
    ConversationsScreen(key: _convKey),
    const ResultsPage(),
    const StatsPage(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.grey[300],
          elevation: 0,
          centerTitle: true,
          title: SizedBox(
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: const Text(
                    "واتساب",
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),

                if (selectedConfigId != null)
                  Text(
                    selectedConfigId!,
                    style: const TextStyle(
                      color: Color.fromARGB(255, 3, 145, 5),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.settings,
                color: Color.fromARGB(255, 3, 145, 5),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                ).then((_) {
                  loadHeaderConfig();
                  _convKey.currentState?.loadSelectedConfig();
                });
              },
            ),
          ],
        ),
        body: SafeArea(child: _pages[_currentIndex]),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: Colors.grey[300],
          selectedItemColor: const Color.fromARGB(255, 3, 145, 5),
          unselectedItemColor: Colors.grey[600],
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'دردشات'),
            BottomNavigationBarItem(
              icon: Icon(Icons.science),
              label: 'النتائج',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),

              label: 'احصائيات',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'الملف الشخصي',
            ),
          ],
        ),
      ),
    );
  }
}

/// -------------------- شاشة الدردشات  --------------------

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => ConversationsScreenState();
}

class ConversationsScreenState extends State<ConversationsScreen> {
  String? selectedConfigId;
  bool isLoadingConfig = true;

  @override
  void initState() {
    super.initState();
    loadSelectedConfig();
    _initBadge();
  }

  Future<void> _initBadge() async {
    await Permission.notification.request();
    final supported = await AppBadgePlus.isSupported();
    if (!supported) {
      print("⚠️ App badge not supported on this device");
    }
  }

  Future<void> loadSelectedConfig() async {
    final prefs = await SharedPreferences.getInstance();

    String? savedId = prefs.getString('selectedConfigId');

    if (savedId == null) {
      savedId = "altohami";
      await prefs.setString('selectedConfigId', savedId);
    }

    setState(() {
      selectedConfigId = savedId;
      isLoadingConfig = false;
    });

    print("🔄 تم تحديث الحساب المختار إلى: $selectedConfigId");
  }

  Widget _buildLoader() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: Color(0xFF039105), strokeWidth: 3),
        SizedBox(height: 14),
        Text(
          "جاري التحميل...",
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ],
    ),
  );

  // ... داخل كلاس ConversationsScreenState

  String formatChatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return "";

    DateTime date = timestamp.toDate();
    DateTime now = DateTime.now();

    // حساب الفرق بالأيام مع تصفير الساعات لمقارنة الأيام بدقة
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime chatDate = DateTime(date.year, date.month, date.day);

    final difference = today.difference(chatDate).inDays;

    if (difference == 0) {
      // إذا كان اليوم: عرض الساعة (مثال: 10:30 PM)
      return intl.DateFormat.jm().format(date);
    } else if (difference == 1) {
      // إذا كان أمس
      return "أمس";
    } else if (difference < 7) {
      // إذا كان خلال الأسبوع الحالي: عرض اسم اليوم (اختياري)
      // return DateFormat.EEEE('ar').format(date);
      return intl.DateFormat('yyyy/MM/dd').format(date);
    } else {
      // تاريخ قديم
      return intl.DateFormat('yyyy/MM/dd').format(date);
    }
  }

  // ... داخل الـ build والـ ListView.builder

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],

      // الزر العائم لبدء محادثة جديدة
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color.fromARGB(255, 3, 145, 5),
        child: const Icon(Icons.chat_bubble, color: Colors.white),
        onPressed: () {
          if (selectedConfigId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) =>
                        PhoneContactsScreen(configId: selectedConfigId!),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("الرجاء اختيار حساب من الإعدادات أولاً"),
              ),
            );
          }
        },
      ),

      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: const Text(
                  "الدردشات",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child:
                  isLoadingConfig
                      ? _buildLoader()
                      : selectedConfigId == null
                      ? const Center(
                        child: Text("الرجاء اختيار حساب من الإعدادات"),
                      )
                      : StreamBuilder<QuerySnapshot>(
                        stream:
                            FirebaseFirestore.instance
                                .collection('whatsapp_config')
                                .doc(selectedConfigId)
                                .collection('chats')
                                .orderBy('timestamp', descending: true)
                                .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return _buildLoader();
                          }

                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Text("لا توجد محادثات لهذا الحساب"),
                            );
                          }

                          final chatDocs = snapshot.data!.docs;

                          // تحديث بادج أيقونة التطبيق
                          final totalUnread = chatDocs.fold<int>(0, (sum, doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return sum + ((data['unread_count'] ?? 0) as num).toInt();
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (totalUnread > 0) {
                              AppBadgePlus.updateBadge(totalUnread);
                            } else {
                              AppBadgePlus.updateBadge(0);
                            }
                          });

                          return ListView.builder(
                            itemCount: chatDocs.length,
                            itemBuilder: (context, index) {
                              var chatData =
                                  chatDocs[index].data()
                                      as Map<String, dynamic>;
                              String phone = chatDocs[index].id;
                              Timestamp? timestamp =
                                  chatData['timestamp'] as Timestamp?;

                              // استخراج القيم مباشرة من بيانات الشات
                              String displayName =
                                  chatData['display_name'] ??
                                  ''; // من جهات الاتصال
                              String senderName =
                                  chatData['sender_name'] ??
                                  ''; // من واتساب (webhook)
                              String lastMsg = chatData['last_message'] ?? '';
                              int unreadCount =
                                  ((chatData['unread_count'] ?? 0) as num)
                                      .toInt();

                              return Column(
                                children: [
                                  ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    leading: const CircleAvatar(
                                      radius: 22,
                                      backgroundColor: Color.fromARGB(
                                        255,
                                        3,
                                        145,
                                        5,
                                      ),
                                      child: Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),

                                    title: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            displayName.isNotEmpty
                                                ? displayName
                                                : phone,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // --- هنا يظهر الوقت ---
                                        Text(
                                          formatChatTimestamp(timestamp),
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),

                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (senderName.isNotEmpty)
                                          Text(
                                            "($senderName)",
                                            style: TextStyle(
                                              color: Colors.blueGrey[700],
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        Text(
                                          lastMsg,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                    trailing:
                                        unreadCount > 0
                                            ? Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: const BoxDecoration(
                                                color: Color.fromARGB(
                                                  255,
                                                  3,
                                                  145,
                                                  5,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Text(
                                                unreadCount > 99
                                                    ? '99+'
                                                    : '$unreadCount',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            )
                                            : null,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) => ChatDetailScreen(
                                                phoneNumber: phone,
                                                configId: selectedConfigId!,

                                                receiverName:
                                                    displayName.isNotEmpty
                                                        ? displayName
                                                        : senderName,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                  Divider(
                                    thickness: 0.5,
                                    height: 1,
                                    color: Colors.grey[400],
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key});

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  String? targetCollection;
  bool isLoading = true;

  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    loadTarget();
  }

  Future<void> loadTarget() async {
    final prefs = await SharedPreferences.getInstance();

    String? savedTarget = prefs.getString('TARGET_COLLECTION');

    if (savedTarget == null) {
      savedTarget = "altohami"; // 👈 القيمة الافتراضية
      await prefs.setString('TARGET_COLLECTION', savedTarget);
    }

    setState(() {
      targetCollection = savedTarget;
      isLoading = false;
    });
  }

  Future<void> openPdf(String url) async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ResultPdfScreen(url: url)),
    );
  }

  Widget _buildLoader() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: Color(0xFF039105), strokeWidth: 3),
        SizedBox(height: 14),
        Text(
          "جاري التحميل...",
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ],
    ),
  );

  bool matchesSearch(Map<String, dynamic> data, String docId) {
    final name = (data['patient_name'] ?? "").toString().toLowerCase();
    final phone = (data['patient_phone'] ?? "").toString().toLowerCase();
    final id = docId.toLowerCase();
    final q = searchQuery.toLowerCase();

    return name.contains(q) || phone.contains(q) || id.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[300],
        body:
            isLoading
                ? _buildLoader()
                : targetCollection == null
                ? const Center(child: Text("لا يوجد كولكشن محدد"))
                : Column(
                  children: [
                    // 🔍 SEARCH BAR
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        onChanged: (value) {
                          setState(() {
                            searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: "بحث باسم المريض او رقم الهاتف او ID ...",
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream:
                            FirebaseFirestore.instance
                                .collection(targetCollection!)
                                .orderBy('created_at', descending: true)
                                .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return _buildLoader();
                          }

                          final docs = snapshot.data!.docs;

                          final filteredDocs =
                              docs.where((doc) {
                                return matchesSearch(
                                  doc.data() as Map<String, dynamic>,
                                  doc.id,
                                );
                              }).toList();

                          if (filteredDocs.isEmpty) {
                            return const Center(child: Text("لا توجد نتائج"));
                          }

                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF039105),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        "الإجمالي: ${filteredDocs.length}",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: filteredDocs.length,
                                  itemBuilder: (context, index) {
                                    final data =
                                        filteredDocs[index].data()
                                            as Map<String, dynamic>;

                                    final name =
                                        data['patient_name'] ?? "بدون اسم";
                                    final phone = data['patient_phone'] ?? "";
                                    final url = data['result_url'];

                                    final createdAt =
                                        data['created_at'] as Timestamp?;

                                    String date = "";
                                    if (createdAt != null) {
                                      date = intl.DateFormat(
                                        'yyyy/MM/dd – hh:mm a',
                                      ).format(createdAt.toDate());
                                    }

                                    return Card(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 3,
                                      ), // 👈 تقليل المسافة بين الكروت
                                      child: ListTile(
                                        dense: true, // 👈 يقلل ارتفاع الكارت
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),

                                        title: Text(
                                          name,
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14, // 👈 تصغير الخط
                                          ),
                                        ),

                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),

                                            Text(
                                              phone,
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black87,
                                              ),
                                            ),

                                            const SizedBox(height: 2),

                                            Text(
                                              date,
                                              textAlign: TextAlign.right,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),

                                        trailing: SizedBox(
                                          height: 32, // 👈 زر أصغر
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF039105,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              textStyle: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            onPressed: () => openPdf(url),
                                            child: const Text(
                                              "عرض",
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}

/// -------------------- شاشة الملف الشخصي--------------------

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? token;
  String? phoneNumberId;
  String? fetchedNumber;
  String? profilePictureUrl;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadProfileData();
  }

  Future<void> loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('TOKEN');
    phoneNumberId = prefs.getString('PHONE_NUMBER_ID');

    if (token != null && phoneNumberId != null) {
      await fetchWhatsAppProfileData(token!, phoneNumberId!);
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> fetchWhatsAppProfileData(String token, String phoneId) async {
    try {
      final phoneUrl = Uri.parse(
        'https://graph.facebook.com/v18.0/$phoneId?fields=display_phone_number&access_token=$token',
      );
      final phoneResponse = await http.get(phoneUrl);

      final profileUrl = Uri.parse(
        'https://graph.facebook.com/v18.0/$phoneId/whatsapp_business_profile?fields=profile_picture_url&access_token=$token',
      );
      final profileResponse = await http.get(profileUrl);

      if (phoneResponse.statusCode == 200) {
        final phoneData = jsonDecode(phoneResponse.body);
        String rawNumber = phoneData['display_phone_number'] ?? "";
        setState(() {
          fetchedNumber = rawNumber.replaceAll(RegExp(r'[\+\s]'), '');
        });
      }

      if (profileResponse.statusCode == 200) {
        final profileData = jsonDecode(profileResponse.body);
        setState(() {
          if (profileData['data'] != null && profileData['data'].isNotEmpty) {
            profilePictureUrl = profileData['data'][0]['profile_picture_url'];
          }
        });
      }
    } catch (e) {
      print("❌ خطأ في جلب البيانات: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: const Text(
                          "الملف الشخصي",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color.fromARGB(
                            255,
                            3,
                            145,
                            5,
                          ).withOpacity(0.3),
                          width: 4,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 65,
                        backgroundColor: Colors.grey[400],
                        backgroundImage:
                            (profilePictureUrl != null)
                                ? NetworkImage(profilePictureUrl!)
                                : null,
                        child:
                            (profilePictureUrl == null)
                                ? const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 70,
                                )
                                : null,
                      ),
                    ),

                    const SizedBox(height: 25),

                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        fetchedNumber != null
                            ? "+$fetchedNumber"
                            : "لا يوجد رقم",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 26,
                          color: Colors.black87,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        "ID: ${phoneNumberId ?? '-'}",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const Spacer(),
                  ],
                ),
              ),
    );
  }
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Text(
          "لا توجد احصائيات حالياً",
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      ),
    );
  }
}
