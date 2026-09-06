import assert from "node:assert/strict";
import {test} from "node:test";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

import {
  REPLAY_SUMMARY_SOURCE_LIVE,
  REPLAY_SUMMARY_SOURCE_SEEDED,
  isSyntheticUserId,
  seededSummarySource,
} from "../seed/lib/live-replay-summary-source.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

test("a board holding only synthetic finishers is seeded", () => {
  assert.equal(
    seededSummarySource({
      survivingFinisherIds: [
        "seeded:live-replay-v1-staging:empire-state-building:0",
        "seeded:live-replay-v1-staging:empire-state-building:1",
      ],
    }),
    REPLAY_SUMMARY_SOURCE_SEEDED
  );
});

test("a board with no finishers at all is seeded", () => {
  assert.equal(
    seededSummarySource({survivingFinisherIds: []}),
    REPLAY_SUMMARY_SOURCE_SEEDED
  );
});

test("one real finisher stops a board calling itself seeded", () => {
  assert.equal(
    seededSummarySource({
      survivingFinisherIds: [
        "seeded:live-replay-v1-staging:taipei-101:0",
        "9M7Cwt2CFGfeOjPglkIhfYcqLKp1",
      ],
    }),
    REPLAY_SUMMARY_SOURCE_LIVE
  );
});

test("only the seeded prefix marks a climber synthetic", () => {
  assert.equal(isSyntheticUserId("seeded:pack:climb:0"), true);
  assert.equal(isSyntheticUserId("seededlooking-real-uid"), false);
  assert.equal(isSyntheticUserId(undefined), false);
});

// The two writers of this field live in different languages, so nothing but a
// test keeps them on the same value. A summary the Cloud Function stamps `live`
// and the seed stamps something else would put the boards back where they were:
// unable to answer whether anyone real is on them.
test("the Cloud Function publishes the same live value the seed reads", () => {
  const source = readFileSync(
    resolve(REPO_ROOT, "functions/src/liveReplayLeaderboard.ts"),
    "utf-8"
  );

  assert.match(
    source,
    new RegExp(`REPLAY_SUMMARY_SOURCE_LIVE = "${REPLAY_SUMMARY_SOURCE_LIVE}"`)
  );
  assert.match(source, /source: REPLAY_SUMMARY_SOURCE_LIVE,/);
});
