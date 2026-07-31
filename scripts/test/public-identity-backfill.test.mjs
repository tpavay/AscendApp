import test from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";

import {
  BACKFILL_ACTIONS,
  hasCurrentIdentityPolicy,
  planPublicIdentityBackfill,
  rowGuardFailures,
  rowPassesIdentityGuard,
  summarizeBackfillPlan,
} from "../lib/public-identity-backfill.mjs";

const RESTORE_SCRIPT = fileURLToPath(
  new URL("../restore-public-identities.mjs", import.meta.url)
);

const STORAGE_PHOTO_URL =
  "https://firebasestorage.googleapis.com/v0/b/" +
  "ascend-staging-fa7d5.firebasestorage.app/o/" +
  "seed-profile-avatars%2Fv1-profile-test%2Fprofile_veteran_champion.png" +
  "?alt=media&token=3f0f3523-2c04-4079-ab5c-7cf5a7123c3e";

// A verbatim staging mirror read 2026-07-31: a seeded persona whose profile
// predates the identity policy. This is the exact shape the backfill exists for.
function seededStagingMirror(overrides = {}) {
  return {
    age: 41,
    displayName: "Tyler R.",
    gender: "man",
    height_cm: 180,
    joined_at: {seconds: 1_750_000_000, nanoseconds: 0},
    lastUpdated: {seconds: 1_752_861_137, nanoseconds: 0},
    location_country: "US",
    location_region: "Texas",
    photoURL: STORAGE_PHOTO_URL,
    userId: "profile_veteran_champion",
    weight_kg: 84,
    ...overrides,
  };
}

function plan(userId, profileData) {
  return planPublicIdentityBackfill({
    profileData,
    profileExists: profileData !== undefined,
    userId,
  });
}

test("a pre-policy mirror with a publishable identity is stamped", () => {
  const result = plan("profile_veteran_champion", seededStagingMirror());

  assert.equal(result.action, BACKFILL_ACTIONS.stamp);
  assert.match(result.reason, /missing identityPolicyVersion and identityChangedAt/u);
  assert.deepEqual(result.warnings, []);
});

test("a mirror that already carries the policy is left alone", () => {
  const result = plan("profile_veteran_champion", seededStagingMirror({
    identityChangedAt: {seconds: 1_754_075_755, nanoseconds: 712_000_000},
    identityPolicyVersion: 1,
  }));

  assert.equal(result.action, BACKFILL_ACTIONS.current);
});

test("each policy field is individually load-bearing", () => {
  const missingTimestamp = plan("profile_veteran_champion", seededStagingMirror({
    identityPolicyVersion: 1,
  }));
  const missingVersion = plan("profile_veteran_champion", seededStagingMirror({
    identityChangedAt: {seconds: 1_754_075_755, nanoseconds: 0},
  }));

  assert.equal(missingTimestamp.action, BACKFILL_ACTIONS.stamp);
  assert.match(missingTimestamp.reason, /missing identityChangedAt/u);
  assert.equal(missingVersion.action, BACKFILL_ACTIONS.stamp);
  assert.match(missingVersion.reason, /missing identityPolicyVersion/u);
});

test("a superseded policy version is advanced rather than trusted", () => {
  const result = plan("profile_veteran_champion", seededStagingMirror({
    identityChangedAt: {seconds: 1_754_075_755, nanoseconds: 0},
    identityPolicyVersion: 0,
  }));

  assert.equal(result.action, BACKFILL_ACTIONS.stamp);
  assert.equal(hasCurrentIdentityPolicy({
    identityChangedAt: {seconds: 1, nanoseconds: 0},
    identityPolicyVersion: 0,
  }), false);
});

test("a user with no public profile mirror is skipped, not invented", () => {
  const result = plan("dBvwJUHI3yRENy4GOrWMNelXpLN2", undefined);

  assert.equal(result.action, BACKFILL_ACTIONS.skip);
  assert.match(result.reason, /no users\/.*\/public_profile\/current/u);
});

// The screening is the whole point of routing through the shared contract: the
// reconciler must not publish an identity the live write path would reject.
test("a display name that fails the shared screening is skipped", () => {
  for (const displayName of ["fuuuck", "Anonymous Climber", "   ", "n1gger"]) {
    const result = plan(
      "profile_veteran_champion",
      seededStagingMirror({displayName})
    );
    assert.equal(
      result.action,
      BACKFILL_ACTIONS.skip,
      `expected to skip ${JSON.stringify(displayName)}`
    );
  }
});

