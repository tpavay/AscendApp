/**
 * The gear drop push: one `gear_drop` alert to every opted-in climber when a
 * gear event opens, read from the hosted unlock catalogue
 * (`web/public/unlocks/catalog.json`) the way `announceClimbDrops` reads the
 * climb catalogue.
 *
 * Gear events are content (`docs/seasonal-unlocks.md`): a new month is a new
 * catalogue entry and a hosting deploy, never a function change. This sweep
 * announces the event whose first day has arrived, and nothing else.
 *
 * ANNOUNCED ONCE, FOR GOOD. `gear_drop_dispatches/{eventId}` is created with
 * `create`, and its existence is the announcement: a rerun, a second instance
 * or a catalogue that flips back and forth finds it already there. A dispatch
 * pages through the audience across runs; each device's receipt is `create`d
 * before the send, so a resume can never alert a device twice. A send that
 * throws keeps its claim and is counted as failed rather than retried - a
 * missed nudge is cheaper than a second one.
 *
 * NEVER STALE. An event announces only from the first day's send hour for
 * three days, and never after it ended. The window closes a dispatch too: it
 * is stored on the dispatch, and a dispatch still unfinished when it closes is
 * expired rather than resumed, so a switch held off mid-send, or a run that
 * kept failing, cannot announce last month's gear weeks later.
 *
 * WHO. The same audience as the climb-drop alert: active iOS devices whose
 * climber turned notifications on and whose registration reports an
 * authorization iOS will deliver on. The onboarding primer's TURN ON writes
 * that one preference, so there is no second one to keep in step.
 *
 * OFF SWITCH, SHIPS OFF. Remote Config `gear_drop_push_enabled`, read from
 * the template on every run, is a rollout: it defaults to false, and only an
 * explicit true sends. Existing climbers opted in to climb alerts only, so no
 * gear push reaches anyone until the captain decides the consent question
 * (App Store guideline 4.5.4: promotional pushes need an explicit opt-in) and
 * turns it on. A switch that cannot be read, or is absent, sends nothing: a
 * push cannot be recalled, so unlike a data path this one fails closed.
 */

import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {claimReceipt} from "./climbDropNotifications";
import {runWithBoundedConcurrency} from "./concurrency";
import {
  deactivatePushTokensByHash,
  fcmInvalidTokenCodes,
  isDeliverableClimbDropRegistration,
} from "./pushNotifications";

export const GEAR_DROP_REMOTE_CONFIG_KEY = "gear_drop_push_enabled";
export const GEAR_DROP_DISPATCH_COLLECTION = "gear_drop_dispatches";
const RECEIPTS_COLLECTION = "receipts";

/** The hour (UTC) of an event's first day the announcement may go out. */
export const GEAR_DROP_SEND_HOUR_UTC = 16;
/** How long after its send hour an event may still be announced. */
export const GEAR_DROP_WINDOW_MS = 3 * 24 * 60 * 60 * 1000;
/** FCM's multicast ceiling, and the page size the sweep claims against. */
const DEVICE_PAGE_SIZE = 500;
/** Device pages per run. The remainder resumes on the next run. */
const MAX_DEVICE_PAGES_PER_RUN = 20;
/** Receipt creates in flight at once. */
const CLAIM_CONCURRENCY = 25;

export interface GearEvent {
  /** The catalogue id, e.g. "thanksgiving-2026". Names a Firestore document. */
  id: string;
  monthName: string;
  /** First day, YYYY-MM-DD, UTC. */
  startsOn: string;
  /** First day after the event, YYYY-MM-DD, UTC. */
  endsBefore: string;
  /** Whether one climb in the event unlocks a live item. */
  firstClimbUnlocksItem: boolean;
}

export interface GearDropMessage {
  body: string;
  title: string;
}

export interface GearDropDispatch {
  id: string;
  body: string;
  /** Epoch milliseconds the dispatch may no longer send after. */
  closesAt: number;
  deviceCursor: string | null;
  title: string;
}

export interface GearDropDevice {
  fcmToken: string;
  tokenHash: string;
}

export interface GearDropDevicePage {
  devices: GearDropDevice[];
  exhausted: boolean;
  lastTokenHash: string | null;
}

export interface GearDropSendOutcome {
  invalidToken: boolean;
  ok: boolean;
  tokenHash: string;
}

