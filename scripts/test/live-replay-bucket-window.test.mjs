import test from "node:test";
import assert from "node:assert/strict";
import {justClimbBucketLimit} from "../seed/lib/live-replay-bucket-window.mjs";

test("the seeded Just Climb board reaches its slowest rival's finish", () => {
  // The slowest seeded rival on staging climbed for 1:40:00. A window that
  // stopped at 60:00 counted it home at its final steps from 60:10 on.
  const limit = justClimbBucketLimit([
    {durationSeconds: 540},
    {durationSeconds: 6000},
    {durationSeconds: 3599},
  ]);
  assert.equal(limit, 600);
  // Bucket 600 is read at 6,000 s: the rival is there on its own clock.
  assert.ok(limit * 10 >= 6000);
});

test("a board of sprints still publishes a readable window", () => {
  assert.equal(justClimbBucketLimit([{durationSeconds: 45}]), 12);
  assert.equal(justClimbBucketLimit([]), 12);
});
