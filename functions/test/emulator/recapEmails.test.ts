/**
 * Weekly and monthly recap compose and send against a real Firestore.
 *
 * The unit suite (test/recapEmails.test.ts) proves the pure math - dedupe
 * keys, tier labels, streak walk, ranking, percentile bands, delta chips,
 * the calendar grid, the cohort plan, and the stored-recap to email mapping
 * - in isolation. This suite proves the things that only exist once real
 * documents are involved: that compose stores one recap per climber with
 * the raw values the app renders (for climbers with no email address too),
 * that the active/zero-activity/never-climbed split reads correctly off
 * `leaderboard_stats` and the `app_access` grants, that rank and percentile
 * come out right for a real multi-climber field, that an abandoned Live
 * Climb attempt is never reported as a finished landmark, that compose never
 * overwrites a stored recap, that send builds each email from the stored
 * recap alone, and that a suppressed climber gets no job at all.
 *
 * Lives under test/emulator/ - see emailQueue.test.ts for why, and for the
 * shared-database-between-tests caveat this suite follows the same way.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  buildRecapDedupeKey,
  buildRecapDocumentId,
  runRecapCompose,
  runRecapSend,
  type CohortScanBound,
  type RecapCadence,
  type RecapComposeSummary,
  type RecapSendSummary,
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

const PROJECT_ID = "demo-ascend-leaderboard-derivation";
const EMAIL_JOBS = "email_jobs";
const LEADERBOARD_STATS = "leaderboard_stats";
const LIVE_REPLAY_LEADERBOARDS = "live_replay_leaderboards";
const APP_STORE_URL = "https://apps.apple.com/app/id6757202987";

// Fixed instants so every test seeds and asserts against the same closed
// week, regardless of when the suite runs: compose at 00:30 UTC on the
// Monday the week closed, send at 13:00 UTC the same day.
const composeNow = new Date("2026-09-28T00:30:00Z");
const now = new Date("2026-09-28T13:00:00Z");
const closedWeek = previousPeriod("weekly", now);
const previousWeek = previousPeriod("weekly", closedWeek.startAt);

let db: admin.firestore.Firestore;
let emulatorFetch: typeof fetch;

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

  // The only stubbed edge: the hosted climb catalogue compose reads to
  // resolve landmark names and pick a comeback climb. Nothing about the
  // recap composition, its storage, or the queue write is stubbed. The real
  // fetch is kept for resetting the emulator between tests.
  emulatorFetch = globalThis.fetch;
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

  admin.initializeApp({projectId: PROJECT_ID});
  db = admin.firestore();
});

beforeEach(async () => {
  // A whole-database reset: recaps live in a subcollection under users, and
  // deleting a user document leaves its subcollections behind, where the
  // send step's collection-group read would find them in the next test.
  await clearFirestore();
  await seedFinalizedPeriod("weekly", closedWeek);
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

    const {send: summary} = await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "active-1")
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
    assert.equal(payload.currentStreakWeeks, 2);

    // Ranked first of three active climbers this week - the concrete rank
    // and its percentile band are both carried, shown together.
    assert.equal(payload.rank, 1);
    assert.equal(payload.fieldSize, 3);
    assert.equal(payload.percentileBand, "Top 50%");

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

    // The email came from the stored recap, which carries the raw values
    // the app renders rather than the email's chips.
    const recap = await readRecap("active-1");
    assert.equal(recap.schemaVersion, 1);
    assert.equal(recap.cadence, "weekly");
    assert.equal(recap.periodKey, closedWeek.key);
    assert.equal(
      (recap.periodStartAt as admin.firestore.Timestamp).toMillis(),
      closedWeek.startAt.getTime()
    );
    assert.equal(
      (recap.periodEndAt as admin.firestore.Timestamp).toMillis(),
      closedWeek.endAt.getTime()
    );
    assert.equal(recap.periodLabel, payload.periodLabel);
    assert.equal(recap.variant, "active");
    assert.equal(recap.inactive, null);
    assert.equal(recap.seenAt, null);
    assert.ok(recap.composedAt instanceof admin.firestore.Timestamp);
    const active = recap.active as Record<string, unknown>;
    assert.deepEqual(
      {...active, calendar: undefined, landmarksFinished: undefined},
      {
        awardRank: null,
        calendar: undefined,
        climberCount: 3,
        climbs: 2,
        currentStreakWeeks: 2,
        firstAscents: [],
        floors: 200,
        landmarksFinished: undefined,
        percentileBand: "Top 50%",
        previousClimbs: 1,
        previousFloors: 150,
        previousSteps: 6000,
        rank: 1,
        steps: 8000,
      }
    );
    assert.deepEqual(active.calendar, payload.calendar);
    assert.deepEqual(active.landmarksFinished, payload.landmarksFinished);

    // A climber with no prior-week row stores null, not zero, and the
    // email shows no chip for it.
    const second = await readRecap("active-2");
    const secondActive = second.active as Record<string, unknown>;
    assert.equal(secondActive.rank, 2);
    assert.equal(secondActive.previousSteps, null);
    assert.equal(secondActive.previousClimbs, null);
    assert.equal(secondActive.previousFloors, null);
  }
);

test(
  "the email built from a stored recap is exactly the email the recap describes",
  async () => {
    await seedUser("exact-1", "exact@example.com");
    await seedUser("exact-2", "exact2@example.com");
    await seedWeeklyStats("exact-1", closedWeek, {
      totalFloors: 40,
      totalSteps: 2400,
      totalWorkouts: 3,
    });
    await seedWeeklyStats("exact-2", closedWeek, {
      totalFloors: 90,
      totalSteps: 5000,
      totalWorkouts: 1,
    });
    await seedWeeklyStats("exact-1", previousWeek, {
      totalFloors: 60,
      totalSteps: 1000,
      totalWorkouts: 3,
    });
    await seedAchievement("exact-1", "weekly", closedWeek.key, 2);
    const workoutId = await seedCompletedLandmarkWorkout(
      "exact-1",
      "eiffel",
      addDays(closedWeek.startAt, 3)
    );
    await seedFirstAscent("exact-1", "eiffel", {
      claimedAt: addDays(closedWeek.startAt, 3),
      workoutId,
    });

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "exact-1")
    );
    const dayOfMonth = (offset: number): number =>
      addDays(closedWeek.startAt, offset).getUTCDate();
    assert.deepEqual(job.payload, {
      calendar: [0, 1, 2, 3, 4, 5, 6].map((offset) => ({
        dayOfMonth: dayOfMonth(offset),
        level: offset === 3 ? "peak" : "none",
      })),
      climbsCompleted: 3,
      ctaUrl: APP_STORE_URL,
      currentStreakWeeks: 2,
      earnedBadges: [
        {detail: "globally", id: "top10", label: "Top 10"},
        {detail: "Eiffel Tower", id: "first-ascent", label: "First Ascent"},
      ],
      // Second of two is the bottom half: the rank stands, with no band.
      fieldSize: 2,
      landmarksFinished: ["Eiffel Tower"],
      periodLabel: (await readRecap("exact-1")).periodLabel,
      rank: 2,
      stepsDelta: {direction: "up", label: "vs last week", value: "1,400"},
      totalFloors: 40,
      totalSteps: 2400,
    });

    const active = (await readRecap("exact-1")).active as
      Record<string, unknown>;
    assert.equal(active.awardRank, 2);
    assert.deepEqual(active.firstAscents, [
      {climbId: "eiffel", name: "Eiffel Tower"},
    ]);
  }
);

test(
  "a landmark the catalogue cannot name still counts as finished",
  async () => {
    await seedUser("unlisted-1", "unlisted@example.com");
    await seedWeeklyStats("unlisted-1", closedWeek, {
      totalFloors: 20,
      totalSteps: 1200,
      totalWorkouts: 1,
    });
    await seedCompletedLandmarkWorkout(
      "unlisted-1",
      "unlisted-climb",
      addDays(closedWeek.startAt, 1)
    );

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "unlisted-1")
    );
    const payload = job.payload as RecapActivePayload;
    assert.deepEqual(payload.landmarksFinished, ["unlisted-climb"]);
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

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "attempter-1")
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

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "dormant-1")
    );
    assert.equal(job.type, "weekly_recap_inactive");

    const payload = job.payload as RecapInactivePayload;
    // The shortest available climb - the most approachable comeback pick.
    assert.equal(payload.suggestedClimbName, "Short Climb");
    assert.equal(payload.ctaUrl, APP_STORE_URL);
    assert.deepEqual(payload.firstAscents, []);
    assert.ok(payload.gapCount >= 1);
  }
);

test(
  "a dormant climber's real gap comes from their latest workout, not lastUpdated",
  async () => {
    await seedUser("dormant-2", "dormant2@example.com");
    // A demographics edit restamped the all-time row yesterday, but the
    // last climb was 3 weeks before `now` (2026-09-28).
    await seedAllTimeStats("dormant-2", addDays(now, -1));
    await seedCompletedLandmarkWorkout("dormant-2", "eiffel", addDays(now, -21));

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "dormant-2")
    );
    const payload = job.payload as RecapInactivePayload;
    assert.equal(payload.gapCount, 3);

    const recap = await readRecap("dormant-2");
    assert.equal(recap.variant, "inactive");
    assert.equal(recap.active, null);
    const inactive = recap.inactive as Record<string, unknown>;
    assert.equal(inactive.gapCount, 3);
    assert.equal(
      (inactive.lastClimbAt as admin.firestore.Timestamp).toMillis(),
      addDays(now, -21).getTime()
    );
  }
);

test(
  "a climber who already came back after the closed week gets no we-missed-you email",
  async () => {
    await seedUser("returner-1", "returner@example.com");
    await seedAllTimeStats("returner-1");
    await seedCompletedLandmarkWorkout("returner-1", "eiffel", closedWeek.endAt);

    const {send: summary} = await composeAndSend();

    const jobId = buildEmailJobId(
      buildRecapDedupeKey("weekly", closedWeek.key, "returner-1")
    );
    const snapshot = await db.collection(EMAIL_JOBS).doc(jobId).get();
    assert.equal(snapshot.exists, false);
    assert.ok(summary.suppressed >= 1);
    assert.equal(summary.errors, 0);

    // The week itself still passed without a climb, so the app keeps its
    // recap; only the "we missed you" email is withheld.
    const recap = await readRecap("returner-1");
    assert.equal(recap.variant, "inactive");
    assert.equal(
      (recap.inactive as Record<string, unknown>).lastClimbAt,
      null
    );
  }
);

test(
  "a climber who came back before compose ran still gets the week's recap",
  async () => {
    await seedUser("early-returner-1", "early@example.com");
    await seedAllTimeStats("early-returner-1");
    await seedCompletedLandmarkWorkout(
      "early-returner-1",
      "eiffel",
      addDays(now, -28)
    );
    // Climbed ten minutes into the new week, before the 00:30 compose.
    await seedCompletedLandmarkWorkout(
      "early-returner-1",
      "short-climb",
      new Date(closedWeek.endAt.getTime() + 10 * 60 * 1000)
    );

    const {send: summary} = await composeAndSend();

    const inactive = (await readRecap("early-returner-1")).inactive as
      Record<string, unknown>;
    assert.equal(
      (inactive.lastClimbAt as admin.firestore.Timestamp).toMillis(),
      addDays(now, -28).getTime()
    );
    assert.equal(inactive.gapCount, 4);
    assert.ok(summary.suppressed >= 1);
  }
);

test(
  "a climber's First Ascents are named instead of the generic comeback nudge",
  async () => {
    await seedUser("first-ascender-1", "firstascender@example.com");
    await seedAllTimeStats("first-ascender-1");
    await seedFirstAscent("first-ascender-1", "eiffel");

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "first-ascender-1")
    );
    assert.deepEqual(job.payload, {
      ctaUrl: APP_STORE_URL,
      earnedBadges: [
        {detail: "Eiffel Tower", id: "first-ascent", label: "First Ascent"},
      ],
      firstAscents: ["Eiffel Tower"],
      gapCount: 1,
      periodLabel: (await readRecap("first-ascender-1")).periodLabel,
      suggestedClimbName: "Short Climb",
    });

    const recap = await readRecap("first-ascender-1");
    assert.deepEqual(recap.inactive, {
      firstAscentsHeld: ["Eiffel Tower"],
      gapCount: 1,
      lastClimbAt: null,
      suggestedClimbId: "short-climb",
      suggestedClimbName: "Short Climb",
    });
  }
);

test(
  "Just Climb's global board never reads as a landmark First Ascent",
  async () => {
    await seedUser("first-ascender-2", "firstascender2@example.com");
    await seedAllTimeStats("first-ascender-2");
    await seedFirstAscent("first-ascender-2", "eiffel");
    await db.collection(LIVE_REPLAY_LEADERBOARDS).doc("just_climb:global").set({
      contextId: "global",
      contextType: "just_climb",
      firstAscentUserId: "first-ascender-2",
    });

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "first-ascender-2")
    );
    const payload = job.payload as RecapInactivePayload;
    assert.deepEqual(payload.firstAscents, ["Eiffel Tower"]);
  }
);

test(
  "a zero-step climb this week is activity, never a we-missed-you email",
  async () => {
    await seedUser("zero-step-1", "zerostep@example.com");
    await seedAllTimeStats("zero-step-1");
    await seedWeeklyStats("zero-step-1", closedWeek, {
      totalFloors: 0,
      totalSteps: 0,
      totalWorkouts: 1,
    });

    await composeAndSend();

    const jobId = buildEmailJobId(
      buildRecapDedupeKey("weekly", closedWeek.key, "zero-step-1")
    );
    const snapshot = await db.collection(EMAIL_JOBS).doc(jobId).get();
    assert.equal(snapshot.exists, false);
    assert.equal(await recapExists("zero-step-1"), false);
  }
);

test(
  "an all-time row with zero steps is not a completed climb",
  async () => {
    await seedUser("zero-step-2", "zerostep2@example.com");
    await seedAllTimeStats("zero-step-2", undefined, 0);

    await composeAndSend();

    const jobId = buildEmailJobId(
      buildRecapDedupeKey("weekly", closedWeek.key, "zero-step-2")
    );
    const snapshot = await db.collection(EMAIL_JOBS).doc(jobId).get();
    assert.equal(snapshot.exists, false);
    assert.equal(await recapExists("zero-step-2"), false);
  }
);

test(
  "an achievement earned this period earns the real Top 10 badge, reused from the canonical record",
  async () => {
    await seedUser("achiever-1", "achiever@example.com");
    await seedWeeklyStats("achiever-1", closedWeek, {
      totalFloors: 5,
      totalSteps: 100,
      totalWorkouts: 1,
    });
    await seedAchievement("achiever-1", "weekly", closedWeek.key, 7);

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "achiever-1")
    );
    const payload = job.payload as RecapActivePayload;
    assert.deepEqual(payload.earnedBadges, [
      {detail: "globally", id: "top10", label: "Top 10"},
    ]);
  }
);

test(
  "an achievement rank outside the top 10 earns the Top 100 badge instead",
  async () => {
    await seedUser("achiever-2", "achiever2@example.com");
    await seedWeeklyStats("achiever-2", closedWeek, {
      totalFloors: 5,
      totalSteps: 100,
      totalWorkouts: 1,
    });
    await seedAchievement("achiever-2", "weekly", closedWeek.key, 42);

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "achiever-2")
    );
    const payload = job.payload as RecapActivePayload;
    assert.deepEqual(payload.earnedBadges, [
      {detail: "globally", id: "top100", label: "Top 100"},
    ]);
  }
);

test(
  "no achievement badge when the climber earned none this period",
  async () => {
    await seedUser("no-achiever-1", "noachiever@example.com");
    await seedWeeklyStats("no-achiever-1", closedWeek, {
      totalFloors: 5,
      totalSteps: 100,
      totalWorkouts: 1,
    });

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "no-achiever-1")
    );
    const payload = job.payload as RecapActivePayload;
    assert.deepEqual(payload.earnedBadges, []);
  }
);

test(
  "a First Ascent claimed this period earns a badge on the active recap",
  async () => {
    await seedUser("period-ascender-1", "periodascender@example.com");
    await seedWeeklyStats("period-ascender-1", closedWeek, {
      totalFloors: 5,
      totalSteps: 100,
      totalWorkouts: 1,
    });
    // Climbed late on the closed week's Sunday; the claim only processed
    // after the week closed, once the workout synced.
    const workoutId = await seedCompletedLandmarkWorkout(
      "period-ascender-1",
      "eiffel",
      new Date(closedWeek.endAt.getTime() - 20 * 60 * 1000)
    );
    await seedFirstAscent("period-ascender-1", "eiffel", {
      claimedAt: new Date(closedWeek.endAt.getTime() + 10 * 60 * 1000),
      workoutId,
    });

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "period-ascender-1")
    );
    const payload = job.payload as RecapActivePayload;
    assert.deepEqual(payload.earnedBadges, [
      {detail: "Eiffel Tower", id: "first-ascent", label: "First Ascent"},
    ]);
  }
);

test(
  "a First Ascent claimed in an earlier period is never re-badged as new",
  async () => {
    await seedUser("period-ascender-2", "periodascender2@example.com");
    await seedWeeklyStats("period-ascender-2", closedWeek, {
      totalFloors: 5,
      totalSteps: 100,
      totalWorkouts: 1,
    });
    // Re-climbed this period, but first-ascended it back in the previous one.
    await seedCompletedLandmarkWorkout(
      "period-ascender-2",
      "eiffel",
      closedWeek.startAt
    );
    const claimingWorkoutId = await seedCompletedLandmarkWorkout(
      "period-ascender-2",
      "eiffel",
      previousWeek.startAt
    );
    await seedFirstAscent("period-ascender-2", "eiffel", {
      claimedAt: previousWeek.startAt,
      workoutId: claimingWorkoutId,
    });

    await composeAndSend();

    const job = await readJob(
      buildRecapDedupeKey("weekly", closedWeek.key, "period-ascender-2")
    );
    const payload = job.payload as RecapActivePayload;
    assert.deepEqual(payload.earnedBadges, []);
    // The re-climb still counts toward landmarks finished - only the badge
    // is period-scoped.
    assert.deepEqual(payload.landmarksFinished, ["Eiffel Tower"]);
  }
);

test("a field of one active climber gets no percentile callout", async () => {
  await seedUser("solo-1", "solo@example.com");
  await seedWeeklyStats("solo-1", closedWeek, {
    totalFloors: 5,
    totalSteps: 100,
    totalWorkouts: 1,
  });

  await composeAndSend();

  const job = await readJob(
    buildRecapDedupeKey("weekly", closedWeek.key, "solo-1")
  );
  const payload = job.payload as RecapActivePayload;
  assert.equal(payload.rank, 1);
  assert.equal(payload.fieldSize, 1);
  assert.equal(payload.percentileBand, undefined);

  // The app never shows "1st of 1": the field is stored only above one.
  const active = (await readRecap("solo-1")).active as Record<string, unknown>;
  assert.equal(active.rank, 1);
  assert.equal(active.climberCount, null);
  assert.equal(active.percentileBand, null);
});

test("unsubscribe suppresses a recap even for an active climber", async () => {
  await seedUser("unsub-1", "unsub@example.com", {lifecycleEmailsEnabled: false});
  await seedWeeklyStats("unsub-1", closedWeek, {
    totalFloors: 50,
    totalSteps: 2000,
    totalWorkouts: 1,
  });

  const {send: summary} = await composeAndSend();

  const jobId = buildEmailJobId(
    buildRecapDedupeKey("weekly", closedWeek.key, "unsub-1")
  );
  const snapshot = await db.collection(EMAIL_JOBS).doc(jobId).get();
  assert.equal(snapshot.exists, false, "unsubscribed climber got no job at all");
  assert.ok(summary.suppressed >= 1);
});

test(
  "a climber who has never completed a climb and holds no access gets nothing",
  async () => {
    await seedUser("new-1", "new@example.com");
    // No leaderboard_stats rows and no app_access grant - onboarding-
    // abandonment emails own this account, not the recap.

    await composeAndSend();

    const jobId = buildEmailJobId(
      buildRecapDedupeKey("weekly", closedWeek.key, "new-1")
    );
    const snapshot = await db.collection(EMAIL_JOBS).doc(jobId).get();
    assert.equal(snapshot.exists, false);
    assert.equal(await recapExists("new-1"), false);
  }
);

test(
  "an entitled account that never climbed gets the never_climbed recap and no email",
  async () => {
    await seedUser("entitled-new-1", "entitlednew@example.com");
    await seedEntitlement("entitled-new-1", addDays(now, 30));

    const {compose, send} = await composeAndSend();

    const recap = await readRecap("entitled-new-1");
    assert.equal(recap.variant, "never_climbed");
    assert.equal(recap.active, null);
    assert.equal(recap.inactive, null);
    assert.equal(recap.seenAt, null);
    assert.equal(compose.neverClimbedCount, 1);

    const jobId = buildEmailJobId(
      buildRecapDedupeKey("weekly", closedWeek.key, "entitled-new-1")
    );
    const job = await db.collection(EMAIL_JOBS).doc(jobId).get();
    assert.equal(job.exists, false);
    assert.equal(send.skippedNeverClimbed, 1);
    assert.equal(send.errors, 0);
  }
);

test(
  "an entitled climber with history gets their real variant, never never_climbed",
  async () => {
    await seedUser("entitled-dormant-1", "entitleddormant@example.com");
    await seedEntitlement("entitled-dormant-1", addDays(now, 30));
    await seedAllTimeStats("entitled-dormant-1");
    await seedUser("entitled-active-1", "entitledactive@example.com");
    await seedEntitlement("entitled-active-1", addDays(now, 30));
    await seedWeeklyStats("entitled-active-1", closedWeek, {
      totalFloors: 10,
      totalSteps: 700,
      totalWorkouts: 1,
    });

    const {compose} = await composeAndSend();

    assert.equal((await readRecap("entitled-dormant-1")).variant, "inactive");
    assert.equal((await readRecap("entitled-active-1")).variant, "active");
    assert.equal(compose.neverClimbedCount, 0);
  }
);

test("an expired grant is not access, so no never_climbed recap", async () => {
  await seedUser("expired-1", "expired@example.com");
  await seedEntitlement("expired-1", addDays(now, -2));

  await composeAndSend();

  assert.equal(await recapExists("expired-1"), false);
});

test(
  "a climber with no email address still gets a recap, and no email",
  async () => {
    await seedUser("no-email-1", null);
    await seedUser("no-email-2", null);
    await seedWeeklyStats("no-email-1", closedWeek, {
      totalFloors: 10,
      totalSteps: 900,
      totalWorkouts: 1,
    });
    await seedAllTimeStats("no-email-2");

    const {send} = await composeAndSend();

    assert.equal((await readRecap("no-email-1")).variant, "active");
    assert.equal((await readRecap("no-email-2")).variant, "inactive");
    assert.equal(send.skippedNoEmail, 2);
    assert.equal((await db.collection(EMAIL_JOBS).get()).size, 0);
  }
);

test(
  "a truncated active-cohort scan composes and sends nothing to anyone",
  async () => {
    for (const uid of ["trunc-a", "trunc-b", "trunc-c"]) {
      await seedUser(uid, `${uid}@example.com`);
      await seedAllTimeStats(uid);
      await seedWeeklyStats(uid, closedWeek, {
        totalFloors: 10,
        totalSteps: 500,
        totalWorkouts: 1,
      });
    }
    await seedUser("trunc-dormant", "trunc-dormant@example.com");
    await seedAllTimeStats("trunc-dormant");

    const {compose, send} = await composeAndSend({maxPages: 2, pageSize: 1});

    assert.equal(compose.outcome, "skipped_truncated");
    assert.equal(compose.composed, 0);
    assert.equal(send.queued, 0);
    assert.equal(send.recapsMissing, true);
    assert.equal((await db.collection(EMAIL_JOBS).get()).size, 0);
    assert.equal((await db.collectionGroup("recaps").get()).size, 0);
  }
);

test(
  "a truncated lifetime scan withholds never_climbed rather than guess",
  async () => {
    // Two dormant climbers fill more than one one-row page, so the
    // lifetime scan is cut short; the entitled account past the cutoff
    // might have climbed, so nobody is told they never did.
    await seedAllTimeStats("cutoff-dormant-a");
    await seedAllTimeStats("cutoff-dormant-b");
    await seedUser("cutoff-entitled", "cutoff@example.com");
    await seedEntitlement("cutoff-entitled", addDays(now, 30));

    const {compose} = await composeAndSend({maxPages: 1, pageSize: 1});

    assert.equal(compose.outcome, "composed");
    assert.equal(compose.neverClimbedCount, 0);
    assert.equal(await recapExists("cutoff-entitled"), false);
  }
);

test(
  "a send whose compose never ran composes first, then sends from the stored recap",
  async () => {
    await seedUser("uncomposed-1", "uncomposed@example.com");
    await seedWeeklyStats("uncomposed-1", closedWeek, {
      totalFloors: 10,
      totalSteps: 500,
      totalWorkouts: 1,
    });

    const summary = await runRecapSend("weekly", now);

    assert.equal(summary.recapsMissing, false);
    assert.equal(summary.composedAtSend, 1);
    assert.equal(summary.recapCount, 1);
    assert.equal(summary.queued, 1);
    assert.equal((await readRecap("uncomposed-1")).variant, "active");
  }
);

test(
  "a climb in the week that synced after compose is recomposed and never told it was missed",
  async () => {
    await seedUser("late-in-week", "lateinweek@example.com");
    await seedAllTimeStats("late-in-week");
    await seedCompletedLandmarkWorkout("late-in-week", "eiffel", addDays(now, -28));

    await runRecapCompose("weekly", composeNow);
    assert.equal((await readRecap("late-in-week")).variant, "inactive");
    const seenAt = admin.firestore.Timestamp.fromDate(addDays(now, -0.25));
    await recapRef("late-in-week").update({seenAt});

    // Sunday 23:00 UTC, synced Monday morning, before the 13:00 send.
    await seedCompletedLandmarkWorkout(
      "late-in-week",
      "short-climb",
      new Date(closedWeek.endAt.getTime() - 60 * 60 * 1000)
    );
    await seedWeeklyStats("late-in-week", closedWeek, {
      totalFloors: 10,
      totalSteps: 500,
      totalWorkouts: 1,
    });

    const send = await runRecapSend("weekly", now);

    const recap = await readRecap("late-in-week");
    assert.equal(recap.variant, "active");
    assert.equal(recap.inactive, null);
    assert.ok(seenAt.isEqual(recap.seenAt as admin.firestore.Timestamp));
    assert.equal(send.queued, 1);
    const job = await db.collection(EMAIL_JOBS).doc(buildEmailJobId(
      buildRecapDedupeKey("weekly", closedWeek.key, "late-in-week")
    )).get();
    assert.equal(job.data()?.type, "weekly_recap_active");
  }
);

test(
  "an older climb that synced late corrects the stored gap before the email",
  async () => {
    await seedUser("old-sync", "oldsync@example.com");
    await seedAllTimeStats("old-sync");
    await seedCompletedLandmarkWorkout("old-sync", "eiffel", addDays(now, -60));

    await runRecapCompose("weekly", composeNow);
    await seedCompletedLandmarkWorkout("old-sync", "short-climb", addDays(now, -15));

    await runRecapSend("weekly", now);

    const inactive = (await readRecap("old-sync")).inactive as
      Record<string, unknown>;
    assert.equal(
      (inactive.lastClimbAt as admin.firestore.Timestamp).toMillis(),
      addDays(now, -15).getTime()
    );
    assert.equal(inactive.gapCount, 2);
  }
);

test(
  "compose waits for the finalizer, then composes without it once the grace runs out",
  async () => {
    await db.collection("leaderboard_periods")
      .doc(`weekly_${closedWeek.key}`)
      .delete();
    await seedUser("waiting-1", "waiting@example.com");
    await seedWeeklyStats("waiting-1", closedWeek, {
      totalFloors: 10,
      totalSteps: 500,
      totalWorkouts: 1,
    });

    const early = await runRecapCompose("weekly", composeNow);
    assert.equal(early.outcome, "awaiting_finalization");
    assert.equal(await recapExists("waiting-1"), false);

    const late = await runRecapCompose(
      "weekly",
      new Date(closedWeek.endAt.getTime() + 61 * 60 * 1000)
    );
    assert.equal(late.outcome, "composed");
    assert.equal((await readRecap("waiting-1")).variant, "active");
  }
);

test(
  "re-composing only turns an inactive recap active, and never resets seenAt",
  async () => {
    await seedUser("seen-1", "seen@example.com");
    await seedAllTimeStats("seen-1");

    const first = await runRecapCompose("weekly", composeNow);
    assert.equal(first.composed, 1);
    const seenAt = admin.firestore.Timestamp.fromDate(addDays(now, -0.25));
    await recapRef("seen-1").update({seenAt});

    // A late sync lands the climber in the active cohort for the same week.
    await seedWeeklyStats("seen-1", closedWeek, {
      totalFloors: 10,
      totalSteps: 500,
      totalWorkouts: 1,
    });
    const second = await runRecapCompose("weekly", composeNow);

    assert.equal(second.composed, 0);
    assert.equal(second.recomposed, 1);
    const recap = await readRecap("seen-1");
    assert.equal(recap.variant, "active");
    assert.ok(seenAt.isEqual(recap.seenAt as admin.firestore.Timestamp));

    const third = await runRecapCompose("weekly", composeNow);
    assert.equal(third.recomposed, 0);
    assert.equal(third.alreadyComposed, 1);
  }
);

test("re-running the same closed week does not double-queue", async () => {
  await seedUser("active-solo", "activesolo@example.com");
  await seedWeeklyStats("active-solo", closedWeek, {
    totalFloors: 10,
    totalSteps: 500,
    totalWorkouts: 1,
  });

  const first = await composeAndSend();
  const second = await composeAndSend();

  assert.ok(first.send.queued >= 1);
  assert.ok(second.compose.alreadyComposed >= 1);
  assert.ok(second.send.alreadyQueued >= 1);

  const snapshot = await db.collection(EMAIL_JOBS).get();
  const matching = snapshot.docs.filter(
    (doc) => doc.data().recipientEmail === "activesolo@example.com"
  );
  assert.equal(matching.length, 1);
});

test(
  "a late-synced climb never earns a second recap for the same closed week",
  async () => {
    await seedUser("late-1", "late@example.com");
    await seedAllTimeStats("late-1");

    const first = await composeAndSend();
    await seedWeeklyStats("late-1", closedWeek, {
      totalFloors: 10,
      totalSteps: 500,
      totalWorkouts: 1,
    });
    const second = await composeAndSend();

    assert.ok(first.send.queued >= 1);
    assert.ok(second.send.alreadyQueued >= 1);

    const snapshot = await db.collection(EMAIL_JOBS).get();
    const matching = snapshot.docs.filter(
      (doc) => doc.data().recipientEmail === "late@example.com"
    );
    assert.equal(matching.length, 1);
    assert.equal(matching[0].data().type, "weekly_recap_inactive");
  }
);

test(
  "a monthly recap is stored and sent under the month, with no streak",
  async () => {
    const monthComposeNow = new Date("2026-09-01T00:30:00Z");
    const monthSendNow = new Date("2026-09-01T13:00:00Z");
    const closedMonth = previousPeriod("monthly", monthSendNow);
    await seedFinalizedPeriod("monthly", closedMonth);
    await seedUser("monthly-1", "monthly@example.com");
    await seedPeriodStats("monthly-1", "monthly", closedMonth, {
      totalFloors: 300,
      totalSteps: 12000,
      totalWorkouts: 6,
    });

    const compose = await runRecapCompose("monthly", monthComposeNow);
    const send = await runRecapSend("monthly", monthSendNow);

    assert.equal(compose.composed, 1);
    assert.equal(send.queued, 1);
    const recap = await readRecap("monthly-1", "monthly", closedMonth.key);
    assert.equal(recap.periodKey, "2026-M08");
    assert.equal(recap.periodLabel, "August 2026");
    const active = recap.active as Record<string, unknown>;
    assert.equal(active.currentStreakWeeks, null);
    assert.equal((active.calendar as unknown[]).length % 7, 0);

    const job = await readJob(
      buildRecapDedupeKey("monthly", closedMonth.key, "monthly-1")
    );
    assert.equal(job.type, "monthly_recap_active");
    const payload = job.payload as RecapActivePayload;
    assert.equal(payload.periodLabel, "August 2026");
    assert.equal(payload.currentStreakWeeks, undefined);
    assert.equal(payload.totalSteps, 12000);
  }
);

/**
 * Runs the weekly compose at 00:30 and the weekly send at 13:00 on the
 * Monday the week closed, the way the two schedules do.
 * @param {CohortScanBound} [cohortScanBound] - Compose's scan bound
 * @return {Promise<{compose: RecapComposeSummary, send: RecapSendSummary}>}
 *   Both runs' summaries
 */
