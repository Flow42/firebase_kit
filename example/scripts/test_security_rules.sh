#!/usr/bin/env bash
# Managed by firebase_kit v0.2.0 — DO NOT EDIT BY HAND.
# Re-generate with: dart run firebase_kit:scaffold
#
# Run Firestore Security Rules tests (test/security_rules/) against the local
# Firestore emulator using @firebase/rules-unit-testing and Node's test runner.
#
# Usage:  bash scripts/test_security_rules.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v java >/dev/null 2>&1 && [[ -d "${JAVA_HOME:-$HOME/android-studio/jbr}/bin" ]]; then
  export JAVA_HOME="${JAVA_HOME:-$HOME/android-studio/jbr}"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

HOST_IP="127.0.0.1"
if [[ -f "scripts/firebase_kit.env" ]]; then
  # shellcheck disable=SC1091
  source "scripts/firebase_kit.env"
fi

PROJECT_ID="${FIREBASE_PROJECT_ID:-demo-app}"
RULES_DIR="${RULES_DIR:-test/security_rules}"

if command -v firebase >/dev/null 2>&1; then
  FIREBASE=(firebase)
else
  echo "firebase CLI not on PATH; falling back to 'npx firebase-tools'."
  export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${TMPDIR:-/tmp}/firebase-kit-npm-cache}"
  FIREBASE=(npx --yes firebase-tools)
  "${FIREBASE[@]}" --version >/dev/null
fi

if command -v pnpm >/dev/null 2>&1; then
  PNPM_CMD=(pnpm)
else
  PNPM_CMD=(npx --yes pnpm)
fi

if [[ ! -d "${RULES_DIR}/node_modules" ]]; then
  echo "Installing security-rules test dependencies..."
  ( cd "${RULES_DIR}" && "${PNPM_CMD[@]}" install )
fi

echo "Running Security Rules tests against the Firestore emulator (project ${PROJECT_ID})..."
"${FIREBASE[@]}" emulators:exec --only firestore --project "${PROJECT_ID}" \
  "cd ${RULES_DIR} && FIREBASE_PROJECT_ID=${PROJECT_ID} node --test"
