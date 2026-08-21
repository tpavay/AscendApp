import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {createHash} from "crypto";
import {
  deactivatePushTokensByHash,
  fcmInvalidTokenCodes,
  isDeliverableClimbDropRegistration,
} from "./pushNotifications";

/**
 * The shipped promise, in the climber's words.
 *
 * Onboarding: "Get an Ascend alert when new climbs open." Settings:
 * "A new landmark opens in the catalog." Collection: "Be the first to know
 * when new climbs drop." Every user-facing string is an alert *at* the open,
 * not advance notice, so this sweep sends the moment a climb reaches
 * `available` in the hosted catalog rather than trying to predict one.
 *
 * There is nothing to predict against, either: the catalogue is a static file
 * published by a hosting deploy, and it carries no unlock timestamp. Advance
 * notice would need a scheduled open time in the catalogue *and* a client that
 * withholds the climb until it arrives - a client change, which this cannot be.
 */

const STATE_COLLECTION = "climb_drop_notification_state";
const STATE_DOCUMENT_ID = "current";
const DISPATCH_COLLECTION = "climb_drop_dispatches";
const RECEIPTS_COLLECTION = "receipts";

/** FCM's multicast ceiling, and the page size the sweep claims against. */
const DEVICE_PAGE_SIZE = 500;
/** Device pages per run. The remainder resumes on the next run. */
const MAX_DEVICE_PAGES_PER_RUN = 20;
/** Dispatches advanced per run, oldest first. */
const MAX_DISPATCHES_PER_RUN = 3;
/** Receipt creates in flight at once, so a page cannot flood Firestore. */
const CLAIM_CONCURRENCY = 25;
/** Firestore rejects an ALREADY_EXISTS create with this gRPC code. */
const ALREADY_EXISTS_CODE = 6;

const MAX_TITLE_LENGTH = 80;
const MAX_BODY_LENGTH = 180;

export type ClimbDropDispatchState = "pending" | "sending" | "sent";

export interface CatalogClimb {
  id: string;
  name: string;
  city?: string | null;
  releaseState?: string | null;
  realStairCount?: number | null;
  totalSteps?: number | null;
}

export interface ClimbCatalogManifest {
  catalogVersion: number;
  catalogPath: string;
}

export interface ClimbDropSweepState {
  announcedClimbIds: string[];
  lastCatalogVersion: number | null;
  sendingEnabled: boolean;
}

export interface ClimbDropDispatch {
  id: string;
  body: string;
  catalogVersion: number | null;
  climbIds: string[];
  deviceCursor: string | null;
  primaryClimbId: string;
  state: ClimbDropDispatchState;
  title: string;
}

export interface ClimbDropDevice {
  fcmToken: string;
  tokenHash: string;
}

export interface ClimbDropDevicePage {
  devices: ClimbDropDevice[];
  exhausted: boolean;
  lastTokenHash: string | null;
}

export interface ClimbDropSendOutcome {
  errorCode: string | null;
  invalidToken: boolean;
  ok: boolean;
  tokenHash: string;
}

export interface ClimbDropClaimResult {
  claimed: ClimbDropDevice[];
  unclaimedCount: number;
}

export interface ClimbDropCatalogSource {
  fetchManifest(): Promise<ClimbCatalogManifest>;
  fetchClimbs(manifest: ClimbCatalogManifest): Promise<CatalogClimb[]>;
}

export interface ClimbDropStore {
  readState(): Promise<ClimbDropSweepState | null>;
  writeBootstrapState(
    announcedClimbIds: string[],
    catalogVersion: number | null
  ): Promise<void>;
  recordCatalogCheck(
    announcedClimbIds: string[],
    catalogVersion: number | null
  ): Promise<void>;
  createDispatchWithBaseline(
    dispatch: ClimbDropDispatch,
    announcedClimbIds: string[],
    catalogVersion: number | null
  ): Promise<boolean>;
  listUnfinishedDispatches(limit: number): Promise<ClimbDropDispatch[]>;
  loadDevicePage(
    afterTokenHash: string | null,
    limit: number
  ): Promise<ClimbDropDevicePage>;
  claimDevices(
    dispatchId: string,
    devices: ClimbDropDevice[]
  ): Promise<ClimbDropClaimResult>;
  recordSendOutcomes(
    dispatchId: string,
    outcomes: ClimbDropSendOutcome[]
  ): Promise<void>;
  advanceDispatch(
    dispatchId: string,
    cursor: string | null,
    counters: ClimbDropSendCounters
  ): Promise<void>;
  completeDispatch(
    dispatchId: string,
    counters: ClimbDropSendCounters
  ): Promise<void>;
  pruneInvalidTokens(tokenHashes: string[]): Promise<void>;
}

export interface ClimbDropSender {
  send(request: {
    body: string;
    climbIds: string[];
    dispatchId: string;
    primaryClimbId: string;
    title: string;
    tokens: ClimbDropDevice[];
  }): Promise<ClimbDropSendOutcome[]>;
}