export interface GearDropCounters {
  claimed: number;
  failed: number;
  invalidTokens: number;
  sent: number;
}

export interface GearDropStore {
  /** Creates the dispatch; false when the event was already announced. */
  createDispatch(
    event: GearEvent,
    message: GearDropMessage
  ): Promise<boolean>;
  listUnfinishedDispatches(): Promise<GearDropDispatch[]>;
  loadDevicePage(
    afterTokenHash: string | null,
    limit: number
  ): Promise<GearDropDevicePage>;
  /** The devices this run won the receipt for; the rest were already sent. */
  claimDevices(
    dispatchId: string,
    devices: GearDropDevice[]
  ): Promise<GearDropDevice[]>;
  recordOutcomes(
    dispatchId: string,
    outcomes: GearDropSendOutcome[],
    counters: GearDropCounters
  ): Promise<void>;
  advanceDispatch(dispatchId: string, cursor: string | null): Promise<void>;
  completeDispatch(dispatchId: string): Promise<void>;
  /** Ends a dispatch whose window closed before its audience was reached. */
  expireDispatch(dispatchId: string): Promise<void>;
  pruneInvalidTokens(tokenHashes: string[]): Promise<void>;
}

export interface GearDropSender {
  send(request: {
    body: string;
    dispatchId: string;
    title: string;
    tokens: GearDropDevice[];
  }): Promise<GearDropSendOutcome[]>;
}

export interface GearDropCatalogSource {
  fetch(): Promise<{events: GearEvent[]}>;
}

export interface GearDropSweepSummary {
  announced: string | null;
  completed: string[];
  expired: string[];
  detectionError: string | null;
  dispatchErrors: Array<{dispatchId: string; message: string}>;
  sendingSkipped: boolean;
  sent: number;
  failed: number;
  invalidTokens: number;
}

// =============================================================================
// Pure helpers - unit-testable without Firestore
// =============================================================================

const DAY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const EVENT_ID_PATTERN = /^[a-z0-9][a-z0-9_-]{0,79}$/;

/**
 * Midnight UTC at the start of a catalogue day.
 * @param {string} day - YYYY-MM-DD
 * @return {number | null} Epoch milliseconds, or null when malformed
 */
export function dayStartMillis(day: unknown): number | null {
  if (typeof day !== "string") {
    return null;
  }
  const match = DAY_PATTERN.exec(day);
  if (!match) {
    return null;
  }
  const [, year, month, date] = match;
  const millis = Date.UTC(Number(year), Number(month) - 1, Number(date));
  const roundTrip = new Date(millis);
  if (roundTrip.getUTCFullYear() !== Number(year) ||
    roundTrip.getUTCMonth() !== Number(month) - 1 ||
    roundTrip.getUTCDate() !== Number(date)) {
    return null;
  }
  return millis;
}

/**
 * Reads the hosted unlock catalogue into the events the sweep can announce.
 *
 * One malformed event costs that event its announcement, never the sweep, and
 * is not recorded as announced, so a corrected publish sends it then.
 * @param {unknown} raw - The decoded catalogue JSON
 * @return {GearEvent[]} Usable events
 */
export function parseGearEvents(raw: unknown): GearEvent[] {
  if (!raw || typeof raw !== "object") {
    return [];
  }
  const catalogue = raw as {events?: unknown; items?: unknown};
  const events = Array.isArray(catalogue.events) ? catalogue.events : [];
  const items = Array.isArray(catalogue.items) ? catalogue.items : [];

  const firstClimbEvents = new Set<string>();
  for (const item of items) {
    const row = item as {
      earn?: {event?: unknown; metric?: unknown; threshold?: unknown};
      status?: unknown;
    } | null;
    if (row?.status === "live" && row.earn?.metric === "climbs" &&
      row.earn.threshold === 1 && typeof row.earn.event === "string") {
      firstClimbEvents.add(row.earn.event);
    }
  }

  const parsed: GearEvent[] = [];
  for (const entry of events) {
    const row = entry as Record<string, unknown> | null;
    const id = row?.id;
    const monthName = row?.monthName;
    const start = dayStartMillis(row?.startsOn);
    const end = dayStartMillis(row?.endsBefore);
    if (typeof id !== "string" || !EVENT_ID_PATTERN.test(id) ||
      typeof monthName !== "string" || monthName.trim().length === 0 ||
      start === null || end === null || start >= end) {
      continue;
    }
    parsed.push({
      endsBefore: row?.endsBefore as string,
      firstClimbUnlocksItem: firstClimbEvents.has(id),
      id,
      monthName: monthName.trim(),
      startsOn: row?.startsOn as string,
    });
  }
  return parsed;
}

