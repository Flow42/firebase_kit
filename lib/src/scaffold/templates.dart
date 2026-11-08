/// Embedded scaffold templates for `dart run firebase_kit:scaffold`.
///
/// Templates are stored as Dart string constants rather than external files
/// looked up via `Isolate.resolvePackageUri` so the executable is completely
/// self-contained, synchronous, and works identically whether invoked via
/// `dart run firebase_kit:scaffold`, by direct file path, or in unit tests.
library;

/// Kit version stamped into the header of every managed file.
const String firebaseKitScaffoldVersion = '0.2.0';

const String _shHeader =
    '''#!/usr/bin/env bash
# Managed by firebase_kit v$firebaseKitScaffoldVersion — DO NOT EDIT BY HAND.
# Re-generate with: dart run firebase_kit:scaffold
''';

const String _slashHeader =
    '''// Managed by firebase_kit v$firebaseKitScaffoldVersion — DO NOT EDIT BY HAND.
// Re-generate with: dart run firebase_kit:scaffold
''';

/// Default per-app configuration file (`scripts/firebase_kit.env`), written
/// only when missing and never overwritten.
const String defaultFirebaseKitEnv =
    '''# Per-app configuration for firebase_kit scripts.
# Owned by the app; `dart run firebase_kit:scaffold` never overwrites this file.

# Firebase "demo-" project id for the Local Emulator Suite (offline-only).
FIREBASE_PROJECT_ID="\${FIREBASE_PROJECT_ID:-demo-app}"

# Comma-separated emulators to start for dev and integration tests.
FIREBASE_EMULATORS="\${FIREBASE_EMULATORS:-auth,firestore}"

# Emulator ports (must match firebase.json).
AUTH_EMULATOR_PORT="\${AUTH_EMULATOR_PORT:-9099}"
FIRESTORE_EMULATOR_PORT="\${FIRESTORE_EMULATOR_PORT:-8080}"

# Default integration test target for `scripts/test_integration.sh`.
TEST_TARGET="\${TEST_TARGET:-integration_test/app_test.dart}"

# Optional override target when running with TEST_DEVICE=web.
WEB_TEST_TARGET="\${WEB_TEST_TARGET:-}"

# Default target device id (or "web" for headless Chrome). Leave empty to
# auto-detect the single USB-connected Android device from `adb devices`.
TEST_DEVICE="\${TEST_DEVICE:-}"

# Extra flags (such as `--dart-define=BACKEND_URL=...`) appended to `flutter run`,
# `flutter test`, and `flutter drive`.
EXTRA_DART_DEFINES="\${EXTRA_DART_DEFINES:-}"
''';