async function composeAndSend(cohortScanBound?: CohortScanBound): Promise<{
  compose: RecapComposeSummary;
  send: RecapSendSummary;
}> {
  const compose = await runRecapCompose("weekly", composeNow, cohortScanBound);
  const send = await runRecapSend(
    "weekly",
    now,
    undefined,
    cohortScanBound
  );
  return {compose, send};
}

/**
 * The stored recap document for a climber and period.
 * @param {string} uid - Firebase Auth user ID
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {string} periodKey - Closed period key
 * @return {admin.firestore.DocumentReference} The recap document
 */
function recapRef(
  uid: string,
  cadence: RecapCadence = "weekly",
  periodKey: string = closedWeek.key
): admin.firestore.DocumentReference {
  return db
    .collection("users")
    .doc(uid)
    .collection("recaps")
    .doc(buildRecapDocumentId(cadence, periodKey));
}

/**
 * Reads a climber's stored recap, failing when compose wrote none.
 * @param {string} uid - Firebase Auth user ID
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {string} periodKey - Closed period key
 * @return {Promise<Record<string, unknown>>} The recap's fields
 */
async function readRecap(
  uid: string,
  cadence: RecapCadence = "weekly",
  periodKey: string = closedWeek.key
): Promise<Record<string, unknown>> {
  const snapshot = await recapRef(uid, cadence, periodKey).get();
  assert.ok(snapshot.exists, `expected a stored recap for ${uid}`);
  return snapshot.data() as Record<string, unknown>;
}

