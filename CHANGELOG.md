# Changelog

## 0.1.0

- Initial extraction from `skilltree_app`.
- Added `AuthService`, `AuthUser`, and `AuthException` with the `FirebaseAuthService` implementation over `firebase_auth` and `google_sign_in` (anonymous sign-in, email/password sign-up and sign-in, Google sign-in, and anonymous-to-email linking).
- Added `FirebaseEmulatorConfig` and `connectToFirebaseEmulators` to wire `FirebaseAuth` and `FirebaseFirestore` to the Firebase Local Emulator Suite.
- Added copy-in `scaffold/` templates (`test_emulator.sh`, `integration_test.dart`) for running integration tests against the emulators.