export interface ClimbDropSendCounters {
  claimedCount: number;
  failedCount: number;
  invalidTokenCount: number;
  sentCount: number;
  unclaimedCount: number;
}

export interface ClimbDropSweepSummary {
  bootstrapped: boolean;
  claimedCount: number;
  dispatchesCreated: string[];
  dispatchesCompleted: string[];
  dispatchErrors: Array<{dispatchId: string; message: string}>;
  failedCount: number;
  invalidTokenCount: number;
  newlyAvailableClimbIds: string[];
  sendingSkipped: boolean;
  sentCount: number;
  unclaimedCount: number;
}

export interface ClimbDropSweepOptions {
  devicePageSize?: number;
  maxDevicePages?: number;
  maxDispatches?: number;
}

/**
 * The climbs a climber can currently race.
 * @param {CatalogClimb[]} climbs Catalogue entries.
 * @return {string[]} Sorted available climb IDs.
 */
export function availableClimbIds(climbs: CatalogClimb[]): string[] {
  return climbs
    .filter((climb) => climb.releaseState === "available")
    .map((climb) => climb.id)
    .filter((id) => typeof id === "string" && id.length > 0)
    .sort();
}

/**
 * The climbs that have opened since the last announcement.
 *
 * The baseline is monotonic - every climb Ascend has ever announced stays in
 * it - so a climb pulled back to `hidden` and later reopened does not announce
 * a second time. A drop is a one-time event per climb, for good: the promise
 * is that a climber hears about a *new* landmark, and the receipts under a
 * dispatch are only a complete no-duplicate guarantee because a climb can
 * belong to exactly one dispatch.
 * @param {CatalogClimb[]} climbs Catalogue entries.
 * @param {string[]} announcedClimbIds Climb IDs already announced.
 * @return {CatalogClimb[]} Newly available climbs, in announcement order.
 */
export function detectNewlyAvailableClimbs(
  climbs: CatalogClimb[],
  announcedClimbIds: string[]
): CatalogClimb[] {
  const announced = new Set(announcedClimbIds);
  const available = new Set(availableClimbIds(climbs));
  const seen = new Set<string>();

  return climbs
    .filter((climb) => {
      if (!available.has(climb.id) || announced.has(climb.id) ||
        seen.has(climb.id)) {
        return false;
      }
      seen.add(climb.id);
      return true;
    })
    .sort(compareByRaceDistance);
}

/**
 * The step count a climb is actually raced over.
 *
 * `realStairCount` is the verified route; `totalSteps` is the height
 * derivation that stands in until one is published. Copy quotes this number,
 * so it follows the same preference the app ranks on.
 * @param {CatalogClimb} climb Catalogue entry.
 * @return {number | null} Reference step count, when the catalogue states one.
 */
export function referenceStepCount(climb: CatalogClimb): number | null {
  for (const candidate of [climb.realStairCount, climb.totalSteps]) {
    if (typeof candidate === "number" && Number.isFinite(candidate) &&
      candidate > 0) {
      return Math.round(candidate);
    }
  }
  return null;
}

/**
 * The stable dispatch ID for a set of climbs opening together.
 *
 * Derived from the climb IDs alone, so re-detecting the same drop - a retry, a
 * redeploy, a state write that failed after the dispatch was created - lands on
 * the document that already exists instead of announcing twice.
 * @param {string[]} climbIds Climb IDs in the drop.
 * @return {string} Deterministic dispatch document ID.
 */
export function buildClimbDropDispatchId(climbIds: string[]): string {
  const sorted = [...climbIds].sort();
  const digest = createHash("sha256")
    .update(sorted.join("\n"))
    .digest("hex")
    .slice(0, 12);
  return `${sorted[0]}-${digest}`;
}

/**
 * Builds the alert for a drop.
 *
 * One push per drop, never one per climb: a deploy that opens four landmarks
 * owes the climber one alert, not four. The marquee climb - the longest race
 * in the drop - leads the copy and carries `climbId`, so the tap the shipped
 * build already routes lands on a real climb detail screen.
 * @param {CatalogClimb[]} climbs Newly available climbs.
 * @return {object} Title, body, and the climb the payload deep-links to.
 */
export function buildClimbDropMessage(climbs: CatalogClimb[]): {
  body: string;
  climbIds: string[];
  primaryClimbId: string;
  title: string;
} {
  if (climbs.length === 0) {
    throw new Error("A climb drop needs at least one climb.");
  }

  const ordered = [...climbs].sort(compareByRaceDistance);
  const names = ordered.map((climb) => climb.name?.trim() || climb.id);

  return {
    body: truncate(buildBody(ordered, names), MAX_BODY_LENGTH),
    climbIds: ordered.map((climb) => climb.id),
    primaryClimbId: ordered[0].id,
    title: truncate(buildTitle(ordered, names), MAX_TITLE_LENGTH),
  };
}

