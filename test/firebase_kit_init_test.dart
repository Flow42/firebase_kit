import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_kit/firebase_kit.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAuth extends MockFirebaseAuth {
  _RecordingAuth({super.signedIn, super.mockUser});

  final List<({String host, int port, bool automaticHostMapping})>
  emulatorCalls = [];

  @override
  Future<void> useAuthEmulator(
    String host,
    int port, {
    bool automaticHostMapping = true,
  }) async {
    emulatorCalls.add((
      host: host,
      port: port,
      automaticHostMapping: automaticHostMapping,
    ));
  }
}

class _RecordingFirestore implements FirebaseFirestore {
  final List<({String host, int port, bool automaticHostMapping})>
  emulatorCalls = [];
  Object? errorToThrow;

  @override
  void useFirestoreEmulator(
    String host,
    int port, {
    bool sslEnabled = false,
    bool automaticHostMapping = true,
  }) {
    emulatorCalls.add((
      host: host,
      port: port,
      automaticHostMapping: automaticHostMapping,
    ));
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    resetEmulatorConnectionStateForTesting();
  });

  test('EmulatorSettings defaults and fromEnvironment defaults', () {
    const defaults = EmulatorSettings();
    expect(defaults.enabled, isTrue);
    expect(defaults.host, 'localhost');
    expect(defaults.authPort, 9099);
    expect(defaults.firestorePort, 8080);
    expect(defaults.automaticHostMapping, isTrue);

    const disabled = EmulatorSettings.disabled();
    expect(disabled.enabled, isFalse);

    final fromEnv = EmulatorSettings.fromEnvironment();
    expect(fromEnv.enabled, isTrue);
    expect(fromEnv.host, 'localhost');
    expect(fromEnv.automaticHostMapping, isTrue);
  });

  test(
    'connectToFirebaseEmulators forwards automaticHostMapping and runs at most once',
    () async {
      final auth = _RecordingAuth();
      final firestore = _RecordingFirestore();

      await connectToFirebaseEmulators(
        config: const EmulatorSettings(
          host: '127.0.0.1',
          authPort: 9099,
          firestorePort: 8080,
          automaticHostMapping: false,
        ),
        authInstance: auth,
        firestoreInstance: firestore,
      );

      expect(areFirebaseEmulatorsConnected, isTrue);
      expect(auth.emulatorCalls, [
        (host: '127.0.0.1', port: 9099, automaticHostMapping: false),
      ]);
      expect(firestore.emulatorCalls, [
        (host: '127.0.0.1', port: 8080, automaticHostMapping: false),
      ]);

      // A second call in the same isolate is a no-op.
      await connectToFirebaseEmulators(
        config: const EmulatorSettings(host: '192.168.1.10'),
        authInstance: auth,
        firestoreInstance: firestore,
      );
      expect(auth.emulatorCalls, hasLength(1));
      expect(firestore.emulatorCalls, hasLength(1));
    },
  );

  test(
    'connectToFirebaseEmulators tolerates Firestore already-started error on hot restart',
    () async {
      final auth = _RecordingAuth();
      final firestore = _RecordingFirestore()
        ..errorToThrow = StateError(
          'Firestore has already been started and its settings can no longer be changed.',
        );

      await connectToFirebaseEmulators(
        authInstance: auth,
        firestoreInstance: firestore,
      );
      expect(firestore.emulatorCalls, hasLength(1));
    },
  );

  test(
    'FirebaseKit.initialize runs appInitializer, connects emulators, and checks session',
    () async {
      var appInitCalls = 0;
      final auth = _RecordingAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u-init', email: 'ada@example.com'),
      );
      final firestore = _RecordingFirestore();

      final kit = await FirebaseKit.initialize(
        emulator: const EmulatorSettings(
          host: '127.0.0.1',
          automaticHostMapping: false,
        ),
        checkSession: true,
        auth: auth,
        firestore: firestore,
        appInitializer: ({options}) async {
          appInitCalls++;
        },
      );

      expect(appInitCalls, 1);
      expect(kit.auth.currentUser?.uid, 'u-init');
      expect(kit.sessionCheck, SessionCheck.valid);
      expect(kit.emulator.automaticHostMapping, isFalse);
      expect(auth.emulatorCalls, hasLength(1));
      expect(firestore.emulatorCalls, hasLength(1));
    },
  );

  test(
    'FirebaseKit.initialize skips emulators when disabled and checkSession=false',
    () async {
      final auth = _RecordingAuth();
      final firestore = _RecordingFirestore();

      final kit = await FirebaseKit.initialize(
        emulator: const EmulatorSettings.disabled(),
        checkSession: false,
        auth: auth,
        firestore: firestore,
        appInitializer: ({options}) async {},
      );

      expect(kit.sessionCheck, isNull);
      expect(auth.emulatorCalls, isEmpty);
      expect(firestore.emulatorCalls, isEmpty);
      expect(areFirebaseEmulatorsConnected, isFalse);
    },
  );
}
