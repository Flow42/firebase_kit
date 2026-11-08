import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_kit/firebase_kit.dart';
import 'package:firebase_kit_example/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String _projectId = DefaultFirebaseOptions.projectId;
const String _emulatorHost = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
  defaultValue: '127.0.0.1',
);
const int _authPort = 9099;
const int _firestorePort = 8080;

Future<void> _deleteUrl(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.deleteUrl(uri);
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode >= 400) {
      throw HttpException(
        'DELETE $uri failed with status ${response.statusCode}',
        uri: uri,
      );
    }
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _getJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 400) {
      throw HttpException(
        'GET $uri failed (${response.statusCode}): $body',
        uri: uri,
      );
    }
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _postJson(
  Uri uri,
  Map<String, dynamic> payload, {
  String? bearerToken,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    if (bearerToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $bearerToken',
      );
    }
    request.write(jsonEncode(payload));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 400) {
      throw HttpException(
        'POST $uri failed (${response.statusCode}): $body',
        uri: uri,
      );
    }
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> _clearEmulators() async {
  await _deleteUrl(
    Uri.parse(
      'http://$_emulatorHost:$_authPort/emulator/v1/projects/$_projectId/accounts',
    ),
  );
  await _deleteUrl(
    Uri.parse(
      'http://$_emulatorHost:$_firestorePort/emulator/v1/projects/$_projectId/databases/(default)/documents',
    ),
  );
}

class _ProfileData {
  const _ProfileData({required this.name, required this.level});

