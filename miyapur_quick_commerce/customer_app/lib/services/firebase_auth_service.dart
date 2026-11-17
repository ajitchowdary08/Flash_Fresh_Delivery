import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../firebase_options.dart';

class FirebaseAuthService {
  static FirebaseAuth? _auth;
  static bool _isFirebaseReady = false;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _auth = FirebaseAuth.instance;
      _isFirebaseReady = true;
    } catch (e) {
      // Fallback: Try initialize without options for native android
      try {
        await Firebase.initializeApp();
        _auth = FirebaseAuth.instance;
        _isFirebaseReady = true;
      } catch (_) {
        _isFirebaseReady = false;
      }
    }
  }

  static bool get isConfigured => _isFirebaseReady && _auth != null;

  /// Dispatches real SMS OTP via Firebase Phone Auth (10,000 Free SMS/Month)
  static Future<void> sendFirebaseOtp({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(String error) onVerificationFailed,
    required Function(PhoneAuthCredential credential) onAutoVerified,
  }) async {
    if (!isConfigured) {
      onVerificationFailed("Firebase is not initialized yet.");
      return;
    }

    try {
      final formattedPhone = phoneNumber.startsWith("+91") ? phoneNumber : "+91$phoneNumber";

      await _auth!.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) {
          // Automatic SMS detection on Android devices
          onAutoVerified(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          onVerificationFailed(e.message ?? "Firebase Phone Auth verification failed.");
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      onVerificationFailed(e.toString());
    }
  }

  /// Verifies the 6-digit SMS OTP code with Firebase
  static Future<UserCredential?> verifySmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    if (!isConfigured) return null;

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    return await _auth!.signInWithCredential(credential);
  }
}
