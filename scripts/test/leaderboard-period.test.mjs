import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, join} from "node:path";
import {currentPeriod, weekInfoUTC} from "../lib/leaderboard-period.mjs";
import {currentPeriod as profileFixtureCurrentPeriod} from "../seed/fixtures/profile-fixtures.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const vector = JSON.parse(
  readFileSync(
    join(here, "../../SharedTestVectors/leaderboard-period-key-vector.json"),
    "utf8"
  )
);

function vectorInstant(date) {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day, 12));
}

// The seeds write the documents the app reads. If they spell a key differently
// from the client or the finalizer, the seeded board is simply invisible - the
// failure looks like an empty board, not like a bug.
test("the seed period derivation matches the shared vector", () => {
  assert.ok(vector.cases.length >= 9, "vector should carry every shape");

  for (const testCase of vector.cases) {
    const instant = vectorInstant(testCase.date);

    assert.equal(
      currentPeriod("weekly", instant).key,
      testCase.weekly,
      `weekly key for ${testCase.date} - ${testCase.name}`
    );
    assert.equal(
      currentPeriod("monthly", instant).key,
      testCase.monthly,
      `monthly key for ${testCase.date} - ${testCase.name}`
    );
    assert.equal(
      currentPeriod("yearly", instant).key,
      testCase.yearly,
      `yearly key for ${testCase.date} - ${testCase.name}`
    );
  }
});

// The profile seed pack derives its own periods through the same module; this
// pins the export the audit script and the seeders actually import.
test("the profile fixture period derivation matches the shared vector", () => {
  for (const testCase of vector.cases) {
    const instant = vectorInstant(testCase.date);

    assert.equal(profileFixtureCurrentPeriod("weekly", instant).key, testCase.weekly);
    assert.equal(profileFixtureCurrentPeriod("monthly", instant).key, testCase.monthly);
    assert.equal(profileFixtureCurrentPeriod("yearly", instant).key, testCase.yearly);
  }
});

test("weekly windows open on Monday UTC and contain their own instant", () => {
  for (const testCase of vector.cases) {
    const instant = vectorInstant(testCase.date);
    const {startAt} = currentPeriod("weekly", instant);

    assert.equal(startAt.getUTCDay(), 1, `${testCase.date} week should open on Monday`);
    assert.ok(startAt <= instant, `${testCase.date} should fall inside its own week`);
    assert.ok(instant - startAt < 7 * 24 * 60 * 60 * 1000);
  }
});

test("week 1 is the week containing Jan 1, so a week key can carry the next year", () => {
  assert.deepEqual(weekInfoUTC(new Date(Date.UTC(2025, 11, 29, 12))), {
    year: 2026,
    week: 1,
    startAt: new Date(Date.UTC(2025, 11, 29)),
  });
});

test("daily and all-time keys stay stable", () => {
  assert.equal(
    currentPeriod("daily", new Date(Date.UTC(2026, 7, 1, 23, 59))).key,
    "2026-08-01"
  );
  assert.equal(currentPeriod("all_time", new Date()).key, "all");
});

test("an unknown time frame fails loudly rather than seeding an unreadable key", () => {
  assert.throws(() => currentPeriod("fortnightly", new Date()), /Unsupported time frame/);
});
