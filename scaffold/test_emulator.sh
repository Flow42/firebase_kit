#!/usr/bin/env bash
#
# Reusable template: run emulator-backed integration tests against the Firebase
# Local Emulator Suite, driving a headless Chrome. Copy into an app's `scripts/`
# (or source it) and set the two knobs below per app.
#
# Usage:  bash scripts/test_emulator.sh
#
# Requirements (auto-resolved via npx if not installed globally):
#   - firebase-tools   (the Firebase CLI + emulators; needs Java)
#   - chromedriver     (matched to the installed Chrome/Chromium)
#   - Flutter with web support enabled
set -euo pipefail

cd "$(dirname "$0")/.."

# --- Per-app knobs (override via env) -----------------------------------------
PROJECT_ID="${FIREBASE_PROJECT_ID:-demo-app}"
TEST_TARGET="${TEST_TARGET:-integration_test/firebase_emulator_test.dart}"
TEST_DRIVER="${TEST_DRIVER:-test_driver/integration_test.dart}"
EMULATORS="${EMULATORS:-auth,firestore}"
CHROMEDRIVER_PORT="${CHROMEDRIVER_PORT:-4444}"

# --- Resolve the Firebase CLI -------------------------------------------------
if command -v firebase >/dev/null 2>&1; then
  FIREBASE=(firebase)
else
  echo "firebase CLI not found on PATH; falling back to 'npx firebase-tools'."
  FIREBASE=(npx --yes firebase-tools)
fi

# --- Start chromedriver -------------------------------------------------------
if command -v chromedriver >/dev/null 2>&1; then
  CHROMEDRIVER=(chromedriver)
else
  echo "chromedriver not found on PATH; falling back to 'npx chromedriver'."
  CHROMEDRIVER=(npx --yes chromedriver)
fi

echo "Starting chromedriver on port ${CHROMEDRIVER_PORT}..."
"${CHROMEDRIVER[@]}" "--port=${CHROMEDRIVER_PORT}" &
CHROMEDRIVER_PID=$!

cleanup() {
  if kill -0 "$CHROMEDRIVER_PID" >/dev/null 2>&1; then
    kill "$CHROMEDRIVER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Give chromedriver a moment to bind its port.
sleep 2

# --- Run the tests inside the emulator lifecycle ------------------------------
# `emulators:exec` boots the emulators, runs the command, then tears down and
# exits non-zero if the command failed.
"${FIREBASE[@]}" emulators:exec --only "${EMULATORS}" --project "${PROJECT_ID}" \
  "flutter drive \
    --driver=${TEST_DRIVER} \
    --target=${TEST_TARGET} \
    -d web-server \
    --browser-name=chrome \
    --driver-port=${CHROMEDRIVER_PORT} \
    --headless"
