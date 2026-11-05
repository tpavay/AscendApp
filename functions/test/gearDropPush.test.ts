import test from "node:test";
import assert from "node:assert/strict";
import {
  GEAR_DROP_SEND_HOUR_UTC,
  buildGearDropMessage,
  dayStartMillis,
  gearDropWindow,
  parseGearEvents,
  readGearDropSwitch,
  runGearDropSweep,
  selectDueGearEvent,
  type GearDropDevice,
  type GearDropCounters,
  type GearDropDispatch,
  type GearDropStore,
  type GearEvent,
} from "../src/gearDropPush.js";

const THANKSGIVING: GearEvent = {
  endsBefore: "2026-12-01",
  firstClimbUnlocksItem: true,
  id: "thanksgiving-2026",
  monthName: "November",
  startsOn: "2026-11-01",
};

const HALLOWEEN: GearEvent = {
  endsBefore: "2026-11-01",
  firstClimbUnlocksItem: false,
  id: "halloween-2026",
  monthName: "October",
  startsOn: "2026-10-01",
};

const CATALOGUE = {
  events: [
    {
      endsBefore: "2026-11-01", id: "halloween-2026", monthName: "October",
      startsOn: "2026-10-01", title: "Halloween",
    },
    {
      endsBefore: "2026-12-01", id: "thanksgiving-2026",
      monthName: "November", startsOn: "2026-11-01", title: "Thanksgiving",
    },
    {id: "Bad Id", monthName: "X", startsOn: "2026-01-01",
      endsBefore: "2026-02-01"},
    {id: "no-month", startsOn: "2026-01-01", endsBefore: "2026-02-01"},
    {id: "backwards", monthName: "May", startsOn: "2026-06-01",
      endsBefore: "2026-05-01"},
    {id: "bad-day", monthName: "May", startsOn: "2026-02-31",
      endsBefore: "2026-05-01"},
  ],
  items: [
    {earn: {event: "thanksgiving-2026", metric: "climbs", threshold: 1},
      id: "pumpkin_pie", status: "live"},
    {earn: {event: "halloween-2026", metric: "visits", threshold: 1},
      id: "pumpkin_classic", status: "live"},
    {earn: {event: "halloween-2026", metric: "climbs", threshold: 1},
      id: "hidden_thing", status: "hidden"},
  ],
};

const at = (iso: string) => new Date(iso);

test("catalogue days parse to midnight UTC and reject impossible dates", () => {
  assert.equal(dayStartMillis("2026-11-01"), Date.UTC(2026, 10, 1));
  assert.equal(dayStartMillis("2026-02-31"), null);
  assert.equal(dayStartMillis("2026-1-1"), null);
  assert.equal(dayStartMillis(undefined), null);
});

test("malformed events are skipped, the rest survive", () => {
  const events = parseGearEvents(CATALOGUE);
  assert.deepEqual(events.map((event) => event.id),
    ["halloween-2026", "thanksgiving-2026"]);
  assert.equal(parseGearEvents(null).length, 0);
  assert.equal(parseGearEvents({}).length, 0);
});

test("a first-climb item counts only when it is live", () => {
  const [halloween, thanksgiving] = parseGearEvents(CATALOGUE);
  assert.equal(halloween.firstClimbUnlocksItem, false);
  assert.equal(thanksgiving.firstClimbUnlocksItem, true);
});

test("the window opens at the send hour of the first day for three days", () => {
  const {opensAt, closesAt} = gearDropWindow(THANKSGIVING);
  assert.equal(opensAt, Date.UTC(2026, 10, 1, GEAR_DROP_SEND_HOUR_UTC));
  assert.equal(closesAt, opensAt + 3 * 24 * 60 * 60 * 1000);
});

test("a short event's window never runs past its end", () => {
  const short: GearEvent = {...THANKSGIVING, endsBefore: "2026-11-03"};
  assert.equal(gearDropWindow(short).closesAt, Date.UTC(2026, 10, 3));
});

