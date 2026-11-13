import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  FREE_WEEK_DURATION_MS,
  FREE_WEEK_ENTITLEMENT_ID,
  freeWeekGrantFields,
  freeWeekRecordRef,
  freeWeekWindow,
  isFreeWeekGrant,
} from "./freeWeek";

export const FREE_WEEK_REMOTE_CONFIG_KEY = "free_week_after_decline_enabled";

// One Remote Config template read serves every grant an instance handles in
// this window. Without it each grant is a management-API call, and that API's
// quota - not Firestore - would be what an unlimited audience runs into.
export const FREE_WEEK_SWITCH_CACHE_MS = 60 * 1000;

export type FreeWeekGrantStatus =
  | "granted"
  | "already_used"
  | "paid_active"
  | "disabled";

export interface FreeWeekGrantResult {
  status: FreeWeekGrantStatus;
  grantedAtMs: number | null;
  expiresAtMs: number | null;
}

export interface FreeWeekGrantDependencies {
  firestore: admin.firestore.Firestore;
  isEnabled(): Promise<boolean>;
  now(): Date;
}

/**
 * Gives one climber their free week, once.
 *
 * The caller supplies nothing: the uid is the one Firebase Authentication
 * verified, and the window is the server clock plus seven days. The record and
 * the grant are written in one transaction, so there is never a grant without
 * the record that stops a second one.
 *
 * - No record and no grant: the week starts now.
 * - A record whose week is still running: the same week is returned, and the
 *   grant is put back if nothing holds access. This is what makes a retried
 *   call idempotent.
 * - A record whose week is over: refused. One week per account, ever.
 * - A grant that is not a free week: refused. A climber who holds paid or
 *   comped access has nothing to be given, and their week is not spent.
 * @param {string} uid - Verified Firebase user id, never client-supplied
 * @param {FreeWeekGrantDependencies} dependencies - Trusted ports
 * @return {Promise<FreeWeekGrantResult>} What the server decided
 */
export async function startFreeWeekForUser(
  uid: string,
  dependencies: FreeWeekGrantDependencies
): Promise<FreeWeekGrantResult> {
  if (!await dependencies.isEnabled()) {
    return {status: "disabled", grantedAtMs: null, expiresAtMs: null};
  }

  const {firestore} = dependencies;
  const recordRef = freeWeekRecordRef(firestore, uid);
  const grantRef = firestore.doc(
    `users/${uid}/entitlements/${FREE_WEEK_ENTITLEMENT_ID}`
  );

  return firestore.runTransaction(async (transaction) => {
    const now = dependencies.now();
    const [record, grant] = await transaction.getAll(recordRef, grantRef);
    const holdsOtherAccess = grant.exists && !isFreeWeekGrant(grant);

    if (record.exists) {
      const window = freeWeekWindow(record);
      // A record this function cannot read still proves a week was given, so
      // it is spent rather than handed out again.
      if (!window || window.expiresAt.getTime() <= now.getTime()) {
        return {
          status: "already_used",
          grantedAtMs: window?.grantedAt.getTime() ?? null,
          expiresAtMs: window?.expiresAt.getTime() ?? null,
        };
      }
      if (holdsOtherAccess) {
        return {
          status: "paid_active",
          grantedAtMs: window.grantedAt.getTime(),
          expiresAtMs: window.expiresAt.getTime(),
        };
      }
      if (!grant.exists) {
        transaction.set(grantRef, freeWeekGrantFields(uid, window, now));
      }
      return {
        status: "granted",
        grantedAtMs: window.grantedAt.getTime(),
        expiresAtMs: window.expiresAt.getTime(),
      };
    }

    if (holdsOtherAccess) {
      return {status: "paid_active", grantedAtMs: null, expiresAtMs: null};
    }

    const window = {
      grantedAt: now,
      expiresAt: new Date(now.getTime() + FREE_WEEK_DURATION_MS),
    };
    transaction.create(recordRef, {
      schemaVersion: 1,
      grantedAt: admin.firestore.Timestamp.fromDate(window.grantedAt),
      expiresAt: admin.firestore.Timestamp.fromDate(window.expiresAt),
    });
    transaction.set(grantRef, freeWeekGrantFields(uid, window, now));
    return {
      status: "granted",
      grantedAtMs: window.grantedAt.getTime(),
      expiresAtMs: window.expiresAt.getTime(),
    };
  });
}

/**
 * Whether the rollout is on for anybody.
 *
 * The app decides per climber, from the value Remote Config resolved for that
 * device, conditions included. The server cannot evaluate a condition, so it
 * answers the only question it can: is the switch on anywhere. Off everywhere
 * is therefore a hard stop that reaches a build still holding a stale `true`,
 * and a staged rollout through a condition is not refused.
 * @param {unknown} template - A Remote Config template
 * @return {boolean} True when the default or any conditional value is true
 */
export function readFreeWeekSwitch(template: unknown): boolean {
  const parameters = (template as {parameters?: Record<string, unknown>} | null)
    ?.parameters;
  const parameter = parameters?.[FREE_WEEK_REMOTE_CONFIG_KEY] as {
    defaultValue?: {value?: unknown};
    conditionalValues?: Record<string, {value?: unknown}>;
  } | undefined;
  const values = [
    parameter?.defaultValue?.value,
    ...Object.values(parameter?.conditionalValues ?? {})
      .map((entry) => entry?.value),
  ];
  // Absent means off: this is a rollout, and only an explicit true grants.
  return values.some((value) =>
    value !== undefined && String(value).toLowerCase() === "true");
}

/**
 * A switch reader that asks Remote Config at most once per cache window.
 *
 * A read that fails answers off and is not cached, so the next call asks
 * again: refusing a week is recoverable, and granting one against a switch
 * nobody could read is not.
 * @param {function(): Promise<unknown>} fetchTemplate - Reads the template
 * @param {function(): Date} now - The clock
 * @return {function(): Promise<boolean>} The cached reader
 */
export function makeCachedFreeWeekSwitch(
  fetchTemplate: () => Promise<unknown>,
  now: () => Date
): () => Promise<boolean> {
  let cached: {value: boolean; readAtMs: number} | null = null;
  return async () => {
    const nowMs = now().getTime();
    if (cached && nowMs - cached.readAtMs < FREE_WEEK_SWITCH_CACHE_MS) {
      return cached.value;
    }
    try {
      const value = readFreeWeekSwitch(await fetchTemplate());
      cached = {value, readAtMs: nowMs};
      return value;
    } catch {
      console.error("startFreeWeek could not read its Remote Config switch");
      return false;
    }
  };
}

const readSwitchFromRemoteConfig = makeCachedFreeWeekSwitch(
  () => admin.remoteConfig().getTemplate(),
  () => new Date()
);

export const startFreeWeek = onCall(
  {timeoutSeconds: 30},
  async (request) => {
    // Deliberately never reads request.data. The only identity this function
    // will act on is the one Firebase Authentication verified.
    const uid = request.auth?.uid;
    if (typeof uid !== "string" || uid.length === 0) {
      throw new HttpsError("unauthenticated", "Sign in to start your free week.");
    }

    try {
      return await startFreeWeekForUser(uid, {
        firestore: admin.firestore(),
        isEnabled: readSwitchFromRemoteConfig,
        now: () => new Date(),
      });
    } catch {
      console.error("startFreeWeek failed");
      throw new HttpsError(
        "unavailable",
        "Ascend could not start your free week. Try again."
      );
    }
  }
);