/**
 * Whether compose stored a weekly recap for a climber.
 * @param {string} uid - Firebase Auth user ID
 * @return {Promise<boolean>} True when the recap exists
 */
async function recapExists(uid: string): Promise<boolean> {
  return (await recapRef(uid).get()).exists;
}

/**
 * Marks a closed period finalized, the way the 00:15 finalizer does in the
 * same batch as the period's achievements.
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {ReturnType<typeof previousPeriod>} period - The closed period
 * @return {Promise<void>}
 */
async function seedFinalizedPeriod(
  cadence: RecapCadence,
  period: ReturnType<typeof previousPeriod>
): Promise<void> {
  await db.collection("leaderboard_periods")
    .doc(`${cadence}_${period.key}`)
    .set({
      periodKey: period.key,
      status: "finalized",
      timeFrame: cadence,
    });
}

/**
 * Seeds a server-owned `app_access` grant, the shape the RevenueCat
 * projection writes and the expiry sweep deletes once `accessUntil` passes.
 * @param {string} uid - Firebase Auth user ID
 * @param {Date} accessUntil - When the access ends
 * @return {Promise<void>}
 */
async function seedEntitlement(uid: string, accessUntil: Date): Promise<void> {
  await db
    .collection("users")
    .doc(uid)
    .collection("entitlements")
    .doc("app_access")
    .set({
      accessUntil: admin.firestore.Timestamp.fromDate(accessUntil),
      isActive: true,
      productId: "ascend_annual",
    });
}

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
 * @param {string | null} email - Registered email, or null for none
 * @param {{lifecycleEmailsEnabled?: boolean}} options - Consent override
 * @return {Promise<void>}
 */
