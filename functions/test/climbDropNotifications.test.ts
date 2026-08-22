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
  claimReceipt,
  climbDropNotificationTestHooks,
  detectNewlyAvailableClimbs,
  mergeAnnouncedClimbIds,
  normalizeCatalogClimbs,
  planDispatchAdvance,
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
  let dispatchWriteFailures = 0;
  let unclaimableTokenHashes = new Set<string>();
  let senderBehavior: (
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
    dispatchCursors(): (string | null)[] {
      return [...dispatchDocuments.values()].map((one) => one.deviceCursor);
    },
    dispatchIds(): string[] {
      return [...dispatchDocuments.keys()];
    },
    dispatchStates(): string[] {
      return [...dispatchDocuments.values()].map((one) => one.state);
    },
    failNextDispatchWrites(count: number) {
      dispatchWriteFailures = count;
    },
    publish(nextCatalog: CatalogClimb[], nextVersion: number) {
      catalog = nextCatalog;
      catalogVersion = nextVersion;
    },
    setUnclaimableTokenHashes(tokenHashes: string[]) {
      unclaimableTokenHashes = new Set(tokenHashes);
    },
    setSenderBehavior(
      behavior: (tokens: ClimbDropDevice[]) => ClimbDropSendOutcome[]
    ) {
      senderBehavior = behavior;
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
      return senderBehavior(request.tokens);
    },
  };

  /**
   * Records the baseline the way the state document does.
   * @param {string[]} announcedClimbIds Monotonic baseline.
   * @param {number | null} version Catalogue version just read.
   * @return {void}
   */
  function writeCatalogCheck(
    announcedClimbIds: string[],
    version: number | null
  ) {
    state = {
      announcedClimbIds,
      lastCatalogVersion: version,
      sendingEnabled: state?.sendingEnabled !== false,
    };
  }

  const store = {
    // Mirrors the Firestore store: the same guard runs inside its
    // transaction, so a completed drop stays completed and the cursor only
    // ever moves forward.
    async advanceDispatch(
      dispatchId: string,
      cursor: string | null
    ) {
      const dispatch = dispatchDocuments.get(dispatchId);
      if (!dispatch) {
        return;
      }
      const advance = planDispatchAdvance(
        {deviceCursor: dispatch.deviceCursor, state: dispatch.state},
        cursor
      );
      if (advance.state) {
        dispatch.state = advance.state;
      }
      if (advance.deviceCursor !== undefined) {
        dispatch.deviceCursor = advance.deviceCursor;
      }
    },

    async claimDevices(dispatchId: string, candidates: ClimbDropDevice[]) {
      const claimed = receipts.get(dispatchId) ?? new Map<string, string>();
      receipts.set(dispatchId, claimed);
      const winners: ClimbDropDevice[] = [];
      let unclaimedCount = 0;
      for (const candidate of candidates) {
        if (claimed.has(candidate.tokenHash)) {
          continue;
        }
        // A transient Firestore refusal on this one create. The receipt never
        // lands, so the device stays unclaimed and unsent.
        if (unclaimableTokenHashes.has(candidate.tokenHash)) {
          unclaimedCount += 1;
          continue;
        }
        claimed.set(candidate.tokenHash, "claimed");
        winners.push(candidate);
      }
      return {claimed: winners, unclaimedCount};
    },

    async completeDispatch(dispatchId: string) {
      const dispatch = dispatchDocuments.get(dispatchId);
      if (dispatch) {
        dispatch.state = "sent";
      }
    },

    // Both writes or neither, the way the Firestore batch commits them.
    async createDispatchWithBaseline(
      dispatch: {
        body: string;
        catalogVersion: number | null;
        climbIds: string[];
        id: string;
        primaryClimbId: string;
        title: string;
      },
      announcedClimbIds: string[],
      version: number | null
    ) {
      if (dispatchWriteFailures > 0) {
        dispatchWriteFailures -= 1;
        throw new Error("the dispatch write was refused");
      }
      if (dispatchDocuments.has(dispatch.id)) {
        writeCatalogCheck(announcedClimbIds, version);
        return false;
      }
      createdAtCounter += 1;
      dispatchDocuments.set(dispatch.id, {
        ...dispatch,
        createdAt: createdAtCounter,
        deviceCursor: null,
        state: "pending",
      });
      writeCatalogCheck(announcedClimbIds, version);
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
      writeCatalogCheck(announcedClimbIds, version);
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
    harness.setSenderBehavior((tokens) => tokens.map((token) => ({
      errorCode: token.tokenHash === "d-dead" ?
        "messaging/registration-token-not-registered" :
        null,
      invalidToken: token.tokenHash === "d-dead",
      ok: token.tokenHash !== "d-dead",
      tokenHash: token.tokenHash,
    })));

    await harness.sweep();
    assert.deepEqual(harness.prunedTokenHashes, ["d-dead"]);

    harness.setSenderBehavior((tokens) => tokens.map((token) => ({
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
  harness.setSenderBehavior((tokens) => tokens.map((token, index) => ({
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
    harness.setSenderBehavior(() => {
      throw new Error("FCM is unreachable");
    });

    const crashed = await harness.sweep();
    assert.deepEqual(
      crashed.dispatchErrors.map((one) => one.message),
      ["FCM is unreachable"]
    );
    assert.deepEqual(harness.dispatchStates(), ["pending"]);

    harness.setSenderBehavior((tokens) => tokens.map((token) => ({
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
  harness.setSenderBehavior((tokens) => {
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

test("a dispatch and its baseline move together or not at all", async () => {
  const harness = makeHarness({
    catalog: [EMPIRE],
    catalogVersion: 10,
    registrations: devices(2),
    state: {announcedClimbIds: [], lastCatalogVersion: 9},
  });

  // The write that creates the dispatch and advances the baseline fails. A
  // baseline that could land alone would record Empire State as announced with
  // nothing to announce it; a dispatch that could land alone would let the next
  // detection fold Empire State into a differently-hashed union whose receipts
  // are a fresh ledger - a second push for a climb already sent.
  harness.failNextDispatchWrites(1);
  await assert.rejects(harness.sweep(), /dispatch write was refused/);
  assert.deepEqual(harness.dispatchIds(), []);
  assert.deepEqual(harness.state?.announcedClimbIds, []);
  assert.equal(harness.state?.lastCatalogVersion, 9);

  // A second climb opens before the retry, so detection now returns the union.
  harness.publish([EMPIRE, WILLIS], 11);
  await harness.sweep();
  await harness.sweep();

  assert.equal(harness.dispatchIds().length, 1);
  const delivered = harness.deliveredTokenHashes();
  assert.equal(delivered.length, 2);
  assert.equal(new Set(delivered).size, 2);
});

test("a device that cannot be claimed is left behind, not blocking the page",
  async () => {
    const harness = makeHarness({
      catalog: [EMPIRE],
      catalogVersion: 10,
      registrations: devices(6),
      state: {announcedClimbIds: [], lastCatalogVersion: 9},
    });
    const options = {devicePageSize: 2};
    // A fault that reproduces on the same device every attempt, every run.
    harness.setUnclaimableTokenHashes(["d00002"]);

    const first = await harness.sweep(options);

    // The rest of the run's page budget is still spent, the drop finishes, and
    // the one device it could not claim is the only cost.
    assert.equal(first.unclaimedCount, 1);
    assert.equal(first.dispatchesCompleted.length, 1);
    assert.deepEqual(harness.dispatchStates(), ["sent"]);
    assert.deepEqual(harness.deliveredTokenHashes().sort(),
      ["d00000", "d00001", "d00003", "d00004", "d00005"]);

    // A wedged dispatch would hold its slot and re-walk the same page for
    // good, so nothing may remain unfinished for the next run to pick up.
    const second = await harness.sweep(options);
    assert.equal(second.claimedCount, 0);
    assert.equal(second.unclaimedCount, 0);
    assert.deepEqual(harness.dispatchStates(), ["sent"]);
  });

test("a claim is retried a bounded number of times, then given up on",
  async () => {
    const waits: number[] = [];
    const wait = async (milliseconds: number) => {
      waits.push(milliseconds);
    };

    let transientAttempts = 0;
    const transient = await claimReceipt(async () => {
      transientAttempts += 1;
      if (transientAttempts < 3) {
        throw Object.assign(new Error("resource exhausted"), {code: 8});
      }
    }, {wait});

    assert.equal(transient, true, "a transient refusal must be retried");
    assert.equal(transientAttempts, 3);
    assert.deepEqual(waits, [50, 100], "the backoff must grow, not spin");

    let persistentAttempts = 0;
    await assert.rejects(claimReceipt(async () => {
      persistentAttempts += 1;
      throw Object.assign(new Error("resource exhausted"), {code: 8});
    }, {wait}), /resource exhausted/);
    assert.equal(persistentAttempts, 3,
      "a device that keeps failing must not be retried without bound");

    let existingAttempts = 0;
    const existing = await claimReceipt(async () => {
      existingAttempts += 1;
      throw Object.assign(new Error("already exists"), {code: 6});
    }, {wait});

    assert.equal(existing, false, "an existing receipt is not a failure");
    assert.equal(existingAttempts, 1, "a claimed device must not be retried");
  });

test("a completed drop stays completed", () => {
  assert.deepEqual(
    planDispatchAdvance({deviceCursor: "d00099", state: "sent"}, "d00050"),
    {},
    "a lagging writer must not flip a finished dispatch back to sending"
  );
  assert.deepEqual(
    planDispatchAdvance({deviceCursor: null, state: "pending"}, "d00099"),
    {deviceCursor: "d00099", state: "sending"}
  );
});

test("the device cursor only ever moves forward", () => {
  assert.deepEqual(
    planDispatchAdvance({deviceCursor: "d00099", state: "sending"}, "d00050"),
    {state: "sending"},
    "an older cursor would re-walk pages the drop has already finished"
  );
  assert.deepEqual(
    planDispatchAdvance({deviceCursor: "d00099", state: "sending"}, null),
    {state: "sending"}
  );
  assert.deepEqual(
    planDispatchAdvance({deviceCursor: "d00099", state: "sending"}, "d00100"),
    {deviceCursor: "d00100", state: "sending"}
  );
});

test("one malformed catalogue row costs that climb, not the sweep", () => {
  const climbs = normalizeCatalogClimbs([
    EMPIRE,
    {id: "no-name", releaseState: "available"},
    {name: "No ID", releaseState: "available"},
    "not-an-object",
    null,
    {...WILLIS, realStairCount: "2109", totalSteps: Number.NaN},
  ]);

  assert.deepEqual(climbs.map((climb) => climb.id),
    ["empire-state-building", "willis-tower"]);
  assert.equal(climbs[1].realStairCount, null);
  assert.equal(climbs[1].totalSteps, null);
  assert.deepEqual(availableClimbIds(climbs),
    ["empire-state-building", "willis-tower"]);
});

test("a climb with no name falls back to its ID rather than throwing", () => {
  const message = buildClimbDropMessage([
    {id: "unnamed-tower", name: undefined as unknown as string,
      realStairCount: 900, releaseState: "available"},
  ]);

  assert.equal(message.title, "New climb: unnamed-tower");
});

test("only Firestore's ALREADY_EXISTS refusal is a claimed device", () => {
  const {isAlreadyExistsError} = climbDropNotificationTestHooks;

  assert.equal(isAlreadyExistsError({code: 6}), true);
  assert.equal(isAlreadyExistsError({code: "already-exists"}), true);
  assert.equal(isAlreadyExistsError({code: 8}), false);
  assert.equal(isAlreadyExistsError({code: "resource-exhausted"}), false);
  assert.equal(isAlreadyExistsError(new Error("deadline exceeded")), false);
  assert.equal(isAlreadyExistsError(null), false);
  assert.equal(isAlreadyExistsError("already exists"), false);
});

test("a receipt records what actually happened to the device", () => {
  const {receiptStateFor} = climbDropNotificationTestHooks;

  assert.equal(receiptStateFor({errorCode: null, invalidToken: false,
    ok: true, tokenHash: "d"}), "delivered");
  assert.equal(receiptStateFor({errorCode: "messaging/internal-error",
    invalidToken: false, ok: false, tokenHash: "d"}), "failed");
  assert.equal(receiptStateFor({
    errorCode: "messaging/registration-token-not-registered",
    invalidToken: true, ok: false, tokenHash: "d"}), "invalid_token");
});

test("truncation leaves the field limit intact and marks the cut", () => {
  const {truncate} = climbDropNotificationTestHooks;

  assert.equal(truncate("Willis Tower", 80), "Willis Tower");
  assert.equal(truncate("abcdef", 6), "abcdef");
  assert.equal(truncate("abcdefg", 6), "abcde…");
  assert.equal(truncate("abcde fg", 7), "abcde…");
});
