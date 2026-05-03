// File generated manually from the Sportsmagician Next.js `lib/firebase.ts`.
//
// For production Android/iOS builds, register those apps in the Firebase console
// and run `flutterfire configure`, or replace `android`/`ios` `appId` values with
// the ones from your downloaded `google-services.json` / `GoogleService-Info.plist`.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDnSdq0hxP0xmrZT-QuBM8Gfh2jeKj0QT0',
    appId: '1:527934608433:web:95d450cb32e2f1513fb110',
    messagingSenderId: '527934608433',
    projectId: 'sportsmagician-audio',
    authDomain: 'sportsmagician-audio.firebaseapp.com',
    storageBucket: 'sportsmagician-audio.firebasestorage.app',
    measurementId: 'G-CMEYMHRY34',
  );

  /// Replace `appId` with your Android mobile SDK app ID when available.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDnSdq0hxP0xmrZT-QuBM8Gfh2jeKj0QT0',
    appId: '1:527934608433:web:95d450cb32e2f1513fb110',
    messagingSenderId: '527934608433',
    projectId: 'sportsmagician-audio',
    storageBucket: 'sportsmagician-audio.firebasestorage.app',
  );

  /// Replace `appId` with your iOS mobile SDK app ID when available.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDnSdq0hxP0xmrZT-QuBM8Gfh2jeKj0QT0',
    appId: '1:527934608433:web:95d450cb32e2f1513fb110',
    messagingSenderId: '527934608433',
    projectId: 'sportsmagician-audio',
    storageBucket: 'sportsmagician-audio.firebasestorage.app',
    iosBundleId: 'com.example.spa',
  );
}