test("the screening agrees with the shared display-name vector", () => {
  const vector = JSON.parse(readFileSync(
    fileURLToPath(new URL(
      "../../SharedTestVectors/display-name-screening-vector.json",
      import.meta.url
    )),
    "utf-8"
  ));

  for (const displayName of vector.allowed) {
    assert.notEqual(
      plan("u", seededStagingMirror({displayName, userId: "u"})).action,
      BACKFILL_ACTIONS.skip,
      `allowed: ${displayName}`
    );
  }
  for (const displayName of vector.rejected) {
    assert.equal(
      plan("u", seededStagingMirror({displayName, userId: "u"})).action,
      BACKFILL_ACTIONS.skip,
      `rejected: ${displayName}`
    );
  }
});

test("a mirror owned by another uid is skipped", () => {
  const result = plan("profile_veteran_champion", seededStagingMirror({
    userId: "someone_else",
  }));

  assert.equal(result.action, BACKFILL_ACTIONS.skip);
  assert.match(result.reason, /does not match the document owner/u);
});

test("a mirror with no photoURL field is skipped rather than given one", () => {
  const mirror = seededStagingMirror();
  delete mirror.photoURL;

  const result = plan("profile_veteran_champion", mirror);

  assert.equal(result.action, BACKFILL_ACTIONS.skip);
  assert.match(result.reason, /no photoURL field/u);
});

// An off-host photo is the shape two real staging accounts carry: a Google
// account avatar. The trigger blanks the photo but still publishes the name, so
// withholding the whole row would leave that climber invisible for no gain.
test("an off-contract photo warns but still publishes the name", () => {
  const result = plan("3XX6Trca0gSFNFNjoYSyIVbnN802", seededStagingMirror({
    displayName: "Urjita Das",
    photoURL: "https://lh3.googleusercontent.com/a/ACg8ocJj4Ixx=s96-c",
    userId: "3XX6Trca0gSFNFNjoYSyIVbnN802",
  }));

  assert.equal(result.action, BACKFILL_ACTIONS.stamp);
  assert.equal(result.warnings.length, 1);
  assert.match(result.warnings[0], /no photo/u);
});

test("an empty photoURL is a valid identity with no photo", () => {
  const result = plan("vjymcbijYvODHEQTxWPEVKPhv4t1", seededStagingMirror({
    displayName: "Tyler Staging QA",
    photoURL: "",
    userId: "vjymcbijYvODHEQTxWPEVKPhv4t1",
  }));

  assert.equal(result.action, BACKFILL_ACTIONS.stamp);
  assert.deepEqual(result.warnings, []);
});

test("the plan summary counts every action", () => {
  const summary = summarizeBackfillPlan([
    plan("profile_veteran_champion", seededStagingMirror()),
    plan("a", undefined),
    plan("b", undefined),
    plan("c", seededStagingMirror({
      identityChangedAt: {seconds: 1, nanoseconds: 0},
      identityPolicyVersion: 1,
      userId: "c",
    })),
  ]);

  assert.deepEqual(summary, {current: 1, skip: 2, stamp: 1, warnings: 0});
});

// A leaderboard row the client parses in full: every clause of parseStat is
// satisfied. Overriding or deleting one field at a time proves each is
// individually load-bearing.
function parsableRow(overrides = {}) {
  return {
    identityChangedAt: {seconds: 1_754_075_755, nanoseconds: 0},
    identityPolicyVersion: 1,
    identityState: "published",
    lastUpdated: {seconds: 1_752_861_137, nanoseconds: 0},
    periodKey: "2026-W31",
    periodStartAt: {seconds: 1_752_800_000, nanoseconds: 0},
    timeFrame: "weekly",
    totalDuration: 3_600,
    totalFloors: 120,
    totalSteps: 4_800,
    totalWorkouts: 3,
    userId: "profile_veteran_champion",
    ...overrides,
  };
}

