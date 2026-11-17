import 'package:flutter/material.dart';
import 'screens/rider_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MiyapurRiderApp());
}

class MiyapurRiderApp extends StatelessWidget {
  const MiyapurRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flash Fresh Delivery Partner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          primary: const Color(0xFF1B5E20),
          secondary: const Color(0xFFFFB300),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAF8),
      ),
      home: const RiderHomeScreen(),
    );
  }
}
