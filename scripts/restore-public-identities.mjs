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
  auditOrphanProjectionIdentityRestoration,
  auditUserIdentityRestoration,
  parseRestorationArgs,
  planOrphanProjectionIdentityRestoration,
  planUserIdentityRestoration,
} from "./lib/public-identity-restoration.mjs";

const OPERATION_ID = "migration/public-identity-restoration";
const FAILURE_DETAIL_LIMIT = 10;
const TRANSACTION_PAGE_LIMIT = 100;

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
const initialState = await inspectRestoration(
  db,
  operationRef,
  args.batchSize
);
printSummary(initialState, environment, args.mode);

if (args.mode === "dry-run") {
  process.exit(0);
}

if (args.mode === "audit") {
  assertAuditPassed(initialState);
  console.log("Audit passed: every public identity projection is current.");
  process.exit(0);
}

const run = await beginRun(db, {
  operationId: OPERATION_ID,
  operationVersion: RESTORATION_OPERATION_VERSION,
  environment,
  rerun: args.rerun,
});

try {
  const appliedState = emptyState();
  mergeState(
    appliedState,
    await scanPublicProfiles(
      db,
      args.batchSize,
      true,
      checkpoint(run, "public_profiles")
    )
  );
  mergeState(
    appliedState,
    await scanProjectionCollections(
      db,
      args.batchSize,
      true,
      checkpoint(run, "projections")
    )
  );
  mergeState(
    appliedState,
    await scanUserMarkers(
      db,
      operationRef,
      args.batchSize,
      true,
      checkpoint(run, "markers")
    )
  );

  await run.recordPending([{
    cursor: null,
    stage: "verification",
  }]);
  const verificationState = await inspectRestoration(
    db,
    operationRef,
    args.batchSize
  );
  assertAuditPassed(verificationState);
  await run.recordPending([]);
  await run.finish({
    orphanProjectionWrites: appliedState.orphanProjectionWrites,
    projectionWrites: appliedState.projectionWrites,
    userMarkers: appliedState.userMarkers,
  });
  console.log(
    "Applied and verified public identity restoration: " +
    JSON.stringify({
      orphanProjectionWrites: appliedState.orphanProjectionWrites,
      projectionWrites: appliedState.projectionWrites,
      userMarkers: appliedState.userMarkers,
    }) + "."
  );
} catch (error) {
  await run.fail(error);
  throw error;
}

async function inspectRestoration(
  firestore,
  migrationRef,
  pageSize
) {
  const state = emptyState();
  mergeState(
    state,
    await scanPublicProfiles(firestore, pageSize, false)
  );
  mergeState(
    state,
    await scanProjectionCollections(firestore, pageSize, false)
  );
  mergeState(
    state,
    await scanUserMarkers(
      firestore,
      migrationRef,
      pageSize,
      false
    )
  );
  return state;
}

async function scanPublicProfiles(
  firestore,
  requestedPageSize,
  apply,
  onPage
) {
  const state = emptyState();
  const pageSize = Math.min(
    requestedPageSize,
    TRANSACTION_PAGE_LIMIT
  );
  let cursor = null;

  while (true) {
    const page = await firestore.runTransaction(async (transaction) => {
      let query = firestore.collection("users")
        .orderBy(FieldPath.documentId())
        .limit(pageSize);
      if (cursor !== null) {
        query = query.startAfter(cursor);
      }

      const users = await transaction.get(query);
      const profiles = await Promise.all(
        users.docs.map((user) =>
          transaction.get(publicProfileReference(user.ref))
        )
      );
      const pageState = emptyState();

      for (let index = 0; index < users.docs.length; index += 1) {
        const user = users.docs[index];
        const profile = profiles[index];
        const plan = userPlan(user, profile);
        pageState.users += 1;

        if (plan.missingPublicProfile) {
          pageState.skippedUsers += 1;
          addFailure(
            pageState,
            `${plan.userId} skipped: missing public_profile/current`
          );
          continue;
        }

        const write = plan.writes.find(
          (candidate) => candidate.path === profile.ref.path
        );
        if (write !== undefined) {
          pageState.projectionWrites += 1;
          addFailure(
            pageState,
            `${write.path} has stale public identity`
          );
          if (apply) {
            transaction.set(profile.ref, write.fields, {merge: true});
          }
        }
      }

      return {
        cursor: users.docs.at(-1) ?? null,
        size: users.size,
        state: pageState,
      };
    });

    mergeState(state, page.state);
    await onPage?.(page.cursor?.ref.path ?? null);
    if (page.size < pageSize || page.cursor === null) {
      break;
    }
    cursor = page.cursor;
  }

  return state;
}

