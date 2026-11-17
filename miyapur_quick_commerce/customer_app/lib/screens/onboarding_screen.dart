import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/glass_card.dart';
import 'main_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      "icon": Icons.bolt_rounded,
      "badge": "⚡ HYPERLOCAL SPEED",
      "title": "10-Minute Instant Delivery",
      "description": "Farm-fresh local vegetables, greens, and daily cooking essentials delivered to your doorstep in 10 minutes from Central Dark Store Hub.",
    },
    {
      "icon": Icons.set_meal_rounded,
      "badge": "🍗 SUNDAY MEAT ENGINE",
      "title": "Sunday Fresh Meat & Seafood",
      "description": "100% Antibiotic-free Sunday fresh chicken & Godavari river fish. Pre-order on Saturday or get live morning delivery on Sunday.",
    },
    {
      "icon": Icons.radar_rounded,
      "badge": "📍 FAST CITYWIDE DELIVERY",
      "title": "Precision Central Dark Store",
      "description": "Direct delivery from Metro Pillar 84 for guaranteed speed, store quality inspection, and zero delays.",
    },
  ];

  void _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('completed_onboarding', true);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar with Skip Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF059669).withOpacity(0.12),
                          ),
                          child: const Icon(Icons.flash_on_rounded, color: Color(0xFF059669), size: 18),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "FLASH FRESH",
                          style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: _finishOnboarding,
                      child: const Text("Skip", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ),

              // PageView Slides
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (idx) => setState(() => _currentPage = idx),
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final item = _pages[index];

                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GlassCard(
                            blur: 24,
                            opacity: 0.95,
                            borderRadius: 36,
                            padding: const EdgeInsets.all(32),
                            borderColor: Colors.grey.shade200,
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF059669).withOpacity(0.12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF059669).withOpacity(0.2),
                                        blurRadius: 30,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Icon(item["icon"] as IconData, size: 64, color: const Color(0xFF059669)),
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item["badge"],
                                    style: const TextStyle(
                                      color: Color(0xFF059669),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  item["title"],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF111827),
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  item["description"],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Page Indicators & Next / Get Started Button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pages.length, (idx) {
                        bool isSelected = _currentPage == idx;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: isSelected ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF059669) : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),

                    LiquidButton(
                      label: _currentPage == _pages.length - 1 ? "Start Shopping" : "Next Slide",
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () {
                        if (_currentPage < _pages.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                          );
                        } else {
                          _finishOnboarding();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
