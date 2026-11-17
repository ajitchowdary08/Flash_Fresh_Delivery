import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'services/firebase_auth_service.dart';
import 'utils/preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Preferences.initPref();
  await FirebaseAuthService.initialize();
  runApp(const FlashFreshApp());
}

class FlashFreshApp extends StatelessWidget {
  const FlashFreshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flash Fresh & Sunday Meat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF059669),
          primary: const Color(0xFF059669),
          secondary: const Color(0xFFD97706),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F8F6),
      ),
      home: const SplashScreen(),
    );
  }
}