async function seedUser(
  uid: string,
  email: string | null,
  options: {lifecycleEmailsEnabled?: boolean} = {}
): Promise<void> {
  const nowTimestamp = admin.firestore.Timestamp.now();
  await db.collection("users").doc(uid).set(email ? {email} : {});
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
  await seedPeriodStats(uid, "weekly", period, totals);
}

/**
 * Seeds a closed-period `leaderboard_stats` row for either cadence.
 * @param {string} uid - Firebase Auth user ID
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {ReturnType<typeof previousPeriod>} period - Closed period
 * @param {{totalFloors: number, totalSteps: number, totalWorkouts: number}}
 *   totals - Period aggregate
 * @return {Promise<void>}
 */
async function seedPeriodStats(
  uid: string,
  cadence: RecapCadence,
  period: ReturnType<typeof previousPeriod>,
  totals: {totalFloors: number; totalSteps: number; totalWorkouts: number}
): Promise<void> {
  const docId = leaderboardDocumentId(uid, cadence, period.key);
  await db.collection(LEADERBOARD_STATS).doc(docId).set({
    isSynthetic: false,
    periodKey: period.key,
    periodStartAt: admin.firestore.Timestamp.fromDate(period.startAt),
    schemaVersion: 2,
    stepsPerMinute: 0,
    timeFrame: cadence,
    totalDuration: 0,
    ...totals,
    userId: uid,
  });
}

