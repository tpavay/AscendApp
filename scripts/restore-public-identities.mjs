#!/usr/bin/env node

/**
 * Backfills the identity policy fields onto public profile mirrors that predate
 * them, so the deployed propagation trigger can repair every projection.
 *
 * Scope is dev and staging. Production holds no leaderboard rows and no public
 * profile data, which is why it was never affected; resolveEnvironment refuses
 * it outright rather than relying on nobody pointing this at it.
 *
 * This script writes exactly one collection: users/{uid}/public_profile/current.
 * It never writes leaderboard_stats or any other projection. Writing the source
 * document fires onPublicProfileIdentityWritten, which fans out to leaderboard
 * rows, replay entries, replay finishers, and First Ascents on its own, and it
 * is the only writer permitted to - firestore.rules makes those fields
 * server-owned on update.
 *
 * Usage:
 *   node scripts/restore-public-identities.mjs --env staging
 *   node scripts/restore-public-identities.mjs --env staging --apply
 *   node scripts/restore-public-identities.mjs --env staging --verify
 */

import {
  BACKFILL_ACTIONS,
  PUBLIC_IDENTITY_BACKFILL_VERSION,
  PUBLIC_IDENTITY_POLICY_VERSION,
  hasCurrentIdentityPolicy,
  planPublicIdentityBackfill,
  rowGuardFailures,
  summarizeBackfillPlan,
} from "./lib/public-identity-backfill.mjs";
import {
  beginRun,
  initFirestore,
  parseCommonArgs,
  resolveEnvironment,
} from "./lib/migration-discipline.mjs";

const OPERATION_ID = "migration/public-identity-policy-backfill";
const USER_PAGE_SIZE = 200;

// --verify is a mode, not a --key value pair, so it comes out before the shared
// parser can demand a value for it.
const verifyOnly = process.argv.includes("--verify");
const args = parseCommonArgs(
  process.argv.filter((value) => value !== "--verify")
);
if (args.rest.get("help") === "true") {
  printUsage();
  process.exit(0);
}

// No allowProduction option: production is out of scope for this repair and the
// refusal is the point, not an oversight.
const environment = resolveEnvironment(args.env);
const db = await initFirestore(environment);

if (verifyOnly) {
  const verification = await verifyProjections(db);
  reportVerification(verification, environment);
  process.exit(verification.failing.length === 0 ? 0 : 1);
}

const plans = await planEveryUser(db);
reportPlan(plans, environment, args.apply);

if (!args.apply) {
  console.log(
    "\nDry run. No documents were written. Re-run with --apply to stamp them."
  );
  process.exit(0);
}

const run = await beginRun(db, {
  environment,
  operationId: OPERATION_ID,
  operationVersion: PUBLIC_IDENTITY_BACKFILL_VERSION,
  rerun: args.rerun,
});

try {
  const pending = plans
    .filter((plan) => plan.action === BACKFILL_ACTIONS.stamp)
    .map((plan) => ({stage: "public_profile", userId: plan.userId}));
  await run.recordPending(pending);

  const applied = await applyPlans(db, plans);
  const unresolved = await verifySources(db, plans, applied);

  await run.recordPending([]);
  await run.finish(
    {
      contended: applied.contended.length,
      missing: applied.missing.length,
      stamped: applied.stamped.length,
      skipped: summarizeBackfillPlan(plans).skip,
    },
    unresolved.map((userId) => ({stage: "public_profile", userId}))
  );

  reportApply(applied, unresolved);
  process.exit(unresolved.length === 0 ? 0 : 1);
} catch (error) {
  await run.fail(error);
  throw error;
}

/**
 * Plans every user with a users/{uid} document.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @return {Promise<object[]>} One plan entry per user, in document-id order.
 */
