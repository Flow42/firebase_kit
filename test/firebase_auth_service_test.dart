import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_kit/firebase_kit.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:mock_exceptions/mock_exceptions.dart';

/// Subclass of [MockUser] that allows tests to control [getIdToken] (which
/// `firebase_auth_mocks` 0.15.2 does not wrap with `maybeThrowException`) and
/// mutates [emailVerified] on [reload].
// ignore: must_be_immutable
class _ControllableMockUser extends MockUser {
  _ControllableMockUser({
    super.uid = 'u1',
    super.isEmailVerified = false,
    this.onGetIdToken,
    this.emailVerifiedAfterReload,
  });

  final Future<String> Function(bool forceRefresh)? onGetIdToken;
  final bool? emailVerifiedAfterReload;
  bool? _reloadedEmailVerified;
  bool reloadCalled = false;

  @override
  bool get emailVerified => _reloadedEmailVerified ?? super.emailVerified;

  @override
  Future<String> getIdToken([bool forceRefresh = false]) {
    final handler = onGetIdToken;
    if (handler != null) {
      return handler(forceRefresh);
    }
    return super.getIdToken(forceRefresh);
  }

  @override
  Future<void> reload() async {
    await super.reload();
    reloadCalled = true;
    if (emailVerifiedAfterReload != null) {
      _reloadedEmailVerified = emailVerifiedAfterReload;
    }
  }
}

/// Fake [GoogleSignInPlatform] to verify native Google Sign-In initialization,
/// account-picker cancellation, and sign-out behaviour on the host VM.
class _FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  int initCalls = 0;
  int authenticateCalls = 0;
  int signOutCalls = 0;
  InitParameters? lastInitParams;
  Duration initDelay = Duration.zero;
  Object? initError;
  Object? authenticateError;
  String? idTokenToReturn = 'google-id-token-123';

  @override
  Future<void> init(InitParameters params) async {
    initCalls++;
    lastInitParams = params;
    if (initDelay > Duration.zero) {
      await Future<void>.delayed(initDelay);
    }
    if (initError != null) {
      throw initError!;
    }
  }

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    authenticateCalls++;
    if (authenticateError != null) {
      throw authenticateError!;
    }
    return AuthenticationResults(
      user: const GoogleSignInUserData(
        email: 'google@example.com',
        id: 'google-uid',
        displayName: 'Google User',
      ),
      authenticationTokens: AuthenticationTokenData(idToken: idTokenToReturn),
    );
  }

  @override
  Future<void> signOut(SignOutParams params) async {
    signOutCalls++;
  }

  @override
  Future<void> disconnect(DisconnectParams params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) => null;

  @override
  bool supportsAuthenticate() => true;

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;
}

Matcher _isAuthException(AuthErrorCode code, [String? message]) {
  var matcher = isA<AuthException>().having((e) => e.code, 'code', code);
  if (message != null) {
    matcher = matcher.having((e) => e.message, 'message', message);
  }
  return matcher;
}