/// Managed `scripts/run_dev.sh`.
const String runDevShTemplate = '''$_shHeader#
# Start the Firebase Emulator Suite (or reuse a running instance), then launch
# the Flutter app pointed at those emulators.
#
# When a USB-connected Android device is detected via `adb devices`, sets up
# `adb reverse` port forwarding for Auth and Firestore and runs the app with
# `FIREBASE_EMULATOR_HOST=127.0.0.1` and `FIREBASE_EMULATOR_HOST_MAPPING=false`.
# Otherwise falls back to host LAN-IP detection for a phone on Wi-Fi.
#
# Usage:
#   bash scripts/run_dev.sh                      # reuse running emulators if up
#   bash scripts/run_dev.sh --restart            # restart emulators before launch
#   bash scripts/run_dev.sh -r -d <device-id>    # restart + pass flutter args
set -euo pipefail

cd "\$(dirname "\$0")/.."

# Ensure Android SDK platform-tools and Android Studio JBR are on PATH when
# installed in their standard locations.
if ! command -v adb >/dev/null 2>&1 && [[ -d "\${ANDROID_HOME:-\$HOME/Android/Sdk}/platform-tools" ]]; then
  export PATH="\${ANDROID_HOME:-\$HOME/Android/Sdk}/platform-tools:\$PATH"
fi
if ! command -v java >/dev/null 2>&1 && [[ -d "\${JAVA_HOME:-\$HOME/android-studio/jbr}/bin" ]]; then
  export JAVA_HOME="\${JAVA_HOME:-\$HOME/android-studio/jbr}"
  export PATH="\$JAVA_HOME/bin:\$PATH"
fi

# --- Parse command-line parameters --------------------------------------------
RESTART_EMULATORS=false
FLUTTER_ARGS=()
EXPLICIT_DEVICE=""

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --restart|-r|--shutdown|-s)
      RESTART_EMULATORS=true
      shift
      ;;
    -d|--device-id)
      FLUTTER_ARGS+=("\$1")
      if [[ \$# -gt 1 ]]; then
        EXPLICIT_DEVICE="\$2"
        FLUTTER_ARGS+=("\$2")
        shift 2
      else
        shift
      fi
      ;;
    *)
      FLUTTER_ARGS+=("\$1")
      shift
      ;;
  esac
done

# Detect host LAN IP first so firebase_kit.env can reference \${HOST_IP} in
# EXTRA_DART_DEFINES (e.g. BACKEND_URL="http://\${HOST_IP}:8000").
LAN_IP="\$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \\K\\S+' || true)"
HOST_IP="\${FIREBASE_EMULATOR_HOST:-\${LAN_IP:-127.0.0.1}}"

if [[ -f "scripts/firebase_kit.env" ]]; then
  # shellcheck disable=SC1091
  source "scripts/firebase_kit.env"
fi

PROJECT="\${FIREBASE_PROJECT_ID:-demo-app}"
AUTH_PORT="\${AUTH_EMULATOR_PORT:-9099}"
FIRESTORE_PORT="\${FIRESTORE_EMULATOR_PORT:-8080}"

# --- Determine USB adb reverse vs Wi-Fi LAN IP --------------------------------
USB_DEVICE=""
if command -v adb >/dev/null 2>&1; then
  if [[ -n "\${EXPLICIT_DEVICE}" ]]; then
    if adb devices | awk 'NR>1 && \$2=="device" {print \$1}' | grep -Fxq "\${EXPLICIT_DEVICE}"; then
      USB_DEVICE="\${EXPLICIT_DEVICE}"
    fi
  else
    USB_DEVICE="\$(adb devices | awk 'NR>1 && \$2=="device" {print \$1; exit}')"
  fi
fi

REVERSED_PORTS=false
if [[ -n "\${USB_DEVICE}" && -z "\${FIREBASE_EMULATOR_HOST:-}" ]]; then
  echo "USB Android device detected (\${USB_DEVICE}); forwarding ports \${AUTH_PORT} and \${FIRESTORE_PORT} via adb reverse..."
  adb -s "\${USB_DEVICE}" reverse "tcp:\${AUTH_PORT}" "tcp:\${AUTH_PORT}"
  adb -s "\${USB_DEVICE}" reverse "tcp:\${FIRESTORE_PORT}" "tcp:\${FIRESTORE_PORT}"
  REVERSED_PORTS=true
  EMULATOR_HOST="127.0.0.1"
  HOST_MAPPING="false"
else
  if [[ -z "\${FIREBASE_EMULATOR_HOST:-}" && -z "\${LAN_IP}" ]]; then
    echo "Could not auto-detect a USB device or LAN IP. Re-run with FIREBASE_EMULATOR_HOST=<ip>." >&2
    exit 1
  fi
  EMULATOR_HOST="\${HOST_IP}"
  HOST_MAPPING="true"
  echo "Host IP for the device to reach: \${EMULATOR_HOST}"
fi

is_emulator_running() {
  ss -tln 2>/dev/null | grep -q ":\${AUTH_PORT}"
}

shutdown_emulators() {
  echo "Shutting down existing Firebase emulators..."
  fuser -k "\${AUTH_PORT}/tcp" "\${FIRESTORE_PORT}/tcp" 4000/tcp 9000/tcp 9199/tcp 2>/dev/null || true
  pkill -f "firebase.*emulators" 2>/dev/null || true
  pkill -f "firebase-tools" 2>/dev/null || true
  sleep 2
}

if [[ "\${RESTART_EMULATORS}" == "true" ]]; then
  shutdown_emulators
fi

SPAWNED_EMULATORS=false
EMULATORS_PID=""

if is_emulator_running; then
  echo "Firebase emulators are already running on port \${AUTH_PORT}. Reusing running instance."
else
  if command -v firebase >/dev/null 2>&1; then
    FIREBASE=(firebase)
  else
    echo "firebase CLI not on PATH; falling back to 'npx firebase-tools'."
    export NPM_CONFIG_CACHE="\${NPM_CONFIG_CACHE:-\${TMPDIR:-/tmp}/firebase-kit-npm-cache}"
    FIREBASE=(npx --yes firebase-tools)
    echo "Ensuring firebase-tools is installed..."
    "\${FIREBASE[@]}" --version >/dev/null
  fi

  echo "Starting Firebase emulators (project \${PROJECT})..."
  "\${FIREBASE[@]}" emulators:start --project "\${PROJECT}" &
  EMULATORS_PID=\$!
  SPAWNED_EMULATORS=true

  echo "Waiting for the Auth emulator on port \${AUTH_PORT}..."
  for _ in \$(seq 1 90); do
    if is_emulator_running; then
      break
    fi
    if ! kill -0 "\${EMULATORS_PID}" >/dev/null 2>&1; then
      echo "Emulators exited before becoming ready. Is another instance running?" >&2
      exit 1
    fi
    sleep 2
  done

  if ! is_emulator_running; then
    echo "Auth emulator did not come up within the timeout." >&2
    exit 1
  fi
  echo "Emulators are up."
fi

cleanup() {
  if [[ "\${REVERSED_PORTS}" == "true" && -n "\${USB_DEVICE}" ]]; then
    adb -s "\${USB_DEVICE}" reverse --remove "tcp:\${AUTH_PORT}" >/dev/null 2>&1 || true
    adb -s "\${USB_DEVICE}" reverse --remove "tcp:\${FIRESTORE_PORT}" >/dev/null 2>&1 || true
  fi
  if [[ "\${SPAWNED_EMULATORS}" == "true" && -n "\${EMULATORS_PID}" ]]; then
    echo
    echo "Shutting down emulators spawned by this process..."
    kill "\${EMULATORS_PID}" >/dev/null 2>&1 || true
    wait "\${EMULATORS_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

EXTRA_ARGS=()
if [[ -n "\${EXTRA_DART_DEFINES:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=(\${EXTRA_DART_DEFINES})
fi

echo "Launching the app..."
flutter run \\
  --dart-define=USE_FIREBASE_EMULATOR=true \\
  --dart-define=FIREBASE_EMULATOR_HOST="\${EMULATOR_HOST}" \\
  --dart-define=FIREBASE_EMULATOR_HOST_MAPPING="\${HOST_MAPPING}" \\
  "\${EXTRA_ARGS[@]}" \\
  "\${FLUTTER_ARGS[@]}"
''';

