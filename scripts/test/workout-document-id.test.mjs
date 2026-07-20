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
import {buildProfileSeedWrites} from "../seed/fixtures/profile-fixtures.mjs";
import {
  BATCH_WRITE_LIMIT,
  REPLAY_SUMMARY_REPAIR_KIND,
  WORKOUT_ID_RENAME_REPAIR_KIND,
  classifyPendingRepairs,
  finalWorkoutDocuments,
  matchWorkoutIdReferenceShape,
  packBatchSizes,
  planAffectedLandmarkProjections,
  planCaseVariantWorkoutMerges,
  planReplaySummaryRepairs,
  planWorkoutIdReferenceRenames,
  planWorkoutIdReferenceRepairs,
  replaySummaryObligationId,
  resolveReplaySummaryDecrement,
  scanWorkoutIdReferences,
} from "../lib/workout-id-case-migration.mjs";

const LOWERCASE_ID = "51c91094-5475-4b25-ab8f-a5d809f90a2f";
const UPPERCASE_ID = LOWERCASE_ID.toUpperCase();
const CLIMB_ID = "empire-state-building";
const DEFAULT_VERSION_TOKEN = "500";

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

test("dropping a duplicate row owes the summary exactly that row", () => {
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

  assert.deepEqual(summaryPlan.owedObligations, [rowObligation(LOWERCASE_ID)]);
  assert.deepEqual(summaryPlan.decrements, [{
    contextKey: "live_climb_empire",
    obligations: [{
      obligationId: obligationIdFor(LOWERCASE_ID),
      rowPath: entryPath(LOWERCASE_ID),
    }],
    droppedRows: 1,
    currentCounts: {completedCount: 89, totalClimbers: 96},
    projectedCounts: {completedCount: 88, totalClimbers: 95},
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

  assert.deepEqual(summaryPlan.decrements[0].projectedCounts, {
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
  assert.deepEqual(summaryPlan.decrements, []);
  assert.deepEqual(summaryPlan.owedObligations, []);
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

  assert.deepEqual(summaryPlan.decrements, []);
  assert.equal(summaryPlan.notes.length, 1);
  assert.deepEqual(summaryPlan.notes[0].obligationIds, [obligationIdFor(LOWERCASE_ID)]);
  assert.equal(summaryPlan.owedObligations.length, 1);
});

test("a run that dies after deleting the rows still owes the whole decrement", () => {
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

  assert.deepEqual(
    firstRun.owedObligations,
    [rowObligation(LOWERCASE_ID), rowObligation(secondLowercase)].sort(
      (lhs, rhs) => lhs.obligationId.localeCompare(rhs.obligationId)
    )
  );

  // The moves committed, the transaction never ran, and no marker exists. Live state no
  // longer shows the duplicates, so only the carried obligations prove the two rows.
  const rerunReferences = [
    summaryReference({completedCount: 89, totalClimbers: 96}),
    entryReference(UPPERCASE_ID),
    entryReference(secondUppercase),
  ];
  const rerun = planReplaySummaryRepairs(
    planWorkoutIdReferenceRepairs(renames, rerunReferences).moves,
    rerunReferences,
    firstRun.owedObligations
  );

  assert.equal(rerun.decrements.length, 1);
  assert.equal(rerun.decrements[0].droppedRows, 2);
  assert.deepEqual(rerun.decrements[0].projectedCounts, {
    completedCount: 87,
    totalClimbers: 94,
  });
});

// The dangerous rerun: run 1 owed two rows, its batch loop deleted only the first, and the
// second is still there to be replanned. Summing per-run obligations would owe three rows
// for two deletions; per-row occurrence ids collapse the replanned row onto the carried one.
test("a rerun that still sees one of the carried rows never owes it twice", () => {
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

  const rerunReferences = [
    summaryReference({completedCount: 89, totalClimbers: 96}),
    entryReference(UPPERCASE_ID),
    entryReference(secondLowercase),
    entryReference(secondUppercase),
  ];
  const rerun = planReplaySummaryRepairs(
    planWorkoutIdReferenceRepairs(renames, rerunReferences).moves,
    rerunReferences,
    firstRun.owedObligations
  );

  assert.equal(rerun.owedObligations.length, 2);
  assert.equal(rerun.decrements.length, 1);
  assert.equal(rerun.decrements[0].droppedRows, 2);
  assert.deepEqual(rerun.decrements[0].projectedCounts, {
    completedCount: 87,
    totalClimbers: 94,
  });
});

test("an obligation whose marker exists is never planned again", () => {
  const carried = rowObligation(LOWERCASE_ID);

  const summaryPlan = planReplaySummaryRepairs(
    [],
    [summaryReference({completedCount: 88, totalClimbers: 95})],
    [carried],
    [carried.obligationId]
  );

  assert.deepEqual(summaryPlan.decrements, []);
  assert.deepEqual(summaryPlan.owedObligations, []);
  assert.deepEqual(summaryPlan.settledObligations, [carried]);
});

// A settled marker names one row at one version, so a duplicate recreated at that same path
// later is a fresh occurrence that owes its own decrement instead of being silently settled.
test("a duplicate recreated at a settled row's path owes a new obligation", () => {
  const settled = rowObligation(LOWERCASE_ID);
  const references = [
    summaryReference({completedCount: 88, totalClimbers: 95}),
    entryReference(LOWERCASE_ID, {}, "900"),
    entryReference(UPPERCASE_ID),
  ];
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    references
  );

  const summaryPlan = planReplaySummaryRepairs(
    repairs.moves,
    references,
    [],
    [settled.obligationId]
  );

  assert.deepEqual(summaryPlan.settledObligations, []);
  assert.deepEqual(summaryPlan.owedObligations, [rowObligation(LOWERCASE_ID, "900")]);
  assert.equal(summaryPlan.decrements[0].droppedRows, 1);
});

test("a duplicate found after the ledger was written is owed on top of the carried one", () => {
  const secondLowercase = "0d0c8f6c-1111-4222-8333-444444444444";
  const carried = rowObligation(secondLowercase);
  const references = [
    summaryReference({completedCount: 88, totalClimbers: 95}),
    entryReference(LOWERCASE_ID),
    entryReference(UPPERCASE_ID),
  ];
  const repairs = planWorkoutIdReferenceRepairs(
    [{workoutId: LOWERCASE_ID, canonicalWorkoutId: UPPERCASE_ID}],
    references
  );

  const summaryPlan = planReplaySummaryRepairs(repairs.moves, references, [carried]);

  assert.equal(summaryPlan.decrements.length, 1);
  assert.equal(summaryPlan.decrements[0].droppedRows, 2);
  assert.deepEqual(summaryPlan.decrements[0].projectedCounts, {
    completedCount: 86,
    totalClimbers: 93,
  });
});

test("climbers who finished between runs keep their counts", () => {
  const carried = rowObligation(LOWERCASE_ID);

  const summaryPlan = planReplaySummaryRepairs(
    [],
    [summaryReference({completedCount: 94, totalClimbers: 101})],
    [carried]
  );

  assert.deepEqual(summaryPlan.decrements[0].projectedCounts, {
    completedCount: 93,
    totalClimbers: 100,
  });

  const resolution = resolveReplaySummaryDecrement(
    // Two more climbers finished after the plan was built; the transaction reads them.
    {completedCount: 96, totalClimbers: 103},
    [],
    summaryPlan.decrements[0].obligations
  );

  assert.deepEqual(resolution.updates, {completedCount: 95, totalClimbers: 102});
  assert.deepEqual(resolution.obligationIds, [carried.obligationId]);
});

test("a decrement whose marker already exists writes nothing", () => {
  const resolution = resolveReplaySummaryDecrement(
    {completedCount: 88, totalClimbers: 95},
    ["obligation-a"],
    [{obligationId: "obligation-a"}]
  );

  assert.equal(resolution.updates, null);
  assert.deepEqual(resolution.obligationIds, []);
});

test("a decrement only discharges the obligations that are still unmarked", () => {
  const resolution = resolveReplaySummaryDecrement(
    {completedCount: 88, totalClimbers: 95},
    ["obligation-a"],
    [
      {obligationId: "obligation-a"},
      {obligationId: "obligation-b"},
      {obligationId: "obligation-c"},
    ]
  );

  assert.deepEqual(resolution.updates, {completedCount: 86, totalClimbers: 93});
  assert.deepEqual(resolution.obligationIds, ["obligation-b", "obligation-c"]);
});

test("a decrement counts one row per distinct obligation, never the same one twice", () => {
  const resolution = resolveReplaySummaryDecrement(
    {completedCount: 88, totalClimbers: 95},
    [],
    [
      {obligationId: "obligation-a"},
      {obligationId: "obligation-a"},
      {obligationId: "obligation-b"},
    ]
  );

  assert.deepEqual(resolution.updates, {completedCount: 86, totalClimbers: 93});
  assert.deepEqual(resolution.obligationIds, ["obligation-a", "obligation-b"]);
});

test("a decrement refuses counts that cannot absorb it", () => {
  assert.throws(
    () => resolveReplaySummaryDecrement(
      {completedCount: 1, totalClimbers: 4},
      [],
      [{obligationId: "obligation-a"}, {obligationId: "obligation-b"}]
    ),
    /cannot absorb/
  );
  assert.throws(
    () => resolveReplaySummaryDecrement(
      {completedCount: "88", totalClimbers: 95},
      [],
      [{obligationId: "obligation-a"}]
    ),
    /cannot absorb/
  );
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
  assert.deepEqual(summaryPlan.owedObligations, []);
  assert.deepEqual(summaryPlan.decrements, []);
});

test("a merge whose heart-rate pointer names a non-canonical id is blocked", () => {
  const plan = planCaseVariantWorkoutMerges([
    {
      userId: "user-1",
      workoutId: LOWERCASE_ID,
      data: completedWorkout({
        heartRateSeries: {
          storagePath: `users/user-1/workout_heart_rate/${LOWERCASE_ID}.json.gz`,
          encoding: "json+gzip",
          sampleCount: 12,
        },
      }),
    },
  ]);

  assert.deepEqual(plan.merges, []);
  assert.deepEqual(plan.conflicts, []);
  assert.equal(plan.heartRateBlocked.length, 1);
  assert.deepEqual(plan.heartRateBlocked[0].staleHeartRateStoragePaths, [
    `users/user-1/workout_heart_rate/${LOWERCASE_ID}.json.gz`,
  ]);
});

test("a merge whose heart-rate pointer already names the canonical id is safe", () => {
  const plan = planCaseVariantWorkoutMerges([
    {
      userId: "user-1",
      workoutId: LOWERCASE_ID,
      data: completedWorkout({
        heartRateSeries: {
          storagePath: `users/user-1/workout_heart_rate/${UPPERCASE_ID}.json.gz`,
          encoding: "json+gzip",
          sampleCount: 12,
        },
      }),
    },
  ]);

  assert.deepEqual(plan.heartRateBlocked, []);
  assert.equal(plan.merges.length, 1);
});

test("a heart-rate pointer on the older twin still blocks the whole group", () => {
  const plan = planCaseVariantWorkoutMerges([
    {
      userId: "user-1",
      workoutId: LOWERCASE_ID,
      data: completedWorkout({
        updatedAt: fakeTimestamp(100),
        heartRateSeries: {
          storagePath: `users/user-1/workout_heart_rate/${LOWERCASE_ID}.json.gz`,
          encoding: "json+gzip",
          sampleCount: 12,
        },
      }),
    },
    {
      userId: "user-1",
      workoutId: UPPERCASE_ID,
      data: completedWorkout({
        updatedAt: fakeTimestamp(200),
        heartRateSeries: {
          storagePath: `users/user-1/workout_heart_rate/${LOWERCASE_ID}.json.gz`,
          encoding: "json+gzip",
          sampleCount: 12,
        },
      }),
    },
  ]);

  assert.deepEqual(plan.merges, []);
  assert.equal(plan.heartRateBlocked.length, 1);
});

test("the ledger's own repair kinds are classified back into their plans", () => {
  const landmarkResult = {userId: "user-1", climbId: CLIMB_ID};
  const rename = {
    kind: WORKOUT_ID_RENAME_REPAIR_KIND,
    workoutId: LOWERCASE_ID,
    canonicalWorkoutId: UPPERCASE_ID,
  };
  const obligation = {kind: REPLAY_SUMMARY_REPAIR_KIND, ...rowObligation(LOWERCASE_ID)};

  const classified = classifyPendingRepairs([landmarkResult, rename, obligation]);

  assert.deepEqual(classified.landmarkResults, [landmarkResult]);
  assert.deepEqual(classified.renames, [rename]);
  assert.deepEqual(classified.summaryObligations, [obligation]);
  assert.deepEqual(classified.unrecognized, []);
});

// An owed repair that vanishes is worse than one that blocks the run, so anything an older
// operation version left behind - or anything malformed - has to surface, not be filtered.
test("a repair kind this version cannot interpret is reported, never filtered away", () => {
  const legacy = {kind: "replaySummaryRecount", contextKey: "live_climb_empire",
    completedCount: 88, totalClimbers: 95};
  const malformedObligation = {
    kind: REPLAY_SUMMARY_REPAIR_KIND,
    contextKey: "live_climb_empire",
    obligationId: "obligation-a",
  };
  const malformedRename = {kind: WORKOUT_ID_RENAME_REPAIR_KIND, workoutId: LOWERCASE_ID};
  const malformedProjection = {userId: "user-1"};

  const classified = classifyPendingRepairs([
    legacy,
    malformedObligation,
    malformedRename,
    malformedProjection,
    null,
  ]);

  assert.deepEqual(classified.landmarkResults, []);
  assert.deepEqual(classified.renames, []);
  assert.deepEqual(classified.summaryObligations, []);
  assert.deepEqual(classified.unrecognized, [
    legacy,
    malformedObligation,
    malformedRename,
    malformedProjection,
    null,
  ]);
});

test("profile fixtures mint canonical profile_workouts document ids", () => {
  const writes = buildProfileSeedWrites({
    db: fakeSeedFirestore(),
    catalog: new Map(),
    Timestamp: {fromDate: (date) => ({toMillis: () => date.getTime()})},
    FieldValue: {serverTimestamp: () => "server-timestamp"},
    now: new Date("2026-07-01T00:00:00.000Z"),
    includeLeaderboardRows: false,
  });

  const profileWorkoutIds = writes
    .filter((entry) => entry.shape === "profileWorkout")
    .map((entry) => entry.ref.path.split("/").at(-1));

  assert.ok(profileWorkoutIds.length > 0);
  for (const documentId of profileWorkoutIds) {
    assert.equal(documentId, canonicalWorkoutDocumentId(documentId));
  }
});

function fakeSeedFirestore() {
  const collectionAt = (path) => ({
    doc: (documentId) => documentAt(`${path}/${documentId}`),
  });
  const documentAt = (path) => ({
    path,
    collection: (collectionId) => collectionAt(`${path}/${collectionId}`),
  });
  return {collection: collectionAt};
}

function entryPath(documentId) {
  return `live_replay_leaderboards/live_climb_empire/splitBuckets/0/entries/${documentId}`;
}

function obligationIdFor(documentId, versionToken = DEFAULT_VERSION_TOKEN) {
  return replaySummaryObligationId("live_climb_empire", entryPath(documentId), versionToken);
}

function rowObligation(documentId, versionToken = DEFAULT_VERSION_TOKEN) {
  return {
    contextKey: "live_climb_empire",
    obligationId: obligationIdFor(documentId, versionToken),
    rowPath: entryPath(documentId),
    versionToken,
  };
}

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

function entryReference(documentId, overrides = {}, versionToken = DEFAULT_VERSION_TOKEN) {
  return referenceFor(
    entryPath(documentId),
    {
      finalSteps: 2_096,
      updatedAt: fakeTimestamp(100),
      userId: "user-1",
      workoutId: documentId,
      ...overrides,
    },
    versionToken
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
    updateTime: fakeTimestamp(Number(DEFAULT_VERSION_TOKEN)),
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

function referenceFor(path, data, versionToken = DEFAULT_VERSION_TOKEN) {
  const shape = matchWorkoutIdReferenceShape(path);
  assert.ok(shape, `no reference shape matches ${path}`);
  const segments = path.split("/");
  return {
    parentPath: segments.slice(0, -1).join("/"),
    documentId: segments.at(-1),
    keyedByWorkoutId: shape.keyedByWorkoutId,
    workoutIdFields: shape.workoutIdFields,
    recencyFields: shape.recencyFields,
    versionToken,
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