/**
 * The window an event may be announced in: its first day's send hour until
 * three days later, and never past the event's own end.
 * @param {GearEvent} event - The event
 * @return {{opensAt: number, closesAt: number}} Epoch milliseconds
 */
export function gearDropWindow(
  event: GearEvent
): {opensAt: number; closesAt: number} {
  const start = dayStartMillis(event.startsOn) ?? 0;
  const end = dayStartMillis(event.endsBefore) ?? 0;
  const opensAt = start + GEAR_DROP_SEND_HOUR_UTC * 60 * 60 * 1000;
  return {
    closesAt: Math.min(opensAt + GEAR_DROP_WINDOW_MS, end),
    opensAt,
  };
}

/**
 * The one event to announce now, or null. An event is due once its window has
 * opened and until it closes; the most recent start wins when two overlap.
 * Whether it was already announced is the store's `create`, not a read here.
 * @param {GearEvent[]} events - Catalogue events
 * @param {Date} now - The sweep's clock
 * @return {GearEvent | null} The event to announce
 */
export function selectDueGearEvent(
  events: GearEvent[],
  now: Date
): GearEvent | null {
  const at = now.getTime();
  const due = events.filter((event) => {
    const {opensAt, closesAt} = gearDropWindow(event);
    return at >= opensAt && at < closesAt;
  });
  due.sort((a, b) => (dayStartMillis(b.startsOn) ?? 0) -
    (dayStartMillis(a.startsOn) ?? 0));
  return due[0] ?? null;
}

/**
 * The push's words. Declarative, an alert at the open, and it promises a
 * first-climb item only when the catalogue really has one.
 * @param {GearEvent} event - The event
 * @return {GearDropMessage} Title and body
 */
export function buildGearDropMessage(event: GearEvent): GearDropMessage {
  return {
    body: event.firstClimbUnlocksItem ?
      "New items for your athlete. Your first climb this month unlocks one." :
      "New items for your athlete. Climb this month to earn them.",
    title: `${event.monthName} gear just dropped`,
  };
}

/**
 * Reads the kill switch out of a Remote Config template.
 * @param {unknown} template - The template, as the Admin SDK returns it
 * @return {boolean} True only when the switch is explicitly on
 */
export function readGearDropSwitch(template: unknown): boolean {
  const parameters = (template as {parameters?: Record<string, unknown>} | null)
    ?.parameters;
  const parameter = parameters?.[GEAR_DROP_REMOTE_CONFIG_KEY] as {
    defaultValue?: {value?: unknown};
  } | undefined;
  const value = parameter?.defaultValue?.value;
  // Absent means off: the push is a rollout, and only an explicit true sends.
  return value !== undefined && String(value).toLowerCase() === "true";
}

// =============================================================================
// The sweep
// =============================================================================

export interface GearDropSweepDeps {
  catalog: GearDropCatalogSource;
  isEnabled(): Promise<boolean>;
  now(): Date;
  sender: GearDropSender;
  store: GearDropStore;
}

/**
 * One sweep: announce a newly due event, then advance every unfinished
 * dispatch. Detection is isolated from delivery, so hosting being unwell
 * cannot stall a dispatch that already exists.
 * @param {GearDropSweepDeps} deps - Injected collaborators
 * @return {Promise<GearDropSweepSummary>} What the run did
 */