/// Managed `scripts/test_integration.sh`.
const String testIntegrationShTemplate = '''$_shHeader#
# Run emulator-backed Flutter integration tests against the Firebase Local
# Emulator Suite.
#
# By default, runs on the single USB-connected physical Android device reported
# by `adb devices` (or the device specified in `TEST_DEVICE`), forwarding the
# Auth and Firestore emulator ports over USB with `adb reverse` and disabling
# FlutterFire's `10.0.2.2` host mapping.
#
# Set `TEST_DEVICE=web` to run in headless Chrome via `flutter drive` instead.
#
# Usage:
#   bash scripts/test_integration.sh
#   TEST_DEVICE=<serial> bash scripts/test_integration.sh
#   TEST_DEVICE=web bash scripts/test_integration.sh
set -euo pipefail

cd "\$(dirname "\$0")/.."

if ! command -v adb >/dev/null 2>&1 && [[ -d "\${ANDROID_HOME:-\$HOME/Android/Sdk}/platform-tools" ]]; then
  export PATH="\${ANDROID_HOME:-\$HOME/Android/Sdk}/platform-tools:\$PATH"
fi
if ! command -v java >/dev/null 2>&1 && [[ -d "\${JAVA_HOME:-\$HOME/android-studio/jbr}/bin" ]]; then
  export JAVA_HOME="\${JAVA_HOME:-\$HOME/android-studio/jbr}"
  export PATH="\$JAVA_HOME/bin:\$PATH"
fi

SAVED_TEST_DEVICE="\${TEST_DEVICE:-}"
SAVED_TEST_TARGET="\${TEST_TARGET:-}"
HOST_IP="127.0.0.1"

if [[ -f "scripts/firebase_kit.env" ]]; then
  # shellcheck disable=SC1091
  source "scripts/firebase_kit.env"
fi

if [[ -n "\${SAVED_TEST_DEVICE}" ]]; then
  TEST_DEVICE="\${SAVED_TEST_DEVICE}"
fi
if [[ -n "\${SAVED_TEST_TARGET}" ]]; then
  TEST_TARGET="\${SAVED_TEST_TARGET}"
fi

PROJECT_ID="\${FIREBASE_PROJECT_ID:-demo-app}"
EMULATORS="\${FIREBASE_EMULATORS:-auth,firestore}"
AUTH_PORT="\${AUTH_EMULATOR_PORT:-9099}"
FIRESTORE_PORT="\${FIRESTORE_EMULATOR_PORT:-8080}"
TEST_DRIVER="\${TEST_DRIVER:-test_driver/integration_test.dart}"
CHROMEDRIVER_PORT="\${CHROMEDRIVER_PORT:-4444}"

export NPM_CONFIG_CACHE="\${NPM_CONFIG_CACHE:-\${TMPDIR:-/tmp}/firebase-kit-npm-cache}"

if command -v firebase >/dev/null 2>&1; then
  FIREBASE=(firebase)
else
  echo "firebase CLI not found on PATH; falling back to 'npx firebase-tools'."
  FIREBASE=(npx --yes firebase-tools)
fi

if [[ "\${TEST_DEVICE:-}" == "web" ]]; then
  TARGET="\${SAVED_TEST_TARGET:-\${WEB_TEST_TARGET:-\${TEST_TARGET:-integration_test/app_test.dart}}}"
  if command -v chromedriver >/dev/null 2>&1; then
    CHROMEDRIVER=(chromedriver)
  else
    echo "chromedriver not found on PATH; falling back to 'npx chromedriver'."
    CHROMEDRIVER=(npx --yes chromedriver)
  fi

  echo "Starting chromedriver on port \${CHROMEDRIVER_PORT}..."
  "\${CHROMEDRIVER[@]}" "--port=\${CHROMEDRIVER_PORT}" &
  CHROMEDRIVER_PID=\$!

  cleanup_web() {
    if kill -0 "\$CHROMEDRIVER_PID" >/dev/null 2>&1; then
      kill "\$CHROMEDRIVER_PID" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_web EXIT INT TERM

  sleep 2

  "\${FIREBASE[@]}" emulators:exec --only "\${EMULATORS}" --project "\${PROJECT_ID}" \\
    "flutter drive \\
      --driver=\${TEST_DRIVER} \\
      --target=\${TARGET} \\
      -d web-server \\
      --browser-name=chrome \\
      --driver-port=\${CHROMEDRIVER_PORT} \\
      --headless \\
      \${EXTRA_DART_DEFINES:-}"
  exit 0
fi

# --- Physical Android device path (default) -----------------------------------
TARGET="\${TEST_TARGET:-integration_test/app_test.dart}"
DEVICE="\${TEST_DEVICE:-}"

if [[ -z "\${DEVICE}" ]]; then
  if ! command -v adb >/dev/null 2>&1; then
    echo "Error: 'adb' not found on PATH and TEST_DEVICE is not set." >&2
    exit 1
  fi
  mapfile -t CONNECTED_DEVICES < <(adb devices | awk 'NR>1 && \$2=="device" {print \$1}')
  if [[ "\${#CONNECTED_DEVICES[@]}" -eq 0 ]]; then
    echo "Error: No connected Android device found via 'adb devices'." >&2
    echo "Connect a physical Android device over USB (with USB debugging enabled) or set TEST_DEVICE." >&2
    exit 1
  elif [[ "\${#CONNECTED_DEVICES[@]}" -gt 1 ]]; then
    echo "Error: Multiple Android devices found (\${CONNECTED_DEVICES[*]}). Set TEST_DEVICE=<serial> to choose one." >&2
    exit 1
  fi
  DEVICE="\${CONNECTED_DEVICES[0]}"
fi

echo "Using Android device: \${DEVICE}"
echo "Forwarding Auth (\${AUTH_PORT}) and Firestore (\${FIRESTORE_PORT}) ports via adb reverse..."
adb -s "\${DEVICE}" reverse "tcp:\${AUTH_PORT}" "tcp:\${AUTH_PORT}"
adb -s "\${DEVICE}" reverse "tcp:\${FIRESTORE_PORT}" "tcp:\${FIRESTORE_PORT}"

cleanup_device() {
  echo "Removing adb reverse port forwards on \${DEVICE}..."
  adb -s "\${DEVICE}" reverse --remove "tcp:\${AUTH_PORT}" >/dev/null 2>&1 || true
  adb -s "\${DEVICE}" reverse --remove "tcp:\${FIRESTORE_PORT}" >/dev/null 2>&1 || true
}
trap cleanup_device EXIT INT TERM

"\${FIREBASE[@]}" emulators:exec --only "\${EMULATORS}" --project "\${PROJECT_ID}" \\
  "flutter test \${TARGET} -d \${DEVICE} \\
    --dart-define=USE_FIREBASE_EMULATOR=true \\
    --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 \\
    --dart-define=FIREBASE_EMULATOR_HOST_MAPPING=false \\
    \${EXTRA_DART_DEFINES:-}"
''';

