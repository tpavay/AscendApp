#!/usr/bin/env node

/**
 * Restores validated account-authored identity to every public projection.
 *
 * Usage:
 *   node scripts/restore-public-identities.mjs --env dev --dry-run
 *   node scripts/restore-public-identities.mjs --env dev --apply
 *   node scripts/restore-public-identities.mjs --env dev --audit
 *   node scripts/restore-public-identities.mjs --env prod \
 *     --confirm-production ascend-prod-9c8f2 --apply
 */

import {FieldPath, FieldValue} from "firebase-admin/firestore";
import {
  beginRun,
  initFirestore,
  operationDocumentRef,
  resolveEnvironment,
} from "./lib/migration-discipline.mjs";
import {
  RESTORATION_OPERATION_VERSION,
  StaleIdentityRestorationPlanError,
  applyFreshUserIdentityRestoration,
  auditFreshUserIdentityRestoration,
  auditOrphanProjectionIdentityRestoration,
  auditUserIdentityRestoration,
  parseRestorationArgs,
  planOrphanProjectionIdentityRestoration,
  planUserIdentityRestoration,
} from "./lib/public-identity-restoration.mjs";

const OPERATION_ID = "migration/public-identity-restoration";

const args = parseRestorationArgs(process.argv);
if (args.help) {
  printUsageAndExit();
}

const environment = resolveEnvironment(args.env, {
  allowProduction: true,
  productionConfirmation: args.productionConfirmation,
});
const db = await initFirestore(environment);
const operationRef = operationDocumentRef(db, OPERATION_ID);
const userDocuments = await readPaginated(
  db.collection("users"),
  args.batchSize
);
const plans = [];

for (const userDocument of userDocuments) {
  plans.push(await buildUserPlan(db, userDocument, args.batchSize));
}

const markerSnapshots = await readMarkers(operationRef, plans);
const orphanState = await reconcileOrphanProjections(
  db,
  args.batchSize,
  false
);
const summary = summarizePlans(
  plans,
  markerSnapshots,
  orphanState.projectionWrites
);
printSummary(summary, environment, args.mode);

if (args.mode === "dry-run") {
  process.exit(0);
}

if (args.mode === "audit") {
  const auditState = await readFreshAuditState(
    db,
    operationRef,
    args.batchSize
  );
  assertAuditPassed(
    auditState.plans,
    auditState.markers,
    auditState.orphanFailures
  );
  console.log("Audit passed: every real-user identity projection is current.");
  process.exit(0);
}

const run = await beginRun(db, {
  operationId: OPERATION_ID,
  operationVersion: RESTORATION_OPERATION_VERSION,
  environment,
  rerun: args.rerun,
});

try {
  const pending = plans
    .filter((plan) => needsApply(plan, markerSnapshots.get(plan.userId)))
    .map((plan) => ({userId: plan.userId}));
  await run.recordPending(pending);

  let projectionWrites = 0;
  let orphanProjectionWrites = 0;
  let userMarkers = 0;
  for (const initialPlan of plans) {
    if (!needsApply(initialPlan, markerSnapshots.get(initialPlan.userId))) {
      continue;
    }
    const outcome = await applyFreshUserIdentityRestoration({
      loadFreshPlan: () => loadFreshUserPlan(
        db,
        initialPlan.userId,
        args.batchSize
      ),
      applyPlan: (plan) => applyUserPlan(
        db,
        operationRef,
        plan,
        args.batchSize
      ),
    });
    projectionWrites += outcome.projectionWrites;
    if (outcome.status === "applied") {
      userMarkers += 1;
    }
  }

  const appliedOrphans = await reconcileOrphanProjections(
    db,
    args.batchSize,
    true
  );
  orphanProjectionWrites = appliedOrphans.projectionWrites;
  projectionWrites += orphanProjectionWrites;

  const verificationState = await readFreshAuditState(
    db,
    operationRef,
    args.batchSize
  );
  assertAuditPassed(
    verificationState.plans,
    verificationState.markers,
    verificationState.orphanFailures
  );
  await run.finish({
    orphanProjectionWrites,
    projectionWrites,
    userMarkers,
  });
  console.log(
    "Applied and verified public identity restoration: " +
    JSON.stringify({
      orphanProjectionWrites,
      projectionWrites,
      userMarkers,
    }) + "."
  );
} catch (error) {
  await run.fail(error);
  throw error;
}

