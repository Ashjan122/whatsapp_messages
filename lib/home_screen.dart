import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  String? selectedConfigId; // أضفنا هذا المتغير هنا

  final GlobalKey<ConversationsScreenState> _convKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    loadHeaderConfig(); // تحميل الاسم عند تشغيل التطبيق
  }

  // دالة لجلب الاسم من التفضيلات
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
          // هذه الخاصية تضمن توسيط العنوان في معظم المنصات
          centerTitle: true,

          // نستخدم Row هنا فقط لكلمة واتساب لأنها في الطرف
          title: SizedBox(
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. كلمة واتساب في أقصى اليمين
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

                // 2. اسم الحساب في المنتصف الحقيقي للشاشة
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

/// -------------------- شاشة الدردشات (ConversationsScreen) --------------------

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

  @override
  Widget build(BuildContext context) {
    // استخدمنا Scaffold هنا خصيصاً لإضافة الـ FloatingActionButton
    return Scaffold(
      backgroundColor: Colors.grey[300],

      // الزر العائم لبدء محادثة جديدة
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color.fromARGB(255, 3, 145, 5),
        child: const Icon(Icons.chat_bubble, color: Colors.white),
        onPressed: () {
          if (selectedConfigId != null) {
            // هنا نفتح شاشة جهات اتصال الهاتف التي أنشأناها
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

      // محتوى الشاشة (الـ Column القديم الخاص بكِ)
      body: Container(
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

                              return FutureBuilder<DocumentSnapshot>(
                                future:
                                    FirebaseFirestore.instance
                                        .collection('customers')
                                        .doc(phone)
                                        .get(),
                                builder: (context, customerSnapshot) {
                                  String displayName = phone;

                                  if (customerSnapshot.hasData &&
                                      customerSnapshot.data!.exists) {
                                    var customerData =
                                        customerSnapshot.data!.data()
                                            as Map<String, dynamic>;
                                    displayName =
                                        customerData['display_name'] ??
                                        customerData['sender_name'] ??
                                        phone;
                                  }

                                  return Column(
                                    children: [
                                      ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
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
                                        title: Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        subtitle: Text(
                                          chatData['last_message'] ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13),
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

/// -------------------- باقي الصفحات --------------------

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? token;
  String? phoneNumberId;
  String? fetchedNumber;
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
      fetchedNumber = await fetchWhatsAppNumber(token!, phoneNumberId!);
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<String?> fetchWhatsAppNumber(String token, String phoneId) async {
    try {
      final url = Uri.parse(
        'https://graph.facebook.com/v22.0/$phoneId?fields=display_phone_number&access_token=$token',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['display_phone_number'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    const CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey,
                      child: Icon(Icons.person, color: Colors.white, size: 50),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      fetchedNumber ?? "لا يوجد رقم",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      phoneNumberId ?? '-',
                      style: const TextStyle(fontSize: 16),
                    ),
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
