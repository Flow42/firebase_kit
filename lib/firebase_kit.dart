/// Reusable, state-management-agnostic Firebase building blocks for Flutter apps.
///
/// - Startup: [FirebaseKit.initialize].
/// - Auth: [AuthService] / [AuthUser] / [AuthException] / [AuthErrorCode] /
///   [SessionCheck] with the `firebase_auth` implementation
///   [FirebaseAuthService].
/// - Emulator: [connectToFirebaseEmulators] + [EmulatorSettings]
///   (and alias [FirebaseEmulatorConfig]).
library;

export 'src/auth/auth_service.dart';
export 'src/auth/firebase_auth_service.dart';
export 'src/emulator/firebase_emulator.dart';
export 'src/firebase_kit_init.dart';
