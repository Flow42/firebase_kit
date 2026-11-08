import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

/// [AuthService] backed by `firebase_auth`. The [FirebaseAuth] instance is
/// injected so tests can pass a `MockFirebaseAuth` (from `firebase_auth_mocks`).
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  AuthUser? _map(User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      isAnonymous: user.isAnonymous,
    );
  }

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<AuthUser> signInAnonymously() => _run(() => _auth.signInAnonymously());

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
    if (kIsWeb) {
      // The Auth emulator serves a fake account picker for popups, so no
      // real OAuth client id is required for local development.
      return _auth.signInWithPopup(GoogleAuthProvider());
    }
    // Native platforms: obtain a Google id token, then exchange it with
    // Firebase. Production mobile requires real OAuth client ids configured
    // via `flutterfire configure`.
    final signIn = GoogleSignIn.instance;
    await signIn.initialize();
    final account = await signIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google sign-in returned no credential.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(credential);
  });

  @override
  Future<AuthUser> linkEmail(String email, String password) => _run(() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No account to upgrade. Sign in first.');
    }
    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: password,
    );
    return user.linkWithCredential(credential);
  });

  @override
  Future<void> signOut() => _auth.signOut();

  /// Runs an auth call, unwraps the [UserCredential], and normalizes Firebase
  /// errors into a presentable [AuthException].
  Future<AuthUser> _run(Future<UserCredential> Function() action) async {
    try {
      final credential = await action();
      final user = _map(credential.user);
      if (user == null) {
        throw const AuthException('Authentication failed. Please try again.');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(e.toString());
    }
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
      case 'credential-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'That password is too weak (min 6 characters).';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return e.message ?? 'Authentication failed (${e.code}).';
    }
  }
}
