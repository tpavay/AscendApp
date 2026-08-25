import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {test} from "node:test";

import {
  FIRST_ASCENT_FIELD_NAMES,
  assertFirstAscentInvariant,
  clearOpenFirstAscentEntries,
  clearedFirstAscentFields,
  firstAscentClaimedAt,
  firstAscentInvariantFailure,
  firstAscentSeedFields,
  isOpenFirstAscentSummary,
  summaryHasFirstAscent,
} from "../seed/lib/live-replay-first-ascent.mjs";
import {PROFILE_SEED_PERSONAS} from "../seed/fixtures/profile-fixtures.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

function readScript(relativePath) {
  return readFileSync(resolve(REPO_ROOT, relativePath), "utf8");
}

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
    firstAscentIdentityState: "published",
    firstAscentIsSynthetic: true,
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

test("a real QA account is never marked as a trusted synthetic holder", () => {
  const fields = firstAscentSeedFields(
    {...attempt, displayName: "Climber", avatarToken: "", photoURL: ""},
    new Date("2026-01-01T00:00:00Z"),
    {isSynthetic: false}
  );

  assert.equal(fields.firstAscentIsSynthetic, false);
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

test("every seeded projection identity declares its lifecycle state", () => {
  const expectedPublishedWrites = new Map([
    ["scripts/seed-demo-user.mjs", 3],
    // Entry rows, plus the finisher document written beside them on each of
    // the two contexts the seed publishes into.
    ["scripts/seed-live-replay-leaderboards.mjs", 4],
  ]);

  for (const [script, expectedCount] of expectedPublishedWrites) {
    const source = readScript(script);
    const writes = source.match(
      /identityState:\s*PUBLIC_IDENTITY_STATE_PUBLISHED/g
    ) ?? [];
    assert.equal(
      writes.length,
      expectedCount,
      `${script} must state whether every projection identity is publishable`
    );
  }
});

test("profile personas seed only climbs the catalogue can race", () => {
  // A persona ID the catalogue never had seeds a climb no surface can resolve,
  // and nothing else in the seed path notices. `colosseum` sat here unnoticed.
  const catalogue = JSON.parse(
    readFileSync(resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json"), "utf8")
  );
  const availableClimbIds = new Set(
    catalogue
      .filter((climb) => climb.releaseState === "available")
      .map((climb) => climb.id)
  );

  for (const persona of PROFILE_SEED_PERSONAS) {
    for (const climbId of persona.climbIds) {
      assert.ok(
        availableClimbIds.has(climbId),
        `${persona.id} seeds ${climbId}, which is not an available racing climb`
      );
    }
  }
});

test("every seed script that publishes a holder routes through the module", () => {
  // A second hand-rolled literal is a copy of the contract the cross-file test
  // above cannot see: it would keep passing while the copy drifts.
  for (const script of ["scripts/seed-demo-user.mjs", "scripts/seed-live-replay-leaderboards.mjs"]) {
    const source = readFileSync(resolve(REPO_ROOT, script), "utf8");

    assert.match(
      source,
      /import\s*\{[^}]*firstAscentSeedFields[^}]*\}\s*from\s*["'][^"']*live-replay-first-ascent\.mjs["']/,
      `${script} must build First Ascent fields through the shared module`
    );

    for (const field of FIRST_ASCENT_FIELD_NAMES) {
      assert.doesNotMatch(
        source,
        new RegExp(`${field}\\s*:`),
        `${script} re-declares ${field} instead of using firstAscentSeedFields`
      );
    }
  }
});

test("holder detection matches the predicate the server claims against", () => {
  // canClaimFirstAscent keys off leaderboardHasFirstAscent, so reading the state
  // any other way would pass a summary the server would refuse to hand over.
  const source = readFileSync(
    resolve(REPO_ROOT, "functions/src/liveReplayLeaderboard.ts"),
    "utf8"
  );
  const predicateBody = source.match(
    /function leaderboardHasFirstAscent\([\s\S]*?\n\}/
  )?.[0];
  assert.ok(predicateBody, "could not locate leaderboardHasFirstAscent in the Cloud Function");

  const serverFields = [...new Set(
    [...predicateBody.matchAll(/data\.(firstAscent\w+)/g)].map((match) => match[1])
  )].sort();

  assert.deepEqual(serverFields, ["firstAscentCompletedAt", "firstAscentUserId"]);

  assert.equal(summaryHasFirstAscent(undefined), false);
  assert.equal(summaryHasFirstAscent({}), false);
  assert.equal(summaryHasFirstAscent({firstAscentUserId: ""}), false);
  assert.equal(summaryHasFirstAscent({firstAscentUserId: "user-1"}), true);
  assert.equal(summaryHasFirstAscent({firstAscentCompletedAt: new Date()}), true);
  assert.equal(
    summaryHasFirstAscent(firstAscentSeedFields(attempt, new Date("2026-01-01T00:00:00Z"))),
    true
  );
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

test("the assert and the audit report against one definition of the contract", () => {
  // The seed throws while building its plan and the audit accumulates failures.
  // That is a difference in reporting, not in what counts as valid.
  const dead = {climbId: "mount-everest", completedCount: 89, hasFirstAscent: false};

  assert.match(firstAscentInvariantFailure(dead), /no First Ascent holder/);
  assert.throws(() => assertFirstAscentInvariant(dead), new RegExp(firstAscentInvariantFailure(dead)));

  assert.equal(
    firstAscentInvariantFailure({climbId: "mount-everest", completedCount: 89, hasFirstAscent: true}),
    null
  );
  assert.equal(
    firstAscentInvariantFailure({climbId: "sky-tower-auckland", completedCount: 0, hasFirstAscent: false}),
    null
  );
});

test("a summary is open only with zero completions and no holder", () => {
  assert.equal(isOpenFirstAscentSummary({completedCount: 0, hasFirstAscent: false}), true);
  assert.equal(isOpenFirstAscentSummary({completedCount: 89, hasFirstAscent: true}), false);
  assert.equal(isOpenFirstAscentSummary({completedCount: 0, hasFirstAscent: true}), false);
  assert.equal(isOpenFirstAscentSummary({completedCount: 89, hasFirstAscent: false}), false);
});

test("a QA climber claiming a seeded open slot reads as held, not open", () => {
  // Sky Tower is seeded cheapest so a QA session can finish it and claim the
  // First Ascent end to end. The server merges the completion and the holder but
  // never resets activityTier, so the summary keeps reading tier "open" while
  // being legitimately held - auditing the tier would fail the one flow the
  // fixture exists for.
  const claimed = {
    activityTier: "open",
    completedCount: 1,
    ...firstAscentSeedFields(attempt, new Date("2026-02-01T00:00:00Z")),
  };
  const state = {
    climbId: "sky-tower-auckland",
    completedCount: claimed.completedCount,
    hasFirstAscent: summaryHasFirstAscent(claimed),
  };

  assert.equal(isOpenFirstAscentSummary(state), false);
  assert.equal(firstAscentInvariantFailure(state), null);
});

// Split buckets holding entries keyed the way the Cloud Function keys them: by
// workoutId, one document per bucket. `entries` deliberately exposes no `where`,
// so a seedPackId-filtered read throws rather than quietly skipping the real
// climber rows this clear exists to remove.
function fakeSplitBuckets(bucketsById) {
  return {
    listDocuments: async () => Object.entries(bucketsById).map(([bucketId, entryIds]) => ({
      id: bucketId,
      collection: (name) => {
        assert.equal(name, "entries", "open climbs must clear the entries collection");
        return {
          get: async () => ({
            docs: entryIds.map((entryId) => ({
              id: entryId,
              ref: {path: `splitBuckets/${bucketId}/entries/${entryId}`},
            })),
          }),
        };
      },
    })),
  };
}

test("clearing an open First Ascent climb deletes every entry in every bucket", async () => {
  // The Cloud Function writes one entry per split bucket, so a QA climber who
  // claims the seeded open slot leaves rows well past bucket zero. Clearing only
  // bucket zero would green the audit - it inspects bucket zero alone - while the
  // phantom opponent still shows up mid-race.
  const deletedPaths = [];
  const writer = {delete: (ref) => deletedPaths.push(ref.path)};

  const deleted = await clearOpenFirstAscentEntries(
    fakeSplitBuckets({0: ["qa-workout-1"], 7: ["qa-workout-1"], 14: ["qa-workout-1"]}),
    writer
  );

  assert.equal(deleted, 3);
  assert.deepEqual(deletedPaths, [
    "splitBuckets/0/entries/qa-workout-1",
    "splitBuckets/7/entries/qa-workout-1",
    "splitBuckets/14/entries/qa-workout-1",
  ]);
});

test("clearing an open First Ascent climb reports zero when nothing was seeded", async () => {
  const writer = {delete: () => assert.fail("nothing to delete")};

  assert.equal(await clearOpenFirstAscentEntries(fakeSplitBuckets({}), writer), 0);
});

test("the seed clears open First Ascent climbs by query, not by seeded ID", () => {
  // A real climber's entry IDs are their workoutId and are unknown to the seed,
  // and an open climb seeds zero attempts, so `clearAttemptIds` is empty for it.
  // Delete-by-seeded-id therefore deletes nothing and re-seeding strands the
  // claimed rows next to a summary reset to zero completions.
  const source = readScript("scripts/seed-live-replay-leaderboards.mjs");
  const clearBody = source.match(
    /async function clearSeedEntriesFromPlan\([\s\S]*?\n\}/
  )?.[0];
  assert.ok(clearBody, "could not locate clearSeedEntriesFromPlan in the seed script");

  assert.match(
    clearBody,
    /isOpenFirstAscentSummary\(/,
    "the clear path must branch on the plan's First Ascent state"
  );
  assert.match(
    clearBody,
    /clearOpenFirstAscentEntries\(/,
    "open climbs must have their entries cleared by query"
  );
});

test("the audit reads the First Ascent state off the data, not activityTier", () => {
  // activityTier is stale by design: the seed writes it once and the Cloud
  // Function's summary merge never resets it.
  const source = readScript("scripts/audit-seed-data.mjs");

  assert.match(source, /isOpenFirstAscentSummary\(/);
  assert.match(source, /firstAscentInvariantFailure\(/);
  assert.doesNotMatch(
    source,
    /\.activityTier\b/,
    "the audit must not read activityTier off a summary"
  );
});
