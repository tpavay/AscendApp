import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  CHAMPION_PUSH_TITLE,
  buildChampionPushMessage,
  evaluateChampionPushEligibility,
  isChampionPushEnabled,
  selectChampionPushDevices,
} from "../src/championPush.js";

const HOUR_MS = 60 * 60 * 1000;
const periodEndAt = new Date("2026-09-28T00:00:00Z");

/**
 * A result document as the finalizer writes it.
 * @param {Record<string, unknown>} overrides - Fields to change
 * @return {Record<string, unknown>} The result's fields
 */
function finalizerResult(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    championUserIds: ["champ-1"],
    periodEndAt: admin.firestore.Timestamp.fromDate(periodEndAt),
    periodKey: "2026-W39",
    source: "leaderboard_finalizer",
    timeFrame: "weekly",
    ...overrides,
  };
}

test("the crown title is one declarative line", () => {
  assert.equal(CHAMPION_PUSH_TITLE, "You took the crown.");
});

test("a weekly champion is named by week number, steps with separators", () => {
  assert.deepEqual(buildChampionPushMessage("weekly", "2026-W38", 12345), {
    body: "Week 38 champion. 12,345 steps. Defend it this week.",
    title: "You took the crown.",
  });
  assert.equal(
    buildChampionPushMessage("weekly", "2026-W05", 900)?.body,
    "Week 5 champion. 900 steps. Defend it this week."
  );
});

test("a monthly champion is named by the month, in UTC", () => {
  assert.deepEqual(buildChampionPushMessage("monthly", "2026-M09", 48210), {
    body: "September champion. 48,210 steps. Defend it all month.",
    title: "You took the crown.",
  });
  assert.equal(
    buildChampionPushMessage("monthly", "2027-M01", 1000)?.body,
    "January champion. 1,000 steps. Defend it all month."
  );
});

test("a yearly champion is named by the year", () => {
  assert.deepEqual(buildChampionPushMessage("yearly", "2026", 1204500), {
    body: "2026 champion. 1,204,500 steps. Defend it all year.",
    title: "You took the crown.",
  });
});

test("one step is a step", () => {
  assert.equal(
    buildChampionPushMessage("weekly", "2026-W01", 1)?.body,
    "Week 1 champion. 1 step. Defend it this week."
  );
});

test("a key that names no period has no copy", () => {
  assert.equal(buildChampionPushMessage("weekly", "2026-W00", 10), null);
  assert.equal(buildChampionPushMessage("weekly", "2026-W54", 10), null);
  assert.equal(buildChampionPushMessage("weekly", "2026-M09", 10), null);
  assert.equal(buildChampionPushMessage("monthly", "2026-M13", 10), null);
  assert.equal(buildChampionPushMessage("monthly", "2026-09", 10), null);
  assert.equal(buildChampionPushMessage("yearly", "26", 10), null);
});

test("a fresh finalizer result pushes to each distinct champion", () => {
  const eligibility = evaluateChampionPushEligibility(
    finalizerResult({
      championUserIds: ["champ-1", "champ-2", "champ-1", "", 7, "a/b"],
    }),
    new Date(periodEndAt.getTime() + 15 * 60 * 1000)
  );

  assert.deepEqual(eligibility, {
    eligible: true,
    result: {
      championUserIds: ["champ-1", "champ-2"],
      periodEndAt,
      periodKey: "2026-W39",
      timeFrame: "weekly",
    },
  });
});

test("a backfilled result never pushes", () => {
  assert.deepEqual(
    evaluateChampionPushEligibility(
      finalizerResult({source: "backfill"}),
      new Date(periodEndAt.getTime() + HOUR_MS)
    ),
    {eligible: false, reason: "not_finalizer"}
  );
});

test("a result older than 48 hours never pushes", () => {
  assert.equal(
    evaluateChampionPushEligibility(
      finalizerResult(),
      new Date(periodEndAt.getTime() + 47 * HOUR_MS)
    ).eligible,
    true
  );
  assert.deepEqual(
    evaluateChampionPushEligibility(
      finalizerResult(),
      new Date(periodEndAt.getTime() + 49 * HOUR_MS)
    ),
    {eligible: false, reason: "stale"}
  );
});

test("a period that has not closed yet never pushes", () => {
  assert.deepEqual(
    evaluateChampionPushEligibility(
      finalizerResult(),
      new Date(periodEndAt.getTime() - HOUR_MS)
    ),
    {eligible: false, reason: "not_closed"}
  );
});

test("a malformed result never pushes", () => {
  const soon = new Date(periodEndAt.getTime() + HOUR_MS);
  for (const overrides of [
    {timeFrame: "daily"},
    {timeFrame: "all_time"},
    {periodKey: 38},
    {periodKey: "2026-M09"},
    {periodEndAt: periodEndAt.toISOString()},
    {championUserIds: "champ-1"},
  ]) {
    assert.deepEqual(
      evaluateChampionPushEligibility(finalizerResult(overrides), soon),
      {eligible: false, reason: "malformed"},
      JSON.stringify(overrides)
    );
  }
});

test("the crown alert is on unless the climber turned it off", () => {
  assert.equal(isChampionPushEnabled(undefined), true);
  assert.equal(isChampionPushEnabled({}), true);
  assert.equal(isChampionPushEnabled({pushChampionCrownEnabled: true}), true);
  assert.equal(isChampionPushEnabled({pushChampionCrownEnabled: false}), false);
  // The climb-drop toggle is a different alert.
  assert.equal(isChampionPushEnabled({pushClimbDropsEnabled: false}), true);
});

test("only the champion's own deliverable devices are sent to", () => {
  const device = (overrides: Record<string, unknown>) => ({
    active: true,
    authorizationStatus: "authorized",
    fcmToken: "token",
    platform: "ios",
    uid: "champ-1",
    ...overrides,
  });

  const devices = selectChampionPushDevices("champ-1", [
    {data: device({fcmToken: "token-ok"}), tokenHash: "hash-ok"},
    {
      data: device({authorizationStatus: "provisional", fcmToken: "token-quiet"}),
      tokenHash: "hash-quiet",
    },
    {data: device({authorizationStatus: "denied"}), tokenHash: "hash-denied"},
    {
      data: device({authorizationStatus: "not_determined"}),
      tokenHash: "hash-unasked",
    },
    {data: device({active: false}), tokenHash: "hash-inactive"},
    {data: device({uid: "someone-else"}), tokenHash: "hash-moved"},
    {data: device({platform: "android"}), tokenHash: "hash-android"},
    {data: device({fcmToken: ""}), tokenHash: "hash-empty"},
    {data: undefined, tokenHash: "hash-missing"},
  ]);

  assert.deepEqual(devices, [
    {fcmToken: "token-ok", tokenHash: "hash-ok"},
    {fcmToken: "token-quiet", tokenHash: "hash-quiet"},
  ]);
});