  factory _ProfileData.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final level = json['level'];
    if (name is! String || level is! int) {
      throw const FormatException('Invalid _ProfileData payload');
    }
    return _ProfileData(name: name, level: level);
  }

  final String name;
  final int level;

  Map<String, dynamic> toJson() => {'name': name, 'level': level};
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AuthService auth;

  setUpAll(() async {
    final kit = await FirebaseKit.initialize(
      options: DefaultFirebaseOptions.currentPlatform,
      emulator: const EmulatorSettings(
        enabled: true,
        host: _emulatorHost,
        automaticHostMapping: false,
      ),
      checkSession: false,
    );
    auth = kit.auth;
  });

  setUp(() async {
    await _clearEmulators();
    if (auth.currentUser != null) {
      await auth.signOut();
    }
  });

  testWidgets(
    'FirebaseKit.initialize connects with host mapping off and repeat connect is a no-op',
    (tester) async {
      final settings = EmulatorSettings.fromEnvironment();
      expect(settings.enabled, isTrue);
      expect(settings.host, _emulatorHost);
      expect(settings.automaticHostMapping, isFalse);

      // Perform an authenticated Firestore read so the native Firestore instance is started.
      final user = await auth.signInAnonymously();
      await FirebaseFirestore.instance.doc('users/${user.uid}').get();

      // Second call in the same isolate is a no-op.
      await connectToFirebaseEmulators(
        config: const EmulatorSettings(
          host: _emulatorHost,
          automaticHostMapping: false,
        ),
      );
      await FirebaseFirestore.instance.doc('users/${user.uid}').get();

      // Simulate a Dart hot restart where static Dart state resets while the
      // native Firestore instance is already started.
      resetEmulatorConnectionStateForTesting();
      await connectToFirebaseEmulators(
        config: const EmulatorSettings(
          host: _emulatorHost,
          automaticHostMapping: false,
        ),
      );
      await FirebaseFirestore.instance.doc('users/${user.uid}').get();
    },
  );

  testWidgets(
    'anonymous sign-in then linkEmail preserves uid and drops anonymity',
    (tester) async {
      final anon = await auth.signInAnonymously();
      expect(anon.isAnonymous, isTrue);

      final linked = await auth.linkEmail('linked@example.com', 'password123');
      expect(linked.uid, anon.uid);
      expect(linked.isAnonymous, isFalse);
      expect(linked.email, 'linked@example.com');
      expect(auth.currentUser?.uid, anon.uid);
    },
  );

  testWidgets(
    'anonymous sign-in then linkGoogle via googleIdToken seam preserves uid',
    (tester) async {
      final googleAuth = FirebaseAuthService(
        auth: FirebaseAuth.instance,
        googleIdToken: () async => jsonEncode({
          'sub': 'google-sub-123',
          'email': 'ada@example.com',
          'email_verified': true,
          'name': 'Ada Lovelace',
        }),
      );

      final anon = await googleAuth.signInAnonymously();
      expect(anon.isAnonymous, isTrue);

      final linked = await googleAuth.linkGoogle();
      expect(linked.uid, anon.uid);
      expect(linked.isAnonymous, isFalse);
      expect(linked.email, 'ada@example.com');

      await googleAuth.signOut();
      final signedInAgain = await googleAuth.signInWithGoogle();
      expect(signedInAgain.uid, anon.uid);
      expect(signedInAgain.email, 'ada@example.com');
    },
  );

  testWidgets('maps Auth emulator error codes to AuthErrorCode enum values', (
    tester,
  ) async {
    // 1. invalidEmail
    await expectLater(
      () => auth.signUpWithEmail('not-an-email', 'password123'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AuthErrorCode.invalidEmail,
        ),
      ),
    );

    // 2. weakPassword
    await expectLater(
      () => auth.signUpWithEmail('weak@example.com', '123'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AuthErrorCode.weakPassword,
        ),
      ),
    );

    // 3. emailAlreadyInUse
    final created = await auth.signUpWithEmail(
      'existing@example.com',
      'password123',
    );
    await expectLater(
      () => auth.signUpWithEmail('existing@example.com', 'password123'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AuthErrorCode.emailAlreadyInUse,
        ),
      ),
    );

    // 4. invalidCredential (wrong password and missing user)
    await auth.signOut();
    await expectLater(
      () => auth.signInWithEmail('existing@example.com', 'wrong-password'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AuthErrorCode.invalidCredential,
        ),
      ),
    );
    await expectLater(
      () => auth.signInWithEmail('nobody@example.com', 'password123'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AuthErrorCode.invalidCredential,
        ),
      ),
    );

    // 5. userDisabled (via Auth emulator Admin account update endpoint)
    await _postJson(
      Uri.parse(
        'http://$_emulatorHost:$_authPort/identitytoolkit.googleapis.com/v1/projects/$_projectId/accounts:update',
      ),
      {'localId': created.uid, 'disableUser': true},
      bearerToken: 'owner',
    );
    await expectLater(
      () => auth.signInWithEmail('existing@example.com', 'password123'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AuthErrorCode.userDisabled,
        ),
      ),
    );

    // 6. noCurrentUser when signed out
    await expectLater(
      () => auth.getIdToken(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AuthErrorCode.noCurrentUser,
        ),
      ),
    );
  });

  testWidgets(
    'ensureValidSession returns valid for active user and signedOut after emulator accounts are cleared',
    (tester) async {
      expect(await auth.ensureValidSession(), SessionCheck.noSession);

      await auth.signUpWithEmail('session@example.com', 'password123');
      expect(await auth.ensureValidSession(), SessionCheck.valid);
      final token = await auth.getIdToken(forceRefresh: true);
      expect(token, isNotEmpty);

      // Clear accounts on the emulator while the client still holds a cached user.
      await _deleteUrl(
        Uri.parse(
          'http://$_emulatorHost:$_authPort/emulator/v1/projects/$_projectId/accounts',
        ),
      );

      final check = await auth.ensureValidSession();
      expect(check, SessionCheck.signedOut);
      expect(auth.currentUser, isNull);
    },
  );

  testWidgets(
    'sendPasswordResetEmail and sendEmailVerification record oobCodes and reloadUser updates emailVerified',
    (tester) async {
      final user = await auth.signUpWithEmail(
        'verify@example.com',
        'password123',
      );
      expect(user.emailVerified, isFalse);

      await auth.sendPasswordResetEmail('verify@example.com');
      await auth.sendEmailVerification();

      final oobJson = await _getJson(
        Uri.parse(
          'http://$_emulatorHost:$_authPort/emulator/v1/projects/$_projectId/oobCodes',
        ),
      );
      final codes = (oobJson['oobCodes'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(
        codes.any(
          (c) =>
              c['email'] == 'verify@example.com' &&
              c['requestType'] == 'PASSWORD_RESET',
        ),
        isTrue,
      );

      final verifyEntry = codes.firstWhere(
        (c) =>
            c['email'] == 'verify@example.com' &&
            c['requestType'] == 'VERIFY_EMAIL',
      );
      final verifyCode = verifyEntry['oobCode'] as String;

      // Apply the verification oobCode against the emulator and reloadUser().
      await _postJson(
        Uri.parse(
          'http://$_emulatorHost:$_authPort/identitytoolkit.googleapis.com/v1/accounts:update?key=demo-api-key',
        ),
        {'oobCode': verifyCode},
      );

      final reloaded = await auth.reloadUser();
      expect(reloaded.emailVerified, isTrue);
      expect(auth.currentUser?.emailVerified, isTrue);
    },
  );

  testWidgets(
    'updateDisplayName, reauthenticateWithEmail, reauthenticateWithGoogle, and deleteAccount',
    (tester) async {
      final user = await auth.signUpWithEmail(
        'delete-me@example.com',
        'password123',
      );
      final updated = await auth.updateDisplayName('Grace Hopper');
      expect(updated.displayName, 'Grace Hopper');
      expect(updated.label, 'Grace Hopper');

      await auth.reauthenticateWithEmail(
        'delete-me@example.com',
        'password123',
      );
      await auth.deleteAccount();
      expect(auth.currentUser, isNull);

      // Re-signing in with the deleted account fails with invalidCredential.
      await expectLater(
        () => auth.signInWithEmail('delete-me@example.com', 'password123'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthErrorCode.invalidCredential,
          ),
        ),
      );

      // Also verify reauthenticateWithGoogle + deleteAccount on a Google user.
      final googleAuth = FirebaseAuthService(
        auth: FirebaseAuth.instance,
        googleIdToken: () async => jsonEncode({
          'sub': 'google-delete-sub',
          'email': 'google-delete@example.com',
          'email_verified': true,
        }),
      );
      await googleAuth.signInWithGoogle();
      expect(googleAuth.currentUser?.uid, isNotNull);
      expect(user.uid, isNot(equals(googleAuth.currentUser?.uid)));
      await googleAuth.reauthenticateWithGoogle();
      await googleAuth.deleteAccount();
      expect(googleAuth.currentUser, isNull);
    },
  );

  testWidgets(
    'UserScope and JsonDocument save, load, watch, and corrupt fallback on device',
    (tester) async {
      final user = await auth.signInAnonymously();
      final scope = UserScope(FirebaseFirestore.instance, user.uid);
      final parseErrors = <Object>[];

      final doc = JsonDocument<_ProfileData>(
        ref: scope.doc('settings/profile'),
        fromJson: _ProfileData.fromJson,
        toJson: (value) => value.toJson(),
        fallback: const _ProfileData(name: 'Fallback', level: 0),
        onParseError: (error, _) => parseErrors.add(error),
      );

      // 1. Missing document returns fallback without calling onParseError.
      final missing = await doc.load();
      expect(missing.name, 'Fallback');
      expect(missing.level, 0);
      expect(parseErrors, isEmpty);

      // 2. Watch stream emits updates as document is saved and corrupted.
      final emissions = <_ProfileData>[];
      final sub = doc.watch().listen(emissions.add);
      addTearDown(sub.cancel);

      // Wait for initial missing emission.
      await tester.pump(const Duration(milliseconds: 200));

      // Save valid data.
      await doc.save(const _ProfileData(name: 'Archer', level: 5));
      final loaded = await doc.load();
      expect(loaded.name, 'Archer');
      expect(loaded.level, 5);

      // Write corrupt data directly to Firestore.
      await scope.doc('settings/profile').set({'name': 999, 'level': 'oops'});
      final corruptLoaded = await doc.load();
      expect(corruptLoaded.name, 'Fallback');
      expect(corruptLoaded.level, 0);
      expect(parseErrors, isNotEmpty);

      await tester.pump(const Duration(milliseconds: 200));
      expect(
        emissions.map((e) => '${e.name}:${e.level}'),
        containsAllInOrder(['Fallback:0', 'Archer:5', 'Fallback:0']),
      );
    },
  );
}
