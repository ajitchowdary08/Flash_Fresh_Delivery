import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/rider_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      title: 'Swiggy Instamart Partner | Flash Fresh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF10121A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFC8019), // Swiggy Orange
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
      home: const RiderHomeScreen(),
    );
  }
}
