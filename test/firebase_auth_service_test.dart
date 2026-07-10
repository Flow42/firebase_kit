import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_kit/firebase_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts signed out', () {
    final service = FirebaseAuthService(auth: MockFirebaseAuth());
    expect(service.currentUser, isNull);
  });

  test('signInAnonymously produces a user', () async {
    final service = FirebaseAuthService(auth: MockFirebaseAuth());
    final user = await service.signInAnonymously();
    expect(user.uid, isNotEmpty);
    expect(service.currentUser, isNotNull);
  });

  test('signUpWithEmail returns a user carrying the email', () async {
    final service = FirebaseAuthService(auth: MockFirebaseAuth());
    final user = await service.signUpWithEmail('ada@example.com', 'secret1');
    expect(user.email, 'ada@example.com');
  });

  test('signInWithEmail signs the user in', () async {
    final service = FirebaseAuthService(auth: MockFirebaseAuth());
    final user = await service.signInWithEmail('grace@example.com', 'secret1');
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
}