/**
 * Builds one user's complete projection plan.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object} userDocument User root snapshot record.
 * @param {number} pageSize Query page size.
 * @return {Promise<object>} Per-user plan.
 */
async function buildUserPlan(firestore, userDocument, pageSize) {
  const userId = userDocument.ref.id;
  const publicProfileRef = userDocument.ref
    .collection("public_profile")
    .doc("current");
  const [
    publicProfileSnapshot,
    leaderboardDocuments,
    replayEntries,
    replayFinishers,
    firstAscents,
  ] = await Promise.all([
    publicProfileRef.get(),
    readPaginated(
      firestore
        .collection("leaderboard_stats")
        .where("userId", "==", userId),
      pageSize
    ),
    readPaginated(
      firestore
        .collectionGroup("entries")
        .where("userId", "==", userId),
      pageSize
    ),
    readPaginated(
      firestore
        .collectionGroup("finishers")
        .where("userId", "==", userId),
      pageSize
    ),
    readPaginated(
      firestore
        .collection("live_replay_leaderboards")
        .where("firstAscentUserId", "==", userId),
      pageSize
    ),
  ]);

  return planUserIdentityRestoration({
    firstAscents: projectionRecords(firstAscents),
    leaderboards: projectionRecords(leaderboardDocuments),
    publicProfile: publicProfileSnapshot.exists ? {
      data: publicProfileSnapshot.data(),
      path: publicProfileRef.path,
      version: versionKey(publicProfileSnapshot.updateTime),
    } : null,
    replayEntries: projectionRecords(replayEntries),
    replayFinishers: projectionRecords(replayFinishers),
    identityChangedAt: userDocument.updateTime,
    sourceVersion: versionKey(userDocument.updateTime),
    userData: userDocument.data,
    userId,
  });
}

/**
 * Reloads one source root before each retry.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {string} userId Firebase Auth uid.
 * @param {number} pageSize Query page size.
 * @return {Promise<object>} Fresh plan or explicit source-deletion skip.
 */
async function loadFreshUserPlan(firestore, userId, pageSize) {
  const snapshot = await firestore.collection("users").doc(userId).get();
  if (!snapshot.exists) {
    return {
      identityDigest: "",
      missingPublicProfile: false,
      skipReason: "source user deleted during restoration",
      sourceVersion: null,
      targetFingerprint: "",
      targets: [],
      userId,
      writes: [],
    };
  }

  return buildUserPlan(
    firestore,
    {
      data: snapshot.data(),
      ref: snapshot.ref,
      updateTime: snapshot.updateTime,
    },
    pageSize
  );
}

/**
 * Applies every projection before writing the per-user completion marker.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {FirebaseFirestore.DocumentReference} operationRef Ledger parent.
 * @param {object} plan Per-user restoration plan.
 * @param {number} batchSize Firestore commit limit.
 * @return {Promise<number>} Projection writes committed.
 */
