import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/rider_auth_screen.dart';
import 'screens/rider_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF12141C),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool("is_rider_logged_in") ?? false;

  runApp(FlashFreshRiderApp(isLoggedIn: isLoggedIn));
}

class FlashFreshRiderApp extends StatelessWidget {
  final bool isLoggedIn;
  const FlashFreshRiderApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flash Fresh Partner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF10121A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFC8019),
          secondary: Color(0xFF00C853),
          surface: Color(0xFF1C1E29),
          onPrimary: Colors.white,
          onSurface: Colors.white,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1A1C28),
          elevation: 0,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161822),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: isLoggedIn ? const RiderHomeScreen() : const RiderAuthScreen(),
    );
  }
}
