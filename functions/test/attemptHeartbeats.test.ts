import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  AttemptHeartbeatPort,
  FlagDocument,
  HeartbeatDocument,
  STALL_THRESHOLD_MS,
  StalledHeartbeat,
  attemptHeartbeatTestHooks,
} from "../src/attemptHeartbeats.js";

const {buildFlag, flagId, flagStalledHeartbeats, isStalled, resolutionPatch} =
  attemptHeartbeatTestHooks;

// 2026-10-23T11:27:00Z: five and a half minutes after the Empire State climb's
// last checkpoint at 11:21:30Z.
const runAt = new Date("2026-10-23T11:27:00.000Z");
const lastSeenAt = admin.firestore.Timestamp.fromDate(
  new Date("2026-10-23T11:21:30.000Z")
);

function heartbeat(
  overrides: Partial<HeartbeatDocument> = {}
): HeartbeatDocument {
  return {
    schemaVersion: 1,
    sessionID: "esb-session",
    mode: "live_climb",
    steps: 66,
    durationSeconds: 62,
    startedAt: admin.firestore.Timestamp.fromDate(
      new Date("2026-10-23T11:20:54.000Z")
    ),
    lastSeenAt,
    state: "open",
    endedAt: null,
    outcome: null,
    climbId: "empire-state-building",
    appVersion: "1.2.3",
    ...overrides,
  };
}

interface FakePortState {
  stalled: StalledHeartbeat[];
  flags: Map<string, FlagDocument>;
  heartbeats: Map<string, HeartbeatDocument | undefined>;
  markedStalled: string[];
  failWriteFor?: string;
}

function makeFakePort(state: FakePortState): AttemptHeartbeatPort {
  return {
    async listStalledHeartbeats() {
      return state.stalled;
    },
    async writeFlag(flag) {
      const id = flagId(flag.userId, flag.sessionID);
      if (state.failWriteFor === id) {
        throw new Error("write refused");
      }
      state.flags.set(id, flag);
      state.markedStalled.push(id);
    },
    async listUnresolvedFlags() {
      return [...state.flags.entries()]
        .filter(([, flag]) => flag.resolvedAt === null)
        .map(([id, flag]) => ({id, flag}));
    },
    async readHeartbeat(userId, sessionID) {
      return state.heartbeats.get(flagId(userId, sessionID));
    },
    async resolveFlag(id, patch, resolvedAt) {
      const existing = state.flags.get(id);
      assert.ok(existing, `resolving unknown flag ${id}`);
      state.flags.set(id, {
        ...existing,
        ...patch,
        resolvedAt: admin.firestore.Timestamp.fromDate(resolvedAt),
      });
    },
  };
}

test("an open heartbeat five minutes silent is stalled; a fresh or ended one is not", () => {
  assert.equal(isStalled(heartbeat(), runAt), true);
  assert.equal(
    isStalled(
      heartbeat({
        lastSeenAt: admin.firestore.Timestamp.fromMillis(
          runAt.getTime() - STALL_THRESHOLD_MS + 1_000
        ),
      }),
      runAt
    ),
    false
  );
  assert.equal(isStalled(heartbeat({state: "ended"}), runAt), false);
  assert.equal(isStalled(heartbeat({state: "stalled"}), runAt), false);
  assert.equal(isStalled(heartbeat({lastSeenAt: undefined}), runAt), false);
});

test("the flag carries the session as the phone last reported it, and how long it has been silent", () => {
  const flag = buildFlag(
    {userId: "ZVm34nnd", sessionID: "esb-session", document: heartbeat()},
    runAt
  );

  assert.equal(flag.userId, "ZVm34nnd");
  assert.equal(flag.sessionID, "esb-session");
  assert.equal(flag.mode, "live_climb");
  assert.equal(flag.steps, 66);
  assert.equal(flag.durationSeconds, 62);
  assert.equal(flag.climbId, "empire-state-building");
  assert.equal(flag.stalledForSeconds, 330);
  assert.equal(flag.resolvedAt, null);
  assert.equal(flag.resolution, null);
  assert.equal(flag.flaggedAt.toMillis(), runAt.getTime());
});

