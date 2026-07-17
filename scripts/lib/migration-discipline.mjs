/**
 * Shared migration-runner discipline for the pre-launch backfills.
 *
 * This is the lightweight, self-contained embodiment of the invariants in
 * data/design-migration-runner-f4/report.md, pending the full project-owned
 * `data:run` plan/apply/verify runner. Every backfill that uses it gets:
 *
 *   - strict `--env dev|staging` resolution (raw project ids, a missing flag,
 *     `.firebaserc` defaults, and unknown values are all refused);
 *   - a HARD refusal of production - these repair scripts are dev/staging only,
 *     and pre-launch production has zero users, so nothing there needs a
 *     backfill (the corrected rules deploy, done separately, is what prod needs);
 *   - dry-run by default: writes require an explicit `--apply`, and there is no
 *     `--dry-run` flag because plan-only is the default state;
 *   - a `_migrations` Firestore ledger entry gating every apply, so "did this
 *     backfill run here?" is answerable from data, not memory;
 *   - a re-run guard: a migration that already succeeded refuses a second apply
 *     unless `--rerun` is passed (the operation body must still be idempotent).
 *
 * When the full runner lands, these scripts become operation modules under it
 * and this helper is deleted.
 */

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

const ENVIRONMENTS = Object.freeze({
  dev: {projectId: "ascend-f2e4f", production: false},
  staging: {projectId: "ascend-staging-fa7d5", production: false},
  prod: {projectId: "ascend-prod-9c8f2", production: true},
});

const MIGRATIONS_COLLECTION = "_migrations";

/**
 * Resolves the target environment from a strict `--env` value.
 * @param {string | null} rawEnv The `--env` argument value.
 * @return {{env: string, projectId: string, production: boolean}} Environment.
 */
export function resolveEnvironment(rawEnv) {
  if (!rawEnv) {
    throw new Error(
      "Missing --env. Pass exactly one of --env dev or --env staging."
    );
  }

  const environment = ENVIRONMENTS[rawEnv];
  if (!environment) {
    throw new Error(
      `Unknown --env "${rawEnv}". Use dev or staging ` +
      "(raw project ids and prod are refused here)."
    );
  }

  if (environment.production) {
    throw new Error(
      "This repair backfill hard-refuses production. Pre-launch prod has zero " +
      "users, so the backfill is a no-op there; prod only needs the corrected " +
      "rules deploy, handled separately."
    );
  }

  return {env: rawEnv, ...environment};
}

/**
 * Parses the flags every disciplined backfill shares.
 * @param {string[]} argv Process argv.
 * @return {{env: string|null, apply: boolean, rerun: boolean, contextKey: string|null, rest: Map<string,string>}}
 *   Parsed common flags plus any operation-specific `--key value` pairs in `rest`.
 */
export function parseCommonArgs(argv) {
  const parsed = {
    env: null,
    apply: false,
    rerun: false,
    contextKey: null,
    rest: new Map(),
  };

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--env":
        parsed.env = requireValue(argv, ++index, "--env");
        break;
      case "--context-key":
        parsed.contextKey = requireValue(argv, ++index, "--context-key");
        break;
      case "--apply":
        parsed.apply = true;
        break;
      case "--rerun":
        parsed.rerun = true;
        break;
      case "--help":
      case "-h":
        parsed.rest.set("help", "true");
        break;
      default:
        if (value.startsWith("--")) {
          parsed.rest.set(value.slice(2), requireValue(argv, ++index, value));
          break;
        }
        throw new Error(`Unknown argument: ${value}`);
    }
  }

  return parsed;
}

/**
 * Requires an argv value after a flag.
 * @param {string[]} argv Process argv.
 * @param {number} index Value index.
 * @param {string} flag Flag name.
 * @return {string} Flag value.
 */
export function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.`);
  }
  return value;
}

/**
 * Initializes Firebase Admin against the resolved project via ADC.
 * @param {{projectId: string}} environment Resolved environment.
 * @return {FirebaseFirestore.Firestore} Firestore instance.
 */
export function initFirestore(environment) {
  initializeApp({
    credential: applicationDefault(),
    projectId: environment.projectId,
  });
  return getFirestore();
}

/**
 * Encodes an operation id for use as a Firestore document id.
 * @param {string} operationId Operation id (may contain slashes).
 * @return {string} Encoded id.
 */
function encodeOperationId(operationId) {
  return operationId.replaceAll("/", "%2F");
}

/**
 * Returns whether this operation+version already succeeded in this environment.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} operationId Operation id.
 * @param {number} version Operation version.
 * @return {Promise<boolean>} True when a succeeded ledger entry exists.
 */
export async function hasSucceededLedgerEntry(db, operationId, version) {
  const snapshot = await db
    .collection(MIGRATIONS_COLLECTION)
    .doc(encodeOperationId(operationId))
    .get();
  const data = snapshot.data();
  return Boolean(
    data &&
    data.status === "succeeded" &&
    data.operationVersion === version
  );
}

/**
 * Records the start of an apply run in the ledger and returns a run handle.
 * A migration that already succeeded refuses a second apply unless rerun is set.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {object} params Run parameters.
 * @return {Promise<{finish: (counts: object) => Promise<void>, fail: (error: unknown) => Promise<void>}>}
 *   Run handle.
 */
export async function beginRun(db, params) {
  const {operationId, operationVersion, environment, rerun} = params;
  if (!rerun && await hasSucceededLedgerEntry(db, operationId, operationVersion)) {
    throw new Error(
      `Operation ${operationId} v${operationVersion} already succeeded in ` +
      `${environment.env}. Pass --rerun to apply again (the body is idempotent).`
    );
  }

  const parentRef = db
    .collection(MIGRATIONS_COLLECTION)
    .doc(encodeOperationId(operationId));
  const runId = `${new Date().toISOString().replaceAll(/[:.]/g, "-")}-` +
    Math.random().toString(36).slice(2, 8);
  const runRef = parentRef.collection("runs").doc(runId);

  await parentRef.set(
    {
      operationId,
      operationVersion,
      environment: environment.env,
      projectId: environment.projectId,
      status: "running",
      lastRunId: runId,
      lastStartedAt: FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
  await runRef.set({
    runId,
    operationId,
    operationVersion,
    environment: environment.env,
    projectId: environment.projectId,
    status: "running",
    startedAt: FieldValue.serverTimestamp(),
  });

  return {
    async finish(counts) {
      await runRef.set(
        {status: "succeeded", counts, finishedAt: FieldValue.serverTimestamp()},
        {merge: true}
      );
      await parentRef.set(
        {
          status: "succeeded",
          lastFinishedAt: FieldValue.serverTimestamp(),
          firstSucceededAt: FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    },
    async fail(error) {
      await runRef.set(
        {
          status: "failed",
          errorMessage: String(error?.message ?? error).slice(0, 500),
          finishedAt: FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      await parentRef.set(
        {status: "failed", lastFinishedAt: FieldValue.serverTimestamp()},
        {merge: true}
      );
    },
  };
}
