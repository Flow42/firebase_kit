import 'package:firebase_kit/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAuthService fake;

  setUp(() {
    fake = FakeAuthService();
  });

  tearDown(() async {
    await fake.dispose();
  });

  test(
    'broadcast stream emits current user on listen and on transitions',
    () async {
      final seeded = FakeAuthService(
        initialUser: const AuthUser(uid: 'initial-1', email: 'a@b.c'),
      );
      addTearDown(seeded.dispose);

      expect(await seeded.authStateChanges().first, isNotNull);
      expect((await seeded.authStateChanges().first)!.uid, 'initial-1');

      final events = <String?>[];
      final sub = fake.authStateChanges().listen((u) => events.add(u?.uid));
      addTearDown(sub.cancel);

      await Future<void>.delayed(Duration.zero);
      final anon = await fake.signInAnonymously();
      await fake.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(events, [null, anon.uid, null]);
    },
  );

  test(
    'signInAnonymously, signUpWithEmail, signInWithEmail, signInWithGoogle',
    () async {
      final anon = await fake.signInAnonymously();
      expect(anon.isAnonymous, isTrue);
      expect(fake.currentUser?.uid, anon.uid);

      final signedUp = await fake.signUpWithEmail('  ada@example.com ', 'pw');
      expect(signedUp.email, 'ada@example.com');
      expect(signedUp.isAnonymous, isFalse);

      final signedIn = await fake.signInWithEmail(' grace@example.com ', 'pw');
      expect(signedIn.email, 'grace@example.com');

      final google = await fake.signInWithGoogle();
      expect(google.email, 'user@gmail.com');
      expect(google.displayName, 'Google User');

      expect(fake.calls, [
        'signInAnonymously',
        'signUpWithEmail:  ada@example.com ',
        'signInWithEmail: grace@example.com ',
        'signInWithGoogle',
      ]);
    },
  );

  test('linkEmail and linkGoogle preserve uid and drop anonymity', () async {
    await expectLater(
      fake.linkEmail('a@b.c', 'pw'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AuthErrorCode.noCurrentUser,
        ),
      ),
    );
    await expectLater(
      fake.linkGoogle(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AuthErrorCode.noCurrentUser,
        ),
      ),
    );

    final anon = await fake.signInAnonymously();
    final linkedEmail = await fake.linkEmail(' ada@example.com ', 'pw');
    expect(linkedEmail.uid, anon.uid);
    expect(linkedEmail.isAnonymous, isFalse);
    expect(linkedEmail.email, 'ada@example.com');

    final anon2 = await fake.signInAnonymously();
    final linkedGoogle = await fake.linkGoogle();
    expect(linkedGoogle.uid, anon2.uid);
    expect(linkedGoogle.isAnonymous, isFalse);
    expect(linkedGoogle.displayName, 'Google User');
  });

  test(
    'failWith arms one failure with optional AuthErrorCode then recovers',
    () async {
      fake.failWith('Bad credentials', code: AuthErrorCode.invalidCredential);

      await expectLater(
        fake.signInWithEmail('a@b.c', 'wrong'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.message, 'message', 'Bad credentials')
              .having((e) => e.code, 'code', AuthErrorCode.invalidCredential),
        ),
      );

      final user = await fake.signInWithEmail('a@b.c', 'right');
      expect(user.email, 'a@b.c');
    },
  );

  test('actionDelay delays resolution', () async {
    fake.actionDelay = const Duration(milliseconds: 25);
    final sw = Stopwatch()..start();
    await fake.signInAnonymously();
    sw.stop();
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(15));
  });

  test('getIdToken and ensureValidSession cover all four outcomes', () async {
    expect(await fake.ensureValidSession(), SessionCheck.noSession);
    await expectLater(
      fake.getIdToken(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AuthErrorCode.noCurrentUser,
        ),
      ),
    );

    final user = await fake.signInAnonymously();
    expect(await fake.getIdToken(), 'fake-id-token-${user.uid}');
    expect(await fake.ensureValidSession(), SessionCheck.valid);

    fake.failWith('offline', code: AuthErrorCode.network);
    expect(await fake.ensureValidSession(), SessionCheck.keptOffline);
    expect(fake.currentUser, isNotNull);

    fake.actionDelay = const Duration(milliseconds: 40);
    expect(
      await fake.ensureValidSession(timeout: const Duration(milliseconds: 10)),
      SessionCheck.keptOffline,
    );
    fake.actionDelay = Duration.zero;
    expect(fake.currentUser, isNotNull);

    fake.failWith('revoked', code: AuthErrorCode.sessionExpired);
    expect(await fake.ensureValidSession(), SessionCheck.signedOut);
    expect(fake.currentUser, isNull);
  });

  test(
    'password reset, email verification, reload, displayName, reauth, delete',
    () async {
      await fake.sendPasswordResetEmail('  ada@example.com  ');
      expect(fake.calls, contains('sendPasswordResetEmail:ada@example.com'));

      await expectLater(
        fake.sendEmailVerification(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthErrorCode.noCurrentUser,
          ),
        ),
      );

      await fake.signUpWithEmail('ada@example.com', 'secret1');
      expect(fake.currentUser!.emailVerified, isFalse);

      await fake.sendEmailVerification();
      final reloaded = await fake.reloadUser();
      expect(reloaded.emailVerified, isTrue);

      final renamed = await fake.updateDisplayName('Ada Lovelace');
      expect(renamed.displayName, 'Ada Lovelace');

      await fake.reauthenticateWithEmail('  ada@example.com ', 'secret1');
      await fake.reauthenticateWithGoogle();
      expect(
        fake.calls,
        containsAll([
          'reauthenticateWithEmail:ada@example.com',
          'reauthenticateWithGoogle',
        ]),
      );

      await fake.deleteAccount();
      expect(fake.currentUser, isNull);
    },
  );
}
