import assert from "node:assert/strict";
import test from "node:test";
import {
  deriveLandmarkResult,
  groupCompletions,
} from "../lib/landmark-result-derivation.mjs";
import {
  canonicalWorkoutDocumentId,
  seededReplayCompletedCount,
  staleWorkoutDocumentIds,
} from "../lib/workout-document-id.mjs";
import {
  BATCH_WRITE_LIMIT,
  finalWorkoutDocuments,
  matchWorkoutIdReferenceShape,
  packBatchSizes,
  planAffectedLandmarkProjections,
  planCaseVariantWorkoutMerges,
  planReplaySummaryRepairs,
  planWorkoutIdReferenceRenames,
  planWorkoutIdReferenceRepairs,
  scanWorkoutIdReferences,
} from "../lib/workout-id-case-migration.mjs";

const LOWERCASE_ID = "51c91094-5475-4b25-ab8f-a5d809f90a2f";
const UPPERCASE_ID = LOWERCASE_ID.toUpperCase();
const CLIMB_ID = "empire-state-building";

test("case variants converge on one workout write and one completion", () => {
  const writes = new Map();
  const data = completedWorkout();
  writes.set(canonicalWorkoutDocumentId(LOWERCASE_ID), data);
  writes.set(canonicalWorkoutDocumentId(UPPERCASE_ID), data);

  assert.equal(writes.size, 1);
  const workouts = [...writes].map(([workoutId, workout]) => ({
    userId: "user-1",
    workoutId,
    data: workout,
  }));
  const completions = groupCompletions(workouts).get("user-1").get(CLIMB_ID);
  const projection = deriveLandmarkResult(CLIMB_ID, completions);

  assert.equal(projection.attemptCount, 1);
  assert.equal(projection.bestWorkoutId, UPPERCASE_ID);
});

test("cleanup plan safely merges seed and client variants", () => {
  const lowercaseData = completedWorkout({
    updatedAt: fakeTimestamp(100),
    participations: [{workoutId: LOWERCASE_ID, contextType: "climb_attempt"}],
  });
  const uppercaseData = completedWorkout({
    updatedAt: fakeTimestamp(200),
    participations: [{workoutId: UPPERCASE_ID, contextType: "climb_attempt"}],
  });

  const plan = planCaseVariantWorkoutMerges([
    {userId: "user-1", workoutId: LOWERCASE_ID, data: lowercaseData},
    {userId: "user-1", workoutId: UPPERCASE_ID, data: uppercaseData},
  ]);

  assert.equal(plan.conflicts.length, 0);
  assert.equal(plan.merges.length, 1);
  assert.equal(plan.merges[0].canonicalWorkoutId, UPPERCASE_ID);
  assert.deepEqual(plan.merges[0].deleteWorkoutIds, [LOWERCASE_ID]);
  assert.equal(plan.merges[0].targetData.participations[0].workoutId, UPPERCASE_ID);
  assert.equal(plan.merges[0].targetData.updatedAt.toMillis(), 200);
});

test("cleanup plan renames a lone non-canonical document", () => {
  const plan = planCaseVariantWorkoutMerges([
    {
      userId: "user-1",
      workoutId: LOWERCASE_ID,
      data: completedWorkout({
        participations: [{workoutId: LOWERCASE_ID, contextType: "climb_attempt"}],
      }),
    },
  ]);

  assert.equal(plan.conflicts.length, 0);
  assert.equal(plan.merges.length, 1);
  assert.equal(plan.merges[0].canonicalWorkoutId, UPPERCASE_ID);
  assert.deepEqual(plan.merges[0].deleteWorkoutIds, [LOWERCASE_ID]);
  assert.equal(plan.merges[0].targetData.participations[0].workoutId, UPPERCASE_ID);
});

test("cleanup plan leaves already-canonical documents alone", () => {
  const plan = planCaseVariantWorkoutMerges([
    {userId: "user-1", workoutId: UPPERCASE_ID, data: completedWorkout()},
  ]);

  assert.equal(plan.merges.length, 0);
  assert.equal(plan.conflicts.length, 0);
});

