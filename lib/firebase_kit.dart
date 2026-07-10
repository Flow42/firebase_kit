/// Reusable, state-management-agnostic Firebase building blocks for Flutter apps.
///
/// - Auth: [AuthService] / [AuthUser] / [AuthException] with the `firebase_auth`
///   implementation [FirebaseAuthService].
/// - Emulator: [connectToFirebaseEmulators] + [FirebaseEmulatorConfig].
library;

export 'src/auth/auth_service.dart';
export 'src/auth/firebase_auth_service.dart';
export 'src/emulator/firebase_emulator.dart';