/**
 * Seeds the never-closing all-time `leaderboard_stats` row, the signal this
 * sweep uses for "has ever completed a climb". `lastUpdated`, when given,
 * is the reconcile stamp the zero-activity gap must never read.
 * @param {string} uid - Firebase Auth user ID
 * @param {Date} lastUpdatedAt - When this row last moved
 * @param {number} totalSteps - All-time steps on the row
 * @return {Promise<void>}
 */
async function seedAllTimeStats(
  uid: string,
  lastUpdatedAt?: Date,
  totalSteps = 100
): Promise<void> {
  const docId = leaderboardDocumentId(uid, "all_time", "all");
  await db.collection(LEADERBOARD_STATS).doc(docId).set({
    isSynthetic: false,
    ...(lastUpdatedAt ?
      {lastUpdated: admin.firestore.Timestamp.fromDate(lastUpdatedAt)} :
      {}),
    periodKey: "all",
    periodStartAt: admin.firestore.Timestamp.fromDate(new Date(0)),
    schemaVersion: 2,
    stepsPerMinute: 0,
    timeFrame: "all_time",
    totalDuration: 100,
    totalFloors: 10,
    totalSteps,
    totalWorkouts: 1,
    userId: uid,
  });
}

/**
 * Seeds the permanent First Ascent record `liveReplayLeaderboard.ts` writes
 * once a climb's First Ascent is claimed - the record both the
 * zero-activity email's `firstAscents` list and the active recap's
 * period-scoped First Ascent badge read. `claim.workoutId` is the claiming
 * workout the active recap matches against the closed period's own
 * workouts; `claim.claimedAt` is the server's processing time, which the
 * recap must never key on.
 * @param {string} uid - Firebase Auth user ID
 * @param {string} climbId - Landmark climb ID this climber first-ascended
 * @param {{workoutId: string, claimedAt: Date}} [claim] - The claim
 * @return {Promise<void>}
 */