test("cleanup plan blocks payload conflicts instead of deleting data", () => {
  const plan = planCaseVariantWorkoutMerges([
    {userId: "user-1", workoutId: LOWERCASE_ID, data: completedWorkout({steps: 2_096})},
    {userId: "user-1", workoutId: UPPERCASE_ID, data: completedWorkout({steps: 2_000})},
  ]);

  assert.equal(plan.merges.length, 0);
  assert.equal(plan.conflicts.length, 1);
  assert.deepEqual(plan.conflicts[0].conflictingFields, ["steps"]);
});

test("merged group rebuilds its landmarkResult from the canonical document", () => {
  const documents = [
    {userId: "user-1", workoutId: LOWERCASE_ID, data: completedWorkout()},
  ];
  const plan = planCaseVariantWorkoutMerges(documents);

  const projections = planAffectedLandmarkProjections(documents, plan.merges);

  assert.equal(projections.length, 1);
  assert.equal(projections[0].climbId, CLIMB_ID);
  assert.equal(projections[0].projection.attemptCount, 1);
  assert.equal(projections[0].projection.bestWorkoutId, UPPERCASE_ID);
});

test("carried repair with no surviving completion is planned for deletion", () => {
  const projections = planAffectedLandmarkProjections(
    [],
    [],
    [{userId: "user-1", climbId: CLIMB_ID}]
  );

  assert.deepEqual(projections, [
    {userId: "user-1", climbId: CLIMB_ID, projection: null},
  ]);
});

test("carried repair that still has a completion is rebuilt, not deleted", () => {
  const documents = [
    {userId: "user-1", workoutId: UPPERCASE_ID, data: completedWorkout()},
  ];

  const projections = planAffectedLandmarkProjections(
    documents,
    [],
    [{userId: "user-1", climbId: CLIMB_ID}]
  );

  assert.equal(projections.length, 1);
  assert.equal(projections[0].projection.attemptCount, 1);
});

test("a merge that loses its only completion still aborts the run", () => {
  const documents = [
    {userId: "user-1", workoutId: LOWERCASE_ID, data: completedWorkout()},
  ];
  const plan = planCaseVariantWorkoutMerges(documents);
  plan.merges[0].targetData = {...plan.merges[0].targetData, sourceMetadata: "{}"};

  assert.throws(
    () => planAffectedLandmarkProjections(documents, plan.merges),
    /No surviving completion for user-1\//
  );
});

test("apply plan chunks past the Firestore batch limit without splitting a group", () => {
  const unitSizes = [
    ...Array.from({length: 400}, () => 2),
    ...Array.from({length: 120}, () => 1),
  ];

  const sizes = packBatchSizes(unitSizes);

  assert.equal(sizes.reduce((sum, size) => sum + size, 0), 920);
  assert.ok(sizes.every((size) => size <= BATCH_WRITE_LIMIT));
  assert.deepEqual(sizes, [500, 420]);
});

test("apply plan fits a small run in one batch", () => {
  assert.deepEqual(packBatchSizes([2, 3, 1]), [6]);
});

test("apply plan commits nothing when there is nothing to do", () => {
  assert.deepEqual(packBatchSizes([]), []);
});

test("apply plan refuses a single group larger than one batch", () => {
  assert.throws(
    () => packBatchSizes([BATCH_WRITE_LIMIT + 1]),
    /above Firestore's 500-write batch limit/
  );
});

test("invalid workout ids are rejected at the canonical boundary", () => {
  assert.throws(() => canonicalWorkoutDocumentId("not-a-uuid"), /Invalid workout UUID/);
});

test("the newest payload decides which fields survive a merge", () => {
  const plan = planCaseVariantWorkoutMerges([
    {
      userId: "user-1",
      workoutId: LOWERCASE_ID,
      data: completedWorkout({updatedAt: fakeTimestamp(100), notes: "older twin note"}),
    },
    {
      userId: "user-1",
      workoutId: UPPERCASE_ID,
      data: completedWorkout({updatedAt: fakeTimestamp(200)}),
    },
  ]);

  assert.equal(plan.conflicts.length, 0);
  assert.equal(plan.merges.length, 1);
  assert.equal("notes" in plan.merges[0].targetData, false);
  assert.deepEqual(plan.merges[0].droppedFields, ["notes"]);
});

