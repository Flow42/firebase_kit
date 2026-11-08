import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'auth/auth_service.dart';
import 'auth/firebase_auth_service.dart';
import 'emulator/firebase_emulator.dart';

/// Single entry point for initializing Firebase, wiring the Local Emulator
/// Suite, and validating any persisted auth session before `runApp`.
class FirebaseKit {
  const FirebaseKit._({
    required this.auth,
    required this.emulator,
    this.sessionCheck,
  });

  /// Ready-to-use [AuthService] backed by `firebase_auth`.
  final AuthService auth;

  /// The [EmulatorSettings] used during initialization.
  final EmulatorSettings emulator;

  /// Result of [AuthService.ensureValidSession] when `checkSession` is `true`,
  /// or `null` when session checking was skipped.
  final SessionCheck? sessionCheck;

  /// Initializes Flutter bindings and Firebase, connects to the emulators when
  /// [emulator] is enabled, optionally validates any persisted session, and
  /// returns the configured [FirebaseKit].
  static Future<FirebaseKit> initialize({
    FirebaseOptions? options,
    EmulatorSettings? emulator,
    bool checkSession = true,
    Duration sessionCheckTimeout = const Duration(seconds: 10),
    String? googleClientId,
    String? googleServerClientId,
    Future<String?> Function()? googleIdToken,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    Future<void> Function({FirebaseOptions? options})? appInitializer,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (appInitializer != null) {
      await appInitializer(options: options);
    } else if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }

    final effectiveEmulator = emulator ?? EmulatorSettings.fromEnvironment();
    if (effectiveEmulator.enabled) {
      await connectToFirebaseEmulators(
        config: effectiveEmulator,
        authInstance: auth,
        firestoreInstance: firestore,
      );
    }

    final authService = FirebaseAuthService(
      auth: auth,
      clientId: googleClientId,
      serverClientId: googleServerClientId,
      googleIdToken: googleIdToken,
    );

    SessionCheck? sessionResult;
    if (checkSession) {
      sessionResult = await authService.ensureValidSession(
        timeout: sessionCheckTimeout,
      );
    }

    return FirebaseKit._(
      auth: authService,
      emulator: effectiveEmulator,
      sessionCheck: sessionResult,
    );
  }
}
