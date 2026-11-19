import 'package:flutter/material.dart';
import 'screens/store_dashboard_screen.dart';
import 'screens/store_login_screen.dart';
import 'utils/store_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorePreferences.init();
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
      // Gate the dashboard behind a manager login. Previously the store app
      // booted straight into the dashboard with no authentication — anyone who
      // installed the app could change prices, delete products, assign riders.
      home: StorePreferences.isLoggedIn ? const StoreDashboardScreen() : const StoreLoginScreen(),
    );
  }
}