async function scanProjectionCollections(
  firestore,
  pageSize,
  apply,
  onPage
) {
  const state = emptyState();
  const scans = [
    {
      kind: "leaderboard",
      query: firestore.collection("leaderboard_stats"),
      stage: "leaderboards",
    },
    {
      kind: "replay",
      query: firestore.collectionGroup("entries"),
      stage: "replay_entries",
    },
    {
      kind: "replay",
      query: firestore.collectionGroup("finishers"),
      stage: "replay_finishers",
    },
    {
      kind: "firstAscent",
      query: firestore.collection("live_replay_leaderboards"),
      stage: "first_ascents",
    },
  ];

  for (const scan of scans) {
    mergeState(
      state,
      await scanProjectionCollection(
        firestore,
        scan.query,
        scan.kind,
        pageSize,
        apply,
        async (cursor) => {
          await onPage?.(`${scan.stage}:${cursor ?? ""}`);
        }
      )
    );
  }

  return state;
}

async function scanProjectionCollection(
  firestore,
  queryBase,
  kind,
  requestedPageSize,
  apply,
  onPage
) {
  const state = emptyState();
  const pageSize = Math.min(
    requestedPageSize,
    TRANSACTION_PAGE_LIMIT
  );
  let cursor = null;

  while (true) {
    const page = await firestore.runTransaction(async (transaction) => {
      let query = queryBase
        .orderBy(FieldPath.documentId())
        .limit(pageSize);
      if (cursor !== null) {
        query = query.startAfter(cursor);
      }

      const targets = await transaction.get(query);
      const userIds = [...new Set(targets.docs
        .map((target) => projectionUserId(target.data(), kind))
        .filter((userId) => userId !== null))];
      const users = await Promise.all(
        userIds.map((userId) =>
          transaction.get(firestore.collection("users").doc(userId))
        )
      );
      const profiles = await Promise.all(
        users.map((user, index) =>
          user.exists ?
            transaction.get(
              publicProfileReference(
                firestore.collection("users").doc(userIds[index])
              )
            ) :
            null
        )
      );
      const sources = new Map(
        userIds.map((userId, index) => [
          userId,
          {
            profile: profiles[index],
            user: users[index],
          },
        ])
      );
      const pageState = emptyState();

      for (const target of targets.docs) {
        const record = projectionRecord(target);
        const userId = projectionUserId(record.data, kind);
        if (userId === null) {
          continue;
        }

        const source = sources.get(userId);
        let write;
        if (source?.user.exists === true) {
          const plan = userPlan(
            source.user,
            source.profile,
            kind,
            record
          );
          write = plan.writes.find(
            (candidate) => candidate.path === record.path
          ) ?? null;
        } else {
          write = planOrphanProjectionIdentityRestoration(
            record,
            false,
            kind
          );
          const failures = auditOrphanProjectionIdentityRestoration(
            record,
            false,
            kind
          );
          for (const failure of failures) {
            addFailure(pageState, failure);
          }
          if (write !== null) {
            pageState.orphanProjectionWrites += 1;
          }
        }

        if (write !== null) {
          pageState.projectionWrites += 1;
          if (source?.user.exists === true) {
            addFailure(
              pageState,
              `${write.path} has stale public identity`
            );
          }
          if (apply) {
            transaction.set(target.ref, write.fields, {merge: true});
          }
        }
      }

      return {
        cursor: targets.docs.at(-1) ?? null,
        size: targets.size,
        state: pageState,
      };
    });

    mergeState(state, page.state);
    await onPage?.(page.cursor?.ref.path ?? null);
    if (page.size < pageSize || page.cursor === null) {
      break;
    }
    cursor = page.cursor;
  }

  return state;
}

