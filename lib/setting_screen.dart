import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<WhatsAppConfig> configs = [];
  String? selectedConfigId;

  final TextEditingController tokenController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController wabaController = TextEditingController();

  String targetCollection = '';

  bool isLoading = true;

  final Color primaryColor = const Color.fromARGB(255, 3, 145, 5);

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await loadSavedSettings();
    await loadConfigs();
  }

  Future<void> loadConfigs() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('whatsapp_config').get();
      configs =
          snapshot.docs
              .map((doc) => WhatsAppConfig.fromFirestore(doc))
              .toList();

      if (selectedConfigId != null &&
          configs.any((c) => c.id == selectedConfigId)) {
        onConfigSelected(selectedConfigId!);
      }
    } catch (e) {
      debugPrint("Error loading configs: $e");
    }
    setState(() {
      isLoading = false;
    });
  }

  Future<void> loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedConfigId = prefs.getString('selectedConfigId');
    final savedToken = prefs.getString('TOKEN');
    final savedPhone = prefs.getString('PHONE_NUMBER_ID');
    final savedWaba = prefs.getString('WABA_ID');
    final savedTarget = prefs.getString('TARGET_COLLECTION');

    setState(() {
      selectedConfigId = savedConfigId;
      tokenController.text = savedToken ?? '';
      phoneController.text = savedPhone ?? '';
      wabaController.text = savedWaba ?? '';
      targetCollection = savedTarget ?? '';
    });
  }

  void onConfigSelected(String id) {
    final config = configs.firstWhere((c) => c.id == id);
    setState(() {
      selectedConfigId = id;
      tokenController.text = config.token;
      phoneController.text = config.phoneNumberId;
      wabaController.text = config.wabaId;
      targetCollection = config.targetCollection; 
    });
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('selectedConfigId', selectedConfigId ?? '');
    await prefs.setString('TOKEN', tokenController.text);
    await prefs.setString('PHONE_NUMBER_ID', phoneController.text);
    await prefs.setString('WABA_ID', wabaController.text);
    await prefs.setString('TARGET_COLLECTION', targetCollection); 

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم حفظ الإعدادات بنجاح")),
      );
    }
  }

  @override
  void dispose() {
    tokenController.dispose();
    phoneController.dispose();
    wabaController.dispose();
    super.dispose();
  }

  InputDecoration buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.black87),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: primaryColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade300,
      body: SafeArea(
        child:
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        child: const Text(
                          "الإعدادات",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "اعدادات الواتساب",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value:
                            configs.any((c) => c.id == selectedConfigId)
                                ? selectedConfigId
                                : null,
                        hint: const Text("اختر الحساب"),
                        isExpanded: true,
                        items:
                            configs.map((config) {
                              return DropdownMenuItem<String>(
                                value: config.id,
                                child: Text(config.name),
                              );
                            }).toList(),
                        onChanged: (value) {
                          if (value != null) onConfigSelected(value);
                        },
                        decoration: buildInputDecoration(""),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: tokenController,
                        decoration: buildInputDecoration("TOKEN"),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: phoneController,
                        decoration: buildInputDecoration("PHONE_NUMBER_ID"),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: wabaController,
                        decoration: buildInputDecoration("WABA_ID"),
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          icon: Icon(Icons.save, color: primaryColor),
                          onPressed: saveSettings,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: primaryColor, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            backgroundColor: Colors.white,
                          ),
                          label: Text(
                            "حفظ",
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}

class WhatsAppConfig {
  final String id;
  final String name;
  final String token;
  final String phoneNumberId;
  final String wabaId;
  final String targetCollection;

  WhatsAppConfig({
    required this.id,
    required this.name,
    required this.token,
    required this.phoneNumberId,
    required this.wabaId,
    required this.targetCollection,
  });

  factory WhatsAppConfig.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return WhatsAppConfig(
      id: doc.id,
      name: doc.id,
      token: data['TOKEN']?.toString() ?? '',
      phoneNumberId: data['PHONE_NUMBER_ID']?.toString() ?? '',
      wabaId: data['WABA_ID']?.toString() ?? '',
      targetCollection: data['target_collection']?.toString() ?? '',
    );
  }
}