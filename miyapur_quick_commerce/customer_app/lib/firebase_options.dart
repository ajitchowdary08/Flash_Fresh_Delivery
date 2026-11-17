import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
/// Automatically configured from your google-services.json
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyARkcj7yKKXeSY9c_tGc1OiRS_iqxIWzXY',
    appId: '1:499021059321:web:3f53d9556a0127cb92fe28',
    messagingSenderId: '499021059321',
    projectId: 'miyapur-quick-commerce',
    storageBucket: 'miyapur-quick-commerce.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyARkcj7yKKXeSY9c_tGc1OiRS_iqxIWzXY',
    appId: '1:499021059321:android:3f53d9556a0127cb92fe28',
    messagingSenderId: '499021059321',
    projectId: 'miyapur-quick-commerce',
    storageBucket: 'miyapur-quick-commerce.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyARkcj7yKKXeSY9c_tGc1OiRS_iqxIWzXY',
    appId: '1:499021059321:ios:3f53d9556a0127cb92fe28',
    messagingSenderId: '499021059321',
    projectId: 'miyapur-quick-commerce',
    storageBucket: 'miyapur-quick-commerce.firebasestorage.app',
  );
}
