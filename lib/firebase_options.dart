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

  // NOTE: No dedicated Firebase Web app was provided for project smas-57b80.
  // These web values reuse the Android credentials so the project reference is
  // correct; if you ship Flutter web, register a Web app in the smas-57b80
  // console and replace apiKey/appId/measurementId with that app's config.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDF_q3PGKqR6-oh0u8iQbGk-53ElvGnOcA',
    appId: '1:78156872254:android:e3fa3da4b25f2c2840ef6f',
    messagingSenderId: '78156872254',
    projectId: 'smas-57b80',
    authDomain: 'smas-57b80.firebaseapp.com',
    storageBucket: 'smas-57b80.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDF_q3PGKqR6-oh0u8iQbGk-53ElvGnOcA',
    appId: '1:78156872254:android:e3fa3da4b25f2c2840ef6f',
    messagingSenderId: '78156872254',
    projectId: 'smas-57b80',
    storageBucket: 'smas-57b80.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB_cbK1oGjPyZeyoRK3xevOJaZxiCLGzEM',
    appId: '1:78156872254:ios:ff774aed580c86ca40ef6f',
    messagingSenderId: '78156872254',
    projectId: 'smas-57b80',
    storageBucket: 'smas-57b80.firebasestorage.app',
    iosBundleId: 'com.sportsmagician.com',
  );
}