test("a field the newest payload keeps but disagrees on still blocks the merge", () => {
  const plan = planCaseVariantWorkoutMerges([
    {
      userId: "user-1",
      workoutId: LOWERCASE_ID,
      data: completedWorkout({updatedAt: fakeTimestamp(100), notes: "older"}),
    },
    {
      userId: "user-1",
      workoutId: UPPERCASE_ID,
      data: completedWorkout({updatedAt: fakeTimestamp(200), notes: "newer"}),
    },
  ]);

  assert.equal(plan.merges.length, 0);
  assert.deepEqual(plan.conflicts[0].conflictingFields, ["notes"]);
});

test("seeded replay count reflects the rows that exist after the seed commits", () => {
  assert.equal(seededReplayCompletedCount([], UPPERCASE_ID), 1);
  assert.equal(seededReplayCompletedCount([LOWERCASE_ID], UPPERCASE_ID), 1);
  assert.equal(seededReplayCompletedCount([UPPERCASE_ID], UPPERCASE_ID), 1);
  assert.equal(seededReplayCompletedCount([LOWERCASE_ID, UPPERCASE_ID], UPPERCASE_ID), 1);
  assert.equal(
    seededReplayCompletedCount(["other-climber-row", LOWERCASE_ID], UPPERCASE_ID),
    2
  );
  assert.deepEqual(staleWorkoutDocumentIds(UPPERCASE_ID), [LOWERCASE_ID]);
});

test("every live replay collection that names a workout id is covered", () => {
  const paths = [
    "live_replay_leaderboards/live_climb_empire",
    "live_replay_leaderboards/live_climb_empire/splitBuckets/0/entries/ID",
    "live_replay_leaderboards/live_climb_empire/completionSnapshots/ID",
    "live_replay_leaderboards/live_climb_empire/finishers/user-1",
    "live_replay_leaderboards/live_climb_empire/userBestAttempts/user-1",
    "users/user-1/liveClimbPublishStatuses/ID",
    "users/user-1/profile_workouts/ID",
  ];

  for (const path of paths) {
    assert.ok(matchWorkoutIdReferenceShape(path), `uncovered path: ${path}`);
  }
  assert.equal(matchWorkoutIdReferenceShape("users/user-1/workouts/ID"), null);
});

test("renames come from this run, the ledger, and live non-canonical references", () => {
  const documents = [
    {userId: "user-1", workoutId: LOWERCASE_ID, data: completedWorkout()},
  ];
  const plan = planCaseVariantWorkoutMerges(documents);
  const otherLowercase = "0d0c8f6c-1111-4222-8333-444444444444";
  const otherUppercase = otherLowercase.toUpperCase();

  const renames = planWorkoutIdReferenceRenames(
    plan.merges,
    [{workoutId: "aaaaaaaa-1111-4222-8333-444444444444", canonicalWorkoutId: "AAAAAAAA-1111-4222-8333-444444444444"}],
    [entryReference(otherLowercase)],
    finalWorkoutDocuments(
      [...documents, {userId: "user-1", workoutId: otherUppercase, data: completedWorkout()}],
      plan.merges
    )
  );

  assert.deepEqual(renames.map((rename) => rename.workoutId).sort(), [
    "0d0c8f6c-1111-4222-8333-444444444444",
    "51c91094-5475-4b25-ab8f-a5d809f90a2f",
    "aaaaaaaa-1111-4222-8333-444444444444",
  ]);
});

test("replay rows keyed on a renamed workout move onto the canonical id", () => {
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    [entryReference(LOWERCASE_ID)]
  );

  assert.equal(repairs.conflicts.length, 0);
  assert.equal(repairs.moves.length, 1);
  assert.equal(repairs.moves[0].fromDocumentId, LOWERCASE_ID);
  assert.equal(repairs.moves[0].toDocumentId, UPPERCASE_ID);
  assert.equal(repairs.moves[0].data.workoutId, UPPERCASE_ID);
});

