import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/rider_home_screen.dart';
import 'screens/rider_login_screen.dart';
import 'utils/rider_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RiderPreferences.init();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF12141C),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const FlashFreshRiderApp());
}

class FlashFreshRiderApp extends StatelessWidget {
  const FlashFreshRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flash Fresh Partner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF10121A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFC8019), // Flash Fresh Orange
          secondary: Color(0xFF00C853), // Partner Green
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
      // Gate the home screen behind a valid login. Previously the app booted
      // straight into RiderHomeScreen with no authentication at all.
      home: RiderPreferences.isLoggedIn ? const RiderHomeScreen() : const RiderLoginScreen(),
    );
  }
}
