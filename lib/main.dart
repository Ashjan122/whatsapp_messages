import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
// أضف هذين السطرين للاستيراد
import 'package:intl/date_symbol_data_local.dart';
import 'package:whatsapp_messages/home_screen.dart';

import 'firebase_options.dart';

void main() async {
  // 1. تأكد من تهيئة الـ Widgets
  WidgetsFlutterBinding.ensureInitialized();

  // 2. تهيئة Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 3. تهيئة بيانات تنسيق التاريخ للغة العربية (لحل مشكلة الـ Exception)
  await initializeDateFormatting('ar', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // يفضل تحديد الـ locale هنا أيضاً لضمان اتجاه النصوص الصحيح (RTL)
      locale: const Locale('ar', 'SA'),
      home: const HomeScreen(),
    );
  }
}
