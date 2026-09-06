import assert from "node:assert/strict";
import {test} from "node:test";

import {
  DEFAULT_TIMEOUT_MS,
  FirestoreCallTimeoutError,
  MAX_BATCH_WRITES,
  createBatchWriter,
  createProgressReporter,
  listDocumentsAcross,
  runPool,
  withRetry,
  withTimeout,
} from "../lib/firestore-bulk.mjs";

/**
 * A Firestore stand-in that records what it was asked to commit.
 * @param {object} [behavior] Per-commit behavior.
 * @return {object} Fake db and its record.
 */
function fakeDb({failFirst = 0, failWith = {code: 10, message: "contention"}, hang = false} = {}) {
  const commits = [];
  let failures = 0;

  return {
    commits,
    batch() {
      const operations = [];
      return {
        set: (ref, data, options) => operations.push({kind: "set", path: ref.path, data, options}),
        update: (ref, data) => operations.push({kind: "update", path: ref.path, data}),
        delete: (ref) => operations.push({kind: "delete", path: ref.path}),
        commit: () => {
          if (hang) return new Promise(() => {});
          if (failures < failFirst) {
            failures += 1;
            return Promise.reject(Object.assign(new Error(failWith.message), {code: failWith.code}));
          }
          commits.push(operations);
          return Promise.resolve();
        },
      };
    },
  };
}

const ref = (path) => ({path});

test("a call that answers inside its deadline just answers", async () => {
  assert.equal(await withTimeout(() => Promise.resolve("ok"), {description: "read", timeoutMs: 50}), "ok");
});

// The whole point of the module. A `BulkWriter.close()` that never settles is
// indistinguishable from a working seed, so nothing here waits without a clock.
test("a call that never answers rejects rather than parking forever", async () => {
  await assert.rejects(
    withTimeout(() => new Promise(() => {}), {description: "listDocuments(x)", timeoutMs: 20}),
    (error) => {
      assert.ok(error instanceof FirestoreCallTimeoutError);
      assert.match(error.message, /listDocuments\(x\) did not answer within 20ms/);
      return true;
    }
  );
});

test("a retryable failure is retried and a refusal is not", async () => {
  let attempts = 0;
  const value = await withRetry(() => {
    attempts += 1;
    return attempts < 3 ?
      Promise.reject(Object.assign(new Error("contention"), {code: 10})) :
      Promise.resolve("landed");
  }, {description: "commit", timeoutMs: 100});

  assert.equal(value, "landed");
  assert.equal(attempts, 3);

  let refusals = 0;
  await assert.rejects(withRetry(() => {
    refusals += 1;
    return Promise.reject(Object.assign(new Error("nope"), {code: 7}));
  }, {description: "commit", timeoutMs: 100}), /commit failed after 1 attempt\(s\)/);
  assert.equal(refusals, 1, "a refusal on the merits is refused just as firmly on the sixth attempt");
});

test("the failure message names the call, so a failed run says what failed", async () => {
  await assert.rejects(
    withRetry(() => Promise.reject(Object.assign(new Error("boom"), {code: 7})), {
      description: "commit of 500 write(s) starting at a/b/c",
      timeoutMs: 100,
    }),
    /commit of 500 write\(s\) starting at a\/b\/c failed after 1 attempt\(s\): boom/
  );
});

test("the pool keeps every slot busy without queueing every promise at once", async () => {
  const seen = [];
  let live = 0;
  let peak = 0;

  await runPool(Array.from({length: 40}, (_, index) => index), 4, async (item) => {
    live += 1;
    peak = Math.max(peak, live);
    await Promise.resolve();
    seen.push(item);
    live -= 1;
  });

  assert.equal(seen.length, 40);
  assert.ok(peak <= 4, `peak concurrency ${peak} exceeded the pool size`);
});

