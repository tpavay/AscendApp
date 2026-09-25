import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, join} from "node:path";
import {
  ENVIRONMENTS,
  PRODUCTION_PROJECT_ID,
  applyEntryWrites,
  backfillRaceBests,
  bestAttemptWorkoutId,
  curveFromData,
  entryUpdatePhases,
  entryWritePlan,
  parseArgs,
  planClimberUpdates,
  plannedEntryCommits,
  renderReport,
  resolveTarget,
  resolvedContextType,
  userAttemptEntry,
} from "../backfill-live-replay-best-per-user.mjs";
import {MAX_BATCH_WRITES} from "../lib/firestore-bulk.mjs";
import {raceGoalKeysByWorkoutId} from "../lib/live-replay-race-best.mjs";
import {MAX_GOAL_KEYS_PER_COMMIT} from "../lib/race-goal-commit-budget.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const vector = JSON.parse(
  readFileSync(
    join(here, "../../SharedTestVectors/live-replay-race-best-vector.json"),
    "utf8"
  )
);

/**
 * One of the captain's climbs as its bucket-zero entry reads on the global
 * Just Climb board, before this rule: no goal keys, whatever flag production
 * held, and the curve the vector carries for it.
 * @param {string} workoutId Vector attempt id.
 * @param {{isBestForUser?: boolean, bestForGoals?: string[]}} stored Stored flags.
 * @return {{attempt: object, curve: object}} Parsed attempt and its curve.
 */
function captainClimb(workoutId, stored = {}) {
  const fixture = vector.attempts[workoutId];
  const attempt = userAttemptEntry(
    {
      completionDurationSeconds: fixture.finalDurationSeconds,
      finalSteps: fixture.finalSteps,
      splitBucketCount: fixture.splitSteps.length,
      splitIntervalSeconds: fixture.splitIntervalSeconds,
      userId: "captain",
      workoutId,
      ...stored,
    },
    workoutId,
    "just_climb"
  );
  assert.ok(attempt);
  return {attempt, curve: {workoutId, ...fixture}};
}

function plan(climbs) {
  return planClimberUpdates({
    attempts: climbs.map((climb) => climb.attempt),
    contextType: "just_climb",
    curves: new Map(climbs.map((climb) => [climb.workoutId ?? climb.curve.workoutId, climb.curve])),
  });
}

// The captain's morning on production: the 149-step climb wore the only flag
// because the collapse ran on the duration metric. With no goal his best is
// his most steps - 1,776 across the first three, then 2,766 once that climb
// lands.
test("the captain's history: the open best becomes 1,776, then 2,766", () => {
  const history = [
    captainClimb("charminar-149", {isBestForUser: true}),
    captainClimb("just-climb-390"),
    captainClimb("cn-tower-1776"),
  ];

  const first = plan(history);
  assert.equal(first.winner, "cn-tower-1776");
  const flags = Object.fromEntries(
    first.updates.filter((u) => u.isBestForUser !== undefined).map((u) => [u.workoutId, u.isBestForUser])
  );
  assert.deepEqual(flags, {"charminar-149": false, "cn-tower-1776": true});

  const later = plan([...history, captainClimb("just-climb-2766")]);
  assert.equal(later.winner, "just-climb-2766");
  assert.equal(
    later.updates.find((u) => u.workoutId === "just-climb-2766")?.isBestForUser,
    true
  );
  assert.equal(
    later.updates.find((u) => u.workoutId === "cn-tower-1776")?.isBestForUser,
    undefined,
    "the CN Tower climb never carried the flag, so nothing is written to demote it"
  );
});

test("a step goal key lands on the fastest climb to that count", () => {
  const {updates, goalKeys} = plan([
    captainClimb("charminar-149"),
    captainClimb("just-climb-390"),
    captainClimb("cn-tower-1776"),
    captainClimb("just-climb-2766"),
  ]);

  // Fastest to 1,700 is the CN Tower climb, not the longer one; fastest to
  // 100 is the 149-step sprint.
  assert.ok(goalKeys.get("cn-tower-1776").includes("steps:1700"));
  assert.ok(goalKeys.get("charminar-149").includes("steps:100"));
  assert.equal(goalKeys.get("just-climb-2766").includes("steps:1700"), false);
  assert.deepEqual(
    updates.find((u) => u.workoutId === "cn-tower-1776")?.bestForGoals,
    goalKeys.get("cn-tower-1776")
  );
});