test("a stale twin of an identical canonical row is deleted, not rewritten", () => {
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    [entryReference(LOWERCASE_ID), entryReference(UPPERCASE_ID)]
  );

  assert.equal(repairs.conflicts.length, 0);
  assert.equal(repairs.moves.length, 1);
  assert.equal(repairs.moves[0].data, null);
});

test("a newer stale twin replaces the canonical row it moves onto", () => {
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    [
      entryReference(LOWERCASE_ID, {finalSteps: 2_096, updatedAt: fakeTimestamp(200)}),
      entryReference(UPPERCASE_ID, {finalSteps: 1_000, updatedAt: fakeTimestamp(100)}),
    ]
  );

  assert.equal(repairs.conflicts.length, 0);
  assert.equal(repairs.moves.length, 1);
  assert.equal(repairs.moves[0].data.finalSteps, 2_096);
});

test("twins that differ with no comparable timestamp block the apply", () => {
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    [
      entryReference(LOWERCASE_ID, {finalSteps: 2_096, updatedAt: undefined}),
      entryReference(UPPERCASE_ID, {finalSteps: 1_000, updatedAt: undefined}),
    ]
  );

  assert.equal(repairs.moves.length, 0);
  assert.equal(repairs.conflicts.length, 1);
});

test("every workout-id-keyed shape resolves twins through its own recency field", () => {
  const shapes = [
    {
      path: (id) => `live_replay_leaderboards/live_climb_empire/splitBuckets/0/entries/${id}`,
      recencyField: "updatedAt",
    },
    {
      path: (id) => `live_replay_leaderboards/live_climb_empire/completionSnapshots/${id}`,
      recencyField: "rankedAt",
    },
    {
      path: (id) => `users/user-1/liveClimbPublishStatuses/${id}`,
      recencyField: "updatedAt",
    },
    {
      path: (id) => `users/user-1/profile_workouts/${id}`,
      recencyField: "lastUpdated",
    },
  ];

  for (const shape of shapes) {
    const repairs = planWorkoutIdReferenceRepairs(
      [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
      [
        referenceFor(shape.path(LOWERCASE_ID), {
          steps: 2_096,
          [shape.recencyField]: fakeTimestamp(200),
        }),
        referenceFor(shape.path(UPPERCASE_ID), {
          steps: 1_000,
          [shape.recencyField]: fakeTimestamp(100),
        }),
      ]
    );

    assert.deepEqual(repairs.conflicts, [], `${shape.recencyField} pair should resolve`);
    assert.equal(repairs.moves.length, 1);
    assert.equal(repairs.moves[0].data.steps, 2_096);
    assert.equal(repairs.moves[0].duplicate, true);
  }
});

test("a twin pair with no recency field at all still blocks the apply", () => {
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    [
      referenceFor(
        `live_replay_leaderboards/live_climb_empire/completionSnapshots/${LOWERCASE_ID}`,
        {rank: 3}
      ),
      referenceFor(
        `live_replay_leaderboards/live_climb_empire/completionSnapshots/${UPPERCASE_ID}`,
        {rank: 4}
      ),
    ]
  );

  assert.equal(repairs.moves.length, 0);
  assert.equal(repairs.conflicts.length, 1);
});

