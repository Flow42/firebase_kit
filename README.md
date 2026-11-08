# firebase_kit

Reusable, **state-management-agnostic** Firebase building blocks shared across Flutter apps.

## What the Kit Is — and Is Not

### What it is
- **Single-call startup (`FirebaseKit.initialize`)**: initializes Flutter bindings and Firebase, wires the Firebase Local Emulator Suite (at most once per process, hot-restart safe), and validates any persisted auth session before `runApp`.
- **Hardened `AuthService` abstraction**: covers sign-in (anonymous, email/password, Google), account linking (`linkEmail`, `linkGoogle`), token retrieval (`getIdToken`), startup session validation (`ensureValidSession`), password reset, email verification, user reload, display-name updates, reauthentication, and account deletion — without leaking `firebase_auth` types to callers.
- **Typed error codes (`AuthErrorCode`)**: maps `FirebaseAuthException` and `GoogleSignInException` codes into a stable Dart enum alongside human-readable messages.
- **In-memory test double (`FakeAuthService`)**: exported from `package:firebase_kit/testing.dart` for fast widget and unit tests without Firebase or `flutter_test` dependencies.
- **Thin Firestore helpers (`JsonDocument<T>`, `UserScope`)**: typed single-document load/save/watch with fallback and parse-error reporting, plus `users/{uid}` path scoping.
- **Executable project scaffolding (`dart run firebase_kit:scaffold`)**: generates and drift-checks (`--check`) dev/test scripts for USB-connected Android devices (`adb reverse`), headless Chrome (`TEST_DEVICE=web`), and Firestore Security Rules tests.

### What it is not
- **Not a multi-language SDK**: targets Flutter apps only (`firebase_core ^4`, `firebase_auth ^6`, `cloud_firestore ^6`).
- **Not a state-management library**: no Riverpod, Bloc, or Provider dependency. Wrap `AuthService` in whatever state layer your app uses.
- **Not a generic Firestore ORM**: concrete repositories, data models, `firebase_options.dart`, and `firestore.rules` stay in each consuming app.
- **No extra Firebase products**: does not include Apple Sign-In, Storage, Functions, Messaging, Remote Config, Analytics, or App Check.

---

## Quick Start

Add `firebase_kit` to your app's `pubspec.yaml`:

```yaml
dependencies:
  firebase_kit:
    git:
      url: https://github.com/Flow42/firebase_kit.git
      ref: v0.2.0
```

Initialize Firebase and `AuthService` in `lib/main.dart`:

```dart
import 'package:firebase_kit/firebase_kit.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  final kit = await FirebaseKit.initialize(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(MyApp(authService: kit.auth));
}
```

> [!WARNING]
> **`USE_FIREBASE_EMULATOR` defaults to `true`!**
> `EmulatorSettings.fromEnvironment()` (used by default in `FirebaseKit.initialize`) reads `--dart-define=USE_FIREBASE_EMULATOR`, which defaults to `true` so local runs never hit production by accident.
> **Production builds MUST pass `--dart-define=USE_FIREBASE_EMULATOR=false`** (or pass `emulator: const EmulatorSettings.disabled()` to `FirebaseKit.initialize`).

---

## Authentication (`AuthService`, `FirebaseAuthService`)

### Operations