test("a duration goal key lands on the most steps within that time", () => {
  const {goalKeys, updates} = plan([
    captainClimb("charminar-149"),
    captainClimb("just-climb-390"),
    captainClimb("cn-tower-1776"),
    captainClimb("just-climb-2766"),
  ]);

  // Five minutes in the CN Tower climb was furthest (444 steps); thirty
  // minutes in the long climb has passed every finished one.
  assert.ok(goalKeys.get("cn-tower-1776").includes("duration:300"));
  assert.ok(goalKeys.get("just-climb-2766").includes("duration:1800"));
  assert.equal(goalKeys.get("just-climb-390").includes("duration:300"), false);
  // Every attempt gets exactly the keys it wins written: the 390-step climb
  // was the quickest of the four to 200 and 300 steps and nothing else.
  assert.deepEqual(
    updates.find((u) => u.workoutId === "just-climb-390")?.bestForGoals,
    ["steps:200", "steps:300"]
  );
});

test("a second run on corrected data plans nothing", () => {
  const history = [
    captainClimb("charminar-149"),
    captainClimb("cn-tower-1776"),
    captainClimb("just-climb-2766"),
  ];
  const first = plan(history);

  const corrected = history.map(({attempt, curve}) => ({
    attempt: {
      ...attempt,
      isBestForUser: attempt.workoutId === first.winner,
      bestForGoals: first.goalKeys.get(attempt.workoutId),
    },
    curve,
  }));

  assert.deepEqual(plan(corrected).updates, []);
});

test("a tower board diffs the flag alone and reads no curves", () => {
  const attempts = [
    userAttemptEntry({completionDurationSeconds: 900, userId: "u", workoutId: "slow"}, "slow", "live_climb"),
    userAttemptEntry({completionDurationSeconds: 700, userId: "u", workoutId: "fast", isBestForUser: false}, "fast", "live_climb"),
  ];

  const {winner, goalKeys, updates} = planClimberUpdates({attempts, contextType: "live_climb"});

  assert.equal(winner, "fast");
  assert.equal(goalKeys, null);
  assert.deepEqual(updates, [{workoutId: "fast", splitBucketCount: 360, isBestForUser: true}]);
});

test("a climber whose attempts resolve no winner is left alone, never demoted", () => {
  assert.equal(
    userAttemptEntry({userId: "u", workoutId: "w"}, "w", "just_climb"),
    null,
    "an entry with no steps is unreadable on a steps-racing board"
  );
  assert.deepEqual(
    planClimberUpdates({attempts: [], contextType: "just_climb", curves: new Map()}).updates,
    []
  );
});

test("the race metric is steps on a Just Climb and the clock on a tower", () => {
  const steps = (workoutId, finalSteps, completionDurationSeconds) =>
    userAttemptEntry({finalSteps, completionDurationSeconds, userId: "u", workoutId}, workoutId, "just_climb");
  assert.equal(
    bestAttemptWorkoutId([steps("short-fast", 149, 70), steps("long", 1776, 1201)], "just_climb"),
    "long"
  );
  const clock = (workoutId, completionDurationSeconds) =>
    userAttemptEntry({completionDurationSeconds, userId: "u", workoutId}, workoutId, "live_climb");
  assert.equal(bestAttemptWorkoutId([clock("slow", 900), clock("fast", 700)], "live_climb"), "fast");
});

test("writes reach only the buckets an attempt published into", () => {
  const plan = entryWritePlan(
    [{workoutId: "w", splitBucketCount: 4, isBestForUser: true, bestForGoals: ["steps:100"]}],
    new Map([[0, new Set(["w"])], [1, new Set(["w"])], [3, new Set(["other"])]])
  );

  assert.deepEqual(plan.writes.map((w) => w.bucketIndex), [0, 1]);
  assert.deepEqual(plan.writes[0].fields, {isBestForUser: true, bestForGoals: ["steps:100"]});
  assert.equal(plan.skipped, 2);
});

test("a stored curve is read back and an unusable one is rebuilt", () => {
  const {attempt} = captainClimb("cn-tower-1776");
  assert.equal(curveFromData(attempt, undefined), null);
  assert.equal(curveFromData(attempt, {splitSteps: [1, "x"]}), null);
  assert.deepEqual(
    curveFromData(attempt, {splitSteps: [10, 20], finalSteps: 20, finalDurationSeconds: 120, splitIntervalSeconds: 60}),
    {workoutId: "cn-tower-1776", finalSteps: 20, finalDurationSeconds: 120, splitIntervalSeconds: 60, splitSteps: [10, 20]}
  );
});

