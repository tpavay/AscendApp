import assert from "node:assert/strict";
import test from "node:test";
import {
  FREE_WEEK_REMOTE_CONFIG_KEY,
  FREE_WEEK_SWITCH_CACHE_MS,
  makeCachedFreeWeekSwitch,
  readFreeWeekSwitch,
} from "../src/revenueCat/freeWeekGrant.js";

function template(parameter: unknown): unknown {
  return {parameters: {[FREE_WEEK_REMOTE_CONFIG_KEY]: parameter}};
}

test("the switch is the rollout the app reads", () => {
  assert.equal(FREE_WEEK_REMOTE_CONFIG_KEY, "free_week_after_decline_enabled");
});

test("an absent or false switch grants nothing", () => {
  assert.equal(readFreeWeekSwitch(null), false);
  assert.equal(readFreeWeekSwitch({}), false);
  assert.equal(readFreeWeekSwitch({parameters: {}}), false);
  assert.equal(
    readFreeWeekSwitch(template({defaultValue: {value: "false"}})),
    false
  );
  assert.equal(
    readFreeWeekSwitch(template({defaultValue: {useInAppDefault: true}})),
    false
  );
});

test("a true default turns the switch on", () => {
  assert.equal(
    readFreeWeekSwitch(template({defaultValue: {value: "true"}})),
    true
  );
  assert.equal(
    readFreeWeekSwitch(template({defaultValue: {value: true}})),
    true
  );
});

test("a staged rollout through a condition is not refused by the server", () => {
  assert.equal(
    readFreeWeekSwitch(template({
      defaultValue: {value: "false"},
      conditionalValues: {"Ten percent": {value: "true"}},
    })),
    true
  );
  assert.equal(
    readFreeWeekSwitch(template({
      defaultValue: {value: "false"},
      conditionalValues: {Internal: {value: "false"}},
    })),
    false
  );
});

test("the template is read once per cache window", async () => {
  let reads = 0;
  let nowMs = 1_000_000;
  const isEnabled = makeCachedFreeWeekSwitch(
    async () => {
      reads += 1;
      return template({defaultValue: {value: "true"}});
    },
    () => new Date(nowMs)
  );

  assert.equal(await isEnabled(), true);
  assert.equal(await isEnabled(), true);
  nowMs += FREE_WEEK_SWITCH_CACHE_MS - 1;
  assert.equal(await isEnabled(), true);
  assert.equal(reads, 1);

  nowMs += 1;
  assert.equal(await isEnabled(), true);
  assert.equal(reads, 2);
});

test("a switch that cannot be read is off, and is asked again next time", async () => {
  let reads = 0;
  const isEnabled = makeCachedFreeWeekSwitch(
    async () => {
      reads += 1;
      if (reads === 1) {
        throw new Error("remote config unavailable");
      }
      return template({defaultValue: {value: "true"}});
    },
    () => new Date(1_000_000)
  );

  assert.equal(await isEnabled(), false);
  assert.equal(await isEnabled(), true);
  assert.equal(reads, 2);
});
