import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

/// Single mapping table from native `FirebaseAuthException.code` strings to
/// [AuthErrorCode] and default user-presentable English messages.
const Map<String, ({AuthErrorCode code, String message})> _firebaseErrorTable =
    {
      'invalid-email': (
        code: AuthErrorCode.invalidEmail,
        message: 'That email address is not valid.',
      ),
      'user-disabled': (
        code: AuthErrorCode.userDisabled,
        message: 'This account has been disabled.',
      ),
      'user-not-found': (
        code: AuthErrorCode.invalidCredential,
        message: 'Incorrect email or password.',
      ),
      'wrong-password': (
        code: AuthErrorCode.invalidCredential,
        message: 'Incorrect email or password.',
      ),
      'invalid-credential': (
        code: AuthErrorCode.invalidCredential,
        message: 'Incorrect email or password.',
      ),
      'INVALID_LOGIN_CREDENTIALS': (
        code: AuthErrorCode.invalidCredential,
        message: 'Incorrect email or password.',
      ),
      'user-mismatch': (
        code: AuthErrorCode.invalidCredential,
        message: 'The credential does not match the current user.',
      ),
      'email-already-in-use': (
        code: AuthErrorCode.emailAlreadyInUse,
        message: 'An account already exists for that email.',
      ),
      'credential-already-in-use': (
        code: AuthErrorCode.emailAlreadyInUse,
        message: 'An account already exists for that email.',
      ),
      'account-exists-with-different-credential': (
        code: AuthErrorCode.emailAlreadyInUse,
        message: 'An account already exists for that email.',
      ),
      'provider-already-linked': (
        code: AuthErrorCode.emailAlreadyInUse,
        message: 'An account already exists for that email.',
      ),
      'weak-password': (
        code: AuthErrorCode.weakPassword,
        message: 'That password is too weak (min 6 characters).',
      ),
      'operation-not-allowed': (
        code: AuthErrorCode.operationNotAllowed,
        message: 'This sign-in method is not enabled.',
      ),
      'requires-recent-login': (
        code: AuthErrorCode.requiresRecentLogin,
        message: 'Please sign in again to complete this action.',
      ),
      'user-token-expired': (
        code: AuthErrorCode.sessionExpired,
        message: 'Your session has expired. Please sign in again.',
      ),
      'invalid-user-token': (
        code: AuthErrorCode.sessionExpired,
        message: 'Your session has expired. Please sign in again.',
      ),
      'too-many-requests': (
        code: AuthErrorCode.tooManyRequests,
        message: 'Too many attempts. Please try again later.',
      ),
      'network-request-failed': (
        code: AuthErrorCode.network,
        message: 'Network error. Check your connection and try again.',
      ),
      'popup-closed-by-user': (
        code: AuthErrorCode.cancelled,
        message: 'Sign-in was cancelled.',
      ),
      'cancelled-popup-request': (
        code: AuthErrorCode.cancelled,
        message: 'Sign-in was cancelled.',
      ),
      'web-context-canceled': (
        code: AuthErrorCode.cancelled,
        message: 'Sign-in was cancelled.',
      ),
      'canceled': (
        code: AuthErrorCode.cancelled,
        message: 'Sign-in was cancelled.',
      ),
    };

