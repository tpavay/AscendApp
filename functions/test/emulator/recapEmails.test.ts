/**
 * Weekly recap composition against a real Firestore.
 *
 * The unit suite (test/recapEmails.test.ts) proves the pure math - dedupe
 * keys, tier labels, streak walk, ranking, percentile bands, delta chips,
 * the calendar grid - in isolation. This suite proves the things that only
 * exist once real documents are involved: that the active/zero-activity
 * cohort split reads correctly off `leaderboard_stats`, that rank and
 * percentile come out right for a real multi-climber field, that an
 * abandoned Live Climb attempt is never reported as a finished landmark,
 * that a suppressed climber gets no job at all, and that a climber who has
 * never completed a climb gets neither recap variant.
 *
 * Lives under test/emulator/ - see emailQueue.test.ts for why, and for the
 * shared-database-between-tests caveat this suite follows the same way.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  buildRecapDedupeKey,
  runRecapSweep,
} from "../../src/recapEmails.js";
import {buildEmailJobId} from "../../src/email/queue.js";
import {
  leaderboardDocumentId,
  previousPeriod,
} from "../../src/leaderboardPeriod.js";
import type {
  EmailJobDocument,
  RecapActivePayload,
  RecapInactivePayload,
} from "../../src/email/types.js";

const EMAIL_JOBS = "email_jobs";
const LEADERBOARD_STATS = "leaderboard_stats";
const APP_STORE_URL = "https://apps.apple.com/app/id6757202987";

// A fixed instant so every test seeds and asserts against the same closed
// week, regardless of when the suite runs.
const now = new Date("2026-09-28T13:00:00Z");
const closedWeek = previousPeriod("weekly", now);
const previousWeek = previousPeriod("weekly", closedWeek.startAt);

let db: admin.firestore.Firestore;

before(() => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );

  process.env.TRANSACTIONAL_EMAIL_CONFIG = JSON.stringify({
    provider: "resend",
    apiKey: "re_emulator_only",
    fromEmail: "hello@updates.ascendstepper.com",
    fromName: "Ascend",
    replyTo: "support@ascendstepper.com",
    unsubscribeSigningKey: "emulator-unsubscribe-signing-key-0123456789",
    websiteUrl: "https://ascendstepper.com",
  });

  // The only stubbed edge: the hosted climb catalogue this sweep reads to
  // resolve landmark names and pick a comeback climb. Nothing about the
  // recap composition or the queue write is stubbed.
  globalThis.fetch = (async (url: string) => {
    if (url.includes("/climbs/manifest.json")) {
      return new Response(
        JSON.stringify({catalogPath: "/climbs/catalog.json", catalogVersion: 1}),
        {headers: {"Content-Type": "application/json"}, status: 200}
      );
    }
    if (url.includes("/climbs/catalog.json")) {
      return new Response(
        JSON.stringify([
          {
            city: "Paris",
            id: "eiffel",
            name: "Eiffel Tower",
            realStairCount: 1710,
            releaseState: "available",
          },
          {
            city: "Nowhere",
            id: "short-climb",
            name: "Short Climb",
            realStairCount: 200,
            releaseState: "available",
          },
        ]),
        {headers: {"Content-Type": "application/json"}, status: 200}
      );
    }
    throw new Error(`recapEmails.test unexpected fetch: ${url}`);
  }) as unknown as typeof fetch;

  admin.initializeApp({projectId: "demo-ascend-leaderboard-derivation"});
  db = admin.firestore();
});

beforeEach(async () => {
  await clearCollection(EMAIL_JOBS);
  await clearCollection(LEADERBOARD_STATS);
  await clearCollection("users");
});

test(
  "an active climber's recap carries stats, landmarks, deltas, rank, and a calendar",
  async () => {
    await seedUser("active-1", "active@example.com");
    await seedUser("active-2", "active2@example.com");
    await seedUser("active-3", "active3@example.com");
    await seedWeeklyStats("active-1", closedWeek, {
      totalFloors: 200,
      totalSteps: 8000,
      totalWorkouts: 2,
    });
    await seedWeeklyStats("active-2", closedWeek, {
      totalFloors: 50,
      totalSteps: 3000,
      totalWorkouts: 1,
    });
    await seedWeeklyStats("active-3", closedWeek, {
      totalFloors: 10,
      totalSteps: 500,
      totalWorkouts: 1,
    });
    // The prior week, for active-1's delta chips.
    await seedWeeklyStats("active-1", previousWeek, {
      totalFloors: 150,
      totalSteps: 6000,
      totalWorkouts: 1,
    });
    await seedCompletedLandmarkWorkout(
      "active-1",
      "eiffel",
      addDays(closedWeek.startAt, 1)
    );
    await seedCompletedLandmarkWorkout(
      "active-1",
      "short-climb",
      addDays(closedWeek.startAt, 2)
    );

    const summary = await runRecapSweep("weekly", now);

    const job = await readJob(
      buildRecapDedupeKey("weekly", "active", closedWeek.key, "active-1")
    );
    assert.equal(job.type, "weekly_recap_active");
    assert.equal(job.status, "queued");
    assert.equal(job.recipientEmail, "active@example.com");

    const payload = job.payload as RecapActivePayload;
    assert.equal(payload.climbsCompleted, 2);
    assert.equal(payload.totalSteps, 8000);
    assert.equal(payload.totalFloors, 200);
    assert.equal(payload.ctaUrl, APP_STORE_URL);
    assert.deepEqual(
      [...payload.landmarksFinished].sort(),
      ["Eiffel Tower", "Short Climb"]
    );
    // Two landmarks finished outrank the rank-based milestone in priority.
    assert.equal(
      payload.milestoneText,
      "You finished Eiffel Tower and 1 more landmark."
    );
    assert.equal(payload.currentStreakWeeks, 2);

    // Ranked first of three active climbers this week.
    assert.equal(payload.rank, 1);
    assert.equal(payload.fieldSize, 3);
    // A top-3 finish states the exact position, not a coarse percentile band.
    assert.equal(payload.percentileLabel, "#1 of 3 climbers");

    // 8000 > 6000 the prior week - a genuine improvement.
    assert.deepEqual(payload.stepsDelta, {
      direction: "up",
      label: "vs last week",
      value: "2,000",
    });
    assert.deepEqual(payload.floorsDelta, {
      direction: "up",
      label: "vs last week",
      value: "50",
    });
    assert.deepEqual(payload.climbsDelta, {
      direction: "up",
      label: "vs last week",
      value: "1",
    });

    // A weekly calendar is always exactly 7 Monday-aligned cells.
    assert.equal(payload.calendar.length, 7);
    assert.ok(payload.calendar.some((cell) => cell.level === "peak"));

    assert.equal(summary.queued >= 1, true);
    assert.equal(summary.errors, 0);
  }
);

test(
  "an abandoned Live Climb attempt is never reported as a finished landmark",
  async () => {
    await seedUser("attempter-1", "attempter@example.com");
    await seedWeeklyStats("attempter-1", closedWeek, {
      totalFloors: 20,
      totalSteps: 1000,
      totalWorkouts: 2,
    });
    await seedCompletedLandmarkWorkout(
      "attempter-1",
      "eiffel",
      addDays(closedWeek.startAt, 1)
    );
    await seedAbandonedLandmarkAttempt(
      "attempter-1",
      "short-climb",
      addDays(closedWeek.startAt, 2)
    );

    await runRecapSweep("weekly", now);

    const job = await readJob(
      buildRecapDedupeKey("weekly", "active", closedWeek.key, "attempter-1")
    );
    const payload = job.payload as RecapActivePayload;
    assert.deepEqual(payload.landmarksFinished, ["Eiffel Tower"]);
  }
);

test(
  "a climber with history but nothing this week gets a gentle nudge to the App Store",
  async () => {
    await seedUser("dormant-1", "dormant@example.com");
    await seedAllTimeStats("dormant-1");

    await runRecapSweep("weekly", now);

    const job = await readJob(
      buildRecapDedupeKey("weekly", "inactive", closedWeek.key, "dormant-1")
    );
    assert.equal(job.type, "weekly_recap_inactive");

    const payload = job.payload as RecapInactivePayload;
    // The shortest available climb - the most approachable comeback pick.
    assert.equal(payload.suggestedClimbName, "Short Climb");
    assert.equal(payload.ctaUrl, APP_STORE_URL);
  }
);

test("a field of one active climber gets no percentile callout", async () => {
  await seedUser("solo-1", "solo@example.com");
  await seedWeeklyStats("solo-1", closedWeek, {
    totalFloors: 5,
    totalSteps: 100,
    totalWorkouts: 1,
  });

  await runRecapSweep("weekly", now);

  const job = await readJob(
    buildRecapDedupeKey("weekly", "active", closedWeek.key, "solo-1")
  );
  const payload = job.payload as RecapActivePayload;
  assert.equal(payload.rank, 1);
  assert.equal(payload.fieldSize, 1);
  assert.equal(payload.percentileLabel, undefined);
});

test("unsubscribe suppresses a recap even for an active climber", async () => {
  await seedUser("unsub-1", "unsub@example.com", {lifecycleEmailsEnabled: false});
  await seedWeeklyStats("unsub-1", closedWeek, {
    totalFloors: 50,
    totalSteps: 2000,
    totalWorkouts: 1,
  });

  const summary = await runRecapSweep("weekly", now);

  const jobId = buildEmailJobId(
    buildRecapDedupeKey("weekly", "active", closedWeek.key, "unsub-1")
  );
  const snapshot = await db.collection(EMAIL_JOBS).doc(jobId).get();
  assert.equal(snapshot.exists, false, "unsubscribed climber got no job at all");
  assert.ok(summary.suppressed >= 1);
});

test(
  "a climber who has never completed a climb gets neither recap variant",
  async () => {
    await seedUser("new-1", "new@example.com");
    // No leaderboard_stats rows at all - onboarding-abandonment emails own
    // this climber, not the recap.

    await runRecapSweep("weekly", now);

    const activeJobId = buildEmailJobId(
      buildRecapDedupeKey("weekly", "active", closedWeek.key, "new-1")
    );
    const inactiveJobId = buildEmailJobId(
      buildRecapDedupeKey("weekly", "inactive", closedWeek.key, "new-1")
    );
    const activeSnapshot = await db
      .collection(EMAIL_JOBS)
      .doc(activeJobId)
      .get();
    const inactiveSnapshot = await db
      .collection(EMAIL_JOBS)
      .doc(inactiveJobId)
      .get();
    assert.equal(activeSnapshot.exists, false);
    assert.equal(inactiveSnapshot.exists, false);
  }
);

test("re-running the same closed week does not double-queue", async () => {
  await seedUser("active-solo", "activesolo@example.com");
  await seedWeeklyStats("active-solo", closedWeek, {
    totalFloors: 10,
    totalSteps: 500,
    totalWorkouts: 1,
  });

  const first = await runRecapSweep("weekly", now);
  const second = await runRecapSweep("weekly", now);

  assert.ok(first.queued >= 1);
  assert.ok(second.alreadyQueued >= 1);

  const snapshot = await db.collection(EMAIL_JOBS).get();
  const matching = snapshot.docs.filter(
    (doc) => doc.data().recipientEmail === "activesolo@example.com"
  );
  assert.equal(matching.length, 1);
});

/**
 * Reads a queued recap job by its dedupe key.
 * @param {string} dedupeKey - Recap dedupe key
 * @return {Promise<EmailJobDocument>} Stored job document
 */
