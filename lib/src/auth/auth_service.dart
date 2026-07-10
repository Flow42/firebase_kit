/// A signed-in (or anonymous) user, decoupled from any Firebase types so the UI
/// and state layers never import `firebase_auth` directly.
class AuthUser {
  final String uid;
  final String? email;
  final String? displayName;
  final bool isAnonymous;

  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.isAnonymous = false,
  });

  /// Best-effort human label for the account.
  String get label {
    if (isAnonymous) return 'Guest';
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    if (email != null && email!.isNotEmpty) return email!;
    return uid;
  }
}

/// Thrown by [AuthService] implementations for any sign-in/up failure. Carries a
/// user-presentable [message].
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}

/// Abstraction over user management. Implemented by `FirebaseAuthService` for
/// production and driven by `firebase_auth_mocks` in tests. Deliberately free of
/// any state-management dependency so each app can wrap it however it likes
/// (Riverpod, Bloc, ChangeNotifier, …).
abstract class AuthService {
  /// Emits the current user on subscription, then on every sign-in/out.
  Stream<AuthUser?> authStateChanges();

  AuthUser? get currentUser;

  Future<AuthUser> signInAnonymously();
  Future<AuthUser> signUpWithEmail(String email, String password);
  Future<AuthUser> signInWithEmail(String email, String password);
  Future<AuthUser> signInWithGoogle();

  /// Upgrades the current anonymous account to a permanent email/password
  /// account, preserving the uid (and therefore all Firestore data).
  Future<AuthUser> linkEmail(String email, String password);

  Future<void> signOut();
}