async function applyUserPlan(
  firestore,
  operationRef,
  plan,
  batchSize
) {
  for (let index = 0; index < plan.writes.length; index += batchSize) {
    const page = plan.writes.slice(index, index + batchSize);
    await firestore.runTransaction(async (transaction) => {
      await assertCurrentSourceVersion(transaction, firestore, plan);
      const targetSnapshots = await Promise.all(
        page.map((write) => transaction.get(firestore.doc(write.path)))
      );
      for (let offset = 0; offset < page.length; offset += 1) {
        const write = page[offset];
        const snapshot = targetSnapshots[offset];
        if (
          !snapshot.exists ||
          versionKey(snapshot.updateTime) !== write.targetVersion
        ) {
          throw new StaleIdentityRestorationPlanError(
            `${write.path} changed after restoration planning`
          );
        }
      }
      for (const write of page) {
        transaction.set(
          firestore.doc(write.path),
          write.fields,
          {merge: true}
        );
      }
    });
  }

  await firestore.runTransaction(async (transaction) => {
    await assertCurrentSourceVersion(transaction, firestore, plan);
    transaction.set(operationRef.collection("users").doc(plan.userId), {
      completedAt: FieldValue.serverTimestamp(),
      identityDigest: plan.identityDigest,
      operationVersion: RESTORATION_OPERATION_VERSION,
      sourceVersion: plan.sourceVersion,
      userId: plan.userId,
    });
  });
  return plan.writes.length;
}

/**
 * Verifies the private source root against the optimistic plan token.
 * @param {FirebaseFirestore.Transaction} transaction Firestore transaction.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object} plan Current restoration plan.
 */
async function assertCurrentSourceVersion(
  transaction,
  firestore,
  plan
) {
  const source = await transaction.get(
    firestore.collection("users").doc(plan.userId)
  );
  if (
    !source.exists ||
    versionKey(source.updateTime) !== plan.sourceVersion
  ) {
    throw new StaleIdentityRestorationPlanError(
      `${plan.userId} changed after restoration planning`
    );
  }
}

/**
 * Rebuilds each audit plan and verifies its source at the marker-read boundary.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {FirebaseFirestore.DocumentReference} operationRef Ledger parent.
 * @param {number} pageSize Query page size.
 * @return {Promise<object>} Fresh plans and markers.
 */
async function readFreshAuditState(
  firestore,
  operationRef,
  pageSize
) {
  const users = await readPaginated(
    firestore.collection("users"),
    pageSize
  );
  const plans = [];
  const markers = new Map();

  for (const user of users) {
    const userId = user.ref.id;
    const result = await auditFreshUserIdentityRestoration({
      loadFreshPlan: () => loadFreshUserPlan(
        firestore,
        userId,
        pageSize
      ),
      loadMarkerForCurrentSource: (plan) =>
        firestore.runTransaction(async (transaction) => {
          await assertCurrentSourceVersion(
            transaction,
            firestore,
            plan
          );
          const marker = await transaction.get(
            operationRef.collection("users").doc(plan.userId)
          );
          return marker.data();
        }),
    });
    plans.push(result.plan);
    markers.set(result.plan.userId, result.marker);
  }

  const orphanState = await reconcileOrphanProjections(
    firestore,
    pageSize,
    false
  );
  return {
    markers,
    orphanFailures: orphanState.failures,
    plans,
  };
}

/**
 * Independently scans every public identity projection so missing user roots
 * cannot hide from the root-first per-user restoration pass.
 *
 * Each page reads rows and their user roots in one transaction. A concurrent
 * root creation or deletion therefore retries against the current state before
 * any identity merge commits.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {number} pageSize Bounded scan and write page size.
 * @param {boolean} apply Whether to commit planned identity merges.
 * @return {Promise<object>} Planned/applied writes and audit failures.
 */
async function reconcileOrphanProjections(
  firestore,
  pageSize,
  apply
) {
  let projectionWrites = 0;
  const failures = [];
  const scans = [
    {
      kind: "leaderboard",
      query: firestore.collection("leaderboard_stats"),
    },
    {
      kind: "replay",
      query: firestore.collectionGroup("entries"),
    },
    {
      kind: "replay",
      query: firestore.collectionGroup("finishers"),
    },
    {
      kind: "firstAscent",
      query: firestore.collection("live_replay_leaderboards"),
    },
  ];

  for (const scan of scans) {
    const result = await reconcileOrphanProjectionScan(
      firestore,
      scan.query,
      scan.kind,
      pageSize,
      apply
    );
    projectionWrites += result.projectionWrites;
    failures.push(...result.failures);
  }

  return {failures, projectionWrites};
}