async function readJob(dedupeKey: string): Promise<EmailJobDocument> {
  const jobId = buildEmailJobId(dedupeKey);
  const snapshot = await db.collection(EMAIL_JOBS).doc(jobId).get();
  assert.ok(snapshot.exists, `expected email job for dedupe key ${dedupeKey}`);
  return snapshot.data() as EmailJobDocument;
}

/**
 * Seeds a climber's user document and consent.
 * @param {string} uid - Firebase Auth user ID
 * @param {string} email - Registered email
 * @param {{lifecycleEmailsEnabled?: boolean}} options - Consent override
 * @return {Promise<void>}
 */
async function seedUser(
  uid: string,
  email: string,
  options: {lifecycleEmailsEnabled?: boolean} = {}
): Promise<void> {
  const nowTimestamp = admin.firestore.Timestamp.now();
  await db.collection("users").doc(uid).set({email});
  await db
    .collection("users")
    .doc(uid)
    .collection("communication_preferences")
    .doc("current")
    .set({
      createdAt: nowTimestamp,
      lifecycleEmailsDecidedAt: nowTimestamp,
      lifecycleEmailsEnabled: options.lifecycleEmailsEnabled ?? true,
      lifecycleEmailsSource: "settings",
      schemaVersion: 1,
      updatedAt: nowTimestamp,
    });
}

