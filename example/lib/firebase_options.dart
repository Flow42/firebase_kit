// Hand-written Firebase configuration for the demo project `demo-firebase-kit`.
//
// Because the project id starts with `demo-`, the Firebase Local Emulator Suite
// runs completely offline and never contacts real Google servers.
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
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const String projectId = 'demo-firebase-kit';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:1234567890:web:demofirebasekitweb',
    messagingSenderId: '1234567890',
    projectId: projectId,
    authDomain: '$projectId.firebaseapp.com',
    storageBucket: '$projectId.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:1234567890:android:demofirebasekitandroid',
    messagingSenderId: '1234567890',
    projectId: projectId,
    storageBucket: '$projectId.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:1234567890:ios:demofirebasekitios',
    messagingSenderId: '1234567890',
    projectId: projectId,
    storageBucket: '$projectId.appspot.com',
    iosBundleId: 'com.example.firebaseKitExample',
  );
}