/**
 * Runs one climb-drop sweep: detect the drop, then send what is owed.
 *
 * Detection and sending are separate so a run that dies mid-send leaves a
 * dispatch the next run resumes. Nothing about the resume can duplicate: a
 * device is claimed by creating its receipt, and a receipt that already exists
 * is a device that has already been sent to.
 * @param {object} deps Injected catalogue, store, and sender.
 * @param {ClimbDropSweepOptions} options Per-run bounds.
 * @return {Promise<ClimbDropSweepSummary>} What the sweep did.
 */
export async function runClimbDropSweep(
  deps: {
    catalog: ClimbDropCatalogSource;
    sender: ClimbDropSender;
    store: ClimbDropStore;
  },
  options: ClimbDropSweepOptions = {}
): Promise<ClimbDropSweepSummary> {
  const summary: ClimbDropSweepSummary = {
    bootstrapped: false,
    claimedCount: 0,
    dispatchErrors: [],
    dispatchesCompleted: [],
    dispatchesCreated: [],
    failedCount: 0,
    invalidTokenCount: 0,
    newlyAvailableClimbIds: [],
    sendingSkipped: false,
    sentCount: 0,
    unclaimedCount: 0,
  };

  const state = await deps.store.readState();

  // First run in an environment. Every available climb is "new" against an
  // empty baseline, so recording the catalogue is the only safe thing to do:
  // announcing the whole catalogue as a drop is the fan-out disaster this
  // function exists to avoid.
  if (!state) {
    const manifest = await deps.catalog.fetchManifest();
    const climbs = await deps.catalog.fetchClimbs(manifest);
    await deps.store.writeBootstrapState(
      availableClimbIds(climbs),
      manifest.catalogVersion
    );
    summary.bootstrapped = true;
    return summary;
  }

  const manifest = await deps.catalog.fetchManifest();
  if (manifest.catalogVersion !== state.lastCatalogVersion) {
    const climbs = await deps.catalog.fetchClimbs(manifest);
    const newlyAvailable = detectNewlyAvailableClimbs(
      climbs,
      state.announcedClimbIds
    );
    summary.newlyAvailableClimbIds = newlyAvailable.map((climb) => climb.id);

    const baseline = mergeAnnouncedClimbIds(
      state.announcedClimbIds,
      availableClimbIds(climbs)
    );

    // The dispatch and the baseline move as one write, so neither can outlive
    // the other. Two writes leave both orders broken: a baseline that lands
    // first records the climb as announced while nothing exists to announce it
    // and never re-detects it, and a dispatch that lands first re-detects the
    // same climb inside a differently-hashed union whose receipts are a fresh
    // ledger - a second push for a climb already sent. A climb belongs to
    // exactly one dispatch, for good, and that is what the whole no-duplicate
    // guarantee rests on.
    if (newlyAvailable.length > 0) {
      const message = buildClimbDropMessage(newlyAvailable);
      const dispatchId = buildClimbDropDispatchId(message.climbIds);
      const created = await deps.store.createDispatchWithBaseline(
        {
          body: message.body,
          catalogVersion: manifest.catalogVersion,
          climbIds: message.climbIds,
          deviceCursor: null,
          id: dispatchId,
          primaryClimbId: message.primaryClimbId,
          state: "pending",
          title: message.title,
        },
        baseline,
        manifest.catalogVersion
      );
      if (created) {
        summary.dispatchesCreated.push(dispatchId);
      }
    } else {
      await deps.store.recordCatalogCheck(baseline, manifest.catalogVersion);
    }
  }

  // The operator stop. A held sweep defers: dispatches stay unfinished and the
  // first run after the flag returns picks them up where they were left.
  if (!state.sendingEnabled) {
    summary.sendingSkipped = true;
    return summary;
  }

  const dispatches = await deps.store.listUnfinishedDispatches(
    options.maxDispatches ?? MAX_DISPATCHES_PER_RUN
  );

  for (const dispatch of dispatches) {
    // Isolated per dispatch: one drop whose send is failing must not stall the
    // drop behind it. The dispatch stays unfinished and the next scheduled run
    // resumes it, which is this function's retry - and the receipts already
    // written mean the resume cannot duplicate.
    try {
      const result = await deliverDispatch(deps, dispatch, options);
      summary.claimedCount += result.claimedCount;
      summary.failedCount += result.failedCount;
      summary.invalidTokenCount += result.invalidTokenCount;
      summary.sentCount += result.sentCount;
      summary.unclaimedCount += result.unclaimedCount;
      if (result.completed) {
        summary.dispatchesCompleted.push(dispatch.id);
      }
    } catch (error) {
      summary.dispatchErrors.push({
        dispatchId: dispatch.id,
        message: error instanceof Error ? error.message : "unknown_error",
      });
    }
  }

  return summary;
}