/**
 * Seeds a closed-period `leaderboard_stats` row, the same shape
 * leaderboardStats.ts derives from real workouts.
 * @param {string} uid - Firebase Auth user ID
 * @param {ReturnType<typeof previousPeriod>} period - Closed weekly period
 * @param {{totalFloors: number, totalSteps: number, totalWorkouts: number}}
 *   totals - Period aggregate
 * @return {Promise<void>}
 */
async function seedWeeklyStats(
  uid: string,
  period: ReturnType<typeof previousPeriod>,
  totals: {totalFloors: number; totalSteps: number; totalWorkouts: number}
): Promise<void> {
  const docId = leaderboardDocumentId(uid, "weekly", period.key);
  await db.collection(LEADERBOARD_STATS).doc(docId).set({
    isSynthetic: false,
    periodKey: period.key,
    periodStartAt: admin.firestore.Timestamp.fromDate(period.startAt),
    schemaVersion: 2,
    stepsPerMinute: 0,
    timeFrame: "weekly",
    totalDuration: 0,
    ...totals,
    userId: uid,
  });
}

/**
 * Seeds the never-closing all-time `leaderboard_stats` row, the signal this
 * sweep uses for "has ever completed a climb".
 * @param {string} uid - Firebase Auth user ID
 * @return {Promise<void>}
 */
