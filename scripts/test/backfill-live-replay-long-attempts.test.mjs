import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, join} from "node:path";
import {
  applyRepublishes,
  backfillGoalKeys,
  boardCurveForWorkout,
  planAttemptRepublish,
  planBackfill,
  renderReport,
} from "../backfill-live-replay-long-attempts.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const captain = JSON.parse(
  readFileSync(join(here, "../../SharedTestVectors/pre-fix-sampler-long-climbs.json"), "utf8")
).climbs[0];

const BOARD = "live_replay_leaderboards/just_climb__global";
const CAPTAIN = "captain";
const WORKOUT = "ninety-minute-climb";

function workoutDocument({durationSeconds, steps, splitIntervalSeconds, splitSteps}) {
  return {
    durationSeconds,
    source: "headphone_motion",
    sourceMetadata: JSON.stringify({
      splitIntervalSeconds,
      splitSteps,
      stopReason: "user_stopped",
      trackingMode: "just_climb",
    }),
    steps,
  };
}

const captainWorkout = workoutDocument({
  durationSeconds: captain.durationSeconds,
  steps: captain.steps,
  splitIntervalSeconds: captain.splitIntervalSeconds,
  splitSteps: captain.splitSteps,
});

/** The captain's attempt as the pre-fix publish left it on the board. */
function preFixEntry(stepsAtBucket, overrides = {}) {
  return {
    avatarToken: "token",
    bestForGoals: ["duration:3600", "steps:7700"],
    completionDurationSeconds: captain.durationSeconds,
    contextId: "global",
    contextType: "just_climb",
    displayName: "Captain",
    finalSteps: captain.steps,
    identityState: "published",
    isBestForUser: true,
    isSynthetic: false,
    photoURL: "",
    schemaVersion: 1,
    splitBucketCount: 360,
    splitIntervalSeconds: 10,
    stepsAtBucket,
    userId: CAPTAIN,
    workoutId: WORKOUT,
    ...overrides,
  };
}

const entryPath = (bucketIndex, workoutId = WORKOUT) =>
  `${BOARD}/splitBuckets/${bucketIndex}/entries/${workoutId}`;

test("a clamped workout's board curve runs through the finish", () => {
  const curve = boardCurveForWorkout(captainWorkout);

  assert.equal(curve.boardSteps.length, 541);
  assert.equal(curve.boardSteps[358], 5015);
  assert.ok(curve.boardSteps[359] < 5040, `60:00 = ${curve.boardSteps[359]}`);
  assert.equal(curve.boardSteps[540], 7708);
});

test("a workout the function would not publish is left alone and named", () => {
  assert.match(boardCurveForWorkout(undefined).reason, /missing/);
  assert.match(
    boardCurveForWorkout(workoutDocument({
      durationSeconds: 24 * 60 * 60 + 1,
      steps: 90000,
      splitIntervalSeconds: 320,
      splitSteps: [1, 2, 3],
    })).reason,
    /24-hour/
  );
});

test("the plan adds every bucket past the hour and rewrites the rest", () => {
  const curve = boardCurveForWorkout(captainWorkout);
  const plan = planAttemptRepublish({entry: preFixEntry(4), boardSteps: curve.boardSteps, workout: curve});

  assert.equal(plan.upToDate, false);
  assert.equal(plan.span, 541);
  assert.deepEqual([plan.createdBuckets[0], plan.createdBuckets.at(-1)], [360, 540]);
  assert.deepEqual([plan.updatedBuckets[0], plan.updatedBuckets.at(-1)], [1, 359]);
  assert.deepEqual(plan.removedBuckets, []);

  const republished = preFixEntry(4, {splitBucketCount: 541});
  assert.deepEqual(
    planAttemptRepublish({entry: republished, boardSteps: curve.boardSteps, workout: curve}),
    {upToDate: true}
  );
});

test("an entry that no longer matches its workout is left for the trigger", () => {
  const curve = boardCurveForWorkout(captainWorkout);
  const edited = preFixEntry(4, {finalSteps: 7000});
  assert.match(
    planAttemptRepublish({entry: edited, boardSteps: curve.boardSteps, workout: curve}).reason,
    /no longer matches/
  );
});

