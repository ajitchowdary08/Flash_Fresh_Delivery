import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/firebase_auth_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_toast.dart';

class AuthScreen extends StatefulWidget {
  final Function(String phone, String name, String userId) onLoginSuccess;
  final VoidCallback? onCancel;

  const AuthScreen({
    super.key,
    required this.onLoginSuccess,
    this.onCancel,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  final PageController _slideController = PageController();
  int _currentSlideIdx = 0;
  Timer? _slideTimer;

  bool _otpSent = false;
  bool _isLoading = false;
  String? _statusMessage;
  String? _firebaseVerificationId;

  Timer? _resendTimer;
  int _resendCountdown = 30;

  final List<Map<String, String>> _carouselSlides = [
    {
      "image": "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=800&q=80",
      "badge": "🥬 DAILY FARM FRESH",
      "title": "Fresh Vegetables & Greens",
      "subtitle": "Farm-harvested vegetables & hydroponic palak delivered in 10-15 minutes.",
    },
    {
      "image": "https://images.unsplash.com/photo-1604503468506-a8da13d82791?w=800&q=80",
      "badge": "🍗 SUNDAY MEAT ENGINE",
      "title": "Sunday Fresh Meat & Seafood",
      "subtitle": "100% Antibiotic-free tender chicken, mutton, and fresh Godavari river fish.",
    },
    {
      "image": "https://images.unsplash.com/photo-1526367790999-0150786686a2?w=800&q=80",
      "badge": "⚡ ULTRA FAST DELIVERY",
      "title": "10-Minute Doorstep Express",
      "description": "Lightning quick dispatch from Central Dark Store directly to your home.",
    },
  ];

  @override
  void initState() {
    super.initState();
    _startSlideTimer();
  }

  void _startSlideTimer() {
    _slideTimer?.cancel();
    _slideTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      if (_slideController.hasClients) {
        int nextIdx = (_currentSlideIdx + 1) % _carouselSlides.length;
        _slideController.animateToPage(
          nextIdx,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _slideController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  String get _fullOtpCode {
    return _otpControllers.map((c) => c.text).join();
  }

  void _fillOtpCode(String code) {
    final cleanCode = code.replaceAll(RegExp(r'\D'), '');
    if (cleanCode.length >= 6) {
      for (int i = 0; i < 6; i++) {
        _otpControllers[i].text = cleanCode[i];
      }
      _focusNodes[5].requestFocus();
      LiquidToast.show(
        context,
        message: "✨ Auto-filled verification code!",
        icon: Icons.auto_awesome_rounded,
        accentColor: const Color(0xFF059669),
      );
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _fullOtpCode.length == 6) {
          _handleVerifyOtp();
        }
      });
    }
  }

  void _handleSendOtp() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.length < 10) {
      LiquidToast.show(
        context,
        message: "Please enter a valid 10-digit mobile number",
        icon: Icons.warning_amber_rounded,
        accentColor: Colors.redAccent,
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    if (FirebaseAuthService.isConfigured) {
      await FirebaseAuthService.sendFirebaseOtp(
        phoneNumber: rawPhone,
        onCodeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _otpSent = true;
            _firebaseVerificationId = verificationId;
            _statusMessage = "SMS verification code sent via Firebase.";
          });
          _startResendTimer();
        },
        onVerificationFailed: (error) async {
          final res = await ApiService.sendOtp(rawPhone);
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _otpSent = true;
            _firebaseVerificationId = null;
            _statusMessage = res['message'];
          });
          _startResendTimer();
          if (res['dev_otp'] != null) {
            _fillOtpCode(res['dev_otp']);
          }
        },
        onAutoVerified: (credential) async {
          final backendUser = await ApiService.syncFirebaseUserWithBackend(
            phone: rawPhone,
            firebaseUid: "firebase_auto_${DateTime.now().millisecondsSinceEpoch}",
          );
          if (!mounted) return;
          widget.onLoginSuccess(
            rawPhone,
            backendUser['name'] ?? "Customer",
            backendUser['user_id'] ?? "usr_firebase_auto",
          );
        },
      );
      return;
    }

    final res = await ApiService.sendOtp(rawPhone);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _otpSent = true;
      _statusMessage = res['message'];
    });

    _startResendTimer();

    if (res['dev_otp'] != null) {
      _fillOtpCode(res['dev_otp']);
    }
  }

  void _handleVerifyOtp() async {
    final enteredCode = _fullOtpCode;
    if (enteredCode.length != 6) {
      LiquidToast.show(
        context,
        message: "Please enter all 6 digits of the code",
        icon: Icons.warning_amber_rounded,
        accentColor: Colors.redAccent,
      );
      return;
    }

    setState(() => _isLoading = true);

    if (_firebaseVerificationId != null && FirebaseAuthService.isConfigured) {
      try {
        final userCred = await FirebaseAuthService.verifySmsCode(
          verificationId: _firebaseVerificationId!,
          smsCode: enteredCode,
        );

        if (!mounted) return;
        setState(() => _isLoading = false);

        if (userCred?.user != null) {
          final backendUser = await ApiService.syncFirebaseUserWithBackend(
            phone: _phoneController.text.trim(),
            firebaseUid: userCred!.user!.uid,
          );
          if (!mounted) return;
          LiquidToast.show(
            context,
            message: "🎉 Welcome back, ${backendUser['name'] ?? 'Customer'}!",
            icon: Icons.check_circle_rounded,
            accentColor: const Color(0xFF059669),
          );
          widget.onLoginSuccess(
            _phoneController.text.trim(),
            backendUser['name'] ?? "Customer",
            backendUser['user_id'] ?? userCred.user!.uid,
          );
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        LiquidToast.show(
          context,
          message: "Invalid SMS code. Please try again.",
          icon: Icons.error_outline_rounded,
          accentColor: Colors.redAccent,
        );
        return;
      }
    }

    final res = await ApiService.verifyOtp(
      _phoneController.text.trim(),
      enteredCode,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      final userName = res['name'] ?? "Customer";
      final userPhone = res['phone'] ?? _phoneController.text.trim();
      final userId = res['user_id'] ?? "usr_verified";

      _showSuccessVerificationAnimation(userName, userPhone, userId);
    } else {
      LiquidToast.show(
        context,
        message: res['message'] ?? "Incorrect verification code",
        icon: Icons.cancel_outlined,
        accentColor: Colors.redAccent,
      );
    }
  }

  void _showSuccessVerificationAnimation(String userName, String phone, String userId) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassCard(
          blur: 24,
          opacity: 0.96,
          borderRadius: 32,
          padding: const EdgeInsets.all(28),
          borderColor: const Color(0xFF059669).withOpacity(0.4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, val, child) {
                  return Transform.scale(
                    scale: val,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF059669),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF059669).withOpacity(0.4),
                            blurRadius: 24,
                            spreadRadius: 4,
                          )
                        ],
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text(
                "Phone Verified!",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
              ),
              const SizedBox(height: 6),
              Text(
                "Welcome back, $userName 🎉",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    widget.onLoginSuccess(phone, userName, userId);
  }

  Widget _buildAnimatedOtpBox(int index) {
    final isFocused = _focusNodes[index].hasFocus;
    final isFilled = _otpControllers[index].text.isNotEmpty;

    return AnimatedScale(
      scale: isFocused ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_otpControllers[index].text.isEmpty && index > 0) {
              _otpControllers[index - 1].clear();
              _focusNodes[index - 1].requestFocus();
              setState(() {});
            }
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 52,
          decoration: BoxDecoration(
            color: isFilled ? const Color(0xFF059669).withOpacity(0.08) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isFocused
                  ? const Color(0xFF059669)
                  : (isFilled ? const Color(0xFF059669).withOpacity(0.6) : Colors.grey.shade300),
              width: isFocused ? 2.2 : (isFilled ? 1.8 : 1.0),
            ),
            boxShadow: isFocused || isFilled
                ? [
                    BoxShadow(
                      color: const Color(0xFF059669).withOpacity(isFocused ? 0.3 : 0.15),
                      blurRadius: isFocused ? 12 : 8,
                      spreadRadius: isFocused ? 1 : 0,
                    )
                  ]
                : null,
          ),
          child: TextField(
            controller: _otpControllers[index],
            focusNode: _focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            style: const TextStyle(
              color: Color(0xFF059669),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
            decoration: const InputDecoration(
              counterText: "",
              border: InputBorder.none,
            ),
            onChanged: (value) {
              final cleanDigits = value.replaceAll(RegExp(r'\D'), '');
              if (cleanDigits.length >= 6) {
                _fillOtpCode(cleanDigits);
                return;
              }
              if (value.isNotEmpty) {
                if (index < 5) {
                  _focusNodes[index + 1].requestFocus();
                } else {
                  _focusNodes[index].unfocus();
                  if (_fullOtpCode.length == 6) {
                    _handleVerifyOtp();
                  }
                }
              } else {
                if (index > 0) {
                  _otpControllers[index - 1].clear();
                  _focusNodes[index - 1].requestFocus();
                }
              }
              setState(() {});
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF082219), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF059669).withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else if (widget.onCancel != null) {
                    widget.onCancel!();
                  }
                },
              ),
              title: const Text(
                "Login / Sign Up",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 18,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Column(
            children: [
              // 1. Redesigned Hero 3-Slide Carousel with Image Banners
              SizedBox(
                height: 220,
                child: PageView.builder(
                  controller: _slideController,
                  itemCount: _carouselSlides.length,
                  onPageChanged: (idx) {
                    setState(() => _currentSlideIdx = idx);
                  },
                  itemBuilder: (context, index) {
                    final slide = _carouselSlides[index];
                    return GlassCard(
                      blur: 16,
                      opacity: 0.95,
                      borderRadius: 24,
                      padding: EdgeInsets.zero,
                      borderColor: Colors.grey.shade200,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.network(
                              slide["image"]!,
                              width: double.infinity,
                              height: 220,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.green.shade50,
                                child: const Icon(Icons.eco_rounded, size: 60, color: Color(0xFF059669)),
                              ),
                            ),
                          ),
                          // Dark gradient overlay for crisp text readability
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.3),
                                  Colors.black.withOpacity(0.85),
                                ],
                                stops: const [0.0, 0.4, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 16,
                            left: 16,
                            right: 16,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    slide["badge"]!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 9,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  slide["title"]!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  slide["subtitle"] ?? slide["description"] ?? "",
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    height: 1.2,
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

              const SizedBox(height: 12),

              // Carousel PageIndicator Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_carouselSlides.length, (index) {
                  final isSel = _currentSlideIdx == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isSel ? 24 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFF059669) : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 20),

              // 2. Login / OTP Glass Form Card (iOS 26 Liquid Glass)
              GlassCard(
                blur: 24,
                opacity: 0.95,
                borderRadius: 28,
                padding: const EdgeInsets.all(20),
                borderColor: Colors.grey.shade200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_otpSent) ...[
                      const Text(
                        "Enter Mobile Number",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "We will send a 6-digit OTP code to verify your phone number",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                      const SizedBox(height: 16),

                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "🇮🇳 +91",
                                style: TextStyle(
                                  color: Color(0xFF059669),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  letterSpacing: 1,
                                ),
                                decoration: InputDecoration(
                                  counterText: "",
                                  hintText: "10-digit mobile number",
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      LiquidButton(
                        label: "Get Verification Code",
                        icon: Icons.arrow_forward_rounded,
                        isLoading: _isLoading,
                        onPressed: _handleSendOtp,
                      ),
                    ] else ...[
                      // OTP Header Status
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF059669).withOpacity(0.12),
                            ),
                            child: const Icon(
                              Icons.mark_email_read_rounded,
                              color: Color(0xFF059669),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Code Sent to +91 ${_phoneController.text.trim()}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                Text(
                                  _statusMessage ?? "Enter the 6-digit code below",
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, color: Color(0xFF059669), size: 20),
                            onPressed: () {
                              setState(() {
                                _otpSent = false;
                                for (var c in _otpControllers) {
                                  c.clear();
                                }
                              });
                            },
                          )
                        ],
                      ),
                      const Divider(height: 24, color: Colors.black12),

                      const Text(
                        "Enter 6-Digit Verification Code",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 6 Animated OTP Boxes
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) => _buildAnimatedOtpBox(index)),
                      ),

                      const SizedBox(height: 12),

                      // Paste OTP & Change Number bar (Kubera-app style)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              if (data != null && data.text != null) {
                                final clean = data.text!.replaceAll(RegExp(r'\D'), '');
                                if (clean.length >= 6) {
                                  _fillOtpCode(clean);
                                } else {
                                  LiquidToast.show(
                                    context,
                                    message: "No 6-digit OTP code found in clipboard",
                                    icon: Icons.warning_amber_rounded,
                                    accentColor: Colors.orange.shade800,
                                  );
                                }
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF059669).withOpacity(0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.content_paste_rounded, size: 14, color: Color(0xFF059669)),
                                  SizedBox(width: 6),
                                  Text(
                                    "Paste OTP",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF059669),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _otpSent = false;
                                for (var c in _otpControllers) {
                                  c.clear();
                                }
                              });
                            },
                            child: const Text(
                              "Change Number",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      LiquidButton(
                        label: "Verify & Proceed",
                        icon: Icons.check_circle_rounded,
                        isLoading: _isLoading,
                        onPressed: _handleVerifyOtp,
                      ),

                      const SizedBox(height: 14),

                      // Resend Code Timer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Didn't receive code? ",
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                          _resendCountdown > 0
                              ? Text(
                                  "Resend in ${_resendCountdown}s",
                                  style: const TextStyle(
                                    color: Color(0xFF059669),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                )
                              : TextButton(
                                  onPressed: _handleSendOtp,
                                  child: const Text(
                                    "Resend Code",
                                    style: TextStyle(
                                      color: Color(0xFF059669),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