async function reconcileOrphanProjectionScan(
  firestore,
  queryBase,
  kind,
  pageSize,
  apply
) {
  let cursor = null;
  let projectionWrites = 0;
  const failures = [];

  while (true) {
    const result = await firestore.runTransaction(async (transaction) => {
      let query = queryBase
        .orderBy(FieldPath.documentId())
        .limit(pageSize);
      if (cursor !== null) {
        query = query.startAfter(cursor);
      }

      const snapshot = await transaction.get(query);
      const records = snapshot.docs.map((document) => ({
        data: document.data(),
        path: document.ref.path,
        ref: document.ref,
        version: versionKey(document.updateTime),
      }));
      const userIds = [...new Set(records
        .map((record) => projectionUserId(record.data, kind))
        .filter((userId) =>
          typeof userId === "string" && userId.length > 0
        ))];
      const userSnapshots = await Promise.all(
        userIds.map((userId) =>
          transaction.get(firestore.collection("users").doc(userId))
        )
      );
      const userRootExists = new Map(
        userIds.map((userId, index) => [
          userId,
          userSnapshots[index].exists,
        ])
      );

      let pageWrites = 0;
      const pageFailures = [];
      for (const record of records) {
        const userId = projectionUserId(record.data, kind);
        const rootExists = typeof userId === "string" &&
          userRootExists.get(userId) === true;
        const write = planOrphanProjectionIdentityRestoration(
          record,
          rootExists,
          kind
        );
        pageFailures.push(
          ...auditOrphanProjectionIdentityRestoration(
            record,
            rootExists,
            kind
          )
        );
        if (write !== null) {
          pageWrites += 1;
          if (apply) {
            transaction.set(record.ref, write.fields, {merge: true});
          }
        }
      }

      return {
        failures: pageFailures,
        lastDocument: snapshot.docs.at(-1) ?? null,
        pageSize: snapshot.size,
        projectionWrites: pageWrites,
      };
    });

    projectionWrites += result.projectionWrites;
    failures.push(...result.failures);
    if (result.pageSize < pageSize || result.lastDocument === null) {
      break;
    }
    cursor = result.lastDocument;
  }

  return {failures, projectionWrites};
}

function projectionUserId(data, kind) {
  return kind === "firstAscent" ?
    data?.firstAscentUserId :
    data?.userId;
}

/**
 * Reads current per-user completion marker data.
 * @param {FirebaseFirestore.DocumentReference} operationRef Ledger parent.
 * @param {object[]} userPlans User plans.
 * @return {Promise<Map<string, object | undefined>>} Marker data by uid.
 */
async function readMarkers(operationRef, userPlans) {
  const markers = new Map();
  const snapshots = await Promise.all(
    userPlans.map((plan) =>
      operationRef.collection("users").doc(plan.userId).get()
    )
  );
  for (let index = 0; index < userPlans.length; index += 1) {
    markers.set(userPlans[index].userId, snapshots[index].data());
  }
  return markers;
}

/**
 * Returns whether a user has stale projections or marker state.
 * @param {object} plan Current plan.
 * @param {object | undefined} marker Completion marker.
 * @return {boolean} Whether apply owes work for this user.
 */
function needsApply(plan, marker) {
  return auditUserIdentityRestoration(plan, marker).length > 0;
}

/**
 * Throws with bounded details when audit finds a mismatch.
 * @param {object[]} plans Current user plans.
 * @param {Map<string, object | undefined>} markers Marker data.
 * @param {string[]} orphanFailures Independent global-row failures.
 */
function assertAuditPassed(plans, markers, orphanFailures = []) {
  const failures = [
    ...plans.flatMap((plan) =>
      auditUserIdentityRestoration(plan, markers.get(plan.userId))
    ),
    ...orphanFailures,
  ];
  if (failures.length > 0) {
    throw new Error(
      `Public identity audit failed with ${failures.length} violation(s): ` +
      failures.slice(0, 10).join("; ")
    );
  }
}

