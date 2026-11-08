import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_kit/firebase_kit.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings {
  const _Settings({required this.theme, required this.fontSize});

  factory _Settings.fromJson(Map<String, dynamic> json) {
    final theme = json['theme'];
    final fontSize = json['fontSize'];
    if (theme is! String || fontSize is! int) {
      throw const FormatException('Invalid _Settings payload');
    }
    return _Settings(theme: theme, fontSize: fontSize);
  }

  final String theme;
  final int fontSize;

  Map<String, dynamic> toJson() => {'theme': theme, 'fontSize': fontSize};

  @override
  bool operator ==(Object other) =>
      other is _Settings && other.theme == theme && other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(theme, fontSize);
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('UserScope', () {
    test('resolves userDoc, relative docs, and relative collections', () {
      final scope = UserScope(firestore, 'alice');
      expect(scope.userDoc.path, 'users/alice');
      expect(scope.doc().path, 'users/alice');
      expect(scope.doc('').path, 'users/alice');
      expect(scope.doc('config/settings').path, 'users/alice/config/settings');
      expect(
        scope.doc('/config/settings/').path,
        'users/alice/config/settings',
      );
      expect(scope.collection('config').path, 'users/alice/config');
      expect(() => scope.collection(''), throwsArgumentError);
    });

    test('honours custom usersCollection root', () {
      final scope = UserScope(firestore, 'bob', usersCollection: 'accounts');
      expect(scope.userDoc.path, 'accounts/bob');
      expect(scope.doc('config/settings').path, 'accounts/bob/config/settings');
      expect(scope.collection('trees').path, 'accounts/bob/trees');
    });
  });

  group('JsonDocument', () {
    const fallback = _Settings(theme: 'system', fontSize: 14);

    test(
      'returns fallback when document is missing without calling onParseError',
      () async {
        Object? capturedError;
        final doc = JsonDocument<_Settings>(
          ref: UserScope(firestore, 'alice').doc('config/settings'),
          fromJson: _Settings.fromJson,
          toJson: (s) => s.toJson(),
          fallback: fallback,
          onParseError: (error, _) => capturedError = error,
        );

        expect(await doc.load(), fallback);
        expect(capturedError, isNull);
      },
    );

    test(
      'saves and loads a valid document, and supports merge: true',
      () async {
        final ref = UserScope(firestore, 'alice').doc('config/settings');
        final doc = JsonDocument<_Settings>(
          ref: ref,
          fromJson: _Settings.fromJson,
          toJson: (s) => s.toJson(),
          fallback: fallback,
        );

        await ref.set({'extraField': 'keep-me'});
        const saved = _Settings(theme: 'dark', fontSize: 18);
        await doc.save(saved, merge: true);

        expect(await doc.load(), saved);
        final raw = (await ref.get()).data()!;
        expect(raw['extraField'], 'keep-me');

        const overwritten = _Settings(theme: 'light', fontSize: 12);
        await doc.save(overwritten);
        expect(await doc.load(), overwritten);
        final rawAfterOverwrite = (await ref.get()).data()!;
        expect(rawAfterOverwrite.containsKey('extraField'), isFalse);
      },
    );

    test(
      'returns fallback and reports to onParseError when document is corrupt',
      () async {
        final ref = UserScope(firestore, 'alice').doc('config/settings');
        await ref.set({'theme': 12345, 'fontSize': 'not-an-int'});

        Object? capturedError;
        StackTrace? capturedStack;
        final doc = JsonDocument<_Settings>(
          ref: ref,
          fromJson: _Settings.fromJson,
          toJson: (s) => s.toJson(),
          fallback: fallback,
          onParseError: (error, stack) {
            capturedError = error;
            capturedStack = stack;
          },
        );

        expect(await doc.load(), fallback);
        expect(capturedError, isA<FormatException>());
        expect(capturedStack, isNotNull);
      },
    );

    test(
      'watch() emits fallback on missing/corrupt and parsed value on valid data',
      () async {
        final ref = UserScope(firestore, 'alice').doc('config/settings');
        final parseErrors = <Object>[];
        final doc = JsonDocument<_Settings>(
          ref: ref,
          fromJson: _Settings.fromJson,
          toJson: (s) => s.toJson(),
          fallback: fallback,
          onParseError: (error, _) => parseErrors.add(error),
        );

        final emissions = <_Settings>[];
        final sub = doc.watch().listen(emissions.add);
        addTearDown(sub.cancel);

        await Future<void>.delayed(Duration.zero);
        const dark = _Settings(theme: 'dark', fontSize: 16);
        await doc.save(dark);
        await Future<void>.delayed(Duration.zero);

        // Corrupt write should emit fallback and notify onParseError.
        await ref.set({'theme': null, 'fontSize': 'bad'});
        await Future<void>.delayed(Duration.zero);

        expect(emissions, [fallback, dark, fallback]);
        expect(parseErrors, hasLength(1));
      },
    );
  });
}
