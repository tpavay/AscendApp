import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {test} from "node:test";
import {fileURLToPath} from "node:url";

import {
  DURATION_BEST_METRIC,
  STEPS_BEST_METRIC,
  syntheticFinisherWrite,
} from "../seed/lib/live-replay-finisher.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

const ATTEMPT = {
  avatarToken: "ZT",
  completionDurationSeconds: 738,
  displayName: "Zara T.",
  finalSteps: 2_096,
  id: "seed_live-replay-v1-dev_canton-tower_0000",
  photoURL: null,
  userId: "seeded:live-replay-v1-dev:canton-tower:0",
};

test("a seeded climb finisher carries the clock its board ranks on", () => {
  const updatedAt = {kind: "server-timestamp"};
  const finisher = syntheticFinisherWrite(ATTEMPT, {
    contextType: "live_climb",
    globalCompletionOrder: 4,
    identityState: "published",
    schemaVersion: 1,
    seedPackId: "live-replay-v1-dev",
    updatedAt,
  });

  // The frozen completion rank counts finishers through an inequality on this
  // field. A finisher missing it is invisible to that count, and the seeded
  // board it sits on would seat a mid-field climber first.
  assert.equal(finisher[DURATION_BEST_METRIC], 738);
  assert.equal(finisher.bestWorkoutId, ATTEMPT.id);
  assert.equal(finisher.userId, ATTEMPT.userId);
  assert.equal(finisher.globalCompletionOrder, 4);
  assert.equal(finisher.isSynthetic, true);
  assert.equal(finisher.photoURL, "");
  assert.equal(finisher.updatedAt, updatedAt);
  // A climb lets the clock vary, so a "best steps" here would read as a target
  // on a board where every finisher takes the same number of steps.
  assert.equal(STEPS_BEST_METRIC in finisher, false);
});

test("a seeded routine finisher carries the steps its intervals rank on", () => {
  const finisher = syntheticFinisherWrite(ATTEMPT, {
    contextType: "routine_template",
    globalCompletionOrder: 1,
    identityState: "published",
    schemaVersion: 1,
    seedPackId: "live-replay-v1-dev",
    updatedAt: {kind: "server-timestamp"},
  });

  assert.equal(finisher[STEPS_BEST_METRIC], 2_096);
  assert.equal(DURATION_BEST_METRIC in finisher, false);
});

test("the seed writes a finisher for every board it seeds entries onto", () => {
  const source = readFileSync(
    `${repositoryRoot}scripts/seed-live-replay-leaderboards.mjs`,
    "utf8"
  );

  // Seeded dev and staging boards carried entries and no finishers at all, so a
  // finishers-based numerator read every one of them as an empty field. Both
  // contexts the seed publishes into have to write one - which they now do
  // through a single writer, so what this pins is that both contexts reach it.
  assert.match(source, /finishersRef: finishersCollection\(db, plan\.climb\.id\)/);
  assert.match(source, /finishersRef: justClimbFinishersCollection\(db\)/);
  assert.match(source, /context\.finishersRef\.doc\(attempt\.userId\)/);
  // And clearing a pack has to take them back out, or a re-seed leaves a
  // stranded climber ahead of the next one.
  assert.match(source, /doomedFinishers/);
  assert.match(source, /finishers\.filter\(\(document\) => isSyntheticUserId\(document\.id\)\)/);
});

test("the seed's best-metric fields are the ones the Cloud Function counts", () => {
  // The numerator behind a frozen rank is an inequality on exactly these
  // fields. A server-side rename would leave every seeded finisher invisible to
  // it and quietly return dev and staging boards to the "1st of 84" state.
  const source = readFileSync(
    `${repositoryRoot}functions/src/liveReplayLeaderboard.ts`,
    "utf8"
  );

  for (const [constant, seedValue] of [
    ["DURATION_BEST_METRIC", DURATION_BEST_METRIC],
    ["STEPS_BEST_METRIC", STEPS_BEST_METRIC],
  ]) {
    const serverValue = source.match(
      new RegExp(`const ${constant} = "([^"]+)"`)
    )?.[1];
    assert.ok(
      serverValue,
      `could not locate ${constant} in the Cloud Function`
    );
    assert.equal(serverValue, seedValue);
  }
});