test("a reference scanned without its full payload can never be moved", () => {
  const stale = entryReference(LOWERCASE_ID);
  stale.partial = true;

  assert.throws(
    () => planWorkoutIdReferenceRepairs(
      [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
      [stale]
    ),
    /scanned without its full payload/
  );
});

test("scanning a twinned entry pair re-reads the canonical row in full", async () => {
  const parentPath = "live_replay_leaderboards/live_climb_empire/splitBuckets/0/entries";
  const firestore = fakeFirestore({
    [`${parentPath}/${LOWERCASE_ID}`]: scannedEntry(LOWERCASE_ID, 90),
    [`${parentPath}/${UPPERCASE_ID}`]: scannedEntry(UPPERCASE_ID, 100),
  });

  const references = await scanWorkoutIdReferences(firestore);

  const canonical = references.find((reference) => reference.documentId === UPPERCASE_ID);
  assert.equal(canonical.partial, false);
  assert.equal(canonical.data.finalSteps, 2_096);
  assert.deepEqual(
    planWorkoutIdReferenceRepairs(
      [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
      references
    ).conflicts,
    []
  );
});

test("scanning a canonical row with no stale twin keeps it trimmed", async () => {
  const parentPath = "live_replay_leaderboards/live_climb_empire/splitBuckets/0/entries";
  const firestore = fakeFirestore({
    [`${parentPath}/${UPPERCASE_ID}`]: scannedEntry(UPPERCASE_ID, 100),
  });

  const references = await scanWorkoutIdReferences(firestore);

  assert.equal(references.length, 1);
  assert.equal(references[0].partial, true);
  assert.equal("finalSteps" in references[0].data, false);
});

test("dropping a duplicate row lowers the summary by exactly that row", () => {
  const references = [
    summaryReference({completedCount: 89, totalClimbers: 96}),
    finisherReference("user-1", 89),
    entryReference(LOWERCASE_ID),
    entryReference(UPPERCASE_ID),
  ];
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    references
  );

  const summaryPlan = planReplaySummaryRepairs(repairs.moves, references);

  assert.deepEqual(summaryPlan.summaryUpdates, [{
    contextKey: "live_climb_empire",
    updates: {completedCount: 88, totalClimbers: 95},
    droppedRows: 1,
    fromLedger: false,
  }]);
  assert.deepEqual(summaryPlan.notes, []);
});

test("a seeded context with no finishers keeps its counts apart from the delta", () => {
  const references = [
    summaryReference({completedCount: 89, totalClimbers: 96}),
    entryReference(LOWERCASE_ID),
    entryReference(UPPERCASE_ID),
  ];
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    references
  );

  const summaryPlan = planReplaySummaryRepairs(repairs.moves, references);

  assert.deepEqual(summaryPlan.summaryUpdates[0].updates, {
    completedCount: 88,
    totalClimbers: 95,
  });
});

test("duplicates outside bucket zero never touch the summary", () => {
  const bucketFivePath = "live_replay_leaderboards/live_climb_empire/splitBuckets/5/entries";
  const references = [
    summaryReference({completedCount: 89, totalClimbers: 96}),
    referenceFor(`${bucketFivePath}/${LOWERCASE_ID}`, {
      updatedAt: fakeTimestamp(100),
      workoutId: LOWERCASE_ID,
    }),
    referenceFor(`${bucketFivePath}/${UPPERCASE_ID}`, {
      updatedAt: fakeTimestamp(100),
      workoutId: UPPERCASE_ID,
    }),
  ];
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    references
  );

  const summaryPlan = planReplaySummaryRepairs(repairs.moves, references);

  assert.equal(repairs.moves.length, 1);
  assert.deepEqual(summaryPlan.summaryUpdates, []);
  assert.deepEqual(summaryPlan.owedRepairs, []);
});

test("a summary too small to absorb the delta is reported, not rewritten", () => {
  const references = [
    summaryReference({completedCount: 0, totalClimbers: 0}),
    entryReference(LOWERCASE_ID),
    entryReference(UPPERCASE_ID),
  ];
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    references
  );

  const summaryPlan = planReplaySummaryRepairs(repairs.moves, references);

  assert.deepEqual(summaryPlan.summaryUpdates, []);
  assert.equal(summaryPlan.notes.length, 1);
});

