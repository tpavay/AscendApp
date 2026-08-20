/**
 * The climb-drop sweep, against an in-memory store that keeps the two
 * Firestore semantics the no-duplicate guarantee rests on: a `create` refuses
 * a document that already exists, and a device page is a stable ordered scan.
 *
 * Everything the shipped copy promises is pinned here - an alert at the open,
 * once per climb, only to devices that asked for it.
 */

import test from "node:test";
import assert from "node:assert/strict";
import {
  availableClimbIds,
  buildClimbDropDispatchId,
  buildClimbDropMessage,
  detectNewlyAvailableClimbs,
  mergeAnnouncedClimbIds,
  referenceStepCount,
  runClimbDropSweep,
} from "../src/climbDropNotifications.js";
import type {
  CatalogClimb,
  ClimbDropDevice,
  ClimbDropSendOutcome,
  ClimbDropSweepOptions,
} from "../src/climbDropNotifications.js";
import {
  pushNotificationTestHooks,
} from "../src/pushNotifications.js";

type Registration = Record<string, unknown> & {tokenHash: string};

const EMPIRE: CatalogClimb = {
  city: "New York",
  id: "empire-state-building",
  name: "Empire State Building",
  realStairCount: 1576,
  releaseState: "available",
  totalSteps: 2096,
};

const WILLIS: CatalogClimb = {
  city: "Chicago",
  id: "willis-tower",
  name: "Willis Tower",
  realStairCount: 2109,
  releaseState: "available",
  totalSteps: 2400,
};

const SHARD_HIDDEN: CatalogClimb = {
  city: "London",
  id: "the-shard",
  name: "The Shard",
  realStairCount: null,
  releaseState: "comingSoon",
  totalSteps: 1705,
};

/**
 * Builds an opted-in, deliverable device registration.
 * @param {string} tokenHash Stable device document ID.
 * @param {object} overrides Fields to override.
 * @return {Registration} Registration document.
 */
function device(
  tokenHash: string,
  overrides: Record<string, unknown> = {}
): Registration {
  return {
    active: true,
    authorizationStatus: "authorized",
    climbDropPushEnabled: true,
    fcmToken: `token-${tokenHash}`,
    platform: "ios",
    tokenHash,
    uid: `uid-${tokenHash}`,
    ...overrides,
  };
}

/**
 * Builds many deliverable devices with sortable token hashes.
 * @param {number} count How many devices to build.
 * @return {Registration[]} Registration documents.
 */
function devices(count: number): Registration[] {
  return Array.from({length: count}, (_unused, index) =>
    device(`d${String(index).padStart(5, "0")}`));
}

interface FakeSendCall {
  dispatchId: string;
  tokenHashes: string[];
}

/**
 * Builds the in-memory catalogue, store, and sender the sweep runs against.
 * @param {object} setup Seed catalogue, devices, and stored state.
 * @return {object} Injected dependencies plus the recorded side effects.
 */
