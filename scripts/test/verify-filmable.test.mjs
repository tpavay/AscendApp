import assert from "node:assert/strict";
import {test} from "node:test";

import {bucketSampleIndices, rankedRows} from "../verify-filmable.mjs";

test("a bucket sample always counts the base and the summit", () => {
  const samples = bucketSampleIndices(272, 9);

  assert.equal(samples[0], 0);
  assert.equal(samples.at(-1), 272);
  assert.equal(samples.length, 9);
  assert.deepEqual(samples, [...samples].sort((lhs, rhs) => lhs - rhs));
});

test("a short board samples every bucket it has rather than repeating one", () => {
  assert.deepEqual(bucketSampleIndices(0, 9), [0]);
  assert.deepEqual(bucketSampleIndices(3, 9), [0, 1, 2, 3]);
  assert.deepEqual(bucketSampleIndices(2, 2), [0, 2]);
});

test("the gap between samples bounds how much of a climb can hide between them", () => {
  const samples = bucketSampleIndices(360, 9);

  for (const [index, bucket] of samples.slice(1).entries()) {
    assert.ok(
      bucket - samples[index] <= Math.ceil(360 / 8),
      `buckets ${samples[index]} and ${bucket} are further apart than one eighth of the climb`
    );
  }
});

test("leaderboard rows collapse to one per climber and re-sort on the metric", () => {
  const rows = [
    {userId: "b", totalSteps: 500, stepsPerMinute: 90},
    {userId: "a", totalSteps: 900, stepsPerMinute: 40},
    {userId: "b", totalSteps: 100, stepsPerMinute: 10},
    {userId: "c", totalSteps: 900, stepsPerMinute: 70},
  ];

  assert.deepEqual(
    rankedRows(rows, "climb").map((row) => row.userId),
    ["a", "c", "b"],
    "a repeated climber must not fill two rows, and ties break on userId"
  );
  assert.deepEqual(
    rankedRows(rows, "pace").map((row) => row.userId),
    ["b", "c", "a"],
    "a different metric is a different podium"
  );
});

test("an unknown metric still produces a stable order rather than throwing", () => {
  const rows = [
    {userId: "a", totalSteps: 100},
    {userId: "b", totalSteps: 200},
  ];

  assert.deepEqual(rankedRows(rows, "unknown").map((row) => row.userId), ["b", "a"]);
});