test("a rerun after a partial apply finishes the decrement the ledger owed", () => {
  const secondLowercase = "0d0c8f6c-1111-4222-8333-444444444444";
  const secondUppercase = secondLowercase.toUpperCase();
  const renames = [
    {workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID},
    {workoutId: secondLowercase, canonicalWorkoutId: secondUppercase},
  ];

  const firstRunReferences = [
    summaryReference({completedCount: 89, totalClimbers: 96}),
    entryReference(LOWERCASE_ID),
    entryReference(UPPERCASE_ID),
    entryReference(secondLowercase),
    entryReference(secondUppercase),
  ];
  const firstRun = planReplaySummaryRepairs(
    planWorkoutIdReferenceRepairs(renames, firstRunReferences).moves,
    firstRunReferences
  );

  assert.deepEqual(firstRun.owedRepairs, [{
    contextKey: "live_climb_empire",
    completedCount: 87,
    totalClimbers: 94,
  }]);

  const rerunReferences = [
    summaryReference({completedCount: 89, totalClimbers: 96}),
    entryReference(LOWERCASE_ID),
    entryReference(UPPERCASE_ID),
    entryReference(secondUppercase),
  ];
  const rerun = planReplaySummaryRepairs(
    planWorkoutIdReferenceRepairs(renames, rerunReferences).moves,
    rerunReferences,
    firstRun.owedRepairs
  );

  assert.deepEqual(rerun.summaryUpdates, [{
    contextKey: "live_climb_empire",
    updates: {completedCount: 87, totalClimbers: 94},
    droppedRows: 1,
    fromLedger: true,
  }]);
  assert.deepEqual(rerun.owedRepairs, firstRun.owedRepairs);
});

test("a duplicate found after the ledger was written lowers the target further", () => {
  const references = [
    summaryReference({completedCount: 88, totalClimbers: 95}),
    entryReference(LOWERCASE_ID),
    entryReference(UPPERCASE_ID),
  ];
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    references
  );

  const summaryPlan = planReplaySummaryRepairs(repairs.moves, references, [
    {contextKey: "live_climb_empire", completedCount: 88, totalClimbers: 95},
  ]);

  assert.deepEqual(summaryPlan.summaryUpdates[0].updates, {
    completedCount: 87,
    totalClimbers: 94,
  });
});

test("an owed decrement never raises a summary that already dropped below it", () => {
  const summaryPlan = planReplaySummaryRepairs(
    [],
    [summaryReference({completedCount: 80, totalClimbers: 90})],
    [{contextKey: "live_climb_empire", completedCount: 87, totalClimbers: 94}]
  );

  assert.deepEqual(summaryPlan.summaryUpdates, []);
  assert.equal(summaryPlan.notes.length, 1);
  assert.deepEqual(summaryPlan.owedRepairs, [
    {contextKey: "live_climb_empire", completedCount: 87, totalClimbers: 94},
  ]);
});

test("a decrement owed by an earlier run is reapplied only when it did not land", () => {
  const owed = {contextKey: "live_climb_empire", completedCount: 88, totalClimbers: 95};

  const outstanding = planReplaySummaryRepairs(
    [],
    [summaryReference({completedCount: 89, totalClimbers: 96})],
    [owed]
  );
  const landed = planReplaySummaryRepairs(
    [],
    [summaryReference({completedCount: 88, totalClimbers: 95})],
    [owed]
  );

  assert.deepEqual(outstanding.summaryUpdates, [{
    contextKey: "live_climb_empire",
    updates: {completedCount: 88, totalClimbers: 95},
    droppedRows: 0,
    fromLedger: true,
  }]);
  assert.deepEqual(landed.summaryUpdates, []);
  assert.deepEqual(landed.owedRepairs, [owed]);
});

test("renaming a row without a twin leaves the summary alone", () => {
  const references = [
    summaryReference({completedCount: 3, totalClimbers: 3}),
    entryReference(LOWERCASE_ID),
  ];
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    references
  );

  const summaryPlan = planReplaySummaryRepairs(repairs.moves, references);

  assert.equal(repairs.moves[0].duplicate, false);
  assert.deepEqual(summaryPlan.owedRepairs, []);
  assert.deepEqual(summaryPlan.summaryUpdates, []);
});

test("fields that store a renamed workout id are rewritten in place", () => {
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    [
      referenceFor("live_replay_leaderboards/live_climb_empire/finishers/user-1", {
        bestWorkoutId: LOWERCASE_ID,
        firstWorkoutId: UPPERCASE_ID,
      }),
      referenceFor("live_replay_leaderboards/live_climb_empire", {
        firstAscentWorkoutId: LOWERCASE_ID,
      }),
    ]
  );

  assert.equal(repairs.moves.length, 0);
  assert.deepEqual(repairs.fieldUpdates.map((update) => update.updates), [
    {firstAscentWorkoutId: UPPERCASE_ID},
    {bestWorkoutId: UPPERCASE_ID},
  ]);
});