test("production needs its project id spelled out, dry run included", () => {
  assert.throws(() => resolveTarget({}), /No target/);
  assert.throws(() => resolveTarget({env: "prod"}), /--confirm-production ascend-prod-9c8f2/);
  assert.throws(() => resolveTarget({env: "prod", confirmProduction: "yes"}), /--confirm-production/);
  assert.throws(() => resolveTarget({env: "qa"}), /Unknown environment/);
  assert.equal(resolveTarget({env: "staging"}).projectId, ENVIRONMENTS.staging);
  assert.equal(
    resolveTarget({env: "prod", confirmProduction: PRODUCTION_PROJECT_ID}).projectId,
    PRODUCTION_PROJECT_ID
  );

  const args = parseArgs(["node", "script", "--env", "prod", "--confirm-production", PRODUCTION_PROJECT_ID, "--dry-run"]);
  assert.deepEqual(args, {
    env: "prod",
    confirmProduction: PRODUCTION_PROJECT_ID,
    dryRun: true,
    contextKey: null,
    help: false,
  });
  assert.throws(() => parseArgs(["node", "script", "--project", "dev"]), /Unknown argument/);
});

test("the context type comes from the summary, else the key", () => {
  assert.equal(resolvedContextType({contextType: "just_climb"}, "x"), "just_climb");
  assert.equal(resolvedContextType({}, "live_climb__burj-khalifa"), "live_climb");
  assert.equal(resolvedContextType({}, ""), null);
});

test("the report names every skipped climber and says when there is nothing to write", () => {
  const target = {label: "ascend-staging-fa7d5 (staging)"};
  const board = {
    contextKey: "just_climb__global", contextType: "just_climb", racesGoals: true,
    attemptsScanned: 12, attemptsUnreadable: 0, climbersScanned: 4, climbersChanged: 0,
    climbersSkipped: 1, attemptsPromoted: 0, attemptsDemoted: 0, goalKeyRewrites: 0,
    curvesRebuilt: 0, entryWritesPlanned: 0, entryWritesApplied: 0, bucketsWithoutEntry: 0,
    commitsPlanned: 0, largestCommitGoalKeys: 0,
  };

  const skipped = renderReport(
    {boards: [board], boardsSkipped: [], oversizedClimbers: [], skippedClimbers: [
      {contextKey: "just_climb__global", userId: "kC8GSV7h", attempts: 8, reason: "DEADLINE_EXCEEDED"},
    ]},
    {target, dryRun: false}
  );
  assert.match(skipped, /Skipped climbers \(1\)/);
  assert.match(skipped, /just_climb__global \/ kC8GSV7h \(8 attempt\(s\)\): DEADLINE_EXCEEDED/);

  const settled = renderReport(
    {boards: [{...board, climbersSkipped: 0}], boardsSkipped: [], oversizedClimbers: [], skippedClimbers: []},
    {target, dryRun: true}
  );
  assert.match(settled, /Nothing to write: every board is already on the current rule\./);
});

test("a dry run that plans a commit over the goal-key budget does not promise a clean run", () => {
  const target = {label: "ascend-prod-9c8f2 (prod)"};
  const board = {
    contextKey: "just_climb__global", contextType: "just_climb", racesGoals: true,
    attemptsScanned: 1, attemptsUnreadable: 0, climbersScanned: 1, climbersChanged: 1,
    climbersSkipped: 0, attemptsPromoted: 0, attemptsDemoted: 0, goalKeyRewrites: 1,
    curvesRebuilt: 1, entryWritesPlanned: 360, entryWritesApplied: 0, bucketsWithoutEntry: 0,
    commitsPlanned: 360, largestCommitGoalKeys: 6_000,
  };
  const report = {
    boards: [board], boardsSkipped: [], skippedClimbers: [],
    oversizedClimbers: [{contextKey: "just_climb__global", userId: "ajNZvPcA", attempts: 1, goalKeys: 6_000}],
  };

  const text = renderReport(report, {target, dryRun: true});
  assert.match(text, /Over the goal-key budget \(1\)/);
  assert.match(text, /just_climb__global \/ ajNZvPcA \(1 attempt\(s\)\): 6000 goal keys in one commit/);
  assert.doesNotMatch(text, /no climber skipped/);
  assert.match(text, /largest 6000 goal keys \(budget 5000\)/);
});

// ---------------------------------------------------------------------------
// Commit sizing. Firestore refuses a commit of 360 rows x 65 goal keys as
// `Transaction too big`, and one production climber's only Just Climb is 360
// rows x 117 keys: a linear 8,100-step hour wins exactly that many goals.