/**
 * Sends one dispatch to as many devices as this run's budget allows.
 *
 * The cursor is persisted at every page boundary rather than once at the end
 * of the run. A run the platform kills mid-drop - the invocation timeout is
 * the one deadline this function cannot negotiate with - then resumes at the
 * last page it finished instead of re-walking every page it already sent to.
 * Correctness never depended on that: the receipts stop a re-walk duplicating.
 * What it costs is a full re-scan and a failed claim per already-alerted
 * device, every run, for as long as the drop takes to finish.
 * @param {object} deps Injected store and sender.
 * @param {ClimbDropDispatch} dispatch Dispatch to advance.
 * @param {ClimbDropSweepOptions} options Per-run bounds.
 * @return {Promise<object>} Counters plus whether the dispatch finished.
 */
async function deliverDispatch(
  deps: {sender: ClimbDropSender; store: ClimbDropStore},
  dispatch: ClimbDropDispatch,
  options: ClimbDropSweepOptions
): Promise<ClimbDropSendCounters & {completed: boolean}> {
  const pageSize = options.devicePageSize ?? DEVICE_PAGE_SIZE;
  const maxPages = options.maxDevicePages ?? MAX_DEVICE_PAGES_PER_RUN;
  const total: ClimbDropSendCounters = emptyCounters();
  let cursor = dispatch.deviceCursor;
  let completed = false;

  for (let page = 0; page < maxPages; page++) {
    // Counted per page, because the dispatch document is written per page and
    // its counters are Firestore increments: carrying a running total across
    // pages would add every earlier page again on every write.
    const counters = emptyCounters();
    const pageStartCursor = cursor;
    const devicePage = await deps.store.loadDevicePage(cursor, pageSize);
    cursor = devicePage.lastTokenHash ?? cursor;

    if (devicePage.devices.length > 0) {
      // Claim before sending. The receipt is what makes a re-run skip the
      // device, so a crash between the claim and the send costs that page its
      // alert - the side of the trade the promise can survive. The other order
      // costs a duplicate push, which it cannot.
      const claim = await deps.store.claimDevices(
        dispatch.id,
        devicePage.devices
      );
      counters.claimedCount += claim.claimed.length;
      counters.unclaimedCount += claim.unclaimedCount;

      if (claim.claimed.length > 0) {
        const outcomes = await deps.sender.send({
          body: dispatch.body,
          climbIds: dispatch.climbIds,
          dispatchId: dispatch.id,
          primaryClimbId: dispatch.primaryClimbId,
          title: dispatch.title,
          tokens: claim.claimed,
        });

        await deps.store.recordSendOutcomes(dispatch.id, outcomes);

        const invalidTokenHashes = outcomes
          .filter((outcome) => outcome.invalidToken)
          .map((outcome) => outcome.tokenHash);
        await deps.store.pruneInvalidTokens(invalidTokenHashes);

        counters.invalidTokenCount += invalidTokenHashes.length;
        counters.sentCount += outcomes.filter((one) => one.ok).length;
        counters.failedCount += outcomes.filter((one) => !one.ok).length;
      }
    }

    total.claimedCount += counters.claimedCount;
    total.failedCount += counters.failedCount;
    total.invalidTokenCount += counters.invalidTokenCount;
    total.sentCount += counters.sentCount;
    total.unclaimedCount += counters.unclaimedCount;

    // A device whose claim never landed has neither a receipt nor an alert, so
    // moving the cursor past its page would cost it the drop for good. The
    // cursor stays where the page started and the next run re-walks it: the
    // devices already claimed refuse a second claim, and the ones that did not
    // get their attempt.
    if (counters.unclaimedCount > 0) {
      await deps.store.advanceDispatch(
        dispatch.id,
        pageStartCursor,
        counters
      );
      break;
    }

    if (devicePage.exhausted) {
      completed = true;
      await deps.store.completeDispatch(dispatch.id, counters);
      break;
    }

    await deps.store.advanceDispatch(dispatch.id, cursor, counters);
  }

  return {...total, completed};
}

/**
 * A zeroed counter set for one page or run.
 * @return {ClimbDropSendCounters} Counters at zero.
 */
function emptyCounters(): ClimbDropSendCounters {
  return {
    claimedCount: 0,
    failedCount: 0,
    invalidTokenCount: 0,
    sentCount: 0,
    unclaimedCount: 0,
  };
}

/**
 * The fields one page boundary may write onto a dispatch document.
 *
 * A completed drop stays completed: `sent` is terminal, so a lagging writer
 * cannot flip a finished dispatch back into the unfinished set and send it a
 * second lap. The cursor only ever moves forward for the same reason - an
 * older cursor would re-walk pages that are already done.
 * @param {object} current Stored dispatch state and cursor.
 * @param {string | null} cursor Cursor this page reached.
 * @return {object} Fields to merge, empty when the dispatch is finished.
 */
export function planDispatchAdvance(
  current: {deviceCursor: string | null; state: string | null},
  cursor: string | null
): {deviceCursor?: string; state?: ClimbDropDispatchState} {
  if (current.state === "sent") {
    return {};
  }
  const advanced: {deviceCursor?: string; state?: ClimbDropDispatchState} = {
    state: "sending",
  };
  if (cursor !== null &&
    (current.deviceCursor === null || cursor > current.deviceCursor)) {
    advanced.deviceCursor = cursor;
  }
  return advanced;
}

