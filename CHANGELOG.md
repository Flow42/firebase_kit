# Changelog

## 0.2.0

### Added
- **`FirebaseKit.initialize`**: single startup entry point in `package:firebase_kit/firebase_kit.dart` that initializes Flutter bindings and Firebase, wires the Local Emulator Suite when enabled, and validates any persisted auth session via `ensureValidSession`.
- **Typed `AuthErrorCode` enum and `SessionCheck` enum**: `AuthException` now includes `final AuthErrorCode code` (defaulting to `AuthErrorCode.unknown`).
- **Expanded `AuthService` and `FirebaseAuthService`**:
  - `AuthUser.emailVerified` (`bool`, default `false`).
  - `linkGoogle()` to upgrade an anonymous account with a Google credential while preserving `uid`.
  - `getIdToken({bool forceRefresh = false})` for custom backend authentication.
  - `ensureValidSession({Duration timeout = const Duration(seconds: 10)})` returning `SessionCheck` (`noSession`, `valid`, `keptOffline`, `signedOut`).
  - `sendPasswordResetEmail(String email)`, `sendEmailVerification()`, `reloadUser()`, `updateDisplayName(String name)`, `reauthenticateWithEmail(String email, String password)`, `reauthenticateWithGoogle()`, and `deleteAccount()`.
  - Optional `clientId`, `serverClientId`, and `googleIdToken` test seam parameters on `FirebaseAuthService`.
- **Testing support (`package:firebase_kit/testing.dart`)**: added `FakeAuthService` with in-memory user state, broadcast `authStateChanges()`, `failWith(message, {code})`, and `actionDelay`.
- **Emulator host-mapping and once-per-process guard**:
  - Added `EmulatorSettings` (`FirebaseEmulatorConfig` remains as a typedef alias) with `automaticHostMapping` (read from `FIREBASE_EMULATOR_HOST_MAPPING`, default `true`) and `EmulatorSettings.disabled()`.
  - `connectToFirebaseEmulators` now forwards `automaticHostMapping` to both `useAuthEmulator` and `useFirestoreEmulator`, runs at most once per isolate, and tolerates native Firestore "already started" errors on hot restart.
- **Thin Firestore helpers**:
  - `JsonDocument<T>` (`load()`, `save(value, {merge = false})`, `watch()`, `fallback`, `onParseError`).
  - `UserScope(firestore, uid, {usersCollection = 'users'})` (`userDoc`, `doc([path])`, `collection(path)`).
- **Scaffold CLI (`dart run firebase_kit:scaffold`)**: generates and drift-checks (`--check`) `scripts/run_dev.sh`, `scripts/test_integration.sh`, `scripts/test_security_rules.sh`, `test_driver/integration_test.dart`, `test/security_rules/rules_test_env.mjs`, and per-app `scripts/firebase_kit.env`.
- **Example app and device integration tests (`example/`)**: exercises `FirebaseKit.initialize`, `FirebaseAuthService`, `JsonDocument`, and `UserScope` against the Auth and Firestore emulators on a physical Android device over USB (`adb reverse`).

### Fixed
- **Google Sign-In on native platforms**:
  - Lazily calls `GoogleSignIn.instance.initialize(clientId: ..., serverClientId: ...)` once per `FirebaseAuthService` instance (concurrency-safe, resets on initialization error).
  - Calls `GoogleSignIn.instance.signOut()` (best-effort) on `signOut()` and `deleteAccount()` so subsequent sign-ins show the account picker.
  - Maps `GoogleSignInExceptionCode.canceled` to `AuthException('Sign-in was cancelled.', code: AuthErrorCode.cancelled)` instead of a raw plugin error string.

### Breaking Changes & Migration
- **`AuthService` interface additions**: custom implementations or fakes of `AuthService` must implement the new methods (`linkGoogle`, `getIdToken`, `ensureValidSession`, `sendPasswordResetEmail`, `sendEmailVerification`, `reloadUser`, `updateDisplayName`, `reauthenticateWithEmail`, `reauthenticateWithGoogle`, `deleteAccount`), or switch to `FakeAuthService` from `package:firebase_kit/testing.dart`.
- **Removed `scaffold/` directory**: replace manual copies of `scaffold/test_emulator.sh` and `scaffold/integration_test.dart` by running `dart run firebase_kit:scaffold` and configuring `scripts/firebase_kit.env`.

## 0.1.0

- Initial extraction from `skilltree_app`.
- Added `AuthService`, `AuthUser`, and `AuthException` with the `FirebaseAuthService` implementation over `firebase_auth` and `google_sign_in` (anonymous sign-in, email/password sign-up and sign-in, Google sign-in, and anonymous-to-email linking).
- Added `FirebaseEmulatorConfig` and `connectToFirebaseEmulators` to wire `FirebaseAuth` and `FirebaseFirestore` to the Firebase Local Emulator Suite.
- Added copy-in `scaffold/` templates (`test_emulator.sh`, `integration_test.dart`) for running integration tests against the emulators.