| Method | Description |
| --- | --- |
| `currentUser` | Synchronously returns the cached `AuthUser?` (`uid`, `email`, `displayName`, `isAnonymous`, `emailVerified`, `label`). |
| `authStateChanges()` | Broadcast stream emitting the current `AuthUser?` immediately upon listen and on every sign-in, sign-out, link, or reload event. |
| `signInAnonymously()` | Signs in as an anonymous guest user. |
| `signInWithEmail(email, password)` | Signs in with trimmed email and password. |
| `signUpWithEmail(email, password)` | Creates a new email/password account. |
| `signInWithGoogle()` | Signs in with Google (lazily initializes `GoogleSignIn.instance` once per service instance on native platforms, or uses `signInWithPopup` on web). |
| `linkEmail(email, password)` | Upgrades the current (typically anonymous) user to an email/password credential while preserving `uid`. |
| `linkGoogle()` | Upgrades the current user with a Google credential while preserving `uid`. |
| `getIdToken({forceRefresh = false})` | Returns the current user's Firebase ID token (`String`) for authenticating against custom backends. Throws `AuthException(code: AuthErrorCode.noCurrentUser)` when signed out. |
| `ensureValidSession({timeout = 10s})` | Force-refreshes the persisted user's token and returns a `SessionCheck` (`noSession`, `valid`, `keptOffline`, `signedOut`). Signs out automatically if the token is rejected by the backend (e.g., after an emulator restart or account deletion), while preserving the session offline on network/timeout errors. |
| `sendPasswordResetEmail(email)` | Sends a password-reset email to the trimmed address. |
| `sendEmailVerification()` | Sends an address-verification email to the current user. |
| `reloadUser()` | Reloads the current user's profile from the server and emits the updated `AuthUser` on `authStateChanges()`. |
| `updateDisplayName(name)` | Updates the current user's display name and emits the updated `AuthUser`. |
| `reauthenticateWithEmail(email, password)` | Reauthenticates the current user with email and password before sensitive operations. |
| `reauthenticateWithGoogle()` | Reauthenticates the current user with Google before sensitive operations. |
| `deleteAccount()` | Permanently deletes the current user's account (and signs out of Google on native platforms). |
| `signOut()` | Signs out of Firebase Auth (and best-effort signs out of Google on native platforms so the account picker is shown next time). |

### Error Codes (`AuthErrorCode`)

Every `AuthException` carries both a human-readable `message` and a typed `code`:

| `AuthErrorCode` | Mapped `FirebaseAuthException` / `GoogleSignInException` codes |
| --- | --- |
| `invalidEmail` | `invalid-email` |
| `userDisabled` | `user-disabled` |
| `invalidCredential` | `user-not-found`, `wrong-password`, `invalid-credential`, `INVALID_LOGIN_CREDENTIALS`, `user-mismatch`, or missing Google ID token |
| `emailAlreadyInUse` | `email-already-in-use`, `credential-already-in-use`, `account-exists-with-different-credential` |
| `weakPassword` | `weak-password` |
| `operationNotAllowed` | `operation-not-allowed` |
| `requiresRecentLogin` | `requires-recent-login` |
| `sessionExpired` | `user-token-expired`, `invalid-user-token` |
| `tooManyRequests` | `too-many-requests` |
| `network` | `network-request-failed` |
| `cancelled` | `popup-closed-by-user`, `cancelled-popup-request`, `web-context-canceled`, `GoogleSignInExceptionCode.canceled` |
| `noCurrentUser` | Operation requires a signed-in user when `currentUser == null` |
| `unknown` | Any unmapped error code |

---

## Testing with `FakeAuthService`

Import `package:firebase_kit/testing.dart` in your unit or widget tests (this entrypoint is separate from `package:firebase_kit/firebase_kit.dart` so test doubles are never bundled into production code):

```dart
import 'package:firebase_kit/firebase_kit.dart';
import 'package:firebase_kit/testing.dart';

final auth = FakeAuthService(
  initialUser: const AuthUser(uid: 'u1', email: 'ada@example.com'),
);

// Arm a one-shot failure for the next operation:
auth.failWith('Wrong password', code: AuthErrorCode.invalidCredential);

// Simulate in-flight latency for spinner tests:
auth.actionDelay = const Duration(milliseconds: 200);
```

---

## Thin Firestore Helpers

### `UserScope`

Scopes document and collection paths under `users/{uid}` (configurable via `usersCollection`):

```dart
final scope = UserScope(FirebaseFirestore.instance, uid);
final userRef = scope.userDoc;                      // users/{uid}
final settingsRef = scope.doc('config/settings');   // users/{uid}/config/settings
final itemsCol = scope.collection('items');         // users/{uid}/items
```

### `JsonDocument<T>`

Wraps a single `DocumentReference<Map<String, dynamic>>` with `fromJson`, `toJson`, `fallback`, and an optional `onParseError` callback:

```dart
final settingsDoc = JsonDocument<AppSettings>(
  ref: UserScope(firestore, uid).doc('config/settings'),
  fromJson: AppSettings.fromJson,
  toJson: (s) => s.toJson(),
  fallback: const AppSettings(),
  onParseError: (error, stackTrace) => debugPrint('Corrupt settings: $error'),
);

final settings = await settingsDoc.load();
await settingsDoc.save(settings.copyWith(darkMode: true));
Stream<AppSettings> stream = settingsDoc.watch();
```