/**
 * Unions the baseline with the currently available set.
 * @param {string[]} announcedClimbIds Existing baseline.
 * @param {string[]} availableIds Currently available climb IDs.
 * @return {string[]} Sorted monotonic baseline.
 */
export function mergeAnnouncedClimbIds(
  announcedClimbIds: string[],
  availableIds: string[]
): string[] {
  return [...new Set([...announcedClimbIds, ...availableIds])].sort();
}

/**
 * Orders climbs by race distance, longest first, then by ID.
 * @param {CatalogClimb} left First climb.
 * @param {CatalogClimb} right Second climb.
 * @return {number} Comparison result.
 */
function compareByRaceDistance(
  left: CatalogClimb,
  right: CatalogClimb
): number {
  const difference = (referenceStepCount(right) ?? 0) -
    (referenceStepCount(left) ?? 0);
  return difference !== 0 ? difference : left.id.localeCompare(right.id);
}

/**
 * Builds the alert title.
 * @param {CatalogClimb[]} climbs Ordered climbs in the drop.
 * @param {string[]} names Display names in the same order.
 * @return {string} Notification title.
 */
function buildTitle(climbs: CatalogClimb[], names: string[]): string {
  if (climbs.length === 1) {
    return `New climb: ${names[0]}`;
  }
  return `${climbs.length} new climbs open`;
}

/**
 * Builds the alert body.
 *
 * Specific over abstract: a single drop names the city and the race distance,
 * because those are the numbers a climber decides on. Nothing here claims the
 * First Ascent is still open - a reopened climb may already have been taken,
 * and a push cannot check.
 * @param {CatalogClimb[]} climbs Ordered climbs in the drop.
 * @param {string[]} names Display names in the same order.
 * @return {string} Notification body.
 */
function buildBody(climbs: CatalogClimb[], names: string[]): string {
  if (climbs.length === 1) {
    const parts: string[] = [];
    const city = climbs[0].city?.trim();
    if (city) {
      parts.push(city);
    }
    const steps = referenceStepCount(climbs[0]);
    if (steps !== null) {
      parts.push(`${steps.toLocaleString("en-US")} steps`);
    }
    parts.push("Be first up.");
    return parts.join(". ");
  }

  if (climbs.length === 2) {
    return `${names[0]} and ${names[1]} just landed. Be first up.`;
  }

  return `${names[0]}, ${names[1]} and ${climbs.length - 2} more ` +
    "just landed. Be first up.";
}

/**
 * Trims a string to a maximum length.
 * @param {string} value Candidate string.
 * @param {number} maxLength Maximum length.
 * @return {string} Bounded string.
 */
function truncate(value: string, maxLength: number): string {
  return value.length <= maxLength ?
    value :
    `${value.slice(0, maxLength - 1).trimEnd()}…`;
}

/**
 * Reads the hosted catalogue the app itself reads.
 *
 * Same origin, same files: `https://{projectId}.web.app/climbs/...`. The
 * catalogue is cached for an hour at the edge, so the fetch carries the
 * manifest's version as a cache key - a published drop is visible to this
 * sweep as soon as the manifest is, rather than up to an hour later.
 * @return {ClimbDropCatalogSource} Catalogue source over Firebase Hosting.
 */
export function makeHostedClimbCatalogSource(): ClimbDropCatalogSource {
  return {
    async fetchClimbs(manifest) {
      const path = manifest.catalogPath.startsWith("/") ?
        manifest.catalogPath.slice(1) :
        manifest.catalogPath;
      const url = `${hostingBaseUrl()}/${path}` +
        `?catalogVersion=${manifest.catalogVersion}`;
      const climbs = await fetchJson(url);
      if (!Array.isArray(climbs)) {
        throw new Error("Climb catalogue must be an array.");
      }
      return normalizeCatalogClimbs(climbs);
    },
    async fetchManifest() {
      const manifest = await fetchJson(
        `${hostingBaseUrl()}/climbs/manifest.json`
      );
      const catalogVersion = (manifest as {catalogVersion?: unknown})
        .catalogVersion;
      const catalogPath = (manifest as {catalogPath?: unknown}).catalogPath;
      if (typeof catalogVersion !== "number" ||
        typeof catalogPath !== "string" || catalogPath.length === 0) {
        throw new Error("Climb catalogue manifest is malformed.");
      }
      return {catalogPath, catalogVersion};
    },
  };
}

/**
 * Reads the hosted catalogue into entries the sender can announce.
 *
 * One malformed row costs that climb its announcement, never the sweep: an
 * entry without an id or a name is skipped, so detection - and every other
 * drop in the same publish - still runs. A skipped climb is not recorded in
 * the baseline either, so a corrected publish announces it then.
 * @param {unknown[]} entries Raw catalogue entries.
 * @return {CatalogClimb[]} Entries with the fields the sender needs.
 */
