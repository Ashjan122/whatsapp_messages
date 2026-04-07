import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_meddages/chat_details_screen.dart';
import 'package:whatsapp_meddages/setting_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // خلي الدردشات أول صفحة
  final List<Widget> _pages = [
    const ConversationsScreen(),
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
          title: const Text(
            "واتساب",
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
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
                );
              },
            ),
          ],
        ),

        // استخدام SafeArea هنا
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
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

/// -------------------- الصفحات --------------------

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

    setState(() {
      isLoading = false;
    });
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
      } else {
        debugPrint('Error fetching number: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception fetching number: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.grey[300],
        appBar: AppBar(
          backgroundColor: Colors.grey[300],
          elevation: 0,
          title: const Text(
            "الملف الشخصي",
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body:
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey,
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 50,
                        ),
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
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: Colors.grey[300],
        width: double.infinity,
        height: double.infinity,
        child: const Center(
          child: Text(
            "لا توجد احصائيات حالياً",
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: Colors.grey[300],
        width: double.infinity,
        height: double.infinity,
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "الدردشات",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    FirebaseFirestore.instance
                        .collection('chats')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("لا توجد محادثات بعد"));
                  }

                  final chatDocs = snapshot.data!.docs;

                  return ListView.builder(
                    itemCount: chatDocs.length,
                    itemBuilder: (context, index) {
                      var chatData =
                          chatDocs[index].data() as Map<String, dynamic>;
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
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                leading: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: const Color.fromARGB(
                                    255,
                                    3,
                                    145,
                                    5,
                                  ),
                                  child: const Icon(
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
