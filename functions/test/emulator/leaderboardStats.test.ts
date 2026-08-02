/**
 * The Admin adapter, against a real Firestore.
 *
 * The unit suite injects a store, so it proves the arithmetic but never the
 * glue: the projection queries, the `isSynthetic` read, the merge that has to
 * overwrite a client-authored row rather than sit beside it. This suite runs
 * the production adapter against the Firestore emulator, which is where issue
 * #307's scenario actually plays out.
 *
 * Lives under test/emulator/ so `npm test` (glob: lib/test/*.test.js) does not
 * pick it up without a Firestore behind it. `npm run test:emulator` runs it.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  makeAdminLeaderboardStatsStore,
  reconcileLeaderboardStats,
} from "../../src/leaderboardStats.js";
import {leaderboardDocumentId} from "../../src/leaderboardPeriod.js";

const LEADERBOARD_STATS = "leaderboard_stats";
const userId = "climber-1";
const workoutId = "AAAAAAAA-1111-2222-3333-444444444444";
// A Saturday, five days into its week and one day into its month.
const NOW = new Date("2026-08-01T12:00:00.000Z");
const IDENTITY_CHANGED_AT = new Date("2026-04-09T12:00:00.000Z");
// The audit's number: what a signed-in climber could publish with one request.
const FORGED_TOTAL_STEPS = 2_000_000_000;

const weeklyDocumentId = leaderboardDocumentId(userId, "weekly", "2026-W31");

let db: admin.firestore.Firestore;

before(() => {
  // Never let this suite pass by quietly doing nothing. Without an emulator the
  // Admin SDK would reach for real credentials, and a skip here would read as a
  // green trust-boundary gate that never ran.
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );
  admin.initializeApp({projectId: "demo-ascend-leaderboard-derivation"});
  db = admin.firestore();
});

beforeEach(async () => {
  await clearFirestore();
});

test("a forged standing is replaced by what the climber actually climbed",
  async () => {
    await seedForgedStanding();
    await seedProfile();
    await seedWorkout();

    const outcome = await reconcileLeaderboardStats(
      makeAdminLeaderboardStatsStore(),
      userId,
      NOW
    );

    assert.equal(outcome.written.length, 5, "one row per board window");
    const stored = await readStanding(weeklyDocumentId);
    assert.equal(stored?.totalSteps, 3000);
    assert.equal(stored?.totalFloors, 150);
    assert.equal(stored?.totalWorkouts, 1);
    assert.equal(stored?.stepsPerMinute, 100);
  });

test("the identity on the row comes from the validated mirror, not the row",
  async () => {
    await seedForgedStanding({displayName: "Spoofed Name"});
    await seedProfile();
    await seedWorkout();

    await reconcileLeaderboardStats(
      makeAdminLeaderboardStatsStore(),
      userId,
      NOW
    );

    const stored = await readStanding(weeklyDocumentId);
    assert.equal(stored?.displayName, "Rockstep");
    assert.equal(stored?.identityState, "published");
    assert.equal(stored?.isSynthetic, false);
  });

test("filter demographics are copied off the private user document",
  async () => {
    await seedProfile();
    await seedWorkout();

    await reconcileLeaderboardStats(
      makeAdminLeaderboardStatsStore(),
      userId,
      NOW
    );

    const stored = await readStanding(weeklyDocumentId);
    assert.equal(stored?.age, 34);
    assert.equal(stored?.weight_kg, 78.5);
    assert.equal(stored?.location_country, "US");
  });

// A workout carries its heart-rate series inline. Reading whole documents to
// add five integers would move megabytes on every save.
test("the workout read projects away the heart-rate series", async () => {
  await seedProfile();
  await seedWorkout({
    heartRateSeries: {
      samples: Array.from({length: 500}, (unused, index) => ({
        t: index,
        bpm: 140,
      })),
    },
  });

  const snapshot = await makeAdminLeaderboardStatsStore().runTransaction(
    (transaction) => transaction.read(userId)
  );

  assert.equal(snapshot.workouts.length, 1);
  assert.equal(snapshot.workouts[0].data.heartRateSeries, undefined);
});

test("a standing does not outlive the workouts behind it", async () => {
  await seedProfile();
  await seedWorkout();
  await reconcileLeaderboardStats(
    makeAdminLeaderboardStatsStore(),
    userId,
    NOW
  );

  await db.doc(`users/${userId}/workouts/${workoutId}`).delete();
  const outcome = await reconcileLeaderboardStats(
    makeAdminLeaderboardStatsStore(),
    userId,
    NOW
  );

  assert.deepEqual(outcome.written, []);
  assert.equal(outcome.deleted.length, 5);
  const remaining = await db
    .collection(LEADERBOARD_STATS)
    .where("userId", "==", userId)
    .get();
  assert.equal(remaining.size, 0);
});

// Seeded competitors have a standing with no canonical workouts by design.
test("a seeded competitor's standing survives a reconciliation", async () => {
  const seededId = leaderboardDocumentId("persona-1", "weekly", "2026-W31");
  await db.collection(LEADERBOARD_STATS).doc(seededId).set({
    userId: "persona-1",
    totalSteps: 42_000,
    isSynthetic: true,
  });

  const outcome = await reconcileLeaderboardStats(
    makeAdminLeaderboardStatsStore(),
    "persona-1",
    NOW
  );

  assert.deepEqual(outcome.deleted, []);
  assert.deepEqual(outcome.skippedSynthetic, [seededId]);
  const stored = await readStanding(seededId);
  assert.equal(stored?.totalSteps, 42_000);
});

// A workout no human could have produced contributes nothing, so a forger who
// writes evidence instead of a total still cannot buy a standing.
test("an implausible workout buys no standing at all", async () => {
  await seedProfile();
  await seedWorkout({steps: FORGED_TOTAL_STEPS, durationSeconds: 1800});

  const outcome = await reconcileLeaderboardStats(
    makeAdminLeaderboardStatsStore(),
    userId,
    NOW
  );

  assert.deepEqual(outcome.written, []);
});

async function seedForgedStanding(
  overrides: Record<string, unknown> = {}
): Promise<void> {
  await db.collection(LEADERBOARD_STATS).doc(weeklyDocumentId).set({
    userId,
    displayName: "Cheater",
    photoURL: "",
    identityPolicyVersion: 1,
    identityChangedAt: admin.firestore.Timestamp.fromDate(IDENTITY_CHANGED_AT),
    identityState: "published",
    timeFrame: "weekly",
    schemaVersion: 2,
    periodKey: "2026-W31",
    periodStartAt: admin.firestore.Timestamp.fromDate(
      new Date("2026-07-27T00:00:00.000Z")
    ),
    totalSteps: FORGED_TOTAL_STEPS,
    totalFloors: FORGED_TOTAL_STEPS,
    totalWorkouts: 1,
    totalDuration: 1800,
    stepsPerMinute: 99_999,
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    ...overrides,
  });
}

async function seedProfile(): Promise<void> {
  await db.doc(`users/${userId}`).set({
    age: 34,
    weight_kg: 78.5,
    location_country: "US",
    location_region: "Oregon",
  });
  await db.doc(`users/${userId}/public_profile/current`).set({
    userId,
    displayName: "Rockstep",
    photoURL: "",
    identityPolicyVersion: 1,
    identityChangedAt: admin.firestore.Timestamp.fromDate(IDENTITY_CHANGED_AT),
  });
}

async function seedWorkout(
  overrides: Record<string, unknown> = {}
): Promise<void> {
  await db.doc(`users/${userId}/workouts/${workoutId}`).set({
    userId,
    source: "headphone_motion",
    integrityLevel: "verified",
    startedAt: admin.firestore.Timestamp.fromDate(
      new Date("2026-08-01T06:00:00.000Z")
    ),
    durationSeconds: 1800,
    steps: 3000,
    floors: 150,
    ...overrides,
  });
}

async function readStanding(
  documentId: string
): Promise<Record<string, unknown> | undefined> {
  const snapshot = await db.collection(LEADERBOARD_STATS).doc(documentId).get();
  return snapshot.data();
}

async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/emulator/v1/projects/` +
      "demo-ascend-leaderboard-derivation/databases/(default)/documents",
    {method: "DELETE"}
  );
  assert.ok(response.ok, `emulator reset failed: ${response.status}`);
}