function makeHarness(setup: {
  catalog: CatalogClimb[];
  catalogVersion: number;
  registrations: Registration[];
  state?: {
    announcedClimbIds: string[];
    lastCatalogVersion: number | null;
    sendingEnabled?: boolean;
  } | null;
}) {
  const registrations = new Map(
    setup.registrations.map((one) => [one.tokenHash, one])
  );
  const receipts = new Map<string, Map<string, string>>();
  const dispatchDocuments = new Map<string, {
    body: string;
    catalogVersion: number | null;
    climbIds: string[];
    createdAt: number;
    deviceCursor: string | null;
    id: string;
    primaryClimbId: string;
    state: "pending" | "sending" | "sent";
    title: string;
  }>();
  const sendCalls: FakeSendCall[] = [];
  const prunedTokenHashes: string[] = [];
  const devicePageCursors: (string | null)[] = [];
  let state = setup.state === undefined ?
    null :
    setup.state;
  let catalog = setup.catalog;
  let catalogVersion = setup.catalogVersion;
  let createdAtCounter = 0;
  let senderBehaviour: (
    tokens: ClimbDropDevice[]
  ) => ClimbDropSendOutcome[] = (tokens) =>
    tokens.map((token) => ({
      errorCode: null,
      invalidToken: false,
      ok: true,
      tokenHash: token.tokenHash,
    }));

  const harness = {
    get catalogVersion() {
      return catalogVersion;
    },
    get devicePageCursors() {
      return devicePageCursors;
    },
    get prunedTokenHashes() {
      return prunedTokenHashes;
    },
    get registrations() {
      return registrations;
    },
    get sendCalls() {
      return sendCalls;
    },
    get state() {
      return state;
    },
    deliveredTokenHashes(): string[] {
      return sendCalls.flatMap((call) => call.tokenHashes);
    },
    dispatchStates(): string[] {
      return [...dispatchDocuments.values()].map((one) => one.state);
    },
    publish(nextCatalog: CatalogClimb[], nextVersion: number) {
      catalog = nextCatalog;
      catalogVersion = nextVersion;
    },
    setSenderBehaviour(
      behaviour: (tokens: ClimbDropDevice[]) => ClimbDropSendOutcome[]
    ) {
      senderBehaviour = behaviour;
    },
    setSendingEnabled(enabled: boolean) {
      if (state) {
        state = {...state, sendingEnabled: enabled};
      }
    },
    sweep(options: ClimbDropSweepOptions = {}) {
      return runClimbDropSweep({catalog: source, sender, store}, options);
    },
  };

  const source = {
    async fetchClimbs() {
      return catalog;
    },
    async fetchManifest() {
      return {catalogPath: "/climbs/catalog-v1.json", catalogVersion};
    },
  };

  const sender = {
    async send(request: {
      dispatchId: string;
      tokens: ClimbDropDevice[];
    }) {
      sendCalls.push({
        dispatchId: request.dispatchId,
        tokenHashes: request.tokens.map((token) => token.tokenHash),
      });
      return senderBehaviour(request.tokens);
    },
  };

  const store = {
    async advanceDispatch(
      dispatchId: string,
      cursor: string | null
    ) {
      const dispatch = dispatchDocuments.get(dispatchId);
      if (dispatch) {
        dispatch.deviceCursor = cursor;
        dispatch.state = "sending";
      }
    },

    async claimDevices(dispatchId: string, candidates: ClimbDropDevice[]) {
      const claimed = receipts.get(dispatchId) ?? new Map<string, string>();
      receipts.set(dispatchId, claimed);
      const winners: ClimbDropDevice[] = [];
      for (const candidate of candidates) {
        if (claimed.has(candidate.tokenHash)) {
          continue;
        }
        claimed.set(candidate.tokenHash, "claimed");
        winners.push(candidate);
      }
      return winners;
    },

    async completeDispatch(dispatchId: string) {
      const dispatch = dispatchDocuments.get(dispatchId);
      if (dispatch) {
        dispatch.state = "sent";
      }
    },

    async createDispatchIfAbsent(dispatch: {
      body: string;
      catalogVersion: number | null;
      climbIds: string[];
      id: string;
      primaryClimbId: string;
      title: string;
    }) {
      if (dispatchDocuments.has(dispatch.id)) {
        return false;
      }
      createdAtCounter += 1;
      dispatchDocuments.set(dispatch.id, {
        ...dispatch,
        createdAt: createdAtCounter,
        deviceCursor: null,
        state: "pending",
      });
      return true;
    },

    async listUnfinishedDispatches(limit: number) {
      return [...dispatchDocuments.values()]
        .filter((one) => one.state !== "sent")
        .sort((left, right) => left.createdAt - right.createdAt)
        .slice(0, limit)
        .map((one) => ({...one}));
    },

    async loadDevicePage(afterTokenHash: string | null, limit: number) {
      devicePageCursors.push(afterTokenHash);
      const ordered = [...registrations.values()]
        .sort((left, right) => left.tokenHash.localeCompare(right.tokenHash))
        .filter((one) =>
          afterTokenHash === null || one.tokenHash > afterTokenHash);
      const page = ordered.slice(0, limit);
      const deliverable = page
        .filter((one) =>
          pushNotificationTestHooks.isDeliverableClimbDropRegistration(one))
        .map((one) => ({
          fcmToken: String(one.fcmToken),
          tokenHash: one.tokenHash,
        }));

      return {
        devices: deliverable,
        exhausted: page.length < limit,
        lastTokenHash: page[page.length - 1]?.tokenHash ?? null,
      };
    },

    async pruneInvalidTokens(tokenHashes: string[]) {
      for (const tokenHash of tokenHashes) {
        prunedTokenHashes.push(tokenHash);
        const registration = registrations.get(tokenHash);
        if (registration) {
          registration.active = false;
        }
      }
    },

    async readState() {
      return state === null ? null : {
        announcedClimbIds: [...state.announcedClimbIds],
        lastCatalogVersion: state.lastCatalogVersion,
        sendingEnabled: state.sendingEnabled !== false,
      };
    },

    async recordCatalogCheck(
      announcedClimbIds: string[],
      version: number | null
    ) {
      state = {
        announcedClimbIds,
        lastCatalogVersion: version,
        sendingEnabled: state?.sendingEnabled !== false,
      };
    },

    async recordSendOutcomes(
      dispatchId: string,
      outcomes: ClimbDropSendOutcome[]
    ) {
      const claimed = receipts.get(dispatchId);
      if (!claimed) {
        return;
      }
      for (const outcome of outcomes) {
        claimed.set(
          outcome.tokenHash,
          outcome.ok ? "delivered" : "failed"
        );
      }
    },

    async writeBootstrapState(
      announcedClimbIds: string[],
      version: number | null
    ) {
      state = {
        announcedClimbIds,
        lastCatalogVersion: version,
        sendingEnabled: true,
      };
    },
  };

  return harness;
}

