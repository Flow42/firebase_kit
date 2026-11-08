// Managed by firebase_kit v0.2.0 — DO NOT EDIT BY HAND.
// Re-generate with: dart run firebase_kit:scaffold

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