- When the document does not exist, `load()` and `watch()` return `fallback` without calling `onParseError`.
- When the document exists but `fromJson` throws, `load()` and `watch()` report the error to `onParseError` and return `fallback`.

---

## Project Scaffolding (`dart run firebase_kit:scaffold`)

Run the scaffold command from the root of a consuming Flutter app:

```bash
dart run firebase_kit:scaffold
```

This writes 5 managed files (each stamped with a versioned `DO NOT EDIT BY HAND` header):
- `scripts/run_dev.sh` — starts or reuses the Firebase emulators (`--restart` to force restart), configures `adb reverse` when a USB-connected Android device is present (falling back to LAN IP otherwise), and runs `flutter run`.
- `scripts/test_integration.sh` — wraps `firebase emulators:exec` around `flutter test <target> -d <device>` for a USB-connected Android device with `adb reverse`, or `flutter drive` in headless Chrome when `TEST_DEVICE=web`.
- `scripts/test_security_rules.sh` — runs Node's built-in test runner (`node --test`) inside `firebase emulators:exec --only firestore`.
- `test_driver/integration_test.dart` — driver entrypoint used for `TEST_DEVICE=web`.
- `test/security_rules/rules_test_env.mjs` — helper wrapping `@firebase/rules-unit-testing` (`createRulesTestEnv`).

It also creates `scripts/firebase_kit.env` **only if missing** (never overwriting app-specific values):

```bash
FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-demo-app}"
FIREBASE_EMULATORS="${FIREBASE_EMULATORS:-auth,firestore}"
AUTH_EMULATOR_PORT="${AUTH_EMULATOR_PORT:-9099}"
FIRESTORE_EMULATOR_PORT="${FIRESTORE_EMULATOR_PORT:-8080}"
TEST_TARGET="${TEST_TARGET:-integration_test/app_test.dart}"
WEB_TEST_TARGET="${WEB_TEST_TARGET:-}"
TEST_DEVICE="${TEST_DEVICE:-}"
EXTRA_DART_DEFINES="${EXTRA_DART_DEFINES:-}"
```

To verify in CI that no managed file has drifted from the current `firebase_kit` version:

```bash
dart run firebase_kit:scaffold --check
```

---

## Running Integration Tests on a USB-Connected Android Device

1. **USB Debugging & `adb reverse`**:
   `scripts/test_integration.sh` automatically detects the connected Android device from `adb devices`, forwards `tcp:9099` (Auth) and `tcp:8080` (Firestore) via `adb reverse`, and passes:
   - `--dart-define=USE_FIREBASE_EMULATOR=true`
   - `--dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1`
   - `--dart-define=FIREBASE_EMULATOR_HOST_MAPPING=false`
   Passing `FIREBASE_EMULATOR_HOST_MAPPING=false` prevents FlutterFire from rewriting `127.0.0.1` to the Android emulator alias `10.0.2.2`, which is unreachable on a physical phone.

2. **Debug-Only Cleartext HTTP Configuration**:
   Android 9+ blocks cleartext HTTP traffic by default, while the local Firebase Emulator Suite serves plain HTTP. Add `android/app/src/debug/res/xml/network_security_config.xml`:

   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <network-security-config>
       <domain-config cleartextTrafficPermitted="true">
           <domain includeSubdomains="true">127.0.0.1</domain>
           <domain includeSubdomains="true">localhost</domain>
           <domain includeSubdomains="true">10.0.2.2</domain>
       </domain-config>
   </network-security-config>
   ```

   And reference it in `android/app/src/debug/AndroidManifest.xml`:

   ```xml
   <manifest xmlns:android="http://schemas.android.com/apk/res/android">
       <uses-permission android:name="android.permission.INTERNET"/>
       <application android:networkSecurityConfig="@xml/network_security_config" />
   </manifest>
   ```

   Because this manifest lives under `src/debug/`, release builds remain TLS-only.

---

## Running `firebase_kit`'s Own Tests

```bash
# Fast host-side unit tests (no network or emulator required):
flutter test

# Full integration test suite on a USB-connected Android device:
cd example
bash scripts/test_integration.sh
```