/**
 * Summarizes current plans without mutation.
 * @param {object[]} plans Per-user plans.
 * @param {Map<string, object | undefined>} markers Marker data.
 * @param {number} orphanProjectionWrites Independent orphan-row writes.
 * @return {object} Plan counts.
 */
function summarizePlans(plans, markers, orphanProjectionWrites) {
  return {
    orphanProjectionWrites,
    projectionWrites: orphanProjectionWrites + plans.reduce(
      (total, plan) => total + plan.writes.length,
      0
    ),
    skippedUsers: plans.filter((plan) => plan.skipReason).length,
    userMarkers: plans.filter(
      (plan) => needsApply(plan, markers.get(plan.userId))
    ).length,
    users: plans.length,
  };
}

/**
 * Maps Firestore records into pure planner inputs.
 * @param {object[]} documents Snapshot records.
 * @return {object[]} Projection records.
 */
function projectionRecords(documents) {
  return documents.map((document) => ({
    data: document.data,
    path: document.ref.path,
    version: versionKey(document.updateTime),
  }));
}

/**
 * Reads a query deterministically in bounded pages.
 * @param {FirebaseFirestore.Query} queryBase Firestore query.
 * @param {number} pageSize Query page size.
 * @return {Promise<object[]>} Snapshot records.
 */
async function readPaginated(queryBase, pageSize) {
  const documents = [];
  let lastDocument = null;

  while (true) {
    let query = queryBase.orderBy(FieldPath.documentId());
    if (lastDocument) {
      query = query.startAfter(lastDocument);
    }
    const snapshot = await query.limit(pageSize).get();
    if (snapshot.empty) {
      break;
    }
    documents.push(...snapshot.docs.map((document) => ({
      data: document.data(),
      ref: document.ref,
      updateTime: document.updateTime,
    })));
    lastDocument = snapshot.docs.at(-1);
    if (snapshot.size < pageSize) {
      break;
    }
  }
  return documents;
}

/**
 * Returns a stable optimistic-concurrency token for an update time.
 * @param {FirebaseFirestore.Timestamp | undefined} timestamp Update time.
 * @return {string | null} Stable version token.
 */
function versionKey(timestamp) {
  if (!timestamp) {
    return null;
  }
  return `${timestamp.seconds}:${timestamp.nanoseconds}`;
}

/**
 * Prints the immutable target and current work counts.
 * @param {object} summary Plan counts.
 * @param {object} environmentValue Named environment.
 * @param {string} mode Runner mode.
 */
function printSummary(summary, environmentValue, mode) {
  console.log([
    `Operation: ${OPERATION_ID} v${RESTORATION_OPERATION_VERSION}`,
    `Environment: ${environmentValue.env} (${environmentValue.projectId})`,
    `Mode: ${mode}`,
    `Users scanned: ${summary.users}`,
    `Users skipped for audit: ${summary.skippedUsers}`,
    `Orphan projection writes required: ${summary.orphanProjectionWrites}`,
    `Projection writes required: ${summary.projectionWrites}`,
    `User markers required: ${summary.userMarkers}`,
  ].join("\n"));
}

/**
 * Prints strict runner usage and exits.
 */
function printUsageAndExit() {
  console.log(`
Restore account-authored public identity.

Usage:
  node scripts/restore-public-identities.mjs --env dev --dry-run
  node scripts/restore-public-identities.mjs --env staging --apply
  node scripts/restore-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --apply
  node scripts/restore-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --audit

Options:
  --env <dev|staging|prod>   Required named environment.
  --dry-run                 Plan and count without mutation.
  --apply                   Apply, verify, and record the migration ledger.
  --audit                   Fail on a mismatch or incomplete user marker.
  --batch-size <1...450>     Firestore write and scan page size.
  --rerun                   Re-apply an already successful operation version.
  --confirm-production <id> Required for prod; must equal ascend-prod-9c8f2.
`);
  process.exit(0);
}