async function seedFirstAscent(
  uid: string,
  climbId: string,
  claim?: {workoutId: string; claimedAt: Date}
): Promise<void> {
  await db.collection("live_replay_leaderboards").doc(climbId).set({
    contextId: climbId,
    contextType: "live_climb",
    ...(claim ?
      {
        firstAscentCompletedAt:
          admin.firestore.Timestamp.fromDate(claim.claimedAt),
        firstAscentWorkoutId: claim.workoutId,
      } :
      {}),
    firstAscentUserId: uid,
  });
}

/**
 * Seeds the closed-period global steps achievement
 * `finalizeLeaderboardAchievements` would have already written - the
 * canonical record the recap's achievement callout reuses rather than
 * re-deriving.
 * @param {string} uid - Firebase Auth user ID
 * @param {string} timeFrame - "weekly" or "monthly"
 * @param {string} periodKey - Closed period key
 * @param {number} rank - Finishing rank
 * @return {Promise<void>}
 */
async function seedAchievement(
  uid: string,
  timeFrame: string,
  periodKey: string,
  rank: number
): Promise<void> {
  await db
    .collection("users")
    .doc(uid)
    .collection("achievements")
    .doc(`global_steps_${timeFrame}_${periodKey}`)
    .set({rank, schemaVersion: 1, type: `${timeFrame}_top_10`});
}

/**
 * Seeds a workout that `parseCompletedLandmarkWorkout`
 * (climbCompletions.ts) recognizes as a genuine landmark finish: a
 * headphone-motion capture whose legacy `stopReason` is `target_reached`.
 * @param {string} uid - Firebase Auth user ID
 * @param {string} climbId - Landmark climb ID
 * @param {Date} startedAt - Workout start time
 * @return {Promise<string>} The seeded workout's ID
 */
async function seedCompletedLandmarkWorkout(
  uid: string,
  climbId: string,
  startedAt: Date
): Promise<string> {
  const reference = await db
    .collection("users")
    .doc(uid)
    .collection("workouts")
    .add({
      durationSeconds: 600,
      source: "headphone_motion",
      sourceMetadata: JSON.stringify({climbId, stopReason: "target_reached"}),
      startedAt: admin.firestore.Timestamp.fromDate(startedAt),
      steps: 1200,
    });
  return reference.id;
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
 * Wipes the whole emulator database between tests.
 * @return {Promise<void>}
 */
async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const response = await emulatorFetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}` +
      "/databases/(default)/documents",
    {method: "DELETE"}
  );
  assert.ok(response.ok, `emulator reset failed: ${response.status}`);
}
