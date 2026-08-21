/**
 * The fan-out primitive both the climb-drop claim and dead-token pruning
 * depend on. Two properties carry all of it: the number in flight is bounded,
 * and one item's failure costs only that item.
 */

import test from "node:test";
import assert from "node:assert/strict";
import {runWithBoundedConcurrency} from "../src/concurrency.js";

test("no more than the limit is ever in flight", async () => {
  const items = Array.from({length: 50}, (_unused, index) => index);
  let inFlight = 0;
  let peak = 0;

  await runWithBoundedConcurrency(items, 5, async () => {
    inFlight += 1;
    peak = Math.max(peak, inFlight);
    await new Promise((resolve) => setTimeout(resolve, 1));
    inFlight -= 1;
  });

  assert.ok(peak <= 5, `peak concurrency was ${peak}`);
  assert.ok(peak > 1, "the work must actually run concurrently");
});

test("every item runs even when some of them fail", async () => {
  const items = ["a", "b", "c", "d", "e"];
  const attempted: string[] = [];

  const failures = await runWithBoundedConcurrency(items, 2, async (item) => {
    attempted.push(item);
    if (item === "b" || item === "d") {
      throw new Error(`${item} refused`);
    }
  });

  assert.deepEqual(attempted.sort(), items);
  assert.deepEqual(failures.map((failure) => failure.item).sort(), ["b", "d"]);
  assert.deepEqual(
    failures.map((failure) => (failure.error as Error).message).sort(),
    ["b refused", "d refused"]
  );
});

test("a failing item never rejects the whole fan-out", async () => {
  const failures = await runWithBoundedConcurrency([1], 4, async () => {
    throw new Error("refused");
  });

  assert.equal(failures.length, 1);
});

test("an empty work list does nothing and reports nothing", async () => {
  let ran = 0;

  const failures = await runWithBoundedConcurrency([], 4, async () => {
    ran += 1;
  });

  assert.equal(ran, 0);
  assert.deepEqual(failures, []);
});
