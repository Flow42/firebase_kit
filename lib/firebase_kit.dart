/// Reusable, state-management-agnostic Firebase building blocks for Flutter apps.
///
/// - Startup: [FirebaseKit.initialize].
/// - Auth: [AuthService] / [AuthUser] / [AuthException] / [AuthErrorCode] /
///   [SessionCheck] with the `firebase_auth` implementation
///   [FirebaseAuthService].
/// - Emulator: [connectToFirebaseEmulators] + [EmulatorSettings]
///   (and alias [FirebaseEmulatorConfig]).
/// - Firestore helpers: [JsonDocument] + [UserScope].
library;

export 'src/auth/auth_service.dart';
export 'src/auth/firebase_auth_service.dart';
export 'src/emulator/firebase_emulator.dart';
export 'src/firebase_kit_init.dart';
export 'src/firestore/json_document.dart';
export 'src/firestore/user_scope.dart';
