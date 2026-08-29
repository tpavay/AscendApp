import test from "node:test";
import assert from "node:assert/strict";

import {readFileSync} from "node:fs";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";

import {
  attemptStanding,
  buildCompletionSnapshots,
  climberStanding,
  collapsesRepeatFinishers,
  ranksOnSteps,
} from "../backfill-live-replay-completion-snapshots.mjs";

const SERVER_SOURCE = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../functions/src/liveReplayLeaderboard.ts"
);
const CONTEXT_TYPES = [
  "live_climb",
  "just_climb",
  "routine_template",
  "routine",
];

// A repaired snapshot is permanent and write-once, so this script has to order a
// board on the metric the publish path ranks that board on. A routine template
// fixes the clock and ranks on steps; every other board, a plain routine
// included, ranks on the clock. Ordering by either answer alone freezes a
// permanent order the board itself contradicts.
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

test("a plain routine board races its attempts on the clock", () => {
  // The server ranks `routine` on duration, not steps - only `routine_template`
  // ranks on steps. A rival who took more steps but longer is behind, and a
  // repair that ordered this board on steps would rewrite a correct one.
  const tallerButSlower = entry({
    contextType: "routine",
    userId: "rival",
    finalSteps: 1_900,
    completionDurationSeconds: 900,
  });
  const own = entry({
    contextType: "routine",
    workoutId: "workout-2",
    finalSteps: 1_840,
    completionDurationSeconds: 700,
  });

  assert.deepEqual(
    attemptStanding([tallerButSlower, own], own),
    {completedCount: 2, rank: 1}
  );
});

test("an open Just Climb races its attempts on the clock", () => {
  assert.deepEqual(
    attemptStanding(
      [
        entry({contextType: "just_climb", userId: "rival", completionDurationSeconds: 640}),
        entry({contextType: "just_climb"}),
      ],
      entry({contextType: "just_climb"})
    ),
    {completedCount: 2, rank: 2}
  );
});

test("a snapshot records the metric and tie policy its board ranks on", () => {
  const [climb] = buildCompletionSnapshots([entry()]);
  const [template] = buildCompletionSnapshots([
    entry({contextType: "routine_template"}),
  ]);
  const [routine] = buildCompletionSnapshots([entry({contextType: "routine"})]);

  assert.equal(climb.rankingMetric, "completionDurationSeconds");
  assert.equal(climb.tiePolicy, "competition_rank_equal_durations_share_rank");
  assert.equal(template.rankingMetric, "finalSteps");
  assert.equal(template.tiePolicy, "competition_rank_equal_steps_share_rank");
  // The stamp a `--force` repair rewrites has to match the one the publish path
  // froze, or the two disagree about what the rank beside it even means.
  assert.equal(routine.rankingMetric, "completionDurationSeconds");
  assert.equal(routine.tiePolicy, "competition_rank_equal_durations_share_rank");
});

/**
 * Reads the context types the server's own `ranksOnSteps` returns true for.
 *
 * Parsed from the source rather than restated, so this guard cannot go stale by
 * agreeing with a copy of the rule instead of the rule.
 * @return {Set<string>} Context types the server ranks on steps.
 */
function serverStepsRankedContextTypes() {
  const source = readFileSync(SERVER_SOURCE, "utf8");
  const body = source.match(
    /function ranksOnSteps\(contextType: string\): boolean \{([\s\S]*?)\n\}/
  );
  assert.ok(body, "Could not find ranksOnSteps in the server source.");

  const constants = new Map(
    [...source.matchAll(/^const ([A-Z_]+_CONTEXT_TYPE) = "([a-z_]+)";$/gm)]
      .map(([, name, value]) => [name, value])
  );
  const named = [...body[1].matchAll(/contextType === ([A-Z_]+_CONTEXT_TYPE)/g)]
    .map(([, name]) => constants.get(name));
  assert.ok(
    named.length > 0 && named.every((value) => value !== undefined),
    "Could not resolve the context types the server ranks on steps."
  );

  return new Set(named);
}

// This script is the repair path and rewrites permanent snapshots over every
// board unless --context-key scopes it, so it must never disagree with the
// publish path about which metric a board ranks on. Parsing the server's own
// predicate is what makes this fail if either side is changed alone - which is
// how a plain `routine` came to be ordered on steps here while the server froze
// it on the clock.
test("the repair path ranks on exactly the metric the server ranks on", () => {
  const serverStepsRanked = serverStepsRankedContextTypes();

  assert.deepEqual(serverStepsRanked, new Set(["routine_template"]));
  for (const contextType of CONTEXT_TYPES) {
    assert.equal(
      ranksOnSteps(contextType),
      serverStepsRanked.has(contextType),
      `${contextType} ranks on a different metric than the publish path.`
    );
  }
});
