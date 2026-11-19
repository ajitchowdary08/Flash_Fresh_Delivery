import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/rider_api_service.dart';
import 'rider_home_screen.dart';

/// OTP login for the rider app. Riders share the customer OTP flow, but the
/// backend resolves role=RIDER from the users table (seeded rider phones).
/// On success the JWT is persisted and the app proceeds to the home screen.
///
/// For local dev, the backend returns the OTP in the API response when
/// SMS_API_KEY is not set — the screen shows it so you can log in without a
/// real SMS. In production the OTP is only delivered by SMS.
class RiderLoginScreen extends StatefulWidget {
  const RiderLoginScreen({super.key});

  @override
  State<RiderLoginScreen> createState() => _RiderLoginScreenState();
}

class _RiderLoginScreenState extends State<RiderLoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _devOtp; // only populated in non-production by the backend
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length != 10) {
      setState(() => _error = "Enter a valid 10-digit mobile number.");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await RiderApiService.sendOtp(phone);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res["success"] == true) {
        _otpSent = true;
        _devOtp = res["dev_otp"]?.toString();
      } else {
        _error = res["message"]?.toString() ?? "Could not send OTP.";
      }
    });
  }

  Future<void> _verifyOtp() async {
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      setState(() => _error = "Enter the 6-digit OTP.");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await RiderApiService.verifyOtp(phone, otp);
    if (!mounted) return;
    if (res["success"] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
      );
    } else {
      setState(() {
        _loading = false;
        _error = res["message"]?.toString() ?? "Verification failed.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10121A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.delivery_dining_rounded,
                size: 64,
                color: Color(0xFFFC8019),
              ),
              const SizedBox(height: 16),
              const Text(
                "Flash Fresh Partner",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _otpSent
                    ? "Enter the OTP sent to +91 ${_phoneCtrl.text.trim()}"
                    : "Sign in with your registered rider phone number",
                style: const TextStyle(fontSize: 14, color: Colors.white54),
              ),
              const SizedBox(height: 28),
              if (!_otpSent) ...[
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    letterSpacing: 2,
                  ),
                  decoration: InputDecoration(
                    prefixText: "+91 ",
                    prefixStyle: const TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                    ),
                    labelText: "Mobile Number",
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF1A1C28),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFC8019),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          )
                        : const Text(
                            "Send OTP",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    letterSpacing: 8,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: "Enter 6-digit OTP",
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF1A1C28),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_devOtp != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2A1E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Color(0xFF00C853)),
                    ),
                    child: Text(
                      "Dev OTP: $_devOtp (shown because SMS is not configured)",
                      style: const TextStyle(
                        color: Color(0xFF00C853),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          )
                        : const Text(
                            "Verify & Continue",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() {
                    _otpSent = false;
                    _error = null;
                  }),
                  child: const Text(
                    "Change number",
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1C28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "Demo rider numbers: 9848012345 (Ravi), 9876524680 (Suresh), 9123456789 (Naresh). "
                  "When the backend has no SMS_API_KEY, the OTP is shown above.",
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
