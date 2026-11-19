import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/store_api_service.dart';
import '../utils/store_preferences.dart';
import 'store_dashboard_screen.dart';

/// OTP login for the store manager app. The manager logs in with the store
/// phone number; the backend resolves role=MANAGER from the users table
/// (seeded manager phone: 9000011111).
class StoreLoginScreen extends StatefulWidget {
  const StoreLoginScreen({super.key});

  @override
  State<StoreLoginScreen> createState() => _StoreLoginScreenState();
}

class _StoreLoginScreenState extends State<StoreLoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _devOtp;
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
      setState(() => _error = "Enter a valid 10-digit store manager number.");
      return;
    }
    setState(() { _loading = true; _error = null; });
    final res = await StoreApiService.sendOtp(phone);
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
    setState(() { _loading = true; _error = null; });
    final res = await StoreApiService.verifyOtp(phone, otp);
    if (!mounted) return;
    if (res["success"] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const StoreDashboardScreen()),
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
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.store_rounded, size: 64, color: Color(0xFF7C3AED)),
              const SizedBox(height: 16),
              const Text(
                "Flash Fresh Store Hub",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                _otpSent ? "Enter the OTP sent to +91 ${_phoneCtrl.text.trim()}" : "Manager login — enter the store's registered phone number",
                style: const TextStyle(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 28),
              if (!_otpSent) ...[
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 2),
                  decoration: InputDecoration(
                    prefixText: "+91 ",
                    prefixStyle: const TextStyle(color: Colors.white70, fontSize: 18),
                    labelText: "Store Manager Mobile",
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        : const Text("Send OTP", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: "Enter 6-digit OTP",
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                if (_devOtp != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF1E2A1E), borderRadius: BorderRadius.circular(10), border: Border.all(color: Color(0xFF10B981))),
                    child: Text("Dev OTP: $_devOtp (shown because SMS is not configured)", style: const TextStyle(color: Color(0xFF10B981), fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        : const Text("Verify & Open Dashboard", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() { _otpSent = false; _error = null; }),
                  child: const Text("Change number", style: TextStyle(color: Colors.white54)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  "Default demo manager number: 9000011111. In production, change this to your store's real number and configure SMS_API_KEY.",
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