test("a run flags each stalled session once and marks its heartbeat stalled", async () => {
  const state: FakePortState = {
    stalled: [
      {
        userId: "climber-a",
        sessionID: "s1",
        document: heartbeat({sessionID: "s1"}),
      },
      {
        userId: "climber-b",
        sessionID: "s2",
        document: heartbeat({sessionID: "s2", mode: "routine"}),
      },
      // Listed by the query but ended between the query and the check:
      // never flagged.
      {
        userId: "climber-c",
        sessionID: "s3",
        document: heartbeat({sessionID: "s3", state: "ended"}),
      },
    ],
    flags: new Map(),
    heartbeats: new Map(),
    markedStalled: [],
  };
  state.heartbeats.set("climber-a__s1", heartbeat({sessionID: "s1", state: "stalled"}));
  state.heartbeats.set("climber-b__s2", heartbeat({sessionID: "s2", state: "stalled"}));

  const summary = await flagStalledHeartbeats(runAt, makeFakePort(state));

  assert.equal(summary.flagged, 2);
  assert.equal(summary.resolved, 0);
  assert.deepEqual(summary.failures, []);
  assert.deepEqual([...state.flags.keys()].sort(), ["climber-a__s1", "climber-b__s2"]);
  assert.deepEqual(state.markedStalled, ["climber-a__s1", "climber-b__s2"]);
});

test("a flagged session that resumed resolves as resumed with the steps it came back with", async () => {
  const state: FakePortState = {
    stalled: [],
    flags: new Map([[
      "climber-a__s1",
      buildFlag({userId: "climber-a", sessionID: "s1", document: heartbeat()}, runAt),
    ]]),
    heartbeats: new Map([[
      "climber-a__s1",
      heartbeat({state: "open", steps: 1_593, durationSeconds: 1_328}),
    ]]),
    markedStalled: [],
  };

  const later = new Date(runAt.getTime() + 20 * 60_000);
  const summary = await flagStalledHeartbeats(later, makeFakePort(state));

  assert.equal(summary.resolved, 1);
  const flag = state.flags.get("climber-a__s1");
  assert.ok(flag);
  assert.equal(flag.resolution, "resumed");
  assert.equal(flag.resumedSteps, 1_593);
  assert.equal(flag.resumedDurationSeconds, 1_328);
  assert.equal(flag.resolvedAt?.toMillis(), later.getTime());
});

test("a flagged session that ended resolves with the climber's outcome", () => {
  assert.deepEqual(
    resolutionPatch(heartbeat({state: "ended", outcome: "saved", steps: 1_576, durationSeconds: 1_172})),
    {
      resolution: "ended",
      outcome: "saved",
      resumedSteps: 1_576,
      resumedDurationSeconds: 1_172,
    }
  );
  assert.equal(resolutionPatch(heartbeat({state: "stalled"})), null);
  assert.equal(resolutionPatch(undefined), null);
});

test("one refused write costs its own flag and the run reports it", async () => {
  const state: FakePortState = {
    stalled: [
      {userId: "climber-a", sessionID: "s1", document: heartbeat({sessionID: "s1"})},
      {userId: "climber-b", sessionID: "s2", document: heartbeat({sessionID: "s2"})},
    ],
    flags: new Map(),
    heartbeats: new Map(),
    markedStalled: [],
    failWriteFor: "climber-a__s1",
  };

  const summary = await flagStalledHeartbeats(runAt, makeFakePort(state));

  assert.equal(summary.flagged, 1);
  assert.deepEqual(summary.failures, ["flag climber-a__s1: write refused"]);
  assert.deepEqual([...state.flags.keys()], ["climber-b__s2"]);
});