/// [AuthService] backed by `firebase_auth`.
///
/// The [FirebaseAuth] instance and [googleIdToken] provider can be injected for
/// unit and device integration testing. On native platforms, [GoogleSignIn] is
/// initialized lazily and at most once per instance, using [clientId] and
/// [serverClientId] when supplied.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    FirebaseAuth? auth,
    String? clientId,
    String? serverClientId,
    Future<String?> Function()? googleIdToken,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _googleClientId = clientId,
       _googleServerClientId = serverClientId,
       _googleIdToken = googleIdToken;

  final FirebaseAuth _auth;
  final String? _googleClientId;
  final String? _googleServerClientId;
  final Future<String?> Function()? _googleIdToken;

  Future<void>? _googleInitFuture;

  AuthUser? _map(User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      isAnonymous: user.isAnonymous,
      emailVerified: user.emailVerified,
    );
  }

  /// Lazily initializes [GoogleSignIn.instance] once behind a concurrent-safe
  /// future guard. If initialization fails, the cached future is cleared so a
  /// later attempt can retry.
  Future<void> _ensureGoogleInitialized() {
    return _googleInitFuture ??= GoogleSignIn.instance
        .initialize(
          clientId: _googleClientId,
          serverClientId: _googleServerClientId,
        )
        .catchError((Object error) {
          _googleInitFuture = null;
          throw error;
        });
  }

  Future<OAuthCredential> _obtainGoogleCredential() async {
    final tokenProvider = _googleIdToken;
    final String? idToken;
    if (tokenProvider != null) {
      idToken = await tokenProvider();
    } else {
      await _ensureGoogleInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      idToken = account.authentication.idToken;
    }
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException(
        'Google sign-in returned no credential.',
        code: AuthErrorCode.invalidCredential,
      );
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  User _requireCurrentUser([String? message]) {
    final user = _auth.currentUser;
    if (user == null) {
      throw AuthException(
        message ?? 'No user is currently signed in.',
        code: AuthErrorCode.noCurrentUser,
      );
    }
    return user;
  }

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<AuthUser> signInAnonymously() => _run(_auth.signInAnonymously);

  @override
  Future<AuthUser> signUpWithEmail(String email, String password) => _run(
    () => _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<AuthUser> signInWithEmail(String email, String password) => _run(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<AuthUser> signInWithGoogle() => _run(() async {
    if (kIsWeb && _googleIdToken == null) {
      // The Auth emulator serves a fake account picker for popups, so no
      // real OAuth client id is required for local development.
      return _auth.signInWithPopup(GoogleAuthProvider());
    }
    final credential = await _obtainGoogleCredential();
    return _auth.signInWithCredential(credential);
  });

  @override
  Future<AuthUser> linkEmail(String email, String password) => _run(() async {
    final user = _requireCurrentUser('No account to upgrade. Sign in first.');
    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: password,
    );
    return user.linkWithCredential(credential);
  });

  @override
  Future<AuthUser> linkGoogle() => _run(() async {
    final user = _requireCurrentUser('No account to upgrade. Sign in first.');
    if (kIsWeb && _googleIdToken == null) {
      return user.linkWithPopup(GoogleAuthProvider());
    }
    final credential = await _obtainGoogleCredential();
    return user.linkWithCredential(credential);
  });

  @override
  Future<String> getIdToken({bool forceRefresh = false}) async {
    final user = _requireCurrentUser();
    try {
      final token = await user.getIdToken(forceRefresh);
      if (token == null || token.isEmpty) {
        throw const AuthException(
          'Could not retrieve an ID token.',
          code: AuthErrorCode.unknown,
        );
      }
      return token;
    } catch (e) {
      throw _toAuthException(e);
    }
  }

  @override
  Future<SessionCheck> ensureValidSession({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final user = _auth.currentUser;
    if (user == null) return SessionCheck.noSession;
    try {
      await user.getIdToken(true).timeout(timeout);
      return SessionCheck.valid;
    } on FirebaseAuthException catch (e) {
      if (_firebaseErrorTable[e.code]?.code == AuthErrorCode.network) {
        return SessionCheck.keptOffline;
      }
      await signOut();
      return SessionCheck.signedOut;
    } on TimeoutException {
      return SessionCheck.keptOffline;
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) =>
      _runVoid(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> sendEmailVerification() => _runVoid(() async {
    final user = _requireCurrentUser();
    await user.sendEmailVerification();
  });

  @override
  Future<AuthUser> reloadUser() async {
    final user = _requireCurrentUser();
    await _runVoid(user.reload);
    final refreshed = _map(_auth.currentUser ?? user);
    if (refreshed == null) {
      throw const AuthException(
        'No user is currently signed in.',
        code: AuthErrorCode.noCurrentUser,
      );
    }
    return refreshed;
  }

  @override
  Future<AuthUser> updateDisplayName(String name) async {
    final user = _requireCurrentUser();
    await _runVoid(() => user.updateDisplayName(name));
    final updated = _map(_auth.currentUser ?? user);
    if (updated == null) {
      throw const AuthException(
        'No user is currently signed in.',
        code: AuthErrorCode.noCurrentUser,
      );
    }
    return updated;
  }

  @override
  Future<void> reauthenticateWithEmail(String email, String password) =>
      _runVoid(() async {
        final user = _requireCurrentUser();
        final credential = EmailAuthProvider.credential(
          email: email.trim(),
          password: password,
        );
        await user.reauthenticateWithCredential(credential);
      });

  @override
  Future<void> reauthenticateWithGoogle() => _runVoid(() async {
    final user = _requireCurrentUser();
    if (kIsWeb && _googleIdToken == null) {
      await user.reauthenticateWithPopup(GoogleAuthProvider());
      return;
    }
    final credential = await _obtainGoogleCredential();
    await user.reauthenticateWithCredential(credential);
  });

  @override
  Future<void> deleteAccount() async {
    await _runVoid(() async {
      final user = _requireCurrentUser();
      await user.delete();
    });
    await _signOutGoogleBestEffort();
  }

  @override
  Future<void> signOut() async {
    await _runVoid(_auth.signOut);
    await _signOutGoogleBestEffort();
  }

  Future<void> _signOutGoogleBestEffort() async {
    if (!kIsWeb && _googleIdToken == null) {
      try {
        await _ensureGoogleInitialized();
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Ignore if native Google Sign-In is not configured or unavailable
        // in the current test/desktop environment.
      }
    }
  }

  /// Runs an auth call, unwraps the [UserCredential], and normalizes errors
  /// into a presentable [AuthException].
  Future<AuthUser> _run(Future<UserCredential> Function() action) async {
    try {
      final credential = await action();
      final user = _map(credential.user);
      if (user == null) {
        throw const AuthException('Authentication failed. Please try again.');
      }
      return user;
    } catch (e) {
      throw _toAuthException(e);
    }
  }

  /// Runs a void auth call and normalizes errors into an [AuthException].
  Future<void> _runVoid(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      throw _toAuthException(e);
    }
  }

  AuthException _toAuthException(Object error) {
    if (error is AuthException) return error;
    if (error is FirebaseAuthException) {
      final entry = _firebaseErrorTable[error.code];
      if (entry != null) {
        return AuthException(entry.message, code: entry.code);
      }
      return AuthException(
        error.message ?? 'Authentication failed (${error.code}).',
        code: AuthErrorCode.unknown,
      );
    }
    if (error is GoogleSignInException) {
      return _fromGoogleSignInException(error);
    }
    return AuthException(error.toString());
  }

  AuthException _fromGoogleSignInException(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return const AuthException(
          'Sign-in was cancelled.',
          code: AuthErrorCode.cancelled,
        );
      case GoogleSignInExceptionCode.userMismatch:
        return const AuthException(
          'The credential does not match the current user.',
          code: AuthErrorCode.invalidCredential,
        );
      default:
        return AuthException(
          e.description ?? 'Google sign-in failed (${e.code.name}).',
          code: AuthErrorCode.unknown,
        );
    }
  }
}
