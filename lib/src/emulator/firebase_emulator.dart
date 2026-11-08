import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Host + ports for the Firebase Local Emulator Suite. Defaults match the ports
/// in a stock `firebase.json` (`auth` 9099, `firestore` 8080).
///
/// The host defaults to `localhost`; when running against emulators from a
/// physical device or a web build served on another interface, override it
/// (e.g. via `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2`).
class FirebaseEmulatorConfig {
  final String host;
  final int authPort;
  final int firestorePort;

  const FirebaseEmulatorConfig({
    this.host = 'localhost',
    this.authPort = 9099,
    this.firestorePort = 8080,
  });

  /// Reads the host from the `FIREBASE_EMULATOR_HOST` compile-time environment
  /// (`--dart-define`), falling back to [host].
  factory FirebaseEmulatorConfig.fromEnvironment({
    int authPort = 9099,
    int firestorePort = 8080,
  }) => FirebaseEmulatorConfig(
    host: const String.fromEnvironment(
      'FIREBASE_EMULATOR_HOST',
      defaultValue: 'localhost',
    ),
    authPort: authPort,
    firestorePort: firestorePort,
  );
}

/// Points the default [FirebaseAuth] and [FirebaseFirestore] instances at the
/// local emulator suite. Call once, after `Firebase.initializeApp`, before any
/// auth/Firestore access.
///
/// Set [auth]/[firestore] to false to wire up only one product.
Future<void> connectToFirebaseEmulators({
  FirebaseEmulatorConfig config = const FirebaseEmulatorConfig(),
  bool auth = true,
  bool firestore = true,
}) async {
  if (auth) {
    await FirebaseAuth.instance.useAuthEmulator(config.host, config.authPort);
  }
  if (firestore) {
    FirebaseFirestore.instance.useFirestoreEmulator(
      config.host,
      config.firestorePort,
    );
  }
}