/// Managed `scripts/test_security_rules.sh`.
const String testSecurityRulesShTemplate = '''$_shHeader#
# Run Firestore Security Rules tests (test/security_rules/) against the local
# Firestore emulator using @firebase/rules-unit-testing and Node's test runner.
#
# Usage:  bash scripts/test_security_rules.sh
set -euo pipefail

cd "\$(dirname "\$0")/.."

if ! command -v java >/dev/null 2>&1 && [[ -d "\${JAVA_HOME:-\$HOME/android-studio/jbr}/bin" ]]; then
  export JAVA_HOME="\${JAVA_HOME:-\$HOME/android-studio/jbr}"
  export PATH="\$JAVA_HOME/bin:\$PATH"
fi

HOST_IP="127.0.0.1"
if [[ -f "scripts/firebase_kit.env" ]]; then
  # shellcheck disable=SC1091
  source "scripts/firebase_kit.env"
fi

PROJECT_ID="\${FIREBASE_PROJECT_ID:-demo-app}"
RULES_DIR="\${RULES_DIR:-test/security_rules}"

if command -v firebase >/dev/null 2>&1; then
  FIREBASE=(firebase)
else
  echo "firebase CLI not on PATH; falling back to 'npx firebase-tools'."
  export NPM_CONFIG_CACHE="\${NPM_CONFIG_CACHE:-\${TMPDIR:-/tmp}/firebase-kit-npm-cache}"
  FIREBASE=(npx --yes firebase-tools)
  "\${FIREBASE[@]}" --version >/dev/null
fi

if command -v pnpm >/dev/null 2>&1; then
  PNPM_CMD=(pnpm)
else
  PNPM_CMD=(npx --yes pnpm)
fi

if [[ ! -d "\${RULES_DIR}/node_modules" ]]; then
  echo "Installing security-rules test dependencies..."
  ( cd "\${RULES_DIR}" && "\${PNPM_CMD[@]}" install )
fi

echo "Running Security Rules tests against the Firestore emulator (project \${PROJECT_ID})..."
"\${FIREBASE[@]}" emulators:exec --only firestore --project "\${PROJECT_ID}" \\
  "cd \${RULES_DIR} && FIREBASE_PROJECT_ID=\${PROJECT_ID} node --test"
''';