export function normalizeCatalogClimbs(entries: unknown[]): CatalogClimb[] {
  const climbs: CatalogClimb[] = [];
  for (const entry of entries) {
    if (!entry || typeof entry !== "object") {
      console.error("climb drop catalogue entry is not an object");
      continue;
    }
    const candidate = entry as Record<string, unknown>;
    const id = typeof candidate.id === "string" ? candidate.id.trim() : "";
    const name = typeof candidate.name === "string" ?
      candidate.name.trim() :
      "";
    if (id.length === 0 || name.length === 0) {
      console.error("climb drop catalogue entry skipped", {id: id || null});
      continue;
    }
    climbs.push({
      city: typeof candidate.city === "string" ? candidate.city : null,
      id,
      name,
      realStairCount: finiteNumberOrNull(candidate.realStairCount),
      releaseState: typeof candidate.releaseState === "string" ?
        candidate.releaseState :
        null,
      totalSteps: finiteNumberOrNull(candidate.totalSteps),
    });
  }
  return climbs;
}

/**
 * Reads a finite number, or nothing.
 * @param {unknown} value Candidate value.
 * @return {number | null} The number when it is usable.
 */
function finiteNumberOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * The hosting origin for the project this function runs in.
 * @return {string} Hosting base URL.
 */
function hostingBaseUrl(): string {
  const projectId = deployedProjectId() ??
    process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT;
  if (!projectId) {
    throw new Error("The project ID is unavailable for catalogue loading.");
  }
  return `https://${projectId}.web.app`;
}

/**
 * The project this function is deployed into.
 * @return {string | undefined} Project ID, when the app resolves one.
 */
function deployedProjectId(): string | undefined {
  try {
    return admin.app().options.projectId;
  } catch {
    return undefined;
  }
}

/**
 * Fetches and decodes a JSON document.
 * @param {string} url Absolute URL.
 * @return {Promise<unknown>} Decoded JSON.
 */