test("a write run republishes the attempt, bucket zero last, and a second run plans nothing", async () => {
  const documents = {
    [BOARD]: {contextType: "just_climb"},
    [`users/${CAPTAIN}/workouts/${WORKOUT}`]: captainWorkout,
    [`${BOARD}/attemptCurves/${WORKOUT}`]: {splitSteps: captain.splitSteps, splitIntervalSeconds: 10},
    // A seeded rival and a long attempt whose backup is gone are both skipped.
    [entryPath(0, "seeded")]: preFixEntry(4, {isSynthetic: true, workoutId: "seeded"}),
    [entryPath(0, "orphan")]: preFixEntry(4, {userId: "someone", workoutId: "orphan"}),
    // A climb inside the hour was never cut short and is not a candidate.
    [entryPath(0, "short")]: preFixEntry(4, {completionDurationSeconds: 1200, workoutId: "short"}),
  };
  captain.splitSteps.forEach((steps, index) => {
    documents[entryPath(index)] = preFixEntry(steps);
  });
  const db = memoryFirestore(documents);

  const plan = await planBackfill(db, {contextKey: null});
  assert.equal(plan.candidates, 3);
  assert.equal(plan.synthetic, 1);
  assert.deepEqual(plan.unrepairable.map((skipped) => skipped.workoutId), ["orphan"]);
  assert.equal(plan.republishes.length, 1);
  assert.match(
    renderReport(plan, {environment: {env: "dev", projectId: "ascend-f2e4f"}, apply: false}),
    /just_climb__global\/ninety-minute-climb: 181 bucket\(s\) created, 360 updated, 0 removed; span 541, attempt curve rewritten/
  );

  const written = await applyRepublishes(db, plan.republishes);
  assert.equal(written, 181 + 359 + 1 + 1);

  // Where the live race will read the captain now.
  const bucket = (index) => db.store.get(entryPath(index));
  assert.equal(bucket(0).splitBucketCount, 541);
  assert.equal(bucket(358).stepsAtBucket, 5015);
  assert.ok(bucket(359).stepsAtBucket < 5040);
  assert.equal(bucket(540).stepsAtBucket, 7708);
  assert.equal(bucket(540).displayName, "Captain");
  assert.equal(bucket(540).isBestForUser, true);
  assert.equal(bucket(200).splitBucketCount, 541);
  assert.equal(db.store.get(`${BOARD}/attemptCurves/${WORKOUT}`).splitSteps.length, 541);

  // Bucket zero lands in the final commit, after every bucket it points at.
  const lastCommit = db.commits.at(-1);
  assert.ok(lastCommit.some((operation) => operation.path === entryPath(0)));
  assert.ok(db.commits.slice(0, -1).every((commit) =>
    commit.every((operation) => operation.path !== entryPath(0))
  ));

  const again = await planBackfill(db, {contextKey: null});
  assert.equal(again.republishes.length, 0);
  assert.equal(again.upToDate, 1);
});