/// Managed `test_driver/integration_test.dart`.
const String integrationTestDriverTemplate = '''$_slashHeader
// Driver used only when running integration tests in headless Chrome
// (`TEST_DEVICE=web bash scripts/test_integration.sh`).
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
''';

/// Managed `test/security_rules/rules_test_env.mjs`.
const String rulesTestEnvMjsTemplate = '''$_slashHeader
// Shared helper for Firestore Security Rules unit tests. Creates the
// `@firebase/rules-unit-testing` environment from `FIRESTORE_EMULATOR_HOST`
// and `FIREBASE_PROJECT_ID`, exposing authenticated/unauthenticated Firestore
// contexts and a rule-disabled seeding helper.
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';

const here = dirname(fileURLToPath(import.meta.url));

/**
 * Initialises the Firestore rules test environment against the running
 * Firestore emulator.
 *
 * @param {object} [options]
 * @param {string} [options.projectId] - Defaults to `process.env.FIREBASE_PROJECT_ID ?? 'demo-app'`.
 * @param {string} [options.rulesPath] - Defaults to `../../firestore.rules` relative to `test/security_rules/`.
 */
export async function createRulesTestEnv({
  projectId = process.env.FIREBASE_PROJECT_ID ?? 'demo-app',
  rulesPath = resolve(here, '..', '..', 'firestore.rules'),
} = {}) {
  const [host, portStr] = (
    process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080'
  ).split(':');

  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync(rulesPath, 'utf8'),
      host,
      port: Number(portStr),
    },
  });

  return {
    testEnv,
    asUser: (uid, tokenOptions) =>
      testEnv.authenticatedContext(uid, tokenOptions).firestore(),
    asGuest: () => testEnv.unauthenticatedContext().firestore(),
    seed: (callback) =>
      testEnv.withSecurityRulesDisabled((ctx) => callback(ctx.firestore())),
    clear: () => testEnv.clearFirestore(),
    cleanup: () => testEnv.cleanup(),
  };
}
''';

