import test from "node:test";
import assert from "node:assert/strict";

import {
  attemptStanding,
  buildCompletionSnapshots,
  climberStanding,
  collapsesRepeatFinishers,
} from "../backfill-live-replay-completion-snapshots.mjs";

// A repaired snapshot is permanent and write-once, so this script has to order a
// board on the metric that board actually ranks on. A routine fixes the clock
// and ranks on steps; assuming duration everywhere froze a routine field in an
// order the board itself contradicts.
function entry(overrides) {
  return {
    completionDurationSeconds: 700,
    completionMillis: 1_000,
    contextId: "cn-tower",
    contextType: "live_climb",
    finalSteps: 2_096,
    rankedAt: null,
    targetStepCount: 2_096,
    userId: "climber-1",
    workoutId: "workout-1",
    ...overrides,
  };
}

test("collapses repeats on the boards the server collapses them on", () => {
  assert.equal(collapsesRepeatFinishers("live_climb"), true);
  assert.equal(collapsesRepeatFinishers("routine_template"), true);
  assert.equal(collapsesRepeatFinishers("just_climb"), false);
  assert.equal(collapsesRepeatFinishers("routine"), false);
});

test("a climb board ranks its climbers on the fastest clock", () => {
  const rival = entry({userId: "rival", completionDurationSeconds: 640});
  const own = entry({workoutId: "workout-2", completionDurationSeconds: 700});

  assert.deepEqual(
    climberStanding([rival, own], own),
    {completedCount: 2, rank: 2}
  );
});

test("a routine board ranks its climbers on the most steps", () => {
  // 1,900 steps beats 1,840 on a routine. Ordered on duration instead, the
  // rival's slower-but-taller run would have read as behind this one.
  const rival = entry({
    contextType: "routine_template",
    contextId: "social-pyramid-20",
    userId: "rival",
    finalSteps: 1_900,
    completionDurationSeconds: 1_200,
  });
  const own = entry({
    contextType: "routine_template",
    contextId: "social-pyramid-20",
    workoutId: "workout-2",
    finalSteps: 1_840,
    completionDurationSeconds: 900,
  });

  assert.deepEqual(
    climberStanding([rival, own], own),
    {completedCount: 2, rank: 2}
  );
});

test("a climber's own slower repeat never seats them behind themselves", () => {
  const faster = entry({completionDurationSeconds: 640});
  const slower = entry({workoutId: "workout-2", completionDurationSeconds: 700});

  assert.deepEqual(
    climberStanding([faster, slower], slower),
    {completedCount: 1, rank: 1}
  );
});

test("climbers tied on a routine's steps share a rank", () => {
  const rival = entry({
    contextType: "routine_template",
    userId: "rival",
    finalSteps: 1_840,
  });
  const own = entry({
    contextType: "routine_template",
    workoutId: "workout-2",
    finalSteps: 1_840,
  });

  assert.deepEqual(
    climberStanding([rival, own], own),
    {completedCount: 2, rank: 1}
  );
});

test("a board that races attempts ranks them on its own metric too", () => {
  const taller = entry({
    contextType: "routine",
    userId: "rival",
    finalSteps: 1_900,
  });
  const own = entry({
    contextType: "routine",
    workoutId: "workout-2",
    finalSteps: 1_840,
  });

  assert.deepEqual(
    attemptStanding([taller, own], own),
    {completedCount: 2, rank: 2}
  );
  assert.deepEqual(
    attemptStanding(
      [entry({userId: "rival", completionDurationSeconds: 640}), entry()],
      entry()
    ),
    {completedCount: 2, rank: 2}
  );
});

test("a snapshot records the metric and tie policy its board ranks on", () => {
  const [climb] = buildCompletionSnapshots([entry()]);
  const [routine] = buildCompletionSnapshots([
    entry({contextType: "routine_template"}),
  ]);

  assert.equal(climb.rankingMetric, "completionDurationSeconds");
  assert.equal(climb.tiePolicy, "competition_rank_equal_durations_share_rank");
  assert.equal(routine.rankingMetric, "finalSteps");
  assert.equal(routine.tiePolicy, "competition_rank_equal_steps_share_rank");
});
