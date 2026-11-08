import 'dart:async';

import '../auth/auth_service.dart';

/// In-memory [AuthService] fake for unit and widget tests.
///
/// Maintains a current user and a broadcast auth-state stream that emits the
/// current user immediately on subscription, matching `FirebaseAuth`'s stream
/// semantics without any Firebase or `flutter_test` dependency.
///
/// Failure modes are opt-in via [failWith], artificial latency via
/// [actionDelay], and every call is recorded in [calls].
class FakeAuthService implements AuthService {
  FakeAuthService({AuthUser? initialUser}) : _current = initialUser {
    _controller = StreamController<AuthUser?>.broadcast(
      onListen: () => _controller.add(_current),
    );
  }

  late final StreamController<AuthUser?> _controller;
  AuthUser? _current;

  /// When non-null, the next auth action throws this instead of succeeding.
  /// Consumed once so a test can assert a single failure and then recover.
  AuthException? _pendingFailure;

  /// Artificial delay before each action resolves. Set this so a widget test
  /// can pump a single frame and observe the in-flight loading state
  /// deterministically, then `pumpAndSettle` to let it complete.
  Duration actionDelay = Duration.zero;

  /// Records every call made to this fake (e.g. `'signInAnonymously'`,
  /// `'signInWithEmail:ada@example.com'`, `'signOut'`).
  final List<String> calls = [];

  var _uidCounter = 0;
  var _pendingEmailVerified = false;

  /// Arm the next action to fail with [message] and optional [code].
  void failWith(String message, {AuthErrorCode code = AuthErrorCode.unknown}) {
    _pendingFailure = AuthException(message, code: code);
  }

  Future<void> _maybeThrow() async {
    if (actionDelay > Duration.zero) {
      await Future<void>.delayed(actionDelay);
    }
    final failure = _pendingFailure;
    if (failure != null) {
      _pendingFailure = null;
      throw failure;
    }
  }

  AuthUser _requireUser([String? message]) {
    final current = _current;
    if (current == null) {
      throw AuthException(
        message ?? 'No user is currently signed in.',
        code: AuthErrorCode.noCurrentUser,
      );
    }
    return current;
  }

  AuthUser _emit(AuthUser user) {
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  @override
  AuthUser? get currentUser => _current;

  @override
  Future<AuthUser> signInAnonymously() async {
    calls.add('signInAnonymously');
    await _maybeThrow();
    return _emit(AuthUser(uid: 'anon-${_uidCounter++}', isAnonymous: true));
  }

  @override
  Future<AuthUser> signUpWithEmail(String email, String password) async {
    calls.add('signUpWithEmail:$email');
    await _maybeThrow();
    return _emit(AuthUser(uid: 'uid-${_uidCounter++}', email: email.trim()));
  }

  @override
  Future<AuthUser> signInWithEmail(String email, String password) async {
    calls.add('signInWithEmail:$email');
    await _maybeThrow();
    return _emit(AuthUser(uid: 'uid-${_uidCounter++}', email: email.trim()));
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    calls.add('signInWithGoogle');
    await _maybeThrow();
    return _emit(
      AuthUser(
        uid: 'google-${_uidCounter++}',
        email: 'user@gmail.com',
        displayName: 'Google User',
      ),
    );
  }

  @override
  Future<AuthUser> linkEmail(String email, String password) async {
    calls.add('linkEmail:$email');
    await _maybeThrow();
    final current = _requireUser('No account to upgrade. Sign in first.');
    return _emit(
      AuthUser(
        uid: current.uid,
        email: email.trim(),
        displayName: current.displayName,
        emailVerified: current.emailVerified,
      ),
    );
  }

  @override
  Future<AuthUser> linkGoogle() async {
    calls.add('linkGoogle');
    await _maybeThrow();
    final current = _requireUser('No account to upgrade. Sign in first.');
    return _emit(
      AuthUser(
        uid: current.uid,
        email: current.email ?? 'user@gmail.com',
        displayName: current.displayName ?? 'Google User',
        emailVerified: current.emailVerified,
      ),
    );
  }

  @override
  Future<String> getIdToken({bool forceRefresh = false}) async {
    calls.add('getIdToken');
    await _maybeThrow();
    final current = _requireUser();
    return 'fake-id-token-${current.uid}';
  }

  @override
  Future<SessionCheck> ensureValidSession({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    calls.add('ensureValidSession');
    if (_current == null) {
      return SessionCheck.noSession;
    }
    if (actionDelay > Duration.zero) {
      if (actionDelay > timeout) {
        await Future<void>.delayed(timeout);
        return SessionCheck.keptOffline;
      }
      await Future<void>.delayed(actionDelay);
    }
    final failure = _pendingFailure;
    if (failure != null) {
      _pendingFailure = null;
      if (failure.code == AuthErrorCode.network) {
        return SessionCheck.keptOffline;
      }
      _current = null;
      _controller.add(null);
      return SessionCheck.signedOut;
    }
    return SessionCheck.valid;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    final trimmed = email.trim();
    calls.add('sendPasswordResetEmail:$trimmed');
    await _maybeThrow();
  }

  @override
  Future<void> sendEmailVerification() async {
    calls.add('sendEmailVerification');
    await _maybeThrow();
    _requireUser();
    _pendingEmailVerified = true;
  }

  @override
  Future<AuthUser> reloadUser() async {
    calls.add('reloadUser');
    await _maybeThrow();
    final current = _requireUser();
    final verified = _pendingEmailVerified ? true : current.emailVerified;
    _pendingEmailVerified = false;
    final refreshed = AuthUser(
      uid: current.uid,
      email: current.email,
      displayName: current.displayName,
      isAnonymous: current.isAnonymous,
      emailVerified: verified,
    );
    _current = refreshed;
    return refreshed;
  }

  @override
  Future<AuthUser> updateDisplayName(String name) async {
    calls.add('updateDisplayName:$name');
    await _maybeThrow();
    final current = _requireUser();
    return _emit(
      AuthUser(
        uid: current.uid,
        email: current.email,
        displayName: name,
        isAnonymous: current.isAnonymous,
        emailVerified: current.emailVerified,
      ),
    );
  }

  @override
  Future<void> reauthenticateWithEmail(String email, String password) async {
    final trimmed = email.trim();
    calls.add('reauthenticateWithEmail:$trimmed');
    await _maybeThrow();
    _requireUser();
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    calls.add('reauthenticateWithGoogle');
    await _maybeThrow();
    _requireUser();
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
    await _maybeThrow();
    _requireUser();
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _current = null;
    _controller.add(null);
  }

  Future<void> dispose() => _controller.close();
}
