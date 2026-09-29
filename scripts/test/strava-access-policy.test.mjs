import assert from "node:assert/strict";
import test from "node:test";

import {
  DEFAULT_STRAVA_CAPACITY,
  normalizeStravaAccess,
  planStravaAccessChange,
} from "../lib/strava-access-policy.mjs";

const EMPTY = normalizeStravaAccess(undefined);

test("a missing or malformed settings document is off with nobody allowed", () => {
  assert.deepEqual(EMPTY, {enabled: false, allowedUserIds: []});
  assert.deepEqual(normalizeStravaAccess({enabled: "true", allowedUserIds: "abc"}), EMPTY);
  assert.deepEqual(
    normalizeStravaAccess({enabled: true, allowedUserIds: ["b-user-1", "a-user-1", "b-user-1", 3]}),
    {enabled: true, allowedUserIds: ["a-user-1", "b-user-1"]}
  );
});

test("the switch flips on and off, and reports when nothing changes", () => {
  const on = planStravaAccessChange(EMPTY, {command: "enable"});
  assert.equal(on.next.enabled, true);
  assert.equal(on.changed, true);
  assert.equal(planStravaAccessChange(on.next, {command: "enable"}).changed, false);
  assert.equal(planStravaAccessChange(on.next, {command: "disable"}).next.enabled, false);
});

test("allowing past Strava's capacity is refused", () => {
  let settings = EMPTY;
  for (let seat = 0; seat < DEFAULT_STRAVA_CAPACITY; seat += 1) {
    settings = planStravaAccessChange(settings, {command: "allow", userId: `climber-${seat}`}).next;
  }
  assert.equal(settings.allowedUserIds.length, DEFAULT_STRAVA_CAPACITY);
  assert.throws(
    () => planStravaAccessChange(settings, {command: "allow", userId: "climber-extra"}),
    /10 of 10 seats/
  );
  const approved = planStravaAccessChange(settings, {
    command: "allow",
    userId: "climber-extra",
    capacity: 999,
  });
  assert.equal(approved.next.allowedUserIds.length, DEFAULT_STRAVA_CAPACITY + 1);
});

test("removing a climber keeps their existing connection and says so", () => {
  const allowed = planStravaAccessChange(EMPTY, {command: "allow", userId: "climber-1"}).next;
  const removed = planStravaAccessChange(allowed, {command: "remove", userId: "climber-1"});
  assert.deepEqual(removed.next.allowedUserIds, []);
  assert.match(removed.summary, /stays until they disconnect/);
  assert.equal(planStravaAccessChange(removed.next, {command: "remove", userId: "climber-1"}).changed, false);
});

test("a removed climber who is still connected keeps holding a seat", () => {
  let settings = EMPTY;
  for (let seat = 0; seat < DEFAULT_STRAVA_CAPACITY; seat += 1) {
    settings = planStravaAccessChange(settings, {command: "allow", userId: `climber-${seat}`}).next;
  }
  settings = planStravaAccessChange(settings, {command: "remove", userId: "climber-0"}).next;
  assert.equal(settings.allowedUserIds.length, DEFAULT_STRAVA_CAPACITY - 1);

  assert.throws(
    () => planStravaAccessChange(settings, {
      command: "allow",
      userId: "climber-extra",
      connectedUserIds: ["climber-0"],
    }),
    /10 of 10 seats/
  );
  const readmitted = planStravaAccessChange(settings, {
    command: "allow",
    userId: "climber-0",
    connectedUserIds: ["climber-0"],
  });
  assert.equal(readmitted.next.allowedUserIds.length, DEFAULT_STRAVA_CAPACITY);
  assert.match(readmitted.summary, /10 of 10 seats/);

  const disconnected = planStravaAccessChange(settings, {
    command: "allow",
    userId: "climber-extra",
    connectedUserIds: [],
  });
  assert.equal(disconnected.next.allowedUserIds.length, DEFAULT_STRAVA_CAPACITY);
});

test("a climber must be named by a plausible uid", () => {
  assert.throws(() => planStravaAccessChange(EMPTY, {command: "allow"}), /Firebase uid/);
  assert.throws(() => planStravaAccessChange(EMPTY, {command: "allow", userId: "a/b"}), /Firebase uid/);
  assert.throws(() => planStravaAccessChange(EMPTY, {command: "allow", userId: "climber-1", capacity: 0}), /capacity/);
});