async function fetchJson(url: string): Promise<unknown> {
  // A hung hosting request must not eat the interval the next run needs.
  const response = await fetch(url, {
    headers: {"cache-control": "no-cache"},
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    throw new Error(`Catalogue request failed (${response.status}).`);
  }
  return response.json();
}

/**
 * Builds the Firestore-backed climb-drop store.
 * @param {admin.firestore.Firestore} firestore Admin Firestore instance.
 * @return {ClimbDropStore} Store over Firestore.
 */
export function makeFirestoreClimbDropStore(
  firestore: admin.firestore.Firestore
): ClimbDropStore {
  const stateRef = firestore
    .collection(STATE_COLLECTION)
    .doc(STATE_DOCUMENT_ID);
  const dispatches = firestore.collection(DISPATCH_COLLECTION);

  /**
   * The baseline fields one catalogue check writes.
   * @param {string[]} announcedClimbIds Monotonic baseline.
   * @param {number | null} catalogVersion Version just read.
   * @param {admin.firestore.Timestamp} now Write time.
   * @return {object} Fields to merge onto the state document.
   */
  function catalogCheckFields(
    announcedClimbIds: string[],
    catalogVersion: number | null,
    now: admin.firestore.Timestamp
  ) {
    return {
      announcedClimbIds,
      lastCatalogChangeAt: now,
      lastCatalogVersion: catalogVersion,
      schemaVersion: 1,
      updatedAt: now,
    };
  }

  return {
    async advanceDispatch(dispatchId, cursor, counters) {
      const dispatchRef = dispatches.doc(dispatchId);
      await firestore.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(dispatchRef);
        const data = snapshot.data() ?? {};
        transaction.set(dispatchRef, {
          updatedAt: admin.firestore.Timestamp.now(),
          ...incrementCounters(counters),
          ...planDispatchAdvance({
            deviceCursor: typeof data.deviceCursor === "string" ?
              data.deviceCursor :
              null,
            state: typeof data.state === "string" ? data.state : null,
          }, cursor),
        }, {merge: true});
      });
    },

    async claimDevices(dispatchId, devices) {
      const receipts = dispatches
        .doc(dispatchId)
        .collection(RECEIPTS_COLLECTION);
      const now = admin.firestore.Timestamp.now();
      const claimed: ClimbDropDevice[] = [];
      let unclaimedCount = 0;
      let next = 0;

      // Bounded concurrency, and no worker rejects. A page of 500 unthrottled
      // creates invites the very RESOURCE_EXHAUSTED it then cannot survive,
      // and a rejection here would abandon the receipts that already landed:
      // those devices would be claimed for good and never sent to.
      const workers = Array.from(
        {length: Math.min(CLAIM_CONCURRENCY, devices.length)},
        async () => {
          while (next < devices.length) {
            const device = devices[next];
            next += 1;
            try {
              // A receipt names the device, never the climber. Storing the uid
              // here would put user-keyed data outside the users/{uid} subtree,
              // which account deletion would then owe its own sweep - and the
              // ledger does not need it: the send question is "has this token
              // already been alerted for this drop".
              await receipts.doc(device.tokenHash).create({
                claimedAt: now,
                dispatchId,
                errorCode: null,
                schemaVersion: 1,
                state: "claimed",
              });
              claimed.push(device);
            } catch (error) {
              // An existing receipt is the whole no-duplicate guarantee: this
              // device has already been sent to for this drop, by an earlier
              // run or by a concurrent one. Anything else leaves the device
              // unclaimed, and the page it belongs to is re-walked.
              if (isAlreadyExistsError(error)) {
                continue;
              }
              unclaimedCount += 1;
              console.error("climb drop receipt claim failed", {
                dispatchId,
                message: error instanceof Error ?
                  error.message :
                  "unknown_error",
              });
            }
          }
        }
      );
      await Promise.all(workers);

      return {claimed, unclaimedCount};
    },

    async completeDispatch(dispatchId, counters) {
      const now = admin.firestore.Timestamp.now();
      await dispatches.doc(dispatchId).set({
        completedAt: now,
        state: "sent",
        updatedAt: now,
        ...incrementCounters(counters),
      }, {merge: true});
    },

    async createDispatchWithBaseline(
      dispatch,
      announcedClimbIds,
      catalogVersion
    ) {
      const now = admin.firestore.Timestamp.now();
      const batch = firestore.batch();
      batch.create(dispatches.doc(dispatch.id), {
        body: dispatch.body,
        catalogVersion: dispatch.catalogVersion,
        claimedCount: 0,
        climbIds: dispatch.climbIds,
        completedAt: null,
        createdAt: now,
        deviceCursor: null,
        failedCount: 0,
        invalidTokenCount: 0,
        primaryClimbId: dispatch.primaryClimbId,
        schemaVersion: 1,
        sentCount: 0,
        state: "pending",
        title: dispatch.title,
        type: "climb_drop",
        unclaimedCount: 0,
        updatedAt: now,
      });
      batch.set(
        stateRef,
        catalogCheckFields(announcedClimbIds, catalogVersion, now),
        {merge: true}
      );

      try {
        await batch.commit();
        return true;
      } catch (error) {
        if (!isAlreadyExistsError(error)) {
          throw error;
        }
        // The dispatch already exists, so the climbs in it are dispatched for
        // good and the baseline may move on its own.
        await stateRef.set(
          catalogCheckFields(announcedClimbIds, catalogVersion, now),
          {merge: true}
        );
        return false;
      }
    },

    async listUnfinishedDispatches(limit) {
      const snapshot = await dispatches
        .where("state", "in", ["pending", "sending"])
        .orderBy("createdAt")
        .limit(limit)
        .get();

      return snapshot.docs.map((document) => {
        const data = document.data();
        return {
          body: String(data.body ?? ""),
          catalogVersion: typeof data.catalogVersion === "number" ?
            data.catalogVersion :
            null,
          climbIds: Array.isArray(data.climbIds) ?
            data.climbIds.map((id: unknown) => String(id)) :
            [],
          deviceCursor: typeof data.deviceCursor === "string" ?
            data.deviceCursor :
            null,
          id: document.id,
          primaryClimbId: String(data.primaryClimbId ?? ""),
          state: data.state as ClimbDropDispatchState,
          title: String(data.title ?? ""),
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
      const devices: ClimbDropDevice[] = [];
      for (const document of snapshot.docs) {
        const data = document.data();
        if (!isDeliverableClimbDropRegistration(data)) {
          continue;
        }
        devices.push({
          fcmToken: data.fcmToken as string,
          tokenHash: document.id,
        });
      }

      const lastDocument = snapshot.docs[snapshot.docs.length - 1];
      return {
        devices,
        exhausted: snapshot.size < limit,
        lastTokenHash: lastDocument?.id ?? null,
      };
    },

    async pruneInvalidTokens(tokenHashes) {
      await deactivatePushTokensByHash(tokenHashes);
    },

    async readState() {
      const snapshot = await stateRef.get();
      if (!snapshot.exists) {
        return null;
      }
      const data = snapshot.data() ?? {};
      return {
        announcedClimbIds: Array.isArray(data.announcedClimbIds) ?
          data.announcedClimbIds.map((id: unknown) => String(id)) :
          [],
        lastCatalogVersion: typeof data.lastCatalogVersion === "number" ?
          data.lastCatalogVersion :
          null,
        // Absent means on. The switch exists to be turned off in an incident,
        // so a document written before it existed must not read as held.
        sendingEnabled: data.sendingEnabled !== false,
      };
    },

    async recordCatalogCheck(announcedClimbIds, catalogVersion) {
      const now = admin.firestore.Timestamp.now();
      await stateRef.set(
        catalogCheckFields(announcedClimbIds, catalogVersion, now),
        {merge: true}
      );
    },

    async writeBootstrapState(announcedClimbIds, catalogVersion) {
      const now = admin.firestore.Timestamp.now();
      await stateRef.set({
        announcedClimbIds,
        bootstrappedAt: now,
        lastCatalogChangeAt: now,
        lastCatalogVersion: catalogVersion,
        schemaVersion: 1,
        sendingEnabled: true,
        updatedAt: now,
      }, {merge: true});
    },

    async recordSendOutcomes(dispatchId, outcomes) {
      if (outcomes.length === 0) {
        return;
      }
      const receipts = dispatches
        .doc(dispatchId)
        .collection(RECEIPTS_COLLECTION);
      const now = admin.firestore.Timestamp.now();
      const batch = firestore.batch();
      for (const outcome of outcomes) {
        batch.set(receipts.doc(outcome.tokenHash), {
          errorCode: outcome.errorCode,
          settledAt: now,
          state: receiptStateFor(outcome),
        }, {merge: true});
      }
      await batch.commit();
    },
  };
}

/**
 * The receipt state one send outcome records.
 * @param {ClimbDropSendOutcome} outcome One device's send outcome.
 * @return {string} Receipt state.
 */
function receiptStateFor(outcome: ClimbDropSendOutcome): string {
  if (outcome.ok) {
    return "delivered";
  }
  return outcome.invalidToken ? "invalid_token" : "failed";
}

/**
 * Builds counter increments for a dispatch document.
 * @param {ClimbDropSendCounters} counters Counters from one run.
 * @return {object} Firestore increment fields.
 */
function incrementCounters(counters: ClimbDropSendCounters) {
  return {
    claimedCount: admin.firestore.FieldValue.increment(counters.claimedCount),
    failedCount: admin.firestore.FieldValue.increment(counters.failedCount),
    invalidTokenCount: admin.firestore.FieldValue.increment(
      counters.invalidTokenCount
    ),
    sentCount: admin.firestore.FieldValue.increment(counters.sentCount),
    unclaimedCount: admin.firestore.FieldValue.increment(
      counters.unclaimedCount
    ),
  };
}

/**
 * Detects Firestore's ALREADY_EXISTS refusal for a `create`.
 * @param {unknown} error Candidate error.
 * @return {boolean} True when the document already existed.
 */
function isAlreadyExistsError(error: unknown): boolean {
  if (!error || typeof error !== "object") {
    return false;
  }
  const code = (error as {code?: unknown}).code;
  return code === ALREADY_EXISTS_CODE || code === "already-exists";
}

/**
 * Builds the FCM-backed sender.
 *
 * The payload keeps the shape the shipped 1.0 build already routes on -
 * `type: "climb_drop"` plus `climbId` deep-links to that climb's detail
 * screen - and adds `climbIds` and `dispatchId` for a later build to read.
 * An unknown data key is inert to the client that does not know it.
 * @param {admin.messaging.Messaging} messaging Admin messaging instance.
 * @return {ClimbDropSender} Sender over FCM multicast.
 */
export function makeFcmClimbDropSender(
  messaging: admin.messaging.Messaging
): ClimbDropSender {
  return {
    async send(request) {
      const response = await messaging.sendEachForMulticast({
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-push-type": "alert",
          },
          payload: {aps: {sound: "default"}},
        },
        data: {
          campaignId: request.dispatchId,
          climbId: request.primaryClimbId,
          climbIds: request.climbIds.join(","),
          dispatchId: request.dispatchId,
          route: "climb_detail",
          type: "climb_drop",
        },
        notification: {
          body: request.body,
          title: request.title,
        },
        tokens: request.tokens.map((device) => device.fcmToken),
      });

      return response.responses.map((sendResponse, index) => {
        const errorCode = sendResponse.error?.code ?? null;
        return {
          errorCode,
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
 * Announces climb drops as the hosted catalogue opens them.
 */
export const announceClimbDrops = onSchedule(
  {
    // A run may outlive its own interval, so the schedule fires again while
    // one is still walking pages. One instance, one request at a time: two
    // concurrent sweeps read the same `deviceCursor`, and the slower one's
    // write drags the drop back to a page already sent - the re-scan the
    // per-page cursor exists to stop. Serializing costs a deferred tick, and
    // the next tick is five minutes away.
    concurrency: 1,
    maxInstances: 1,
    schedule: "every 5 minutes",
    timeZone: "Etc/UTC",
    // A run may claim, send to, and settle receipts for
    // `MAX_DEVICE_PAGES_PER_RUN` pages of 500 devices. The default 60s
    // invocation timeout cannot execute
    // the budget the code declares, and a killed run costs a re-scan rather
    // than a duplicate - so the timeout is raised to match the budget instead
    // of the budget being trimmed to a deadline no drop should ever meet.
    timeoutSeconds: 540,
  },
  async () => {
    const summary = await runClimbDropSweep({
      catalog: makeHostedClimbCatalogSource(),
      sender: makeFcmClimbDropSender(admin.messaging()),
      store: makeFirestoreClimbDropStore(admin.firestore()),
    });

    if (summary.dispatchErrors.length > 0) {
      console.error("announceClimbDrops sweep left drops unsent", summary);
      return;
    }

    console.log("announceClimbDrops sweep completed", summary);
  }
);

export const climbDropNotificationTestHooks = {
  buildBody,
  buildTitle,
  isAlreadyExistsError,
  receiptStateFor,
  truncate,
};
