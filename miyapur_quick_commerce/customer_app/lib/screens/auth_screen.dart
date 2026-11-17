import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/firebase_auth_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_toast.dart';

class AuthScreen extends StatefulWidget {
  final Function(String phone, String name, String userId) onLoginSuccess;

  const AuthScreen({super.key, required this.onLoginSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _otpSent = false;
  bool _isLoading = false;
  String? _statusMessage;
  String? _firebaseVerificationId;

  Timer? _resendTimer;
  int _resendCountdown = 30;

  @override
  void dispose() {
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
      // Auto submit after short delay
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
          // Graceful fallback to backend OTP service if Firebase project lacks SMS permissions
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
          // No Navigator.pop() — IndexedStack handles switch automatically
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

    // Auto OTP Fill if dev_otp is returned by backend
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
          // No Navigator.pop() — IndexedStack handles switch automatically
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
    // Show success dialog
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
                "Phone Number Verified!",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
              ),
              const SizedBox(height: 6),
              Text(
                "Welcome back to Flash Fresh, $userName 🎉",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 1200));

    // Close the success dialog safely
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // Small gap so IndexedStack re-renders before onLoginSuccess rebuilds parent
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    // onLoginSuccess flips _isLoggedIn in MainShell → IndexedStack switches to
    // the logged-in screens automatically. No Navigator.pop() needed here.
    widget.onLoginSuccess(phone, userName, userId);
  }

  Widget _buildAnimatedOtpBox(int index) {
    final isFocused = _focusNodes[index].hasFocus;
    final isFilled = _otpControllers[index].text.isNotEmpty;

    return AnimatedScale(
      scale: isFocused ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
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
                _focusNodes[index - 1].requestFocus();
              }
            }
            setState(() {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Authentication", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF111827))),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Hero Brand Banner
              GlassCard(
                blur: 24,
                opacity: 0.95,
                borderRadius: 28,
                borderColor: Colors.grey.shade200,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF059669).withOpacity(0.12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF059669).withOpacity(0.2),
                            blurRadius: 20,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: const Icon(Icons.flash_on_rounded, size: 44, color: Color(0xFF059669)),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "FLASH FRESH & SUNDAY MEAT",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF111827), letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "⚡ 10-Minute Farm-Fresh Delivery to Your Doorstep",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Login / OTP Glass Form Card
              GlassCard(
                blur: 20,
                opacity: 0.95,
                borderRadius: 28,
                borderColor: Colors.grey.shade200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_otpSent) ...[
                      const Text("Enter Mobile Number", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF111827))),
                      const SizedBox(height: 4),
                      Text("We will send a 6-digit verification code via SMS", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      const SizedBox(height: 14),

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
                              child: const Text("🇮🇳 +91", style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w900, fontSize: 14)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                style: const TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.bold, fontSize: 17, letterSpacing: 1),
                                decoration: InputDecoration(
                                  counterText: "",
                                  hintText: "10-digit mobile number",
                                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.normal),
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
                            child: const Icon(Icons.mark_email_read_rounded, color: Color(0xFF059669), size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Code Sent to +91 ${_phoneController.text.trim()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF111827))),
                                Text(_statusMessage ?? "Enter the 6-digit code below", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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

                      const Text("Enter 6-Digit Verification Code", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF111827))),
                      const SizedBox(height: 14),

                      // 6 Animated OTP Boxes
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) => _buildAnimatedOtpBox(index)),
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
                          Text("Didn't receive code? ", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          _resendCountdown > 0
                              ? Text(
                                  "Resend in ${_resendCountdown}s",
                                  style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 12),
                                )
                              : TextButton(
                                  onPressed: _handleSendOtp,
                                  child: const Text("Resend Code", style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w900, fontSize: 12)),
                                ),
                        ],
                      ),
                    ],
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