/// Descriptor for a single file managed by `dart run firebase_kit:scaffold`.
class ManagedScaffoldFile {
  const ManagedScaffoldFile({
    required this.relativePath,
    required this.content,
    this.executable = false,
  });

  final String relativePath;
  final String content;
  final bool executable;
}

/// All files managed by `dart run firebase_kit:scaffold`.
const List<ManagedScaffoldFile> managedScaffoldFiles = [
  ManagedScaffoldFile(
    relativePath: 'scripts/run_dev.sh',
    content: runDevShTemplate,
    executable: true,
  ),
  ManagedScaffoldFile(
    relativePath: 'scripts/test_integration.sh',
    content: testIntegrationShTemplate,
    executable: true,
  ),
  ManagedScaffoldFile(
    relativePath: 'scripts/test_security_rules.sh',
    content: testSecurityRulesShTemplate,
    executable: true,
  ),
  ManagedScaffoldFile(
    relativePath: 'test_driver/integration_test.dart',
    content: integrationTestDriverTemplate,
  ),
  ManagedScaffoldFile(
    relativePath: 'test/security_rules/rules_test_env.mjs',
    content: rulesTestEnvMjsTemplate,
  ),
];

/// Path to the per-app configuration file (created only when missing).
const String firebaseKitEnvRelativePath = 'scripts/firebase_kit.env';
