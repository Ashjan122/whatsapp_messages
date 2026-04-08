import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:whatsapp_messages/chat_details_screen.dart';

class PhoneContactsScreen extends StatefulWidget {
  final String configId;
  const PhoneContactsScreen({super.key, required this.configId});

  @override
  State<PhoneContactsScreen> createState() => _PhoneContactsScreenState();
}

class _PhoneContactsScreenState extends State<PhoneContactsScreen> {
  List<Contact>? _allContacts;
  List<Contact>? _filteredContacts;
  bool _permissionDenied = false;
  final TextEditingController _searchController = TextEditingController();

  // توحيد اللون هنا ليسهل تغييره لاحقاً
  final Color backgroundColor = Colors.grey[200]!;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
    _searchController.addListener(_filterContacts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchContacts() async {
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      setState(() => _permissionDenied = true);
    } else {
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withAccounts: true,
      );

      setState(() {
        _allContacts = contacts;
        _filteredContacts = contacts;
      });
    }
  }

  void _filterContacts() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredContacts =
          _allContacts?.where((contact) {
            bool nameMatches = contact.displayName.toLowerCase().contains(
              query,
            );
            bool phoneMatches = contact.phones.any(
              (p) => p.number.contains(query),
            );
            return nameMatches || phoneMatches;
          }).toList();
    });
  }

  String _formatPhoneNumber(String raw) {
    String cleaned = raw.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+')) cleaned = cleaned.substring(1);
    if (cleaned.startsWith('09') || cleaned.startsWith('01')) {
      cleaned = '249' + cleaned.substring(1);
    }
    return cleaned;
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return const Scaffold(
        body: Center(child: Text("تم رفض الوصول لجهات الاتصال")),
      );
    }

    if (_allContacts == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      // تحديد لون خلفية الشاشة (القائمة)
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          "جهات اتصال الهاتف",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: backgroundColor, // جعل الـ AppBar بنفس اللون
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white, // لون حقل الكتابة نفسه يظل أبيض للوضوح
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                decoration: const InputDecoration(
                  hintText: "بحث عن اسم أو رقم...",
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ),
        ),
      ),
      body:
          _filteredContacts!.isEmpty
              ? const Center(child: Text("لا توجد نتائج مطابقة"))
              : ListView.separated(
                itemCount: _filteredContacts!.length,
                // تخصيص شكل الفاصل ليتناسب مع الخلفية الرمادية
                separatorBuilder:
                    (context, index) =>
                        Divider(height: 1, indent: 70, color: Colors.grey[300]),
                itemBuilder: (context, i) {
                  Contact contact = _filteredContacts![i];
                  String rawNumber =
                      contact.phones.isNotEmpty
                          ? contact.phones.first.number
                          : "بدون رقم";

                  String formattedNumber =
                      rawNumber != "بدون رقم"
                          ? _formatPhoneNumber(rawNumber)
                          : "بدون رقم";

                  return ListTile(
                    // ListTile يأخذ لون خلفية الـ Scaffold تلقائياً
                    leading: CircleAvatar(
                      backgroundColor: const Color.fromARGB(255, 3, 145, 5),
                      child: Text(
                        contact.displayName.isNotEmpty
                            ? contact.displayName[0].toUpperCase()
                            : "?",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      contact.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(formattedNumber),
                    onTap: () {
                      if (formattedNumber != "بدون رقم") {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => ChatDetailScreen(
                                  phoneNumber: formattedNumber,
                                  configId: widget.configId,
                                ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("هذه الجهة لا تملك رقم هاتف"),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
    );
  }
}