export async function runGearDropSweep(
  deps: GearDropSweepDeps
): Promise<GearDropSweepSummary> {
  const summary: GearDropSweepSummary = {
    announced: null,
    completed: [],
    detectionError: null,
    dispatchErrors: [],
    expired: [],
    failed: 0,
    invalidTokens: 0,
    sendingSkipped: false,
    sent: 0,
  };

  // The operator stop comes first and covers detection too: a held switch
  // creates no dispatch, so the event stays announceable until its window
  // closes. A switch that cannot be read is a held switch.
  let enabled = false;
  try {
    enabled = await deps.isEnabled();
  } catch (error) {
    summary.detectionError = "switch_unreadable: " + messageOf(error);
  }
  if (!enabled) {
    summary.sendingSkipped = true;
    return summary;
  }

  try {
    const {events} = await deps.catalog.fetch();
    const due = selectDueGearEvent(events, deps.now());
    if (due) {
      const created = await deps.store.createDispatch(
        due,
        buildGearDropMessage(due)
      );
      summary.announced = created ? due.id : null;
    }
  } catch (error) {
    summary.detectionError = messageOf(error);
  }

  for (const dispatch of await deps.store.listUnfinishedDispatches()) {
    if (deps.now().getTime() >= dispatch.closesAt) {
      try {
        await deps.store.expireDispatch(dispatch.id);
        summary.expired.push(dispatch.id);
      } catch (error) {
        summary.dispatchErrors.push({
          dispatchId: dispatch.id,
          message: messageOf(error),
        });
      }
      continue;
    }
    const counters: GearDropCounters =
      {claimed: 0, failed: 0, invalidTokens: 0, sent: 0};
    try {
      if (await deliverDispatch(deps, dispatch, counters)) {
        summary.completed.push(dispatch.id);
      }
    } catch (error) {
      summary.dispatchErrors.push({
        dispatchId: dispatch.id,
        message: messageOf(error),
      });
    } finally {
      summary.sent += counters.sent;
      summary.failed += counters.failed;
      summary.invalidTokens += counters.invalidTokens;
    }
  }

  return summary;
}

/**
 * Walks one dispatch's audience, a page at a time, until the run's page
 * budget is spent or the audience is exhausted.
 * @param {GearDropSweepDeps} deps - Injected collaborators
 * @param {GearDropDispatch} dispatch - The dispatch to advance
 * @param {GearDropCounters} counters - Counters the caller reports
 * @return {Promise<boolean>} True when the audience was exhausted
 */
async function deliverDispatch(
  deps: GearDropSweepDeps,
  dispatch: GearDropDispatch,
  counters: GearDropCounters
): Promise<boolean> {
  let cursor = dispatch.deviceCursor;

  for (let pages = 0; pages < MAX_DEVICE_PAGES_PER_RUN; pages++) {
    const page = await deps.store.loadDevicePage(cursor, DEVICE_PAGE_SIZE);

    if (page.devices.length > 0) {
      const claimed = await deps.store.claimDevices(dispatch.id, page.devices);

      if (claimed.length > 0) {
        let outcomes: GearDropSendOutcome[];
        try {
          outcomes = await deps.sender.send({
            body: dispatch.body,
            dispatchId: dispatch.id,
            title: dispatch.title,
            tokens: claimed,
          });
        } catch {
          // Nothing reached FCM, but the claims stand: the page is written
          // off rather than retried, so a half-sent page can never alert a
          // device twice.
          outcomes = claimed.map((device) => ({
            invalidToken: false,
            ok: false,
            tokenHash: device.tokenHash,
          }));
        }

        const invalid = outcomes
          .filter((outcome) => outcome.invalidToken)
          .map((outcome) => outcome.tokenHash);
        // This page's own counts. The dispatch document accumulates them
        // with `increment`, so handing it the run's running total would
        // count every earlier page again.
        const delta: GearDropCounters = {
          claimed: claimed.length,
          failed: outcomes.filter((outcome) => !outcome.ok).length,
          invalidTokens: invalid.length,
          sent: outcomes.filter((outcome) => outcome.ok).length,
        };
        counters.claimed += delta.claimed;
        counters.failed += delta.failed;
        counters.invalidTokens += delta.invalidTokens;
        counters.sent += delta.sent;

        await deps.store.recordOutcomes(dispatch.id, outcomes, delta);
        await deps.store.pruneInvalidTokens(invalid);
      }
    }

    if (page.exhausted) {
      await deps.store.completeDispatch(dispatch.id);
      return true;
    }

    cursor = page.lastTokenHash;
    await deps.store.advanceDispatch(dispatch.id, cursor);
  }

  return false;
}

/**
 * A readable line for an unknown thrown value.
 * @param {unknown} error - Whatever was thrown
 * @return {string} A short message
 */
function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : "unknown_error";
}

// =============================================================================
// Production collaborators
// =============================================================================