test("writes are committed in batches no larger than Firestore accepts", async () => {
  const db = fakeDb();
  const writer = createBatchWriter(db, {batchSize: 1_000});

  for (let index = 0; index < 1_100; index += 1) {
    writer.set(ref(`c/${index}`), {index});
  }

  assert.equal(await writer.drain(), 1_100);
  assert.equal(db.commits.length, 3);
  assert.deepEqual(db.commits.map((batch) => batch.length), [MAX_BATCH_WRITES, MAX_BATCH_WRITES, 100]);
  assert.equal(db.commits.flat().length, 1_100);
});

test("a flush commits what is buffered and leaves the queue usable", async () => {
  const db = fakeDb();
  const writer = createBatchWriter(db);

  writer.set(ref("c/1"), {});
  await writer.flush();
  assert.equal(db.commits.length, 1);

  writer.delete(ref("c/2"));
  assert.equal(await writer.drain(), 2);
  assert.equal(db.commits.length, 2);
  assert.deepEqual(db.commits[1], [{kind: "delete", path: "c/2"}]);
});

test("a commit the backend keeps refusing fails the run instead of retrying forever", async () => {
  const db = fakeDb({failFirst: Infinity, failWith: {code: 7, message: "permission denied"}});
  const writer = createBatchWriter(db);
  writer.set(ref("c/1"), {});

  await assert.rejects(writer.drain(), /commit of 1 write\(s\) starting at c\/1 failed/);
});

test("progress counts what landed, not what was queued", async () => {
  const db = fakeDb();
  const progress = createProgressReporter({label: "Seed", total: 700, quiet: true});
  const writer = createBatchWriter(db, {progress});

  for (let index = 0; index < 700; index += 1) {
    writer.set(ref(`c/${index}`), {});
  }
  assert.equal(progress.count(), 0, "nothing has landed until a commit returns");

  await writer.drain();
  assert.equal(progress.count(), 700);
  progress.finish();
});

test("a phase that stops making progress is called wedged rather than waited on", async () => {
  const progress = createProgressReporter({
    label: "Seed",
    stallMs: 5,
    intervalMs: 5,
    quiet: true,
  });

  progress.assertAlive();
  await new Promise((resolve) => {
    setTimeout(resolve, 40);
  });

  assert.ok(progress.stall(), "the watchdog never fired");
  assert.throws(() => progress.assertAlive(), /made no progress/);
  progress.finish();
});

test("listing many collections fans out and returns everything it found", async () => {
  const collections = Array.from({length: 30}, (_, index) => ({
    path: `b/${index}/entries`,
    listDocuments: () => Promise.resolve([ref(`b/${index}/entries/a`), ref(`b/${index}/entries/b`)]),
  }));

  const found = await listDocumentsAcross(collections, {concurrency: 8});
  assert.equal(found.length, 60);
});

test("the default deadline is long enough for a real commit and short enough to notice", () => {
  assert.ok(DEFAULT_TIMEOUT_MS >= 10_000 && DEFAULT_TIMEOUT_MS <= 60_000);
});

// A clear that enumerated 300,000 documents crashed on `doomed.push(...found)`:
// spreading an array into arguments has a ceiling, and the enumeration went
// straight past it. There is no length at which the appender stops working.
test("collecting a fan-out result survives an array longer than the argument limit", async () => {
  const {appendAll} = await import("../lib/firestore-bulk.mjs");
  const huge = new Array(300_000).fill(0).map((_value, index) => index);
  const target = [1, 2];

  assert.throws(() => target.push(...huge), RangeError);
  assert.equal(appendAll(target, huge).length, 300_002);
  assert.equal(target[2], 0);
  assert.equal(target.at(-1), 299_999);
});

// A clear that enumerated 300,000 documents crashed on `doomed.push(...found)`:
// spreading an array into arguments has a ceiling, and the enumeration went
// straight past it. There is no length at which the appender stops working.
test("collecting a fan-out result survives an array longer than the argument limit", async () => {
  const {appendAll} = await import("../lib/firestore-bulk.mjs");
  const huge = new Array(300_000).fill(0).map((_value, index) => index);
  const target = [1, 2];

  assert.throws(() => target.push(...huge), RangeError);
  assert.equal(appendAll(target, huge).length, 300_002);
  assert.equal(target[2], 0);
  assert.equal(target.at(-1), 299_999);
});
