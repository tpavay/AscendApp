import assert from "node:assert/strict";
import {test} from "node:test";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const SOURCE = readFileSync(
  resolve(REPO_ROOT, "scripts/seed-live-replay-leaderboards.mjs"),
  "utf8"
);

/**
 * @param {string} name Function name.
 * @return {string} Its body.
 */
function body(name) {
  const found = SOURCE.match(new RegExp(`function ${name}\\([\\s\\S]*?\\n\\}\\n`, "u"))?.[0];
  assert.ok(found, `could not locate ${name} in the seed script`);
  return found;
}

// A repeat seed is 520,784 identical writes unless it can tell that a board
// already holds them. That is worth about three minutes a run, so it is worth a
// guard: every input the entries depend on has to be inside the hash.
test("the fingerprint is taken over the step values, not the parameters behind them", () => {
  const fingerprint = body("contextFingerprint");

  assert.match(
    fingerprint,
    /series\.join\(","\)/,
    "hashing the curve parameters instead of the values it produces means a " +
    "change to stepsAtBucketIndex leaves every board looking unchanged"
  );
  for (const field of [
    "attempt.id",
    "attempt.userId",
    "attempt.displayName",
    "attempt.photoURL",
    "attempt.finalSteps",
  ]) {
    assert.ok(fingerprint.includes(field), `${field} reaches an entry but not its fingerprint`);
  }
  assert.match(fingerprint, /SEED_WRITE_REVISION/, "a shape change needs a way to invalidate the hash");
  assert.match(fingerprint, /context\.maxBucketIndex/, "the bucket range decides how many rows exist");
});

// The one ordering that makes the skip safe. A fingerprint written before its
// rows makes an interrupted run look complete to the next one, forever.
test("the fingerprint is stamped after the rows it describes have landed", () => {
  const write = SOURCE.slice(SOURCE.indexOf("async function writeSeedPlan("));
  const flushBeforeStamp = write.indexOf("await writer.flush();\n    writer.set(context.summaryRef, {");
  const stamp = write.indexOf(`[SEED_FINGERPRINT_FIELD]: context.fingerprint`);

  assert.ok(flushBeforeStamp > 0, "the entry writes are no longer flushed before the fingerprint");
  assert.ok(stamp > flushBeforeStamp, "the fingerprint is stamped before its rows are known to have landed");
});

test("a fingerprint match skips a board, and --force overrides it", () => {
  const write = SOURCE.slice(SOURCE.indexOf("async function writeSeedPlan("));

  assert.match(
    write,
    /if \(!args\.force && previous\[SEED_FINGERPRINT_FIELD\] === context\.fingerprint\)/,
    "the skip must be both fingerprint-driven and overridable"
  );
});

// Clearing the pack has to invalidate the fingerprint, or the next seed looks at
// an emptied board, sees a matching hash, and writes nothing back.
test("clearing a board drops its fingerprint", () => {
  const clear = SOURCE.slice(
    SOURCE.indexOf("async function clearSeedPack("),
    SOURCE.indexOf("function clearableContexts(")
  );

  const drops = [...clear.matchAll(/\[SEED_FINGERPRINT_FIELD\]: FieldValue\.delete\(\)/g)];
  assert.equal(drops.length, 2, "both the per-climb boards and the Just Climb board must drop it");
});