const PRODUCTION_SHAPE = {
  userId: "ajNZvPcA",
  workoutId: "one-hour-8100",
  finalSteps: 8_100,
  completionDurationSeconds: 3_600,
  splitIntervalSeconds: 10,
  splitBucketCount: 360,
};

function productionShapeSplitSteps() {
  return Array.from(
    {length: PRODUCTION_SHAPE.splitBucketCount},
    (_unused, index) => Math.round(((index + 1) * PRODUCTION_SHAPE.finalSteps) / PRODUCTION_SHAPE.splitBucketCount)
  );
}

function productionShapeGoalKeys() {
  return raceGoalKeysByWorkoutId([{
    workoutId: PRODUCTION_SHAPE.workoutId,
    finalSteps: PRODUCTION_SHAPE.finalSteps,
    finalDurationSeconds: PRODUCTION_SHAPE.completionDurationSeconds,
    splitIntervalSeconds: PRODUCTION_SHAPE.splitIntervalSeconds,
    splitSteps: productionShapeSplitSteps(),
  }]).get(PRODUCTION_SHAPE.workoutId);
}

/**
 * An in-memory Firestore with just the surface the backfill touches, storing
 * documents by path and recording every commit it accepts.
 * @param {Record<string, object>} documents Initial documents by path.
 * @param {object} [behavior] Commit behavior.
 * @param {(operations: object[]) => boolean} [behavior.refuse] Refuses a
 *   commit the way Firestore refuses one that is too big.
 * @return {object} Fake db, its store, and its accepted commits.
 */
function memoryFirestore(documents, {refuse = () => false} = {}) {
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
  const collectionRef = (path) => ({
    path,
    id: path.split("/").at(-1),
    get parent() {
      return docRef(path.split("/").slice(0, -1).join("/"));
    },
    doc: (id) => docRef(`${path}/${id}`),
    get: async () => ({docs: children(path).map(snapshot)}),
    listDocuments: async () => children(path).map(docRef),
  });

  return {
    store,
    commits,
    collection: collectionRef,
    getAll: async (...refs) => refs.map((ref) => snapshot(ref.path)),
    batch() {
      const operations = [];
      return {
        update: (ref, data) => operations.push({path: ref.path, data}),
        commit: async () => {
          if (refuse(operations)) {
            throw Object.assign(
              new Error("3 INVALID_ARGUMENT: Transaction too big. Decrease transaction size."),
              {code: 3}
            );
          }
          for (const {path, data} of operations) {
            store.set(path, {...store.get(path), ...data});
          }
          commits.push(operations);
        },
      };
    },
  };
}

const BOARD_PATH = "live_replay_leaderboards/just_climb__global";
const entryPath = (bucketIndex) =>
  `${BOARD_PATH}/splitBuckets/${bucketIndex}/entries/${PRODUCTION_SHAPE.workoutId}`;

function productionShapeBoard() {
  const documents = {[BOARD_PATH]: {contextType: "just_climb"}};
  for (const [bucketIndex, stepsAtBucket] of productionShapeSplitSteps().entries()) {
    documents[entryPath(bucketIndex)] = {...PRODUCTION_SHAPE, stepsAtBucket};
  }
  return documents;
}

const goalKeysIn = (operations) =>
  operations.reduce((sum, operation) => sum + (operation.data.bestForGoals?.length ?? 0), 0);

test("a 360-bucket, 117-key attempt plans every commit under the budget and every row written", () => {
  const goalKeys = productionShapeGoalKeys();
  assert.equal(goalKeys.length, 117);
  const db = memoryFirestore({});
  const {writes} = entryWritePlan(
    [{workoutId: PRODUCTION_SHAPE.workoutId, splitBucketCount: 360, isBestForUser: true, bestForGoals: goalKeys}],
    new Map(Array.from({length: 360}, (_unused, index) => [index, new Set([PRODUCTION_SHAPE.workoutId])]))
  );
  assert.equal(writes.length * goalKeys.length, 42_120, "the commit production would have sent as one");

  const commits = plannedEntryCommits(entryUpdatePhases(db.collection(BOARD_PATH.split("/")[0]).doc("just_climb__global"), writes));

  for (const commit of commits) {
    assert.ok(commit.weight <= MAX_GOAL_KEYS_PER_COMMIT, `a commit carries ${commit.weight} goal keys`);
    assert.ok(commit.operations.length <= MAX_BATCH_WRITES);
    assert.equal(commit.weight, goalKeysIn(commit.operations));
  }
  const planned = commits.flatMap((commit) => commit.operations.map((operation) => operation.ref.path));
  assert.equal(planned.length, 360);
  assert.equal(new Set(planned).size, 360, "every bucket's row is planned exactly once");
  assert.deepEqual(commits.at(-1).operations.map((operation) => operation.ref.path), [entryPath(0)],
    "bucket zero commits on its own, after every other bucket");
});