async function planEveryUser(firestore) {
  const {FieldPath} = await import("firebase-admin/firestore");
  const plans = [];
  let cursor = null;

  while (true) {
    let query = firestore
      .collection("users")
      .orderBy(FieldPath.documentId())
      .limit(USER_PAGE_SIZE);
    if (cursor !== null) {
      query = query.startAfter(cursor);
    }

    const users = await query.select().get();
    if (users.empty) {
      break;
    }

    const profiles = await firestore.getAll(
      ...users.docs.map((user) => publicProfileReference(user.ref))
    );
    for (const [index, user] of users.docs.entries()) {
      const profile = profiles[index];
      plans.push({
        ...planPublicIdentityBackfill({
          profileData: profile.data(),
          profileExists: profile.exists,
          userId: user.id,
        }),
        updateTime: profile.exists ? profile.updateTime : null,
      });
    }

    if (users.size < USER_PAGE_SIZE) {
      break;
    }
    cursor = users.docs.at(-1);
  }

  return plans;
}

/**
 * Stamps the policy fields onto every mirror the plan marked stampable.
 *
 * The write is guarded by the update time the plan was read at, so a profile the
 * account republished in the meantime is reported rather than clobbered.
 * A mirror deleted between planning and applying is the same "the account
 * changed under us" class of event as a republish, so it is recorded and the
 * run carries on rather than stranding every remaining stampable mirror.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object[]} plans Planned actions.
 * @return {Promise<{stamped: string[], contended: string[], missing: string[]}>}
 *   Applied uids, split by outcome.
 */
async function applyPlans(firestore, plans) {
  const {FieldValue} = await import("firebase-admin/firestore");
  const stamped = [];
  const contended = [];
  const missing = [];

  for (const plan of plans) {
    if (plan.action !== BACKFILL_ACTIONS.stamp) {
      continue;
    }

    try {
      await publicProfileReference(firestore.collection("users").doc(plan.userId))
        .update(
          {
            identityChangedAt: FieldValue.serverTimestamp(),
            identityPolicyVersion: PUBLIC_IDENTITY_POLICY_VERSION,
          },
          // The snapshot's own update time, passed through verbatim: it carries
          // nanosecond precision that any millisecond round-trip would lose,
          // and a lossy value never matches.
          {lastUpdateTime: plan.updateTime}
        );
      stamped.push(plan.userId);
    } catch (error) {
      if (isMissingDocumentFailure(error)) {
        missing.push(plan.userId);
      } else if (isPreconditionFailure(error)) {
        contended.push(plan.userId);
      } else {
        throw error;
      }
    }
  }

  return {contended, missing, stamped};
}

/**
 * Rereads every stamped mirror and returns the uids that still lack the policy.
 *
 * Mirrors that were deleted under the run are excluded: there is no longer a
 * document to repair, so counting them unrepaired would fail an honest run.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object[]} plans Planned actions.
 * @param {{missing: string[]}} applied Outcomes from applyPlans.
 * @return {Promise<string[]>} Uids whose source document is still unrepaired.
 */
async function verifySources(firestore, plans, applied) {
  const deleted = new Set(applied.missing);
  const targets = plans
    .filter((plan) => plan.action === BACKFILL_ACTIONS.stamp)
    .map((plan) => plan.userId)
    .filter((userId) => !deleted.has(userId));
  if (targets.length === 0) {
    return [];
  }

  const profiles = await firestore.getAll(
    ...targets.map((userId) =>
      publicProfileReference(firestore.collection("users").doc(userId)))
  );
  return targets.filter((userId, index) =>
    !hasCurrentIdentityPolicy(profiles[index].data()));
}

/**
 * Reads every leaderboard row and reports which would survive the client guard.
 *
 * Read-only. Propagation is asynchronous, so a run immediately after --apply can
 * legitimately still show rows in flight; re-run until it comes back clean.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @return {Promise<{failing: object[], passing: object[]}>} Row verdicts.
 */
async function verifyProjections(firestore) {
  const rows = await firestore.collection("leaderboard_stats").get();
  const failing = [];
  const passing = [];

  for (const row of rows.docs) {
    const data = row.data();
    const failures = rowGuardFailures(data);
    const verdict = {
      displayName: data.displayName ?? null,
      failures,
      id: row.id,
      userId: data.userId ?? null,
    };
    if (failures.length === 0) {
      passing.push(verdict);
    } else {
      failing.push(verdict);
    }
  }

  return {failing, passing};
}