test("nothing is due before the send hour, one event is due inside", () => {
  const events = [HALLOWEEN, THANKSGIVING];
  assert.equal(selectDueGearEvent(events, at("2026-11-01T15:59:00Z")), null);
  assert.equal(
    selectDueGearEvent(events, at("2026-11-01T16:00:00Z"))?.id,
    "thanksgiving-2026"
  );
  assert.equal(
    selectDueGearEvent(events, at("2026-11-03T12:00:00Z"))?.id,
    "thanksgiving-2026"
  );
});

test("a stale event is never announced", () => {
  assert.equal(
    selectDueGearEvent([THANKSGIVING], at("2026-11-04T17:00:00Z")),
    null
  );
  assert.equal(
    selectDueGearEvent([HALLOWEEN], at("2026-11-02T00:00:00Z")),
    null
  );
});

test("the message is declarative and promises only what the catalogue has", () => {
  assert.deepEqual(buildGearDropMessage(THANKSGIVING), {
    body: "New items for your athlete. Your first climb this month " +
      "unlocks one.",
    title: "November gear just dropped",
  });
  assert.equal(
    buildGearDropMessage(HALLOWEEN).body,
    "New items for your athlete. Climb this month to earn them."
  );
});

test("push copy has no em dash and none of the banned words", () => {
  for (const event of [HALLOWEEN, THANKSGIVING]) {
    const {title, body} = buildGearDropMessage(event);
    for (const line of [title, body]) {
      assert.ok(!line.includes("—"), line);
      assert.ok(!/\b(race|live|field)\b/i.test(line), line);
    }
  }
});

test("the switch ships off: only an explicit true sends", () => {
  assert.equal(readGearDropSwitch({parameters: {}}), false);
  assert.equal(readGearDropSwitch(null), false);
  assert.equal(readGearDropSwitch({parameters: {
    gear_drop_push_enabled: {}}}), false);
  assert.equal(readGearDropSwitch({parameters: {
    gear_drop_push_enabled: {defaultValue: {value: "true"}}}}), true);
  assert.equal(readGearDropSwitch({parameters: {
    gear_drop_push_enabled: {defaultValue: {value: "false"}}}}), false);
});

// -----------------------------------------------------------------------------
// The sweep, against an in-memory store
// -----------------------------------------------------------------------------

/**
 * An in-memory store with the same create-once semantics as Firestore.
 */
class MemoryStore implements GearDropStore {
  dispatches = new Map<string, GearDropDispatch & {state: string}>();
  recorded: GearDropCounters[] = [];
  receipts = new Map<string, Set<string>>();
  pruned: string[] = [];
  devices: GearDropDevice[];

  /**
   * @param {GearDropDevice[]} devices - The audience, ordered by hash
   */
  constructor(devices: GearDropDevice[]) {
    this.devices = devices;
  }

  /** @inheritdoc */
  async createDispatch(
    event: GearEvent,
    message: {body: string; title: string}
  ) {
    if (this.dispatches.has(event.id)) {
      return false;
    }
    this.dispatches.set(event.id, {
      ...message,
      closesAt: gearDropWindow(event).closesAt,
      deviceCursor: null,
      id: event.id,
      state: "sending",
    });
    return true;
  }

  /** @inheritdoc */
  async listUnfinishedDispatches() {
    return [...this.dispatches.values()].filter((d) => d.state === "sending");
  }

  /** @inheritdoc */
  async loadDevicePage(after: string | null, limit: number) {
    const start = after ?
      this.devices.findIndex((d) => d.tokenHash === after) + 1 :
      0;
    const page = this.devices.slice(start, start + limit);
    return {
      devices: page,
      exhausted: page.length < limit,
      lastTokenHash: page[page.length - 1]?.tokenHash ?? null,
    };
  }

  /** @inheritdoc */
  async claimDevices(dispatchId: string, devices: GearDropDevice[]) {
    const held = this.receipts.get(dispatchId) ?? new Set<string>();
    this.receipts.set(dispatchId, held);
    return devices.filter((device) => {
      if (held.has(device.tokenHash)) {
        return false;
      }
      held.add(device.tokenHash);
      return true;
    });
  }

  /** @inheritdoc */
  async recordOutcomes(
    _dispatchId: string,
    _outcomes: unknown,
    counters: GearDropCounters
  ) {
    this.recorded.push({...counters});
  }

  /** @inheritdoc */
  async expireDispatch(dispatchId: string) {
    const dispatch = this.dispatches.get(dispatchId);
    if (dispatch) {
      dispatch.state = "expired";
    }
  }