/**
 * The hosting origin of the project this function runs in.
 * @return {string} Hosting base URL
 */
function hostingBaseUrl(): string {
  let projectId: string | undefined;
  try {
    projectId = admin.app().options.projectId;
  } catch {
    projectId = undefined;
  }
  projectId = projectId ?? process.env.GCLOUD_PROJECT ??
    process.env.GCP_PROJECT;
  if (!projectId) {
    throw new Error("The project ID is unavailable for catalogue loading.");
  }
  return `https://${projectId}.web.app`;
}

/**
 * The hosted unlock catalogue, same origin as the climb catalogue.
 * @return {GearDropCatalogSource} Source over Firebase Hosting
 */
export function makeHostedGearCatalogSource(): GearDropCatalogSource {
  return {
    async fetch() {
      const response = await fetch(`${hostingBaseUrl()}/unlocks/catalog.json`, {
        headers: {"cache-control": "no-cache"},
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) {
        throw new Error(`Unlock catalogue request failed (${response.status}).`);
      }
      return {events: parseGearEvents(await response.json())};
    },
  };
}

/**
 * Reads `gear_drop_push_enabled` from the project's Remote Config template.
 * @return {Promise<boolean>} Whether the push may send
 */
export async function readGearDropSwitchFromRemoteConfig(): Promise<boolean> {
  return readGearDropSwitch(await admin.remoteConfig().getTemplate());
}

/**
 * The Firestore-backed store.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @return {GearDropStore} Store over Firestore
 */
export function makeFirestoreGearDropStore(
  firestore: admin.firestore.Firestore
): GearDropStore {
  const dispatches = firestore.collection(GEAR_DROP_DISPATCH_COLLECTION);

  return {
    async advanceDispatch(dispatchId, cursor) {
      await dispatches.doc(dispatchId).update({
        deviceCursor: cursor,
        updatedAt: admin.firestore.Timestamp.now(),
      });
    },

    async claimDevices(dispatchId, devices) {
      const receipts = dispatches.doc(dispatchId)
        .collection(RECEIPTS_COLLECTION);
      const claimed: GearDropDevice[] = [];
      await runWithBoundedConcurrency(devices, CLAIM_CONCURRENCY,
        async (device) => {
          const outcome = await claimReceipt(() =>
            receipts.doc(device.tokenHash).create({
              claimedAt: admin.firestore.Timestamp.now(),
              state: "claimed",
            }));
          if (outcome === "claimed") {
            claimed.push(device);
          }
        });
      return claimed;
    },

    async completeDispatch(dispatchId) {
      const now = admin.firestore.Timestamp.now();
      await dispatches.doc(dispatchId).update({
        completedAt: now,
        deviceCursor: null,
        state: "sent",
        updatedAt: now,
      });
    },

    async createDispatch(event, message) {
      const now = admin.firestore.Timestamp.now();
      try {
        await dispatches.doc(event.id).create({
          body: message.body,
          claimedCount: 0,
          closesAt: admin.firestore.Timestamp.fromMillis(
            gearDropWindow(event).closesAt
          ),
          createdAt: now,
          deviceCursor: null,
          eventId: event.id,
          failedCount: 0,
          invalidTokenCount: 0,
          schemaVersion: 1,
          sentCount: 0,
          state: "sending",
          title: message.title,
          updatedAt: now,
        });
        return true;
      } catch (error) {
        const code = (error as {code?: unknown}).code;
        if (code === 6 || code === "already-exists") {
          return false;
        }
        throw error;
      }
    },

    async expireDispatch(dispatchId) {
      const now = admin.firestore.Timestamp.now();
      await dispatches.doc(dispatchId).update({
        expiredAt: now,
        state: "expired",
        updatedAt: now,
      });
    },

    async listUnfinishedDispatches() {
      // A single equality filter, so no composite index is needed; there is
      // rarely more than one unfinished dispatch and their order is moot.
      const snapshot = await dispatches.where("state", "==", "sending")
        .limit(3).get();
      return snapshot.docs.map((document) => {
        const closesAt = document.get("closesAt");
        return {
          body: String(document.get("body") ?? ""),
          closesAt: closesAt instanceof admin.firestore.Timestamp ?
            closesAt.toMillis() :
            0,
          deviceCursor: typeof document.get("deviceCursor") === "string" ?
            document.get("deviceCursor") as string :
            null,
          id: document.id,
          title: String(document.get("title") ?? ""),
        };
      });
    },

    async loadDevicePage(afterTokenHash, limit) {
      let query = firestore.collection("notification_devices")
        .where("active", "==", true)
        .where("climbDropPushEnabled", "==", true)
        .where("platform", "==", "ios")
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(limit);
      if (afterTokenHash) {
        query = query.startAfter(afterTokenHash);
      }
      const snapshot = await query.get();
      const devices: GearDropDevice[] = [];
      for (const document of snapshot.docs) {
        const data = document.data();
        if (isDeliverableClimbDropRegistration(data)) {
          devices.push({
            fcmToken: data.fcmToken as string,
            tokenHash: document.id,
          });
        }
      }
      return {
        devices,
        exhausted: snapshot.size < limit,
        lastTokenHash: snapshot.docs[snapshot.docs.length - 1]?.id ?? null,
      };
    },

    async pruneInvalidTokens(tokenHashes) {
      await deactivatePushTokensByHash(tokenHashes);
    },

    async recordOutcomes(dispatchId, outcomes, counters) {
      const receipts = dispatches.doc(dispatchId)
        .collection(RECEIPTS_COLLECTION);
      const now = admin.firestore.Timestamp.now();
      const batch = firestore.batch();
      for (const outcome of outcomes) {
        batch.set(receipts.doc(outcome.tokenHash), {
          settledAt: now,
          state: outcome.ok ?
            "delivered" :
            outcome.invalidToken ? "invalid_token" : "failed",
        }, {merge: true});
      }
      batch.update(dispatches.doc(dispatchId), {
        claimedCount: admin.firestore.FieldValue.increment(counters.claimed),
        failedCount: admin.firestore.FieldValue.increment(counters.failed),
        invalidTokenCount:
          admin.firestore.FieldValue.increment(counters.invalidTokens),
        sentCount: admin.firestore.FieldValue.increment(counters.sent),
        updatedAt: now,
      });
      await batch.commit();
    },
  };
}

/**
 * The FCM-backed sender. `type: "gear_drop"` carries no climb, so the app
 * routes nothing and a tap simply opens Ascend, where the event card is.
 * @param {admin.messaging.Messaging} messaging - Admin messaging instance
 * @return {GearDropSender} Sender over FCM multicast
 */
export function makeFcmGearDropSender(
  messaging: admin.messaging.Messaging
): GearDropSender {
  return {
    async send(request) {
      const response = await messaging.sendEachForMulticast({
        apns: {
          headers: {"apns-priority": "10", "apns-push-type": "alert"},
          payload: {aps: {sound: "default"}},
        },
        data: {
          campaignId: request.dispatchId,
          dispatchId: request.dispatchId,
          type: "gear_drop",
        },
        notification: {body: request.body, title: request.title},
        tokens: request.tokens.map((device) => device.fcmToken),
      });
      return response.responses.map((sendResponse, index) => {
        const errorCode = sendResponse.error?.code;
        return {
          invalidToken: Boolean(errorCode) &&
            fcmInvalidTokenCodes.has(errorCode as string),
          ok: sendResponse.success,
          tokenHash: request.tokens[index].tokenHash,
        };
      });
    },
  };
}

/**
 * Announces a gear event the day it opens.
 */
export const announceGearDrops = onSchedule(
  {
    // One sweep at a time: two would read the same device cursor and the
    // slower write would drag the dispatch back to a page already sent.
    concurrency: 1,
    maxInstances: 1,
    schedule: "every 15 minutes",
    timeZone: "Etc/UTC",
    timeoutSeconds: 540,
  },
  async () => {
    const summary = await runGearDropSweep({
      catalog: makeHostedGearCatalogSource(),
      isEnabled: readGearDropSwitchFromRemoteConfig,
      now: () => new Date(),
      sender: makeFcmGearDropSender(admin.messaging()),
      store: makeFirestoreGearDropStore(admin.firestore()),
    });
    const degraded = summary.detectionError !== null ||
      summary.dispatchErrors.length > 0;
    (degraded ? console.error : console.log)(
      degraded ?
        "announceGearDrops sweep degraded" :
        "announceGearDrops sweep completed",
      summary
    );
  }
);