function reportPlan(plans, environmentValue, apply) {
  const summary = summarizeBackfillPlan(plans);
  console.log([
    `Operation: ${OPERATION_ID} v${PUBLIC_IDENTITY_BACKFILL_VERSION}`,
    `Environment: ${environmentValue.env} (${environmentValue.projectId})`,
    `Mode: ${apply ? "apply" : "dry-run"}`,
    `Users scanned: ${plans.length}`,
    `To stamp: ${summary.stamp}`,
    `Already current: ${summary.current}`,
    `Skipped, no publishable identity: ${summary.skip}`,
    "",
    "Per user:",
  ].join("\n"));

  for (const plan of plans) {
    console.log(`  [${plan.action}] ${plan.userId}: ${plan.reason}`);
    for (const warning of plan.warnings) {
      console.log(`      warning: ${warning}`);
    }
  }
}

function reportApply(applied, unresolved) {
  console.log(`\nStamped ${applied.stamped.length} public profile mirror(s).`);
  if (applied.contended.length > 0) {
    console.log(
      "Left alone because the account republished mid-run (re-run to pick " +
      `them up): ${applied.contended.join(", ")}`
    );
  }
  if (applied.missing.length > 0) {
    console.log(
      "Left alone because the mirror was deleted mid-run (nothing to " +
      `repair): ${applied.missing.join(", ")}`
    );
  }
  if (unresolved.length > 0) {
    console.log(
      `Still missing the identity policy after the write: ${unresolved.join(", ")}`
    );
    return;
  }
  console.log(
    "Every stamped mirror now carries the identity policy. The " +
    "onPublicProfileIdentityWritten trigger propagates to leaderboard_stats " +
    "and the replay projections asynchronously - confirm with --verify."
  );
}

function reportVerification(verification, environmentValue) {
  const total = verification.failing.length + verification.passing.length;
  console.log([
    `Environment: ${environmentValue.env} (${environmentValue.projectId})`,
    `leaderboard_stats rows: ${total}`,
    `Would render: ${verification.passing.length}`,
    `Would be dropped by the client: ${verification.failing.length}`,
  ].join("\n"));

  for (const row of verification.failing) {
    console.log(
      `  [dropped] ${row.id} (${row.displayName ?? "no display name"}, ` +
      `userId ${row.userId ?? "none"}) fails: ${row.failures.join(", ")}`
    );
  }

  if (verification.failing.length === 0) {
    console.log("\nEvery leaderboard row satisfies the full client contract.");
  }
}

function publicProfileReference(userReference) {
  return userReference.collection("public_profile").doc("current");
}

// Firestore surfaces a lastUpdateTime precondition miss as FAILED_PRECONDITION.
function isPreconditionFailure(error) {
  return error?.code === 9 || /FAILED_PRECONDITION/u.test(String(error));
}

// An update against a document deleted since planning comes back as NOT_FOUND.
function isMissingDocumentFailure(error) {
  return error?.code === 5 || /NOT_FOUND/u.test(String(error));
}

function printUsage() {
  console.log(`
Backfill the identity policy onto public profile mirrors that predate it.

Writes only users/{uid}/public_profile/current. The deployed propagation
trigger fans the identity out to leaderboard_stats and the replay projections;
this script never writes them.

Usage:
  node scripts/restore-public-identities.mjs --env <dev|staging>            Plan only.
  node scripts/restore-public-identities.mjs --env <dev|staging> --apply    Stamp.
  node scripts/restore-public-identities.mjs --env <dev|staging> --verify   Read back.

Options:
  --env <dev|staging>  Required. Production is refused; it holds nothing to repair.
  --apply              Write. Without it this plans and exits.
  --verify             Read leaderboard_stats and report which rows the client
                       would drop. Writes nothing.
  --rerun              Apply again after a successful run (the body is idempotent).
`);
}