// This mirrors the guard in LeaderboardRepository.parseStat. If these two ever
// disagree, --verify reports a green leaderboard the client still empties out.
test("the row guard matches the client's parseStat contract", () => {
  assert.equal(rowPassesIdentityGuard(parsableRow()), true);

  for (const field of [
    "identityChangedAt",
    "identityPolicyVersion",
    "identityState",
    "lastUpdated",
    "periodKey",
    "periodStartAt",
    "timeFrame",
    "userId",
  ]) {
    const row = parsableRow();
    delete row[field];
    assert.equal(rowPassesIdentityGuard(row), false, `dropped without ${field}`);
    assert.deepEqual(rowGuardFailures(row), [field], `only ${field} is unmet`);
  }

  assert.equal(rowPassesIdentityGuard(parsableRow({identityPolicyVersion: 2})), false);
  assert.equal(rowPassesIdentityGuard(parsableRow({identityState: "wat"})), false);
  // A pending or deleted row needs no timestamp; only "published" does.
  assert.equal(rowPassesIdentityGuard(parsableRow({
    identityChangedAt: undefined,
    identityState: "pending_public_profile",
  })), true);
  assert.equal(rowPassesIdentityGuard(undefined), false);
});

// Rows predating schemaVersion 2 carry neither period field. They never matched
// the client's query either, so --verify must report them dropped rather than
// counting them as rendering.
test("a pre-schemaVersion-2 row is reported dropped, not rendering", () => {
  const legacy = parsableRow();
  delete legacy.periodStartAt;
  delete legacy.lastUpdated;

  assert.equal(rowPassesIdentityGuard(legacy), false);
  assert.deepEqual(rowGuardFailures(legacy), ["periodStartAt", "lastUpdated"]);
});

// The client reads these through timestampValue, which takes a Timestamp or a
// Date and nothing else - a serialized string is not a timestamp there.
test("timestamp clauses require a real timestamp, not a string", () => {
  for (const field of ["identityChangedAt", "lastUpdated", "periodStartAt"]) {
    assert.equal(
      rowPassesIdentityGuard(parsableRow({[field]: "2026-07-31T00:00:00Z"})),
      false,
      `${field} as a string`
    );
    assert.equal(
      rowPassesIdentityGuard(parsableRow({[field]: new Date(1_752_800_000_000)})),
      true,
      `${field} as a Date`
    );
  }
});

// parseStat drops a row whose four totals are all zero, so a stamped-but-empty
// row must not be counted as one the leaderboard will show.
test("a row with no effort at all is dropped", () => {
  const empty = parsableRow({
    totalDuration: 0,
    totalFloors: 0,
    totalSteps: 0,
    totalWorkouts: 0,
  });

  assert.equal(rowPassesIdentityGuard(empty), false);
  assert.deepEqual(rowGuardFailures(empty), ["totals are all zero"]);

  for (const field of [
    "totalDuration",
    "totalFloors",
    "totalSteps",
    "totalWorkouts",
  ]) {
    assert.equal(
      rowPassesIdentityGuard({...empty, [field]: 1}),
      true,
      `${field} alone carries the row`
    );
  }
});

test("production is refused rather than merely not targeted", () => {
  const result = runRestore(["--env", "prod", "--apply"]);

  assert.equal(result.failed, true);
  assert.match(result.output, /hard-refuses production/u);
});

test("a raw project id is not an environment", () => {
  const result = runRestore(["--env", "ascend-staging-fa7d5"]);

  assert.equal(result.failed, true);
  assert.match(result.output, /Unknown --env/u);
});

test("--env is required", () => {
  const result = runRestore([]);

  assert.equal(result.failed, true);
  assert.match(result.output, /Missing --env/u);
});

// --verify is a mode, not a --key value pair; the shared parser would otherwise
// demand a value for it and die before the environment is even resolved.
test("--verify survives argument parsing", () => {
  const result = runRestore(["--env", "prod", "--verify"]);

  assert.equal(result.failed, true);
  assert.match(result.output, /hard-refuses production/u);
  assert.doesNotMatch(result.output, /--verify requires a value/u);
});

function runRestore(args) {
  try {
    execFileSync(process.execPath, [RESTORE_SCRIPT, ...args], {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return {failed: false, output: ""};
  } catch (error) {
    return {failed: true, output: `${error.stdout ?? ""}${error.stderr ?? ""}`};
  }
}