test("repairs are idempotent once every reference is canonical", () => {
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    [entryReference(UPPERCASE_ID)]
  );

  assert.deepEqual(repairs.moves, []);
  assert.deepEqual(repairs.fieldUpdates, []);
  assert.deepEqual(repairs.conflicts, []);
  assert.deepEqual(repairs.unresolved, []);
});

test("a non-canonical reference with no surviving workout is reported, not guessed at", () => {
  const repairs = planWorkoutIdReferenceRepairs([], [entryReference(LOWERCASE_ID)]);

  assert.deepEqual(repairs.moves, []);
  assert.deepEqual(repairs.fieldUpdates, []);
  assert.equal(repairs.unresolved.length, 1);
  assert.equal(repairs.unresolved[0].workoutId, LOWERCASE_ID);
});

function entryReference(documentId, overrides = {}) {
  return referenceFor(
    `live_replay_leaderboards/live_climb_empire/splitBuckets/0/entries/${documentId}`,
    {
      finalSteps: 2_096,
      updatedAt: fakeTimestamp(100),
      userId: "user-1",
      workoutId: documentId,
      ...overrides,
    }
  );
}

function summaryReference(data) {
  return referenceFor("live_replay_leaderboards/live_climb_empire", data);
}

function finisherReference(userId, globalCompletionOrder) {
  return referenceFor(`live_replay_leaderboards/live_climb_empire/finishers/${userId}`, {
    globalCompletionOrder,
    updatedAt: fakeTimestamp(100),
    userId,
  });
}

function scannedEntry(documentId, updatedAtSeconds) {
  return {
    finalSteps: 2_096,
    updatedAt: fakeTimestamp(updatedAtSeconds),
    userId: "user-1",
    workoutId: documentId,
  };
}

/**
 * Minimal stand-in for the Firestore surface `scanWorkoutIdReferences` uses: streamed
 * collection and collection-group queries, plus the `getAll` re-read of canonical twins.
 * @param {Record<string, object>} documents Document data keyed by full path.
 * @return {object} Fake Firestore instance.
 */
function fakeFirestore(documents) {
  const snapshotFor = (path) => ({
    id: path.split("/").at(-1),
    ref: {path, parent: {path: path.split("/").slice(0, -1).join("/")}},
    exists: path in documents,
    data: () => documents[path],
  });
  const streamOf = (paths) => ({
    async* stream() {
      for (const path of paths) {
        yield snapshotFor(path);
      }
    },
  });
  const paths = Object.keys(documents);

  return {
    collection: (collectionId) => streamOf(
      paths.filter((path) => path.split("/").length === 2 && path.startsWith(`${collectionId}/`))
    ),
    collectionGroup: (collectionId) => streamOf(
      paths.filter((path) => path.split("/").at(-2) === collectionId)
    ),
    doc: (path) => path,
    getAll: async (...refs) => refs.map((path) => snapshotFor(path)),
  };
}

function referenceFor(path, data) {
  const shape = matchWorkoutIdReferenceShape(path);
  assert.ok(shape, `no reference shape matches ${path}`);
  const segments = path.split("/");
  return {
    parentPath: segments.slice(0, -1).join("/"),
    documentId: segments.at(-1),
    keyedByWorkoutId: shape.keyedByWorkoutId,
    workoutIdFields: shape.workoutIdFields,
    recencyFields: shape.recencyFields,
    data,
  };
}

function completedWorkout(overrides = {}) {
  return {
    source: "headphone_motion",
    steps: 2_096,
    durationSeconds: 1_338,
    updatedAt: fakeTimestamp(100),
    sourceMetadata: JSON.stringify({
      climbId: CLIMB_ID,
      stopReason: "target_reached",
      targetStepCount: 2_096,
      trackingMode: "live_climb",
    }),
    ...overrides,
  };
}

function fakeTimestamp(millis) {
  return {toMillis: () => millis};
}
