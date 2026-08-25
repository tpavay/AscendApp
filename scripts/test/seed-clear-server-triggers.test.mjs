import assert from "node:assert/strict";
import {test} from "node:test";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

function read(relativePath) {
  return readFileSync(resolve(REPO_ROOT, relativePath), "utf-8");
}

// Deleting `users/{uid}` fires `cleanupDeletedUserData`, which sweeps every
// subcollection under that user. A seed that deletes the persona root first is
// therefore racing an account-deletion sweep against its own writes, and on
// 2026-08-24 it lost: 376 documents written at 00:30:35 UTC, `public_profile`,
// `profile_stats`, `achievements` and `profile_workouts` deleted for all twelve
// personas at 00:30:40, audit red. A clear still deletes them - there the sweep
// is the point.
test("the profiles seed does not delete persona root user documents", () => {
  const source = read("scripts/seed-test-users.mjs");
  const seedCall = source.match(
    /await commitDeletes\(\s*db,\s*await seedDocumentRefs\(db([^)]*)\)\s*\);\s*await commitWrites/
  );

  assert.ok(seedCall, "the seed no longer clears before writing in a shape this can read");
  assert.match(
    seedCall[1],
    /includeUserDocuments:\s*false/,
    "the seed path must opt out of deleting users/{uid} or it races the deletion sweep"
  );
});

test("the profiles clear still deletes persona root user documents", () => {
  const source = read("scripts/seed-test-users.mjs");
  const clearBlock = source.slice(
    source.indexOf('if (args.command === "clear")'),
    source.indexOf("const avatarURLs =")
  );

  assert.match(clearBlock, /await seedDocumentRefs\(db\)/);
  assert.doesNotMatch(clearBlock, /includeUserDocuments/);
});

// The global Just Climb context carries one row per attempt on every seeded
// climb, so its contents outlive the climb list. Retiring a climb takes its own
// board away but leaves its attempts here under ids the current plan cannot
// name - staging accumulated 424 of them from eight retired climbs.
test("the global Just Climb context is cleared by seed pack, not by derived id", () => {
  const source = read("scripts/seed-live-replay-leaderboards.mjs");
  const clearBlock = source.slice(
    source.indexOf("async function clearJustClimbSeedRows("),
    source.indexOf("async function clearSeedEntriesFromPlan(")
  );

  assert.match(clearBlock, /justClimbEntriesCollection\(db, bucketIndex\)\s*\n?\s*\.where\("seedPackId", "==", seedPackId\)/);
  assert.match(clearBlock, /justClimbFinishersCollection\(db\)\s*\n?\s*\.where\("seedPackId", "==", seedPackId\)/);
});

test("no derived id list survives for the Just Climb context", () => {
  const source = read("scripts/seed-live-replay-leaderboards.mjs");
  const planBlock = source.slice(
    source.indexOf("const justClimbAttempts ="),
    source.indexOf("return {\n    climbPlans,")
  );

  assert.doesNotMatch(
    planBlock,
    /clearAttemptIds|clearUserIds/,
    "a derived id list here is the drift that left 424 rows behind"
  );
});

// Every synthetic row the query-based clear has to find must carry the field it
// filters on, or the clear silently deletes nothing.
test("every seeded Just Climb row carries the seed pack id the clear filters on", () => {
  const source = read("scripts/seed-live-replay-leaderboards.mjs");
  const writeBlock = source.slice(source.indexOf("async function writeSeedPlan("));
  const finisherWrite = writeBlock.slice(
    writeBlock.indexOf("justClimbFinishersCollection(db).doc(attempt.userId)")
  ).slice(0, 400);

  assert.ok(
    writeBlock.includes("justClimbFinishersCollection(db).doc(attempt.userId)"),
    "the seed no longer writes Just Climb finishers in a shape this can read"
  );
  assert.match(finisherWrite, /seedPackId: args\.seedPackId,/);
  assert.match(read("scripts/seed/lib/live-replay-finisher.mjs"), /seedPackId/);
});

// The guard removed when the open set widened from 4 to 32. The old invariant
// (open climbs disjoint from the demo account's) is deliberately false now, so
// this pins the one that replaced it: the wholesale open-board wipe deletes
// every finisher and replay row regardless of who wrote them, so it must never
// reach a board a real climber has finished. A First Ascent is permanent, and
// staging is raced by TestFlight testers.
test("an open board a real climber finished is never cleared or rewritten", () => {
  const source = read("scripts/seed-live-replay-leaderboards.mjs");

  assert.match(
    source,
    /async function claimedOpenClimbIds\(/,
    "nothing identifies open boards a real climber has already finished"
  );
  assert.match(
    source,
    /finishers\.some\(\(document\) => !isSyntheticUserId\(document\.id\)\)/,
    "claimed boards must be detected by a non-synthetic finisher id"
  );

  const clearBlock = source.slice(
    source.indexOf("async function clearSeedEntriesFromPlan(")
  ).slice(0, 1200);
  assert.match(
    clearBlock,
    /claimedOpen\.has\(plan\.climb\.id\)/,
    "the clear must skip a board a real climber has finished"
  );

  const writeBlock = source.slice(source.indexOf("async function writeSeedPlan("));
  assert.match(
    writeBlock.slice(0, 1500),
    /claimedOpen\.has\(plan\.climb\.id\)/,
    "the write must skip a board a real climber has finished"
  );
});

// Deleting users/{uid} fires cleanupDeletedUserData about five seconds later. A
// clear that returns immediately hands back an environment with that delete
// still in flight, so a seed started inside the window loses its fresh writes -
// the failure that red-lit the first end-to-end run, reachable again through
// clear-then-seed.
test("the profiles clear waits for the account-deletion sweep to drain", () => {
  const source = read("scripts/seed-test-users.mjs");
  const clearBlock = source.slice(
    source.indexOf('if (args.command === "clear")'),
    source.indexOf("const avatarURLs =")
  );

  assert.match(clearBlock, /await waitForDeletionSweep\(db\)/);
  assert.match(source, /async function waitForDeletionSweep\(/);
  assert.match(
    source,
    /SWEPT_SUBCOLLECTIONS = \[[^\]]*"public_profile"[^\]]*"profile_stats"/s,
    "the drain check must poll the subcollections the sweep owns"
  );
});
