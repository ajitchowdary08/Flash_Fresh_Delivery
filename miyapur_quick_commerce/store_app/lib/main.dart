import 'package:flutter/material.dart';
import 'screens/store_dashboard_screen.dart';

void main() {
  runApp(const FlashFreshStoreApp());
}

class FlashFreshStoreApp extends StatelessWidget {
  const FlashFreshStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flash Fresh Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF064E3B)),
        useMaterial3: true,
      ),
      home: const StoreDashboardScreen(),
    );
  }
}