test("the first sweep records the catalogue instead of announcing it",
  async () => {
    const harness = makeHarness({
      catalog: [EMPIRE, WILLIS, SHARD_HIDDEN],
      catalogVersion: 10,
      registrations: devices(3),
      state: null,
    });

    const summary = await harness.sweep();

    assert.equal(summary.bootstrapped, true);
    assert.deepEqual(harness.sendCalls, []);
    assert.deepEqual(
      harness.state?.announcedClimbIds,
      ["empire-state-building", "willis-tower"]
    );
  });

test("a climb reaching available alerts every opted-in device exactly once",
  async () => {
    const harness = makeHarness({
      catalog: [EMPIRE, SHARD_HIDDEN],
      catalogVersion: 10,
      registrations: devices(3),
      state: {announcedClimbIds: ["empire-state-building"],
        lastCatalogVersion: 10},
    });

    harness.publish([EMPIRE, {...SHARD_HIDDEN, realStairCount: 1200,
      releaseState: "available"}], 11);
    const first = await harness.sweep();

    assert.deepEqual(first.newlyAvailableClimbIds, ["the-shard"]);
    assert.deepEqual(harness.deliveredTokenHashes().sort(),
      ["d00000", "d00001", "d00002"]);
    assert.deepEqual(harness.dispatchStates(), ["sent"]);
  });

test("re-running the sweep never alerts a device twice for one climb",
  async () => {
    const harness = makeHarness({
      catalog: [EMPIRE],
      catalogVersion: 10,
      registrations: devices(4),
      state: {announcedClimbIds: [], lastCatalogVersion: 9},
    });

    await harness.sweep();
    // A redeploy re-publishes the same catalogue under a new version, and the
    // sweep runs again. Neither may re-announce a climb already sent.
    harness.publish([EMPIRE], 11);
    await harness.sweep();
    await harness.sweep();

    const delivered = harness.deliveredTokenHashes();
    assert.equal(delivered.length, new Set(delivered).size);
    assert.equal(delivered.length, 4);
  });

test("a climb pulled back and reopened does not announce a second time",
  async () => {
    const harness = makeHarness({
      catalog: [EMPIRE],
      catalogVersion: 10,
      registrations: devices(2),
      state: {announcedClimbIds: [], lastCatalogVersion: 9},
    });

    await harness.sweep();
    harness.publish([{...EMPIRE, releaseState: "hidden"}], 11);
    await harness.sweep();
    harness.publish([EMPIRE], 12);
    await harness.sweep();

    assert.equal(harness.deliveredTokenHashes().length, 2);
  });

test("a device that never opted in, or turned the toggle off, is not sent to",
  async () => {
    const harness = makeHarness({
      catalog: [EMPIRE],
      catalogVersion: 10,
      registrations: [
        device("d-opted-in"),
        device("d-toggle-off", {climbDropPushEnabled: false}),
        device("d-never-answered", {climbDropPushEnabled: undefined}),
        device("d-ios-denied", {authorizationStatus: "denied"}),
        device("d-not-determined", {authorizationStatus: "not_determined"}),
        device("d-signed-out", {active: false}),
        device("d-other-platform", {platform: "android"}),
        device("d-no-token", {fcmToken: ""}),
      ],
      state: {announcedClimbIds: [], lastCatalogVersion: 9},
    });

    await harness.sweep();

    assert.deepEqual(harness.deliveredTokenHashes(), ["d-opted-in"]);
  });

