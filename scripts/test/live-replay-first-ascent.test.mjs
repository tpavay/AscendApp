import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {test} from "node:test";

import {
  FIRST_ASCENT_FIELD_NAMES,
  assertFirstAscentInvariant,
  clearedFirstAscentFields,
  firstAscentClaimedAt,
  firstAscentSeedFields,
} from "../seed/lib/live-replay-first-ascent.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

const attempt = {
  id: "seed-attempt-1",
  userId: "seeded:pack:mount-everest:0",
  displayName: "Sarah K.",
  avatarToken: "SK",
  photoURL: "https://example.test/sarah.jpg",
};

test("seeded First Ascent fields match the server's published shape", () => {
  const claimedAt = new Date("2026-01-01T00:00:00Z");
  const fields = firstAscentSeedFields(attempt, claimedAt);

  assert.deepEqual(fields, {
    firstAscentAvatarToken: "SK",
    firstAscentCompletedAt: claimedAt,
    firstAscentDisplayName: "Sarah K.",
    firstAscentPhotoURL: "https://example.test/sarah.jpg",
    firstAscentUserId: "seeded:pack:mount-everest:0",
    firstAscentWorkoutId: "seed-attempt-1",
  });
});

test("a holder without a photo seeds an empty string, never undefined", () => {
  // The client reads photoURL off the summary; undefined would drop the field
  // and diverge from the server, which always writes "".
  const fields = firstAscentSeedFields(
    {...attempt, photoURL: undefined},
    new Date("2026-01-01T00:00:00Z")
  );

  assert.equal(fields.firstAscentPhotoURL, "");
});

test("seeded First Ascent fields cover exactly the declared field names", () => {
  const fields = firstAscentSeedFields(attempt, new Date("2026-01-01T00:00:00Z"));

  assert.deepEqual(
    Object.keys(fields).sort(),
    [...FIRST_ASCENT_FIELD_NAMES].sort()
  );
});

test("seed script publishes the same First Ascent fields as the Cloud Function", () => {
  // The seed script and `firstAscentWrite` must publish identical shapes: the
  // client reads one contract, so a field added on one side and not the other
  // silently changes how seeded climbs render versus real ones.
  const source = readFileSync(
    resolve(REPO_ROOT, "functions/src/liveReplayLeaderboard.ts"),
    "utf8"
  );
  const writeBody = source.match(
    /function firstAscentWrite\([\s\S]*?\n\}/
  )?.[0];
  assert.ok(writeBody, "could not locate firstAscentWrite in the Cloud Function");

  const serverFields = [...writeBody.matchAll(/(firstAscent\w+):/g)]
    .map((match) => match[1])
    .sort();

  assert.deepEqual(serverFields, [...FIRST_ASCENT_FIELD_NAMES].sort());
});

test("clearing removes every First Ascent field", () => {
  const sentinel = Symbol("delete");
  const cleared = clearedFirstAscentFields(sentinel);

  assert.deepEqual(Object.keys(cleared).sort(), [...FIRST_ASCENT_FIELD_NAMES].sort());
  for (const field of FIRST_ASCENT_FIELD_NAMES) {
    assert.equal(cleared[field], sentinel, `${field} must be cleared`);
  }
});

test("claim dates are deterministic across seed runs", () => {
  assert.deepEqual(
    firstAscentClaimedAt("pack", "mount-everest"),
    firstAscentClaimedAt("pack", "mount-everest")
  );
});

test("claim dates differ per climb so held First Ascents sort stably", () => {
  const climbIds = [
    "mount-everest",
    "empire-state-building",
    "burj-khalifa",
    "eiffel-tower",
    "cn-tower",
  ];
  const claimedAt = climbIds.map((id) => firstAscentClaimedAt("pack", id).getTime());

  assert.equal(new Set(claimedAt).size, climbIds.length);
});

test("claim dates are in the past", () => {
  // A First Ascent is a completed historical event; a future date would render
  // as a climb topped tomorrow.
  const claimedAt = firstAscentClaimedAt("pack", "mount-everest");

  assert.ok(claimedAt.getTime() < Date.now(), `${claimedAt.toISOString()} is not in the past`);
});

test("completions without a holder are rejected", () => {
  // The exact state the seed script used to publish: canClaimFirstAscent is
  // `!hasFirstAscent && previousCompletedCount === 0`, so 89 completions with no
  // holder can never be claimed and never renders as held.
  assert.throws(
    () => assertFirstAscentInvariant({
      climbId: "mount-everest",
      completedCount: 89,
      hasFirstAscent: false,
    }),
    /no First Ascent holder/
  );
});

test("a holder without completions is rejected", () => {
  assert.throws(
    () => assertFirstAscentInvariant({
      climbId: "mount-everest",
      completedCount: 0,
      hasFirstAscent: true,
    }),
    /0 completions/
  );
});

test("the two reachable First Ascent states are accepted", () => {
  assert.doesNotThrow(() => assertFirstAscentInvariant({
    climbId: "mount-everest",
    completedCount: 89,
    hasFirstAscent: true,
  }));

  assert.doesNotThrow(() => assertFirstAscentInvariant({
    climbId: "sky-tower-auckland",
    completedCount: 0,
    hasFirstAscent: false,
  }));
});