test("the write run commits exactly the planned commits and lands every row", async () => {
  const goalKeys = productionShapeGoalKeys();
  const db = memoryFirestore({});
  const writes = Array.from({length: 360}, (_unused, bucketIndex) => ({
    bucketIndex,
    workoutId: PRODUCTION_SHAPE.workoutId,
    fields: {isBestForUser: true, bestForGoals: goalKeys},
  }));
  const phases = entryUpdatePhases(db.collection("live_replay_leaderboards").doc("just_climb__global"), writes);
  let committed = 0;

  await applyEntryWrites(db, phases, {onCommitted: (count) => {
    committed += count;
  }});

  assert.equal(committed, 360);
  assert.deepEqual(
    db.commits.map((commit) => commit.length),
    plannedEntryCommits(phases).map((commit) => commit.operations.length)
  );
  for (const commit of db.commits) {
    assert.ok(goalKeysIn(commit) <= MAX_GOAL_KEYS_PER_COMMIT);
  }
  assert.deepEqual(db.commits.at(-1).map((operation) => operation.path), [entryPath(0)]);
  assert.equal(db.commits.slice(0, -1).flat().some((operation) => operation.path === entryPath(0)), false);
});

test("the production-shaped climber migrates in a write run, and the next dry run plans nothing", async () => {
  const db = memoryFirestore(productionShapeBoard());

  const dry = await backfillRaceBests(db, {dryRun: true, contextKey: "just_climb__global"});
  assert.equal(dry.boards[0].entryWritesPlanned, 360);
  assert.ok(dry.boards[0].largestCommitGoalKeys <= MAX_GOAL_KEYS_PER_COMMIT);
  // 42 rows of 117 keys fit the budget: 359 later buckets in 9 commits, then
  // bucket zero alone.
  assert.equal(dry.boards[0].commitsPlanned, 10);
  assert.deepEqual(dry.oversizedClimbers, []);
  assert.equal(db.commits.length, 0, "a dry run commits nothing");

  const run = await backfillRaceBests(db, {dryRun: false, contextKey: "just_climb__global"});
  assert.deepEqual(run.skippedClimbers, []);
  assert.equal(run.boards[0].entryWritesApplied, 360);
  assert.equal(db.commits.length, dry.boards[0].commitsPlanned);
  for (let bucketIndex = 0; bucketIndex < 360; bucketIndex += 1) {
    const entry = db.store.get(entryPath(bucketIndex));
    assert.equal(entry.isBestForUser, true);
    assert.equal(entry.bestForGoals.length, 117);
  }
  assert.ok(db.store.has(`${BOARD_PATH}/attemptCurves/${PRODUCTION_SHAPE.workoutId}`), "the rebuilt curve is stored");

  const again = await backfillRaceBests(db, {dryRun: true, contextKey: "just_climb__global"});
  assert.equal(again.boards[0].entryWritesPlanned, 0);
  assert.deepEqual(again.skippedClimbers, []);
});

test("a climber whose later commit is refused keeps bucket zero untouched, so the next run replans them in full", async () => {
  const refusedBucket = `${BOARD_PATH}/splitBuckets/200/`;
  const db = memoryFirestore(productionShapeBoard(), {
    refuse: (operations) => operations.some((operation) => operation.path.startsWith(refusedBucket)),
  });

  const run = await backfillRaceBests(db, {dryRun: false, contextKey: "just_climb__global"});

  assert.equal(run.skippedClimbers.length, 1);
  assert.match(run.skippedClimbers[0].reason, /Transaction too big/);
  assert.equal(db.store.get(entryPath(0)).bestForGoals, undefined, "bucket zero was never written");
  assert.ok(run.boards[0].entryWritesApplied < 360);

  const healed = memoryFirestore(Object.fromEntries(db.store));
  const again = await backfillRaceBests(healed, {dryRun: false, contextKey: "just_climb__global"});
  assert.deepEqual(again.skippedClimbers, []);
  assert.equal(again.boards[0].entryWritesApplied, 360, "the whole climber is rewritten, not just bucket zero");
});
