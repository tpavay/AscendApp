import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {isRecoverableLegacyCompletion} from "../src/legacyClimbCompletion.js";
import {liveReplayLeaderboardTestHooks} from "../src/liveReplayLeaderboard.js";

interface VectorCase {
  name: string;
  source: string;
  climbId: string | null;
  stopReason: string;
  steps: number;
  targetStepCount: number | null;
  expected: boolean;
}

// Compiled output is CommonJS (see tsconfig NodeNext + no package "type"), so
// __dirname is the compiled lib/test directory; walk up to the repo root.
const vectorPath = join(
  __dirname,
  "../../../SharedTestVectors/legacy-recoverable-completion-vector.json"
);
const vector = JSON.parse(readFileSync(vectorPath, "utf8")) as {
  cases: VectorCase[];
};

test("TS predicate matches the shared parity vector", () => {
  assert.ok(vector.cases.length >= 10, "vector should carry every shape");

  for (const testCase of vector.cases) {
    const actual = isRecoverableLegacyCompletion({
      source: testCase.source,
      climbId: testCase.climbId,
      stopReason: testCase.stopReason,
      steps: testCase.steps,
      targetStepCount: testCase.targetStepCount,
    });
    assert.equal(
      actual,
      testCase.expected,
      `case ${testCase.name} expected ${testCase.expected}`
    );
  }
});

test("publishes a legacy landmark completion without First Ascent", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeLegacyWorkoutDocument(),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload?.contextId, "burj-khalifa");
  assert.equal(payload?.firstAscentEligible, false);
});

test("does not publish a legacy backup that missed its target", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeLegacyWorkoutDocument({stopReason: "user_stopped"}),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload, null);
});

/**
 * Builds a legacy Live Climb backup: headphone-motion, a landmark climbId, no
 * trackingMode and no target key, and no participation - the shape a reinstall
 * downloads for a pre-participation completion.
 * @param {Record<string, unknown>} metadataOverrides Metadata overrides.
 * @return {Record<string, unknown>} Legacy workout backup document.
 */
function makeLegacyWorkoutDocument(
  metadataOverrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    durationSeconds: 900,
    source: "headphone_motion",
    steps: 2909,
    sourceMetadata: JSON.stringify({
      climbId: "burj-khalifa",
      splitIntervalSeconds: 10,
      splitSteps: [0, 400, 900, 1500, 2100, 2909],
      stopReason: "target_reached",
      ...metadataOverrides,
    }),
  };
}
