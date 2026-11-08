import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Settings for connecting to the Firebase Local Emulator Suite.
///
/// Defaults match the stock ports in `firebase.json` (`auth` 9099,
/// `firestore` 8080).
///
/// When [automaticHostMapping] is `true` (the default), FlutterFire rewrites
/// `localhost` and `127.0.0.1` to `10.0.2.2` on Android so Android emulators
/// reach the host machine. On a physical Android device using `adb reverse`,
/// set [automaticHostMapping] to `false` (or pass
/// `--dart-define=FIREBASE_EMULATOR_HOST_MAPPING=false`) so `127.0.0.1` is
/// preserved.
class EmulatorSettings {
  final bool enabled;
  final String host;
  final int authPort;
  final int firestorePort;
  final bool automaticHostMapping;

  const EmulatorSettings({
    this.enabled = true,
    this.host = 'localhost',
    this.authPort = 9099,
    this.firestorePort = 8080,
    this.automaticHostMapping = true,
  });

  /// Disables emulator connection (for production builds).
  const EmulatorSettings.disabled() : this(enabled: false);

  /// Reads emulator settings from compile-time `--dart-define` variables:
  /// - `USE_FIREBASE_EMULATOR` (default `true` — pass `false` in production!)
  /// - `FIREBASE_EMULATOR_HOST` (default `'localhost'`)
  /// - `FIREBASE_EMULATOR_HOST_MAPPING` (default `true`)
  factory EmulatorSettings.fromEnvironment({
    int authPort = 9099,
    int firestorePort = 8080,
  }) => EmulatorSettings(
    enabled: const bool.fromEnvironment(
      'USE_FIREBASE_EMULATOR',
      defaultValue: true,
    ),
    host: const String.fromEnvironment(
      'FIREBASE_EMULATOR_HOST',
      defaultValue: 'localhost',
    ),
    automaticHostMapping: const bool.fromEnvironment(
      'FIREBASE_EMULATOR_HOST_MAPPING',
      defaultValue: true,
    ),
    authPort: authPort,
    firestorePort: firestorePort,
  );
}

/// Backwards-compatible alias for [EmulatorSettings].
typedef FirebaseEmulatorConfig = EmulatorSettings;

bool _emulatorsConnected = false;

/// Whether [connectToFirebaseEmulators] has already run in this Dart isolate.
bool get areFirebaseEmulatorsConnected => _emulatorsConnected;

/// Resets the once-per-process emulator guard. For unit tests only.
@visibleForTesting
void resetEmulatorConnectionStateForTesting() {
  _emulatorsConnected = false;
}

/// Points [FirebaseAuth] and [FirebaseFirestore] at the local emulator suite
/// at most once per process.
///
/// Calling `useFirestoreEmulator` after Firestore has been used throws; a
/// second call to [connectToFirebaseEmulators] in the same isolate is a
/// safe no-op.
Future<void> connectToFirebaseEmulators({
  EmulatorSettings config = const EmulatorSettings(),
  bool auth = true,
  bool firestore = true,
  FirebaseAuth? authInstance,
  FirebaseFirestore? firestoreInstance,
}) async {
  if (!config.enabled || _emulatorsConnected) return;
  _emulatorsConnected = true;

  if (auth) {
    await (authInstance ?? FirebaseAuth.instance).useAuthEmulator(
      config.host,
      config.authPort,
      automaticHostMapping: config.automaticHostMapping,
    );
  }
  if (firestore) {
    try {
      (firestoreInstance ?? FirebaseFirestore.instance).useFirestoreEmulator(
        config.host,
        config.firestorePort,
        automaticHostMapping: config.automaticHostMapping,
      );
    } catch (e) {
      // On a Flutter hot restart, Dart static state resets while the native
      // Firestore instance in the host OS process may already be running.
      final msg = e.toString();
      if (!msg.contains('already been started') &&
          !msg.contains('failed-precondition') &&
          !msg.contains('IllegalStateException')) {
        rethrow;
      }
    }
  }
}