async function seedAllTimeStats(uid: string): Promise<void> {
  const docId = leaderboardDocumentId(uid, "all_time", "all");
  await db.collection(LEADERBOARD_STATS).doc(docId).set({
    isSynthetic: false,
    periodKey: "all",
    periodStartAt: admin.firestore.Timestamp.fromDate(new Date(0)),
    schemaVersion: 2,
    stepsPerMinute: 0,
    timeFrame: "all_time",
    totalDuration: 100,
    totalFloors: 10,
    totalSteps: 100,
    totalWorkouts: 1,
    userId: uid,
  });
}

/**
 * Seeds a workout that `parseCompletedLandmarkWorkout`
 * (climbCompletions.ts) recognizes as a genuine landmark finish: a
 * headphone-motion capture whose legacy `stopReason` is `target_reached`.
 * @param {string} uid - Firebase Auth user ID
 * @param {string} climbId - Landmark climb ID
 * @param {Date} startedAt - Workout start time
 * @return {Promise<void>}
 */
async function seedCompletedLandmarkWorkout(
  uid: string,
  climbId: string,
  startedAt: Date
): Promise<void> {
  await db.collection("users").doc(uid).collection("workouts").add({
    durationSeconds: 600,
    source: "headphone_motion",
    sourceMetadata: JSON.stringify({climbId, stopReason: "target_reached"}),
    startedAt: admin.firestore.Timestamp.fromDate(startedAt),
    steps: 1200,
  });
}

/**
 * Seeds a workout that looks like a Live Climb attempt on a landmark but
 * never finished it - the exact shape the pre-fix bug misreported as a
 * completed landmark.
 * @param {string} uid - Firebase Auth user ID
 * @param {string} climbId - Landmark climb ID
 * @param {Date} startedAt - Workout start time
 * @return {Promise<void>}
 */
async function seedAbandonedLandmarkAttempt(
  uid: string,
  climbId: string,
  startedAt: Date
): Promise<void> {
  await db.collection("users").doc(uid).collection("workouts").add({
    durationSeconds: 120,
    source: "headphone_motion",
    sourceMetadata: JSON.stringify({
      climbId,
      climbTargetStepCount: 5000,
      stopReason: "manual_stop",
    }),
    startedAt: admin.firestore.Timestamp.fromDate(startedAt),
    steps: 900,
  });
}

/**
 * Shifts a date by whole days.
 * @param {Date} date - Starting instant
 * @param {number} days - Days to add
 * @return {Date} Shifted instant
 */
function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

/**
 * Clears every document in a top-level collection between tests.
 * @param {string} name - Collection name
 * @return {Promise<void>}
 */
async function clearCollection(name: string): Promise<void> {
  const snapshot = await db.collection(name).get();
  await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
}
