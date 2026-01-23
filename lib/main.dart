import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'core/utils/theme.dart';
import 'core/utils/bindings.dart';
import 'features/auth/views/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Noor Grocery Store',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialBinding: GlobalBinding(),
      home: const LoginScreen(),
    );
  }
}