async function scanUserMarkers(
  firestore,
  migrationRef,
  requestedPageSize,
  apply,
  onPage
) {
  const state = emptyState();
  const pageSize = Math.min(
    requestedPageSize,
    TRANSACTION_PAGE_LIMIT
  );
  let cursor = null;

  while (true) {
    const page = await firestore.runTransaction(async (transaction) => {
      let query = firestore.collection("users")
        .orderBy(FieldPath.documentId())
        .limit(pageSize);
      if (cursor !== null) {
        query = query.startAfter(cursor);
      }

      const users = await transaction.get(query);
      const profiles = await Promise.all(
        users.docs.map((user) =>
          transaction.get(publicProfileReference(user.ref))
        )
      );
      const markers = await Promise.all(
        users.docs.map((user) =>
          transaction.get(
            migrationRef.collection("users").doc(user.ref.id)
          )
        )
      );
      const pageState = emptyState();

      for (let index = 0; index < users.docs.length; index += 1) {
        const user = users.docs[index];
        const profile = profiles[index];
        if (!profile.exists) {
          continue;
        }

        const plan = userPlan(user, profile);
        const markerFailures = auditUserIdentityRestoration(
          plan,
          markers[index].data()
        ).filter((failure) =>
          failure.includes("matching completion marker")
        );
        if (markerFailures.length === 0) {
          continue;
        }

        pageState.userMarkers += 1;
        addFailure(pageState, markerFailures[0]);
        if (apply && plan.writes.length === 0) {
          transaction.set(
            markers[index].ref,
            {
              completedAt: FieldValue.serverTimestamp(),
              identityDigest: plan.identityDigest,
              operationVersion: RESTORATION_OPERATION_VERSION,
              sourceVersion: plan.sourceVersion,
              userId: plan.userId,
            },
            {merge: true}
          );
        }
      }

      return {
        cursor: users.docs.at(-1) ?? null,
        size: users.size,
        state: pageState,
      };
    });

    mergeState(state, page.state);
    await onPage?.(page.cursor?.ref.path ?? null);
    if (page.size < pageSize || page.cursor === null) {
      break;
    }
    cursor = page.cursor;
  }

  return state;
}

function userPlan(
  user,
  profile,
  projectionKind = null,
  projection = null
) {
  const input = {
    firstAscents: [],
    identityChangedAt: user.updateTime,
    leaderboards: [],
    publicProfile: profile?.exists === true ?
      projectionRecord(profile) :
      null,
    replayEntries: [],
    replayFinishers: [],
    sourceVersion: versionKey(user.updateTime),
    userData: user.data(),
    userId: user.ref.id,
  };

  if (projectionKind === "leaderboard") {
    input.leaderboards = [projection];
  } else if (projectionKind === "replay") {
    input.replayEntries = [projection];
  } else if (projectionKind === "firstAscent") {
    input.firstAscents = [projection];
  }

  return planUserIdentityRestoration(input);
}

function projectionRecord(document) {
  return {
    data: document.data(),
    path: document.ref.path,
    version: versionKey(document.updateTime),
  };
}

function projectionUserId(data, kind) {
  const userId = kind === "firstAscent" ?
    data?.firstAscentUserId :
    data?.userId;
  return typeof userId === "string" && userId.length > 0 ?
    userId :
    null;
}

function publicProfileReference(userReference) {
  return userReference.collection("public_profile").doc("current");
}

function checkpoint(runHandle, stage) {
  return async (cursor) => {
    await runHandle.recordPending([{
      cursor,
      stage,
    }]);
  };
}

function emptyState() {
  return {
    failureCount: 0,
    failureDetails: [],
    orphanProjectionWrites: 0,
    projectionWrites: 0,
    skippedUsers: 0,
    userMarkers: 0,
    users: 0,
  };
}

function addFailure(state, failure) {
  state.failureCount += 1;
  if (state.failureDetails.length < FAILURE_DETAIL_LIMIT) {
    state.failureDetails.push(failure);
  }
}

function mergeState(target, source) {
  target.failureCount += source.failureCount;
  target.orphanProjectionWrites += source.orphanProjectionWrites;
  target.projectionWrites += source.projectionWrites;
  target.skippedUsers += source.skippedUsers;
  target.userMarkers += source.userMarkers;
  target.users += source.users;
  for (const failure of source.failureDetails) {
    if (target.failureDetails.length >= FAILURE_DETAIL_LIMIT) {
      break;
    }
    target.failureDetails.push(failure);
  }
  return target;
}

function assertAuditPassed(state) {
  if (state.failureCount > 0) {
    throw new Error(
      `Public identity audit failed with ${state.failureCount} ` +
      `violation(s): ${state.failureDetails.join("; ")}`
    );
  }
}

function versionKey(timestamp) {
  if (!timestamp) {
    return null;
  }
  return `${timestamp.seconds}:${timestamp.nanoseconds}`;
}

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
