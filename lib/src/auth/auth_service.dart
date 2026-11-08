/// Machine-readable error codes carried by [AuthException] so apps can branch
/// on specific failure modes and localize messages without parsing English text.
enum AuthErrorCode {
  invalidEmail,
  userDisabled,
  invalidCredential,
  emailAlreadyInUse,
  weakPassword,
  operationNotAllowed,
  requiresRecentLogin,
  sessionExpired,
  tooManyRequests,
  network,
  cancelled,
  noCurrentUser,
  unknown,
}

/// Outcome of [AuthService.ensureValidSession].
enum SessionCheck {
  /// No user was signed in when the check ran.
  noSession,

  /// The current user's ID token was refreshed and accepted by the backend.
  valid,

  /// The backend could not be reached (network error or timeout); the local
  /// session was left intact so the app can continue offline.
  keptOffline,

  /// The backend rejected the session (e.g. token revoked, user deleted, or
  /// the Auth emulator restarted); the stale session was signed out.
  signedOut,
}

/// A signed-in (or anonymous) user, decoupled from any Firebase types so the UI
/// and state layers never import `firebase_auth` directly.
class AuthUser {
  final String uid;
  final String? email;
  final String? displayName;
  final bool isAnonymous;
  final bool emailVerified;

  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.isAnonymous = false,
    this.emailVerified = false,
  });

  /// Best-effort human label for the account.
  String get label {
    if (isAnonymous) return 'Guest';
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    if (email != null && email!.isNotEmpty) return email!;
    return uid;
  }
}

/// Thrown by [AuthService] implementations for any auth failure. Carries a
/// default English [message] and a machine-readable [code].
class AuthException implements Exception {
  final String message;
  final AuthErrorCode code;

  const AuthException(this.message, {this.code = AuthErrorCode.unknown});

  @override
  String toString() => 'AuthException: $message';
}

/// Abstraction over user management. Implemented by `FirebaseAuthService` for
/// production, `FakeAuthService` (in `package:firebase_kit/testing.dart`) for
/// widget tests, and driven by `firebase_auth_mocks` in unit tests.
///
/// Deliberately free of any state-management dependency so each app can wrap it
/// however it likes (Riverpod, Bloc, ChangeNotifier, …).
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

  /// Upgrades the current anonymous account to a permanent Google account,
  /// preserving the uid (and therefore all Firestore data).
  Future<AuthUser> linkGoogle();

  /// Returns the current user's JWT ID token, optionally forcing a refresh.
  /// Throws [AuthException] with [AuthErrorCode.noCurrentUser] if signed out.
  Future<String> getIdToken({bool forceRefresh = false});

  /// Force-refreshes the current user's ID token to detect stale sessions
  /// (e.g. after the Auth emulator restarts or an account is deleted).
  ///
  /// Network errors and timeouts keep the local session ([SessionCheck.keptOffline]);
  /// any other auth failure signs out and returns [SessionCheck.signedOut].
  Future<SessionCheck> ensureValidSession({
    Duration timeout = const Duration(seconds: 10),
  });

  /// Sends a password-reset email to [email] (trimmed).
  Future<void> sendPasswordResetEmail(String email);

  /// Sends a verification email to the current user.
  /// Throws [AuthException] with [AuthErrorCode.noCurrentUser] if signed out.
  Future<void> sendEmailVerification();

  /// Reloads the current user's profile and [AuthUser.emailVerified] state.
  /// Throws [AuthException] with [AuthErrorCode.noCurrentUser] if signed out.
  Future<AuthUser> reloadUser();

  /// Updates the current user's display name and returns the updated [AuthUser].
  /// Throws [AuthException] with [AuthErrorCode.noCurrentUser] if signed out.
  Future<AuthUser> updateDisplayName(String name);

  /// Re-authenticates the current user with [email] and [password] so
  /// security-sensitive operations (such as [deleteAccount]) can proceed after
  /// failing with [AuthErrorCode.requiresRecentLogin].
  Future<void> reauthenticateWithEmail(String email, String password);

  /// Re-authenticates the current user with Google so security-sensitive
  /// operations (such as [deleteAccount]) can proceed after failing with
  /// [AuthErrorCode.requiresRecentLogin].
  Future<void> reauthenticateWithGoogle();

  /// Permanently deletes the current user's account. May fail with
  /// [AuthErrorCode.requiresRecentLogin], in which case the caller should
  /// re-authenticate and retry.
  Future<void> deleteAccount();

  Future<void> signOut();
}
