import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
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
    setState(() {
      selectedConfigId = prefs.getString('selectedConfigId');
    });
  }

  List<Widget> get _pages => [
    ConversationsScreen(key: _convKey),
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
  }

  Future<void> loadSelectedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedConfigId = prefs.getString('selectedConfigId');
      isLoadingConfig = false;
    });
    print("🔄 تم تحديث الحساب المختار إلى: $selectedConfigId");
  }
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
                      ? const Center(child: CircularProgressIndicator())
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
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Text("لا توجد محادثات لهذا الحساب"),
                            );
                          }

                          final chatDocs = snapshot.data!.docs;

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
                                    trailing: const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
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
