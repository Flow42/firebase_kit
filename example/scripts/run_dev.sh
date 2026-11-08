#!/usr/bin/env bash
# Managed by firebase_kit v0.2.0 — DO NOT EDIT BY HAND.
# Re-generate with: dart run firebase_kit:scaffold
#
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

cd "$(dirname "$0")/.."

# Ensure Android SDK platform-tools and Android Studio JBR are on PATH when
# installed in their standard locations.
if ! command -v adb >/dev/null 2>&1 && [[ -d "${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools" ]]; then
  export PATH="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools:$PATH"
fi
if ! command -v java >/dev/null 2>&1 && [[ -d "${JAVA_HOME:-$HOME/android-studio/jbr}/bin" ]]; then
  export JAVA_HOME="${JAVA_HOME:-$HOME/android-studio/jbr}"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

# --- Parse command-line parameters --------------------------------------------
RESTART_EMULATORS=false
FLUTTER_ARGS=()
EXPLICIT_DEVICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --restart|-r|--shutdown|-s)
      RESTART_EMULATORS=true
      shift
      ;;
    -d|--device-id)
      FLUTTER_ARGS+=("$1")
      if [[ $# -gt 1 ]]; then
        EXPLICIT_DEVICE="$2"
        FLUTTER_ARGS+=("$2")
        shift 2
      else
        shift
      fi
      ;;
    *)
      FLUTTER_ARGS+=("$1")
      shift
      ;;
  esac
done

# Detect host LAN IP first so firebase_kit.env can reference ${HOST_IP} in
# EXTRA_DART_DEFINES (e.g. BACKEND_URL="http://${HOST_IP}:8000").
LAN_IP="$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || true)"
HOST_IP="${FIREBASE_EMULATOR_HOST:-${LAN_IP:-127.0.0.1}}"

if [[ -f "scripts/firebase_kit.env" ]]; then
  # shellcheck disable=SC1091
  source "scripts/firebase_kit.env"
fi

PROJECT="${FIREBASE_PROJECT_ID:-demo-app}"
AUTH_PORT="${AUTH_EMULATOR_PORT:-9099}"
FIRESTORE_PORT="${FIRESTORE_EMULATOR_PORT:-8080}"

# --- Determine USB adb reverse vs Wi-Fi LAN IP --------------------------------
USB_DEVICE=""
if command -v adb >/dev/null 2>&1; then
  if [[ -n "${EXPLICIT_DEVICE}" ]]; then
    if adb devices | awk 'NR>1 && $2=="device" {print $1}' | grep -Fxq "${EXPLICIT_DEVICE}"; then
      USB_DEVICE="${EXPLICIT_DEVICE}"
    fi
  else
    USB_DEVICE="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  fi
fi

REVERSED_PORTS=false
if [[ -n "${USB_DEVICE}" && -z "${FIREBASE_EMULATOR_HOST:-}" ]]; then
  echo "USB Android device detected (${USB_DEVICE}); forwarding ports ${AUTH_PORT} and ${FIRESTORE_PORT} via adb reverse..."
  adb -s "${USB_DEVICE}" reverse "tcp:${AUTH_PORT}" "tcp:${AUTH_PORT}"
  adb -s "${USB_DEVICE}" reverse "tcp:${FIRESTORE_PORT}" "tcp:${FIRESTORE_PORT}"
  REVERSED_PORTS=true
  EMULATOR_HOST="127.0.0.1"
  HOST_MAPPING="false"
else
  if [[ -z "${FIREBASE_EMULATOR_HOST:-}" && -z "${LAN_IP}" ]]; then
    echo "Could not auto-detect a USB device or LAN IP. Re-run with FIREBASE_EMULATOR_HOST=<ip>." >&2
    exit 1
  fi
  EMULATOR_HOST="${HOST_IP}"
  HOST_MAPPING="true"
  echo "Host IP for the device to reach: ${EMULATOR_HOST}"
fi

is_emulator_running() {
  ss -tln 2>/dev/null | grep -q ":${AUTH_PORT}"
}

shutdown_emulators() {
  echo "Shutting down existing Firebase emulators..."
  fuser -k "${AUTH_PORT}/tcp" "${FIRESTORE_PORT}/tcp" 4000/tcp 9000/tcp 9199/tcp 2>/dev/null || true
  pkill -f "firebase.*emulators" 2>/dev/null || true
  pkill -f "firebase-tools" 2>/dev/null || true
  sleep 2
}

if [[ "${RESTART_EMULATORS}" == "true" ]]; then
  shutdown_emulators
fi

SPAWNED_EMULATORS=false
EMULATORS_PID=""

if is_emulator_running; then
  echo "Firebase emulators are already running on port ${AUTH_PORT}. Reusing running instance."
else
  if command -v firebase >/dev/null 2>&1; then
    FIREBASE=(firebase)
  else
    echo "firebase CLI not on PATH; falling back to 'npx firebase-tools'."
    export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${TMPDIR:-/tmp}/firebase-kit-npm-cache}"
    FIREBASE=(npx --yes firebase-tools)
    echo "Ensuring firebase-tools is installed..."
    "${FIREBASE[@]}" --version >/dev/null
  fi

  echo "Starting Firebase emulators (project ${PROJECT})..."
  "${FIREBASE[@]}" emulators:start --project "${PROJECT}" &
  EMULATORS_PID=$!
  SPAWNED_EMULATORS=true

  echo "Waiting for the Auth emulator on port ${AUTH_PORT}..."
  for _ in $(seq 1 90); do
    if is_emulator_running; then
      break
    fi
    if ! kill -0 "${EMULATORS_PID}" >/dev/null 2>&1; then
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
  if [[ "${REVERSED_PORTS}" == "true" && -n "${USB_DEVICE}" ]]; then
    adb -s "${USB_DEVICE}" reverse --remove "tcp:${AUTH_PORT}" >/dev/null 2>&1 || true
    adb -s "${USB_DEVICE}" reverse --remove "tcp:${FIRESTORE_PORT}" >/dev/null 2>&1 || true
  fi
  if [[ "${SPAWNED_EMULATORS}" == "true" && -n "${EMULATORS_PID}" ]]; then
    echo
    echo "Shutting down emulators spawned by this process..."
    kill "${EMULATORS_PID}" >/dev/null 2>&1 || true
    wait "${EMULATORS_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

EXTRA_ARGS=()
if [[ -n "${EXTRA_DART_DEFINES:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=(${EXTRA_DART_DEFINES})
fi

echo "Launching the app..."
flutter run \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  --dart-define=FIREBASE_EMULATOR_HOST="${EMULATOR_HOST}" \
  --dart-define=FIREBASE_EMULATOR_HOST_MAPPING="${HOST_MAPPING}" \
  "${EXTRA_ARGS[@]}" \
  "${FLUTTER_ARGS[@]}"