  /** @inheritdoc */
  async advanceDispatch(dispatchId: string, cursor: string | null) {
    const dispatch = this.dispatches.get(dispatchId);
    if (dispatch) {
      dispatch.deviceCursor = cursor;
    }
  }

  /** @inheritdoc */
  async completeDispatch(dispatchId: string) {
    const dispatch = this.dispatches.get(dispatchId);
    if (dispatch) {
      dispatch.state = "sent";
    }
  }

  /** @inheritdoc */
  async pruneInvalidTokens(hashes: string[]) {
    this.pruned.push(...hashes);
  }
}

/**
 * @param {number} count - Devices to make
 * @return {GearDropDevice[]} Devices ordered by hash
 */
function makeDevices(count: number): GearDropDevice[] {
  return Array.from({length: count}, (_, index) => ({
    fcmToken: `token-${index}`,
    tokenHash: `hash-${String(index).padStart(4, "0")}`,
  }));
}

/**
 * @param {Partial<Parameters<typeof runGearDropSweep>[0]>} overrides - Deps
 * @param {MemoryStore} store - Store
 * @param {string[][]} sends - Receives the tokens of each send
 * @return {Parameters<typeof runGearDropSweep>[0]} Sweep deps
 */
function deps(
  overrides: Partial<Parameters<typeof runGearDropSweep>[0]>,
  store: MemoryStore,
  sends: string[][]
): Parameters<typeof runGearDropSweep>[0] {
  return {
    catalog: {fetch: async () => ({events: [HALLOWEEN, THANKSGIVING]})},
    isEnabled: async () => true,
    now: () => at("2026-11-01T17:00:00Z"),
    sender: {
      async send(request) {
        sends.push(request.tokens.map((device) => device.fcmToken));
        return request.tokens.map((device) => ({
          invalidToken: false, ok: true, tokenHash: device.tokenHash}));
      },
    },
    store,
    ...overrides,
  };
}

test("a due event is announced to every device once", async () => {
  const store = new MemoryStore(makeDevices(3));
  const sends: string[][] = [];
  const summary = await runGearDropSweep(deps({}, store, sends));

  assert.equal(summary.announced, "thanksgiving-2026");
  assert.deepEqual(summary.completed, ["thanksgiving-2026"]);
  assert.equal(summary.sent, 3);
  assert.deepEqual(sends, [["token-0", "token-1", "token-2"]]);
});

test("a second sweep sends nothing: the event is already announced", async () => {
  const store = new MemoryStore(makeDevices(3));
  const sends: string[][] = [];
  await runGearDropSweep(deps({}, store, sends));
  const again = await runGearDropSweep(deps({}, store, sends));

  assert.equal(again.announced, null);
  assert.equal(again.sent, 0);
  assert.equal(sends.length, 1);
});

test("a device already claimed is never sent a second time on resume", async () => {
  const store = new MemoryStore(makeDevices(2));
  await store.createDispatch(THANKSGIVING, buildGearDropMessage(THANKSGIVING));
  store.receipts.set("thanksgiving-2026", new Set(["hash-0000"]));
  const sends: string[][] = [];

  const summary = await runGearDropSweep(deps({}, store, sends));

  assert.deepEqual(sends, [["token-1"]]);
  assert.equal(summary.sent, 1);
});

test("a switch held off creates no dispatch and sends nothing", async () => {
  const store = new MemoryStore(makeDevices(3));
  const sends: string[][] = [];
  const summary = await runGearDropSweep(
    deps({isEnabled: async () => false}, store, sends));

  assert.equal(summary.sendingSkipped, true);
  assert.equal(store.dispatches.size, 0);
  assert.equal(sends.length, 0);
});

test("the event stays announceable after the switch returns", async () => {
  const store = new MemoryStore(makeDevices(1));
  const sends: string[][] = [];
  await runGearDropSweep(deps({isEnabled: async () => false}, store, sends));
  const summary = await runGearDropSweep(deps({}, store, sends));

  assert.equal(summary.announced, "thanksgiving-2026");
  assert.equal(sends.length, 1);
});

