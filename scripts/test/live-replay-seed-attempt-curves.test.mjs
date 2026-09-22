import assert from "node:assert/strict";
import {test} from "node:test";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

import {ATTEMPT_CURVES_COLLECTION} from "../lib/live-replay-race-best.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const read = (path) => readFileSync(resolve(REPO_ROOT, path), "utf8");
const SEED = read("scripts/seed-live-replay-leaderboards.mjs");
const DEMO_SEED = read("scripts/seed-demo-user.mjs");
const BACKFILL = read("scripts/backfill-live-replay-best-per-user.mjs");
const SERVER = read("functions/src/liveReplayLeaderboard.ts");

/**
 * @param {string} source File contents.
 * @param {string} name Function name.
 * @return {string} Its body.
 */
function body(source, name) {
  const found = source.match(
    new RegExp(`(?:async )?function ${name}\\([\\s\\S]*?\\n\\}\\n`, "u")
  )?.[0];
  assert.ok(found, `could not locate ${name}`);
  return found;
}

// The server reads a Just Climb attempt's curve from one collection and
// rebuilds it from `stepsAtBucket` when the document is missing - anchored one
// interval late against what a seed judged its goal keys on. Every writer of
// seeded rows has to name the same collection the server and the backfill
// read, or the first reconciliation over a seeded board rewrites the keys.
test("the seeds, the backfill and the server name one curve collection", () => {
  assert.equal(ATTEMPT_CURVES_COLLECTION, "attemptCurves");
  assert.match(SERVER, /const ATTEMPT_CURVES_COLLECTION = "attemptCurves";/);
  assert.match(BACKFILL, /const ATTEMPT_CURVES_COLLECTION = "attemptCurves";/);
  assert.match(SEED, /ATTEMPT_CURVES_COLLECTION,\n  attemptCurveWrite,/);
  assert.match(DEMO_SEED, /import \{ATTEMPT_CURVES_COLLECTION\} from "\.\/lib\/live-replay-race-best\.mjs";/);
});

test("the pack seed stores each Just Climb curve beside its rows", () => {
  const write = SEED.slice(SEED.indexOf("async function writeSeedPlan("));

  assert.match(
    write,
    /writer\.set\(\n\s+context\.attemptCurvesRef\.doc\(attempt\.id\),\n\s+attemptCurveWrite\(attempt\.userId, curve, now\)\n\s+\);/,
    "a seeded Just Climb row's curve has to land in attemptCurves"
  );
  assert.match(
    body(SEED, "raceCurvesByAttemptId"),
    /splitSteps: series\.slice\(1\)/,
    "bucket 0 is the start line, so the stored curve is anchored from bucket 1"
  );
  assert.match(
    body(SEED, "goalKeysByAttemptId"),
    /curvesByAttemptId\.get\(attempt\.id\)/,
    "the goal keys have to be judged on the curves that are stored"
  );
  assert.match(
    body(SEED, "contextFingerprint"),
    /SEED_WRITE_REVISION/,
    "a board seeded before curves existed has to be rewritten with them"
  );
});

test("the pack seed retires and clears its curve documents with its rows", () => {
  assert.match(
    body(SEED, "retiredRowRefs"),
    /context\.attemptCurvesRef\.listDocuments\(\)/
  );
  assert.match(
    body(SEED, "seededDocumentsUnder"),
    /contextRef\.collection\(ATTEMPT_CURVES_COLLECTION\)\.listDocuments\(\)/
  );
});

test("the demo seed stores and clears its Just Climb curve", () => {
  assert.match(
    body(DEMO_SEED, "addReplayWrites"),
    /leaderboardRef\.collection\(ATTEMPT_CURVES_COLLECTION\)\.doc\(context\.workoutId\),\n\s+curveWrite,/
  );
  assert.match(
    body(DEMO_SEED, "addReplayClearWrites"),
    /deletes\.push\(leaderboardRef\.collection\(ATTEMPT_CURVES_COLLECTION\)\.doc\(entryId\)\);/
  );
});