test("an invalid token is pruned rather than retried on the next drop",
  async () => {
    const harness = makeHarness({
      catalog: [EMPIRE],
      catalogVersion: 10,
      registrations: [device("d-live"), device("d-dead")],
      state: {announcedClimbIds: [], lastCatalogVersion: 9},
    });
    harness.setSenderBehaviour((tokens) => tokens.map((token) => ({
      errorCode: token.tokenHash === "d-dead" ?
        "messaging/registration-token-not-registered" :
        null,
      invalidToken: token.tokenHash === "d-dead",
      ok: token.tokenHash !== "d-dead",
      tokenHash: token.tokenHash,
    })));

    await harness.sweep();
    assert.deepEqual(harness.prunedTokenHashes, ["d-dead"]);

    harness.setSenderBehaviour((tokens) => tokens.map((token) => ({
      errorCode: null,
      invalidToken: false,
      ok: true,
      tokenHash: token.tokenHash,
    })));
    harness.publish([EMPIRE, WILLIS], 11);
    await harness.sweep();

    const secondDrop = harness.sendCalls[harness.sendCalls.length - 1];
    assert.deepEqual(secondDrop.tokenHashes, ["d-live"]);
  });

test("a partial batch failure is recorded and never re-sent", async () => {
  const harness = makeHarness({
    catalog: [EMPIRE],
    catalogVersion: 10,
    registrations: devices(4),
    state: {announcedClimbIds: [], lastCatalogVersion: 9},
  });
  harness.setSenderBehaviour((tokens) => tokens.map((token, index) => ({
    errorCode: index % 2 === 0 ? null : "messaging/internal-error",
    invalidToken: false,
    ok: index % 2 === 0,
    tokenHash: token.tokenHash,
  })));

  const first = await harness.sweep();
  assert.equal(first.sentCount, 2);
  assert.equal(first.failedCount, 2);
  assert.deepEqual(harness.prunedTokenHashes, []);

  harness.publish([EMPIRE], 11);
  await harness.sweep();

  const delivered = harness.deliveredTokenHashes();
  assert.equal(delivered.length, new Set(delivered).size);
});

test("a sender that dies mid-drop resumes without re-sending the claimed",
  async () => {
    const harness = makeHarness({
      catalog: [EMPIRE],
      catalogVersion: 10,
      registrations: devices(3),
      state: {announcedClimbIds: [], lastCatalogVersion: 9},
    });
    harness.setSenderBehaviour(() => {
      throw new Error("FCM is unreachable");
    });

    const crashed = await harness.sweep();
    assert.deepEqual(
      crashed.dispatchErrors.map((one) => one.message),
      ["FCM is unreachable"]
    );
    assert.deepEqual(harness.dispatchStates(), ["pending"]);

    harness.setSenderBehaviour((tokens) => tokens.map((token) => ({
      errorCode: null,
      invalidToken: false,
      ok: true,
      tokenHash: token.tokenHash,
    })));
    await harness.sweep();

    // The claim is what survived the crash, so the devices in flight when the
    // sender died are never sent to twice.
    const delivered = harness.deliveredTokenHashes();
    assert.equal(delivered.length, new Set(delivered).size);
  });

test("a drop larger than one multicast batch stays inside FCM's ceiling",
  async () => {
    const harness = makeHarness({
      catalog: [EMPIRE],
      catalogVersion: 10,
      registrations: devices(1200),
      state: {announcedClimbIds: [], lastCatalogVersion: 9},
    });

    await harness.sweep();

    assert.deepEqual(
      harness.sendCalls.map((call) => call.tokenHashes.length),
      [500, 500, 200]
    );
    const delivered = harness.deliveredTokenHashes();
    assert.equal(delivered.length, 1200);
    assert.equal(new Set(delivered).size, 1200);
  });

test("a run that spends its page budget resumes where it stopped",
  async () => {
    const harness = makeHarness({
      catalog: [EMPIRE],
      catalogVersion: 10,
      registrations: devices(250),
      state: {announcedClimbIds: [], lastCatalogVersion: 9},
    });
    const options = {devicePageSize: 100, maxDevicePages: 1};

    await harness.sweep(options);
    assert.deepEqual(harness.dispatchStates(), ["sending"]);

    await harness.sweep(options);
    await harness.sweep(options);
    assert.deepEqual(harness.dispatchStates(), ["sent"]);

    const delivered = harness.deliveredTokenHashes();
    assert.equal(delivered.length, 250);
    assert.equal(new Set(delivered).size, 250);
  });