test("a switch that cannot be read sends nothing", async () => {
  const store = new MemoryStore(makeDevices(3));
  const sends: string[][] = [];
  const summary = await runGearDropSweep(deps({
    isEnabled: async () => {
      throw new Error("remote config unavailable");
    },
  }, store, sends));

  assert.equal(summary.sendingSkipped, true);
  assert.match(summary.detectionError ?? "", /switch_unreadable/);
  assert.equal(store.dispatches.size, 0);
  assert.equal(sends.length, 0);
});

test("a stale event is not announced even with the switch on", async () => {
  const store = new MemoryStore(makeDevices(3));
  const sends: string[][] = [];
  const summary = await runGearDropSweep(
    deps({now: () => at("2026-11-10T17:00:00Z")}, store, sends));

  assert.equal(summary.announced, null);
  assert.equal(store.dispatches.size, 0);
});

test("a catalogue fetch failure is recorded and delivery still runs", async () => {
  const store = new MemoryStore(makeDevices(2));
  await store.createDispatch(THANKSGIVING, buildGearDropMessage(THANKSGIVING));
  const sends: string[][] = [];
  const summary = await runGearDropSweep(deps({
    catalog: {fetch: async () => {
      throw new Error("hosting 503");
    }},
  }, store, sends));

  assert.equal(summary.detectionError, "hosting 503");
  assert.equal(summary.sent, 2);
});

test("a send that throws is written off, never retried", async () => {
  const store = new MemoryStore(makeDevices(2));
  const sends: string[][] = [];
  const failing = deps({
    sender: {send: async () => {
      throw new Error("fcm down");
    }},
  }, store, sends);

  const first = await runGearDropSweep(failing);
  assert.equal(first.failed, 2);
  assert.equal(first.sent, 0);

  const second = await runGearDropSweep(deps({}, store, sends));
  assert.equal(second.sent, 0, "the claimed devices are not sent again");
});

test("invalid tokens are pruned", async () => {
  const store = new MemoryStore(makeDevices(2));
  const sends: string[][] = [];
  const summary = await runGearDropSweep(deps({
    sender: {send: async (request) => request.tokens.map((device, index) => ({
      invalidToken: index === 1,
      ok: index !== 1,
      tokenHash: device.tokenHash,
    }))},
  }, store, sends));

  assert.equal(summary.invalidTokens, 1);
  assert.deepEqual(store.pruned, ["hash-0001"]);
});

test("each page records its own counts, never the running total", async () => {
  // 1,001 devices: three pages of 500, 500 and 1.
  const store = new MemoryStore(makeDevices(1001));
  const sends: string[][] = [];
  const summary = await runGearDropSweep(deps({}, store, sends));

  assert.equal(summary.sent, 1001);
  assert.deepEqual(store.recorded.map((delta) => delta.sent), [500, 500, 1]);
  const total = store.recorded.reduce((sum, delta) => sum + delta.sent, 0);
  assert.equal(total, 1001, "the dispatch document's increments add up");
  assert.equal(
    store.recorded.reduce((sum, delta) => sum + delta.claimed, 0),
    1001
  );
});

test("a dispatch whose window closed is expired, never resumed", async () => {
  const store = new MemoryStore(makeDevices(3));
  await store.createDispatch(THANKSGIVING, buildGearDropMessage(THANKSGIVING));
  const sends: string[][] = [];
  // December 10: the November event's window closed on November 4.
  const summary = await runGearDropSweep(
    deps({now: () => at("2026-12-10T17:00:00Z")}, store, sends));

  assert.deepEqual(summary.expired, ["thanksgiving-2026"]);
  assert.equal(sends.length, 0);
  assert.equal(store.dispatches.get("thanksgiving-2026")?.state, "expired");
});

test("a dispatch still inside its window resumes after the switch returns", async () => {
  const store = new MemoryStore(makeDevices(2));
  await store.createDispatch(THANKSGIVING, buildGearDropMessage(THANKSGIVING));
  const sends: string[][] = [];
  const held = await runGearDropSweep(
    deps({isEnabled: async () => false}, store, sends));
  assert.equal(held.sent, 0);

  const resumed = await runGearDropSweep(deps({}, store, sends));
  assert.equal(resumed.sent, 2);
  assert.equal(resumed.expired.length, 0);
});
