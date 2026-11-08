#!/usr/bin/env bash
# Managed by firebase_kit v0.2.0 — DO NOT EDIT BY HAND.
# Re-generate with: dart run firebase_kit:scaffold
#
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

cd "$(dirname "$0")/.."

if ! command -v adb >/dev/null 2>&1 && [[ -d "${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools" ]]; then
  export PATH="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools:$PATH"
fi
if ! command -v java >/dev/null 2>&1 && [[ -d "${JAVA_HOME:-$HOME/android-studio/jbr}/bin" ]]; then
  export JAVA_HOME="${JAVA_HOME:-$HOME/android-studio/jbr}"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

SAVED_TEST_DEVICE="${TEST_DEVICE:-}"
SAVED_TEST_TARGET="${TEST_TARGET:-}"
HOST_IP="127.0.0.1"

if [[ -f "scripts/firebase_kit.env" ]]; then
  # shellcheck disable=SC1091
  source "scripts/firebase_kit.env"
fi

if [[ -n "${SAVED_TEST_DEVICE}" ]]; then
  TEST_DEVICE="${SAVED_TEST_DEVICE}"
fi
if [[ -n "${SAVED_TEST_TARGET}" ]]; then
  TEST_TARGET="${SAVED_TEST_TARGET}"
fi

PROJECT_ID="${FIREBASE_PROJECT_ID:-demo-app}"
EMULATORS="${FIREBASE_EMULATORS:-auth,firestore}"
AUTH_PORT="${AUTH_EMULATOR_PORT:-9099}"
FIRESTORE_PORT="${FIRESTORE_EMULATOR_PORT:-8080}"
TEST_DRIVER="${TEST_DRIVER:-test_driver/integration_test.dart}"
CHROMEDRIVER_PORT="${CHROMEDRIVER_PORT:-4444}"

export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${TMPDIR:-/tmp}/firebase-kit-npm-cache}"

if command -v firebase >/dev/null 2>&1; then
  FIREBASE=(firebase)
else
  echo "firebase CLI not found on PATH; falling back to 'npx firebase-tools'."
  FIREBASE=(npx --yes firebase-tools)
fi

if [[ "${TEST_DEVICE:-}" == "web" ]]; then
  TARGET="${SAVED_TEST_TARGET:-${WEB_TEST_TARGET:-${TEST_TARGET:-integration_test/app_test.dart}}}"
  if command -v chromedriver >/dev/null 2>&1; then
    CHROMEDRIVER=(chromedriver)
  else
    echo "chromedriver not found on PATH; falling back to 'npx chromedriver'."
    CHROMEDRIVER=(npx --yes chromedriver)
  fi

  echo "Starting chromedriver on port ${CHROMEDRIVER_PORT}..."
  "${CHROMEDRIVER[@]}" "--port=${CHROMEDRIVER_PORT}" &
  CHROMEDRIVER_PID=$!

  cleanup_web() {
    if kill -0 "$CHROMEDRIVER_PID" >/dev/null 2>&1; then
      kill "$CHROMEDRIVER_PID" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_web EXIT INT TERM

  sleep 2

  "${FIREBASE[@]}" emulators:exec --only "${EMULATORS}" --project "${PROJECT_ID}" \
    "flutter drive \
      --driver=${TEST_DRIVER} \
      --target=${TARGET} \
      -d web-server \
      --browser-name=chrome \
      --driver-port=${CHROMEDRIVER_PORT} \
      --headless \
      ${EXTRA_DART_DEFINES:-}"
  exit 0
fi

# --- Physical Android device path (default) -----------------------------------
TARGET="${TEST_TARGET:-integration_test/app_test.dart}"
DEVICE="${TEST_DEVICE:-}"

if [[ -z "${DEVICE}" ]]; then
  if ! command -v adb >/dev/null 2>&1; then
    echo "Error: 'adb' not found on PATH and TEST_DEVICE is not set." >&2
    exit 1
  fi
  mapfile -t CONNECTED_DEVICES < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
  if [[ "${#CONNECTED_DEVICES[@]}" -eq 0 ]]; then
    echo "Error: No connected Android device found via 'adb devices'." >&2
    echo "Connect a physical Android device over USB (with USB debugging enabled) or set TEST_DEVICE." >&2
    exit 1
  elif [[ "${#CONNECTED_DEVICES[@]}" -gt 1 ]]; then
    echo "Error: Multiple Android devices found (${CONNECTED_DEVICES[*]}). Set TEST_DEVICE=<serial> to choose one." >&2
    exit 1
  fi
  DEVICE="${CONNECTED_DEVICES[0]}"
fi

echo "Using Android device: ${DEVICE}"
echo "Forwarding Auth (${AUTH_PORT}) and Firestore (${FIRESTORE_PORT}) ports via adb reverse..."
adb -s "${DEVICE}" reverse "tcp:${AUTH_PORT}" "tcp:${AUTH_PORT}"
adb -s "${DEVICE}" reverse "tcp:${FIRESTORE_PORT}" "tcp:${FIRESTORE_PORT}"

cleanup_device() {
  echo "Removing adb reverse port forwards on ${DEVICE}..."
  adb -s "${DEVICE}" reverse --remove "tcp:${AUTH_PORT}" >/dev/null 2>&1 || true
  adb -s "${DEVICE}" reverse --remove "tcp:${FIRESTORE_PORT}" >/dev/null 2>&1 || true
}
trap cleanup_device EXIT INT TERM

"${FIREBASE[@]}" emulators:exec --only "${EMULATORS}" --project "${PROJECT_ID}" \
  "flutter test ${TARGET} -d ${DEVICE} \
    --dart-define=USE_FIREBASE_EMULATOR=true \
    --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 \
    --dart-define=FIREBASE_EMULATOR_HOST_MAPPING=false \
    ${EXTRA_DART_DEFINES:-}"