test("one run takes a goal back from the clamped curve that won it", async () => {
  // The captain's real hour: 5,400 steps in 59:50, more than the ~5,030 the
  // ninety-minute climb had at 60:00. The clamped curve reached 7,708 at
  // 60:00, so it held duration:3600 over this attempt.
  const hour = {workoutId: "one-hour", durationSeconds: 3590, steps: 5400};
  const hourCurve = Array.from({length: 360}, (_, index) =>
    Math.min(hour.steps, Math.floor((index + 1) * 10 * hour.steps / hour.durationSeconds))
  );
  const documents = {
    [BOARD]: {contextType: "just_climb"},
    [`users/${CAPTAIN}/workouts/${WORKOUT}`]: captainWorkout,
    [`${BOARD}/attemptCurves/${WORKOUT}`]: {splitSteps: captain.splitSteps, splitIntervalSeconds: 10},
    [`${BOARD}/attemptCurves/${hour.workoutId}`]: {
      finalDurationSeconds: hour.durationSeconds,
      finalSteps: hour.steps,
      splitIntervalSeconds: 10,
      splitSteps: hourCurve,
    },
  };
  captain.splitSteps.forEach((steps, index) => {
    documents[entryPath(index)] = preFixEntry(steps);
  });
  hourCurve.forEach((steps, index) => {
    documents[entryPath(index, hour.workoutId)] = preFixEntry(steps, {
      bestForGoals: [],
      completionDurationSeconds: hour.durationSeconds,
      finalSteps: hour.steps,
      isBestForUser: false,
      workoutId: hour.workoutId,
    });
  });
  const db = memoryFirestore(documents);
  const goalsOf = (workoutId, bucketIndex = 0) =>
    db.store.get(entryPath(bucketIndex, workoutId)).bestForGoals;

  const plan = await planBackfill(db, {contextKey: null});
  assert.deepEqual(plan.longAttemptBoards, ["just_climb__global"]);

  // The plan shows the rewrite and writes nothing.
  const planned = await backfillGoalKeys(db, plan.longAttemptBoards, {dryRun: true});
  assert.ok(planned.boards[0].goalKeyRewrites > 0);
  assert.ok(goalsOf(WORKOUT).includes("duration:3600"));

  await applyRepublishes(db, plan.republishes);
  const applied = await backfillGoalKeys(db, plan.longAttemptBoards, {dryRun: false});

  assert.deepEqual(applied.skippedClimbers, []);
  assert.ok(goalsOf(hour.workoutId).includes("duration:3600"));
  assert.ok(goalsOf(hour.workoutId, 359).includes("duration:3600"));
  assert.equal(goalsOf(WORKOUT).includes("duration:3600"), false);
  // The keys reach the buckets past the hour the republish created.
  assert.deepEqual(goalsOf(WORKOUT, 540), goalsOf(WORKOUT));
  assert.ok(goalsOf(WORKOUT).includes("steps:7700"));

  // A second run changes nothing.
  const again = await backfillGoalKeys(db, (await planBackfill(db, {contextKey: null})).longAttemptBoards, {
    dryRun: false,
  });
  assert.equal(again.boards[0].entryWritesApplied, 0);
});

/**
 * An in-memory Firestore with the surface the backfill touches.
 * @param {Record<string, object>} documents Initial documents by path.
 * @return {object} Fake db, its store and its accepted commits.
 */
function memoryFirestore(documents) {
  const store = new Map(Object.entries(documents));
  const commits = [];
  const depth = (path) => path.split("/").length;
  const children = (path) =>
    [...store.keys()].filter((key) => key.startsWith(`${path}/`) && depth(key) === depth(path) + 1);
  const snapshot = (path) => ({
    id: path.split("/").at(-1),
    exists: store.has(path),
    data: () => store.get(path),
  });
  const docRef = (path) => ({
    path,
    id: path.split("/").at(-1),
    get parent() {
      return collectionRef(path.split("/").slice(0, -1).join("/"));
    },
    collection: (name) => collectionRef(`${path}/${name}`),
    get: async () => snapshot(path),
    set: async (data) => {
      store.set(path, data);
    },
  });
  const query = (path, filters) => ({
    where: (field, op, value) => {
      assert.equal(op, ">=");
      return query(path, [...filters, (data) => data[field] >= value]);
    },
    get: async () => ({
      docs: children(path).map(snapshot).filter((doc) => filters.every((filter) => filter(doc.data()))),
    }),
  });
  const collectionRef = (path) => ({
    ...query(path, []),
    path,
    id: path.split("/").at(-1),
    get parent() {
      return docRef(path.split("/").slice(0, -1).join("/"));
    },
    doc: (id) => docRef(`${path}/${id}`),
    listDocuments: async () => {
      const ids = new Set([...store.keys()]
        .filter((key) => key.startsWith(`${path}/`))
        .map((key) => key.slice(path.length + 1).split("/")[0]));
      return [...ids].map((id) => docRef(`${path}/${id}`));
    },
  });

  return {
    store,
    commits,
    collection: collectionRef,
    doc: docRef,
    getAll: async (...refs) => refs.map((ref) => snapshot(ref.path)),
    batch() {
      const operations = [];
      return {
        set: (ref, data) => operations.push({kind: "set", path: ref.path, data}),
        update: (ref, data) => operations.push({kind: "update", path: ref.path, data}),
        delete: (ref) => operations.push({kind: "delete", path: ref.path}),
        commit: async () => {
          for (const {kind, path, data} of operations) {
            if (kind === "delete") store.delete(path);
            else if (kind === "set") store.set(path, data);
            else {
              assert.ok(store.has(path), `update of missing ${path}`);
              store.set(path, {...store.get(path), ...data});
            }
          }
          commits.push(operations);
        },
      };
    },
  };
}