void main() {
  group('Basic sign-in and auth state', () {
    test('starts signed out', () {
      final service = FirebaseAuthService(auth: MockFirebaseAuth());
      expect(service.currentUser, isNull);
    });

    test('signInAnonymously produces a user', () async {
      final service = FirebaseAuthService(auth: MockFirebaseAuth());
      final user = await service.signInAnonymously();
      expect(user.uid, isNotEmpty);
      expect(user.isAnonymous, isTrue);
      expect(user.label, 'Guest');
      expect(service.currentUser, isNotNull);
    });

    test('signUpWithEmail returns a user carrying the trimmed email', () async {
      final service = FirebaseAuthService(auth: MockFirebaseAuth());
      final user = await service.signUpWithEmail(
        '  ada@example.com  ',
        'secret1',
      );
      expect(user.email, 'ada@example.com');
    });

    test('signInWithEmail signs the user in', () async {
      final service = FirebaseAuthService(auth: MockFirebaseAuth());
      final user = await service.signInWithEmail(
        'grace@example.com',
        'secret1',
      );
      expect(user.uid, isNotEmpty);
      expect(service.currentUser, isNotNull);
    });

    test('authStateChanges reflects sign-in and sign-out', () async {
      final service = FirebaseAuthService(auth: MockFirebaseAuth());
      expectLater(
        service.authStateChanges().map((u) => u?.uid),
        emitsInOrder([isNull, isNotNull, isNull]),
      );
      await service.signInAnonymously();
      await service.signOut();
    });

    test('signOut clears the current user', () async {
      final service = FirebaseAuthService(
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1')),
      );
      expect(service.currentUser, isNotNull);
      await service.signOut();
      expect(service.currentUser, isNull);
    });

    test('AuthUser defaults emailVerified to false and formats label', () {
      const bare = AuthUser(uid: 'u-bare');
      expect(bare.emailVerified, isFalse);
      expect(bare.label, 'u-bare');

      const withEmail = AuthUser(uid: 'u-email', email: 'a@b.c');
      expect(withEmail.label, 'a@b.c');

      const withName = AuthUser(
        uid: 'u-name',
        email: 'a@b.c',
        displayName: 'Ada',
        emailVerified: true,
      );
      expect(withName.label, 'Ada');
      expect(withName.emailVerified, isTrue);
    });
  });

  group('Google Sign-In seam and native plugin handling', () {
    late GoogleSignInPlatform originalPlatform;
    late _FakeGoogleSignInPlatform fakeGooglePlatform;

    setUp(() {
      originalPlatform = GoogleSignInPlatform.instance;
      fakeGooglePlatform = _FakeGoogleSignInPlatform();
      GoogleSignInPlatform.instance = fakeGooglePlatform;
    });

    tearDown(() {
      GoogleSignInPlatform.instance = originalPlatform;
    });

    test('signInWithGoogle uses injected googleIdToken seam', () async {
      final mockUser = MockUser(
        uid: 'g-1',
        email: 'ada@example.com',
        displayName: 'Ada',
      );
      final service = FirebaseAuthService(
        auth: MockFirebaseAuth(mockUser: mockUser),
        googleIdToken: () async => 'fake-google-jwt',
      );
      final user = await service.signInWithGoogle();
      expect(user.uid, 'g-1');
      expect(fakeGooglePlatform.initCalls, 0);
      expect(fakeGooglePlatform.authenticateCalls, 0);
    });

    test('signInWithGoogle throws invalidCredential when token is null', () {
      final service = FirebaseAuthService(
        auth: MockFirebaseAuth(),
        googleIdToken: () async => null,
      );
      expect(
        service.signInWithGoogle(),
        throwsA(
          _isAuthException(
            AuthErrorCode.invalidCredential,
            'Google sign-in returned no credential.',
          ),
        ),
      );
    });

    test(
      'native GoogleSignIn initializes lazily and once under concurrent calls',
      () async {
        fakeGooglePlatform.initDelay = const Duration(milliseconds: 20);
        final service = FirebaseAuthService(
          auth: MockFirebaseAuth(mockUser: MockUser(uid: 'g-native')),
          clientId: 'my-client-id',
          serverClientId: 'my-server-client-id',
        );

        expect(fakeGooglePlatform.initCalls, 0);

        final results = await Future.wait([
          service.signInWithGoogle(),
          service.signInWithGoogle(),
        ]);

        expect(results, hasLength(2));
        expect(fakeGooglePlatform.initCalls, 1);
        expect(fakeGooglePlatform.authenticateCalls, 2);
        expect(fakeGooglePlatform.lastInitParams?.clientId, 'my-client-id');
        expect(
          fakeGooglePlatform.lastInitParams?.serverClientId,
          'my-server-client-id',
        );
      },
    );

    test('signOut also signs out of native GoogleSignIn', () async {
      final service = FirebaseAuthService(
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1')),
      );
      await service.signOut();
      expect(fakeGooglePlatform.signOutCalls, 1);
    });

    test(
      'GoogleSignInException(canceled) maps to AuthErrorCode.cancelled',
      () async {
        fakeGooglePlatform.authenticateError = const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        );
        final service = FirebaseAuthService(auth: MockFirebaseAuth());
        await expectLater(
          service.signInWithGoogle(),
          throwsA(
            _isAuthException(AuthErrorCode.cancelled, 'Sign-in was cancelled.'),
          ),
        );
      },
    );
  });

  group('Account linking (linkEmail & linkGoogle)', () {
    test('linkEmail throws noCurrentUser when signed out', () {
      final service = FirebaseAuthService(auth: MockFirebaseAuth());
      expect(
        service.linkEmail('ada@example.com', 'secret1'),
        throwsA(
          _isAuthException(
            AuthErrorCode.noCurrentUser,
            'No account to upgrade. Sign in first.',
          ),
        ),
      );
    });

    test('linkEmail links credential and preserves uid', () async {
      final mockUser = MockUser(uid: 'keep-uid', email: 'ada@example.com');
      final auth = MockFirebaseAuth(signedIn: true, mockUser: mockUser);
      final service = FirebaseAuthService(auth: auth);

      final linked = await service.linkEmail('  ada@example.com ', 'secret1');
      expect(linked.uid, 'keep-uid');
    });

    test('linkGoogle throws noCurrentUser when signed out', () {
      final service = FirebaseAuthService(
        auth: MockFirebaseAuth(),
        googleIdToken: () async => 'fake-token',
      );
      expect(
        service.linkGoogle(),
        throwsA(
          _isAuthException(
            AuthErrorCode.noCurrentUser,
            'No account to upgrade. Sign in first.',
          ),
        ),
      );
    });

    test('linkGoogle links Google credential and preserves uid', () async {
      final mockUser = MockUser(uid: 'keep-uid-g', email: 'ada@example.com');
      final auth = MockFirebaseAuth(signedIn: true, mockUser: mockUser);
      final service = FirebaseAuthService(
        auth: auth,
        googleIdToken: () async => 'fake-google-token',
      );

      final linked = await service.linkGoogle();
      expect(linked.uid, 'keep-uid-g');
    });
  });

  group('Token, session check, profile, reset, verification, reauth, delete', () {
    test('getIdToken throws noCurrentUser when signed out', () {
      final service = FirebaseAuthService(auth: MockFirebaseAuth());
      expect(
        service.getIdToken(),
        throwsA(_isAuthException(AuthErrorCode.noCurrentUser)),
      );
    });

    test('getIdToken returns JWT when signed in', () async {
      bool? capturedForceRefresh;
      final user = _ControllableMockUser(
        onGetIdToken: (forceRefresh) async {
          capturedForceRefresh = forceRefresh;
          return 'jwt-token-abc';
        },
      );
      final service = FirebaseAuthService(
        auth: MockFirebaseAuth(signedIn: true, mockUser: user),
      );

      final token = await service.getIdToken(forceRefresh: true);
      expect(token, 'jwt-token-abc');
      expect(capturedForceRefresh, isTrue);
    });

    test('ensureValidSession returns noSession when signed out', () async {
      final service = FirebaseAuthService(auth: MockFirebaseAuth());
      expect(await service.ensureValidSession(), SessionCheck.noSession);
    });

    test(
      'ensureValidSession returns valid when token refresh succeeds',
      () async {
        final user = _ControllableMockUser(
          onGetIdToken: (_) async => 'fresh-token',
        );
        final service = FirebaseAuthService(
          auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        );
        expect(await service.ensureValidSession(), SessionCheck.valid);
        expect(service.currentUser, isNotNull);
      },
    );

    test(
      'ensureValidSession returns keptOffline on network-request-failed and keeps user',
      () async {
        final user = _ControllableMockUser(
          onGetIdToken: (_) async =>
              throw FirebaseAuthException(code: 'network-request-failed'),
        );
        final service = FirebaseAuthService(
          auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        );
        expect(await service.ensureValidSession(), SessionCheck.keptOffline);
        expect(service.currentUser, isNotNull);
      },
    );

    test(
      'ensureValidSession returns keptOffline on timeout and keeps user',
      () async {
        final completer = Completer<String>();
        final user = _ControllableMockUser(
          onGetIdToken: (_) => completer.future,
        );
        final service = FirebaseAuthService(
          auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        );
        final result = await service.ensureValidSession(
          timeout: const Duration(milliseconds: 20),
        );
        expect(result, SessionCheck.keptOffline);
        expect(service.currentUser, isNotNull);
      },
    );

    test(
      'ensureValidSession signs out and returns signedOut on invalid token error',
      () async {
        final user = _ControllableMockUser(
          onGetIdToken: (_) async =>
              throw FirebaseAuthException(code: 'user-token-expired'),
        );
        final service = FirebaseAuthService(
          auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        );
        expect(await service.ensureValidSession(), SessionCheck.signedOut);
        expect(service.currentUser, isNull);
      },
    );

    test(
      'sendPasswordResetEmail trims email and delegates to FirebaseAuth',
      () async {
        final auth = MockFirebaseAuth();
        whenCalling(
          Invocation.method(#sendPasswordResetEmail, null, {
            #email: 'bad-email',
            #actionCodeSettings: null,
          }),
        ).on(auth).thenThrow(FirebaseAuthException(code: 'invalid-email'));

        final service = FirebaseAuthService(auth: auth);
        await service.sendPasswordResetEmail('  ada@example.com  ');

        await expectLater(
          service.sendPasswordResetEmail('  bad-email  '),
          throwsA(_isAuthException(AuthErrorCode.invalidEmail)),
        );
      },
    );

    test('sendEmailVerification requires a signed-in user', () async {
      final signedOut = FirebaseAuthService(auth: MockFirebaseAuth());
      await expectLater(
        signedOut.sendEmailVerification(),
        throwsA(_isAuthException(AuthErrorCode.noCurrentUser)),
      );

      final user = MockUser(uid: 'u1');
      final signedIn = FirebaseAuthService(
        auth: MockFirebaseAuth(signedIn: true, mockUser: user),
      );
      await signedIn.sendEmailVerification();
    });

    test('reloadUser refreshes user state and requires currentUser', () async {
      final signedOut = FirebaseAuthService(auth: MockFirebaseAuth());
      await expectLater(
        signedOut.reloadUser(),
        throwsA(_isAuthException(AuthErrorCode.noCurrentUser)),
      );

      final user = _ControllableMockUser(
        uid: 'u1',
        isEmailVerified: false,
        emailVerifiedAfterReload: true,
      );
      final signedIn = FirebaseAuthService(
        auth: MockFirebaseAuth(signedIn: true, mockUser: user),
      );
      expect(signedIn.currentUser!.emailVerified, isFalse);

      final reloaded = await signedIn.reloadUser();
      expect(user.reloadCalled, isTrue);
      expect(reloaded.emailVerified, isTrue);
    });

    test(
      'updateDisplayName updates displayName and returns refreshed user',
      () async {
        final signedOut = FirebaseAuthService(auth: MockFirebaseAuth());
        await expectLater(
          signedOut.updateDisplayName('Grace'),
          throwsA(_isAuthException(AuthErrorCode.noCurrentUser)),
        );

        final user = MockUser(uid: 'u1', displayName: 'Old Name');
        final signedIn = FirebaseAuthService(
          auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        );
        final updated = await signedIn.updateDisplayName('Grace Hopper');
        expect(updated.displayName, 'Grace Hopper');
      },
    );

    test('reauthenticateWithEmail and reauthenticateWithGoogle', () async {
      final signedOut = FirebaseAuthService(
        auth: MockFirebaseAuth(),
        googleIdToken: () async => 'g-token',
      );
      await expectLater(
        signedOut.reauthenticateWithEmail('a@b.c', 'secret1'),
        throwsA(_isAuthException(AuthErrorCode.noCurrentUser)),
      );
      await expectLater(
        signedOut.reauthenticateWithGoogle(),
        throwsA(_isAuthException(AuthErrorCode.noCurrentUser)),
      );

      final user = MockUser(uid: 'u1', email: 'a@b.c');
      final signedIn = FirebaseAuthService(
        auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        googleIdToken: () async => 'g-token',
      );
      await signedIn.reauthenticateWithEmail('  a@b.c ', 'secret1');
      await signedIn.reauthenticateWithGoogle();
    });

    test('deleteAccount deletes user and maps requires-recent-login', () async {
      final signedOut = FirebaseAuthService(auth: MockFirebaseAuth());
      await expectLater(
        signedOut.deleteAccount(),
        throwsA(_isAuthException(AuthErrorCode.noCurrentUser)),
      );

      final user = MockUser(uid: 'u1');
      final auth = MockFirebaseAuth(signedIn: true, mockUser: user);
      final service = FirebaseAuthService(auth: auth);

      await service.deleteAccount();

      whenCalling(Invocation.method(#delete, const []))
          .on(user)
          .thenThrow(FirebaseAuthException(code: 'requires-recent-login'));

      await expectLater(
        service.deleteAccount(),
        throwsA(
          _isAuthException(
            AuthErrorCode.requiresRecentLogin,
            'Please sign in again to complete this action.',
          ),
        ),
      );
    });
  });

  group('FirebaseAuthException code mapping table', () {
    final cases =
        <
          ({
            String nativeCode,
            AuthErrorCode expectedCode,
            String expectedMessage,
          })
        >[
          (
            nativeCode: 'invalid-email',
            expectedCode: AuthErrorCode.invalidEmail,
            expectedMessage: 'That email address is not valid.',
          ),
          (
            nativeCode: 'user-disabled',
            expectedCode: AuthErrorCode.userDisabled,
            expectedMessage: 'This account has been disabled.',
          ),
          (
            nativeCode: 'user-not-found',
            expectedCode: AuthErrorCode.invalidCredential,
            expectedMessage: 'Incorrect email or password.',
          ),
          (
            nativeCode: 'wrong-password',
            expectedCode: AuthErrorCode.invalidCredential,
            expectedMessage: 'Incorrect email or password.',
          ),
          (
            nativeCode: 'invalid-credential',
            expectedCode: AuthErrorCode.invalidCredential,
            expectedMessage: 'Incorrect email or password.',
          ),
          (
            nativeCode: 'INVALID_LOGIN_CREDENTIALS',
            expectedCode: AuthErrorCode.invalidCredential,
            expectedMessage: 'Incorrect email or password.',
          ),
          (
            nativeCode: 'user-mismatch',
            expectedCode: AuthErrorCode.invalidCredential,
            expectedMessage: 'The credential does not match the current user.',
          ),
          (
            nativeCode: 'email-already-in-use',
            expectedCode: AuthErrorCode.emailAlreadyInUse,
            expectedMessage: 'An account already exists for that email.',
          ),
          (
            nativeCode: 'credential-already-in-use',
            expectedCode: AuthErrorCode.emailAlreadyInUse,
            expectedMessage: 'An account already exists for that email.',
          ),
          (
            nativeCode: 'account-exists-with-different-credential',
            expectedCode: AuthErrorCode.emailAlreadyInUse,
            expectedMessage: 'An account already exists for that email.',
          ),
          (
            nativeCode: 'provider-already-linked',
            expectedCode: AuthErrorCode.emailAlreadyInUse,
            expectedMessage: 'An account already exists for that email.',
          ),
          (
            nativeCode: 'weak-password',
            expectedCode: AuthErrorCode.weakPassword,
            expectedMessage: 'That password is too weak (min 6 characters).',
          ),
          (
            nativeCode: 'operation-not-allowed',
            expectedCode: AuthErrorCode.operationNotAllowed,
            expectedMessage: 'This sign-in method is not enabled.',
          ),
          (
            nativeCode: 'requires-recent-login',
            expectedCode: AuthErrorCode.requiresRecentLogin,
            expectedMessage: 'Please sign in again to complete this action.',
          ),
          (
            nativeCode: 'user-token-expired',
            expectedCode: AuthErrorCode.sessionExpired,
            expectedMessage: 'Your session has expired. Please sign in again.',
          ),
          (
            nativeCode: 'invalid-user-token',
            expectedCode: AuthErrorCode.sessionExpired,
            expectedMessage: 'Your session has expired. Please sign in again.',
          ),
          (
            nativeCode: 'too-many-requests',
            expectedCode: AuthErrorCode.tooManyRequests,
            expectedMessage: 'Too many attempts. Please try again later.',
          ),
          (
            nativeCode: 'network-request-failed',
            expectedCode: AuthErrorCode.network,
            expectedMessage:
                'Network error. Check your connection and try again.',
          ),
          (
            nativeCode: 'popup-closed-by-user',
            expectedCode: AuthErrorCode.cancelled,
            expectedMessage: 'Sign-in was cancelled.',
          ),
          (
            nativeCode: 'cancelled-popup-request',
            expectedCode: AuthErrorCode.cancelled,
            expectedMessage: 'Sign-in was cancelled.',
          ),
          (
            nativeCode: 'web-context-canceled',
            expectedCode: AuthErrorCode.cancelled,
            expectedMessage: 'Sign-in was cancelled.',
          ),
          (
            nativeCode: 'canceled',
            expectedCode: AuthErrorCode.cancelled,
            expectedMessage: 'Sign-in was cancelled.',
          ),
          (
            nativeCode: 'some-unmapped-code',
            expectedCode: AuthErrorCode.unknown,
            expectedMessage: 'Authentication failed (some-unmapped-code).',
          ),
        ];

    for (final c in cases) {
      test('maps "${c.nativeCode}" to ${c.expectedCode.name}', () async {
        final auth = MockFirebaseAuth();
        whenCalling(
          Invocation.method(#signInAnonymously, null),
        ).on(auth).thenThrow(FirebaseAuthException(code: c.nativeCode));

        final service = FirebaseAuthService(auth: auth);
        await expectLater(
          service.signInAnonymously(),
          throwsA(_isAuthException(c.expectedCode, c.expectedMessage)),
        );
      });
    }
  });
}
