import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/glass_card.dart';
import 'onboarding_screen.dart';
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    Timer(const Duration(milliseconds: 2800), _checkFirstLaunch);
  }

  void _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final bool completedOnboarding = prefs.getBool('completed_onboarding') ?? false;

    if (!mounted) return;

    if (completedOnboarding) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (_, __, ___) => const MainShell(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (_, __, ___) => const OnboardingScreen(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: GlassCard(
                    blur: 24,
                    opacity: 0.95,
                    borderRadius: 36,
                    padding: const EdgeInsets.all(28),
                    borderColor: const Color(0xFF059669).withOpacity(0.3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF059669).withOpacity(0.25),
                                blurRadius: 24,
                                spreadRadius: 4,
                              )
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Image.asset(
                              "assets/images/app_logo.png",
                              width: 60,
                              height: 60,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.flash_on_rounded,
                                size: 50,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "FLASH FRESH",
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "QUICK COMMERCE",
                          style: TextStyle(
                            color: Color(0xFF059669),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 44),

              // Converted HTML/CSS Physics Loader
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    const CssPhysicsLoader(em: 16.0),
                    const SizedBox(height: 24),
                    Text(
                      "⚡ Fresh Veggies & Sunday Meats Express",
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
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

/// Exact Flutter conversion of HTML/CSS Keyframe Physics Loader:
/// width/height scaling, box-shadows, 165deg rotation, multi-color pulsing.
class CssPhysicsLoader extends StatefulWidget {
  final double em;

  const CssPhysicsLoader({super.key, this.em = 16.0});

  @override
  State<CssPhysicsLoader> createState() => _CssPhysicsLoaderState();
}

class _CssPhysicsLoaderState extends State<CssPhysicsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.em * 2.5;
    return Transform.rotate(
      angle: 165 * math.pi / 180,
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, child) {
            return CustomPaint(
              painter: _CssPhysicsLoaderPainter(_anim.value, widget.em),
            );
          },
        ),
      ),
    );
  }
}

class _CssPhysicsLoaderPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final double em;

  _CssPhysicsLoaderPainter(this.progress, this.em);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dotRadius = 0.25 * em;

    // 4 Distinct CSS Colors
    const c1 = Color(0xBFE11462); // rgba(225, 20, 98, 0.75)
    const c2 = Color(0xBF6FCADC); // rgba(111, 202, 220, 0.75)
    const c3 = Color(0xBF3DB88F); // rgba(61, 184, 143, 0.75)
    const c4 = Color(0xBFE9A920); // rgba(233, 169, 32, 0.75)

    double interp(double p, double p0, double v0, double p1, double v1) {
      if (p <= p0) return v0;
      if (p >= p1) return v1;
      final t = (p - p0) / (p1 - p0);
      return v0 + (v1 - v0) * t;
    }

    // 1. BEFORE8 Animation (Horizontal Stretching)
    double bWidth, bX1, bY1, bX2, bY2;
    if (progress <= 0.35) {
      bWidth = interp(progress, 0.0, 0.5 * em, 0.35, 2.5 * em);
      bX1 = interp(progress, 0.0, 1.0 * em, 0.35, 0.0);
      bY1 = -0.5 * em;
      bX2 = interp(progress, 0.0, -1.0 * em, 0.35, 0.0);
      bY2 = 0.5 * em;
    } else if (progress <= 0.70) {
      bWidth = interp(progress, 0.35, 2.5 * em, 0.70, 0.5 * em);
      bX1 = interp(progress, 0.35, 0.0, 0.70, -1.0 * em);
      bY1 = -0.5 * em;
      bX2 = interp(progress, 0.35, 0.0, 0.70, 1.0 * em);
      bY2 = 0.5 * em;
    } else {
      bWidth = 0.5 * em;
      bX1 = interp(progress, 0.70, -1.0 * em, 1.0, 1.0 * em);
      bY1 = -0.5 * em;
      bX2 = interp(progress, 0.70, 1.0 * em, 1.0, -1.0 * em);
      bY2 = 0.5 * em;
    }

    final paint1 = Paint()..color = c1;
    final paint2 = Paint()..color = c2;

    final bPillRect = Rect.fromCenter(center: center, width: bWidth, height: 0.5 * em);
    canvas.drawRRect(RRect.fromRectAndRadius(bPillRect, Radius.circular(dotRadius)), paint1);
    canvas.drawCircle(center + Offset(bX1, bY1), dotRadius, paint1);
    canvas.drawCircle(center + Offset(bX2, bY2), dotRadius, paint2);

    // 2. AFTER6 Animation (Vertical Stretching)
    double aHeight, aX3, aY3, aX4, aY4;
    if (progress <= 0.35) {
      aHeight = interp(progress, 0.0, 0.5 * em, 0.35, 2.5 * em);
      aX3 = 0.5 * em;
      aY3 = interp(progress, 0.0, 1.0 * em, 0.35, 0.0);
      aX4 = -0.5 * em;
      aY4 = interp(progress, 0.0, -1.0 * em, 0.35, 0.0);
    } else if (progress <= 0.70) {
      aHeight = interp(progress, 0.35, 2.5 * em, 0.70, 0.5 * em);
      aX3 = 0.5 * em;
      aY3 = interp(progress, 0.35, 0.0, 0.70, -1.0 * em);
      aX4 = -0.5 * em;
      aY4 = interp(progress, 0.35, 0.0, 0.70, 1.0 * em);
    } else {
      aHeight = 0.5 * em;
      aX3 = 0.5 * em;
      aY3 = interp(progress, 0.70, -1.0 * em, 1.0, 1.0 * em);
      aX4 = -0.5 * em;
      aY4 = interp(progress, 0.70, 1.0 * em, 1.0, -1.0 * em);
    }

    final paint3 = Paint()..color = c3;
    final paint4 = Paint()..color = c4;

    final aPillRect = Rect.fromCenter(center: center, width: 0.5 * em, height: aHeight);
    canvas.drawRRect(RRect.fromRectAndRadius(aPillRect, Radius.circular(dotRadius)), paint3);
    canvas.drawCircle(center + Offset(aX3, aY3), dotRadius, paint3);
    canvas.drawCircle(center + Offset(aX4, aY4), dotRadius, paint4);
  }

  @override
  bool shouldRepaint(covariant _CssPhysicsLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