test("a run killed mid-drop resumes at the page it finished", async () => {
  const harness = makeHarness({
    catalog: [EMPIRE],
    catalogVersion: 10,
    registrations: devices(250),
    state: {announcedClimbIds: [], lastCatalogVersion: 9},
  });
  const options = {devicePageSize: 100};

  // The third page's send dies the way an invocation timeout does: after two
  // pages have gone out, with nothing left to write the run's progress.
  let sends = 0;
  harness.setSenderBehaviour((tokens) => {
    sends += 1;
    if (sends === 3) {
      throw new Error("the invocation was killed mid-drop");
    }
    return tokens.map((token) => ({
      errorCode: null,
      invalidToken: false,
      ok: true,
      tokenHash: token.tokenHash,
    }));
  });

  const killed = await harness.sweep(options);
  assert.equal(killed.dispatchErrors.length, 1);
  const cursorsBeforeResume = harness.devicePageCursors.length;

  await harness.sweep(options);

  // The cursor is persisted per page, so the resume opens where the killed run
  // stopped. Re-walking from the start would still be correct - the receipts
  // refuse a second claim - but it would re-scan and re-claim every device
  // already alerted, on every run, for as long as the drop takes to finish.
  assert.equal(
    harness.devicePageCursors[cursorsBeforeResume],
    "d00199",
    "the resume must not re-walk pages the killed run already finished"
  );
});

test("the operator stop defers the drop instead of dropping it", async () => {
  const harness = makeHarness({
    catalog: [EMPIRE],
    catalogVersion: 10,
    registrations: devices(2),
    state: {announcedClimbIds: [], lastCatalogVersion: 9,
      sendingEnabled: false},
  });

  const held = await harness.sweep();
  assert.equal(held.sendingSkipped, true);
  assert.deepEqual(harness.sendCalls, []);
  assert.deepEqual(harness.dispatchStates(), ["pending"]);

  harness.setSendingEnabled(true);
  await harness.sweep();

  assert.equal(harness.deliveredTokenHashes().length, 2);
});

test("only available climbs count as open", () => {
  assert.deepEqual(
    availableClimbIds([EMPIRE, SHARD_HIDDEN, {...WILLIS,
      releaseState: "disabled"}]),
    ["empire-state-building"]
  );
});

test("detection reads the announced baseline, not the available set", () => {
  const detected = detectNewlyAvailableClimbs(
    [EMPIRE, WILLIS],
    ["empire-state-building"]
  );

  assert.deepEqual(detected.map((climb) => climb.id), ["willis-tower"]);
});

test("the baseline only ever grows", () => {
  assert.deepEqual(
    mergeAnnouncedClimbIds(["willis-tower"], ["empire-state-building"]),
    ["empire-state-building", "willis-tower"]
  );
});

test("the race distance prefers the verified stair count", () => {
  assert.equal(referenceStepCount(EMPIRE), 1576);
  assert.equal(referenceStepCount(SHARD_HIDDEN), 1705);
  assert.equal(referenceStepCount({id: "x", name: "X"}), null);
});

test("the dispatch ID is stable regardless of detection order", () => {
  assert.equal(
    buildClimbDropDispatchId(["willis-tower", "empire-state-building"]),
    buildClimbDropDispatchId(["empire-state-building", "willis-tower"])
  );
  assert.notEqual(
    buildClimbDropDispatchId(["willis-tower"]),
    buildClimbDropDispatchId(["empire-state-building"])
  );
});

test("one climb names the landmark, the city, and the race distance", () => {
  const message = buildClimbDropMessage([EMPIRE]);

  assert.equal(message.title, "New climb: Empire State Building");
  assert.equal(message.body, "New York. 1,576 steps. Be first up.");
  assert.equal(message.primaryClimbId, "empire-state-building");
});

test("a multi-climb drop is one alert led by the longest race", () => {
  const message = buildClimbDropMessage([EMPIRE, WILLIS]);

  assert.equal(message.title, "2 new climbs open");
  assert.equal(
    message.body,
    "Willis Tower and Empire State Building just landed. Be first up."
  );
  assert.equal(message.primaryClimbId, "willis-tower");
});

test("a drop of three or more counts the rest", () => {
  const message = buildClimbDropMessage([
    EMPIRE,
    WILLIS,
    {...SHARD_HIDDEN, releaseState: "available"},
  ]);

  assert.equal(message.title, "3 new climbs open");
  assert.equal(
    message.body,
    "Willis Tower, The Shard and 1 more just landed. Be first up."
  );
});

test("alert copy stays inside the push field limits", () => {
  const longName = "A".repeat(200);
  const message = buildClimbDropMessage([
    {city: "B".repeat(200), id: "long", name: longName, realStairCount: 900,
      releaseState: "available"},
  ]);

  assert.ok(message.title.length <= 80, message.title);
  assert.ok(message.body.length <= 180, message.body);
});

test("an empty drop is a programming error, not a silent no-op", () => {
  assert.throws(() => buildClimbDropMessage([]), /at least one climb/);
});
