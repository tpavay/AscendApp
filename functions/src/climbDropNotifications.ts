import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {createHash} from "crypto";
import {delay, runWithBoundedConcurrency} from "./concurrency";
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
/**
 * Attempts one device's receipt create gets before the drop moves on.
 *
 * Bounded on purpose. A device whose create keeps failing is left behind,
 * costing that one device its alert - the same trade the claim-before-send
 * ordering already accepts. Waiting for it instead would stall the whole
 * drop on one document, and a drop that never finishes is the broken promise.
 */
const CLAIM_ATTEMPT_LIMIT = 3;
const CLAIM_RETRY_BASE_DELAY_MS = 50;
/**
 * Sends one claimed device gets before the drop may give up on it.
 *
 * `sendEachForMulticast` reports a per-token refusal inside its response, so a
 * send that *throws* is a batch that never reached FCM at all - nothing was
 * delivered, and re-sending it cannot duplicate. The claim is still kept, and
 * the receipt is marked `unsent` so a later run re-sends to exactly those
 * devices and no others. Bounded, because a device whose send keeps throwing
 * would otherwise hold the page - and its cursor - open for good.
 *
 * This is only half the stop rule. See `SEND_ABANDON_MIN_ELAPSED_MS`.
 */
const SEND_ATTEMPT_LIMIT = 3;
/**
 * How long a claimed receipt is protected from being given up on.
 *
 * A retry budget without a clock is no budget. Three sends fit inside three
 * five-minute ticks, so an attempt counter alone writes off a whole page of
 * 500 climbers after roughly fifteen minutes of FCM being unwell - and every
 * later page then delivers normally, leaving exactly those climbers the ones
 * who never heard about the climb. The stop rule is conjunctive: attempts
 * spent AND this window elapsed, neither term alone.
 *
 * The floor is an absolute date written onto the receipt when it is first
 * claimed, not a duration recomputed per run, so it survives a restart, a
 * redeploy and a cold start rather than starting over with the process.
 */
const SEND_ABANDON_MIN_ELAPSED_MS = 30 * 60 * 1000;
/** How much of a climb ID a dispatch ID may carry, after sanitizing. */
const MAX_DISPATCH_ID_PREFIX_LENGTH = 60;
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
  abandonedCount: number;
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
  recordSendFailure(
    dispatchId: string,
    tokenHashes: string[]
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

/**
 * What one dispatch has done so far this run.
 *
 * Owned by the caller rather than returned, because a dispatch that throws
 * part-way has still committed everything it did before the throw - and the
 * devices it gave up on are exactly what the run must report.
 */
export interface ClimbDropDispatchProgress extends ClimbDropSendCounters {
  abandonedCount: number;
}

export interface ClimbDropSweepSummary {
  /** Devices this run wrote off: claimed, never reached, retries spent. */
  abandonedCount: number;
  bootstrapped: boolean;
  claimedCount: number;
  detectionError: string | null;
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
 * The digest alone is what makes the ID unique, so the leading climb ID is
 * only there to make the document legible in the console - and it is
 * sanitized down to one Firestore path segment before it is spliced into one.
 * A catalogue row is hand-authored, and `tour/eiffel` would otherwise resolve
 * `dispatches.doc(...)` to a collection and throw inside the admin SDK.
 * @param {string[]} climbIds Climb IDs in the drop.
 * @return {string} Deterministic dispatch document ID.
 */
export function buildClimbDropDispatchId(climbIds: string[]): string {
  const sorted = [...climbIds].sort();
  const digest = createHash("sha256")
    .update(sorted.join("\n"))
    .digest("hex")
    .slice(0, 12);
  const prefix = dispatchIdPrefix(sorted[0] ?? "");
  return prefix.length > 0 ? `${prefix}-${digest}` : digest;
}

/**
 * Reduces a climb ID to something safe to name a document with.
 * @param {string} climbId Catalogue climb ID.
 * @return {string} Sanitized, bounded prefix - empty when nothing survives.
 */
function dispatchIdPrefix(climbId: string): string {
  return climbId
    .replace(/[^A-Za-z0-9_-]/g, "-")
    .slice(0, MAX_DISPATCH_ID_PREFIX_LENGTH)
    .replace(/^[-_]+|[-_]+$/g, "");
}

/**
 * Whether a catalogue climb ID can name Firestore documents and paths.
 *
 * A climb ID is carried into document IDs, the monotonic baseline and the push
 * payload, so one that cannot be a path segment is not a climb this sweep can
 * announce.
 * @param {string} climbId Trimmed catalogue climb ID.
 * @return {boolean} True when the ID is usable.
 */
function isUsableClimbId(climbId: string): boolean {
  return climbId.length > 0 &&
    climbId.length <= 1_000 &&
    !climbId.includes("/") &&
    climbId !== "." &&
    climbId !== ".." &&
    // eslint-disable-next-line no-control-regex
    !/[\u0000-\u001f\u007f]/.test(climbId);
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
    abandonedCount: 0,
    bootstrapped: false,
    claimedCount: 0,
    detectionError: null,
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

  // Detection is isolated from delivery. A drop that already exists owes its
  // remaining devices an alert whether or not hosting is answering, and
  // delivery reads nothing from the catalogue - so a fetch that fails records
  // itself on the summary and the run falls through to the dispatches still in
  // flight. Left unguarded, one 503 on `manifest.json` stalls every drop
  // mid-send for as long as hosting is unwell.
  try {
    await detectClimbDrop(deps, state, summary);
  } catch (error) {
    summary.detectionError = error instanceof Error ?
      error.message :
      "unknown_error";
  }

  // No state document means no baseline, so there is nothing to send against
  // either: the bootstrap run records the catalogue and stops.
  if (!state) {
    return summary;
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
    const progress: ClimbDropDispatchProgress = {
      abandonedCount: 0,
      ...emptyCounters(),
    };
    try {
      const completed = await deliverDispatch(
        deps,
        dispatch,
        options,
        progress
      );
      if (completed) {
        summary.dispatchesCompleted.push(dispatch.id);
      }
    } catch (error) {
      summary.dispatchErrors.push({
        dispatchId: dispatch.id,
        message: error instanceof Error ? error.message : "unknown_error",
      });
    } finally {
      // Whatever this dispatch already committed is reported either way. A
      // page that gave up on devices and then threw on the next send would
      // otherwise log only `left drops unsent`, silencing the one alarm the
      // abandon counter exists to raise.
      summary.abandonedCount += progress.abandonedCount;
      summary.claimedCount += progress.claimedCount;
      summary.failedCount += progress.failedCount;
      summary.invalidTokenCount += progress.invalidTokenCount;
      summary.sentCount += progress.sentCount;
      summary.unclaimedCount += progress.unclaimedCount;
    }
  }

  return summary;
}

/**
 * Detects a drop and creates its dispatch, or records a first catalogue.
 *
 * Everything that reads hosting lives here, so the caller can treat a
 * catalogue failure as a degraded detection rather than a dead run.
 * @param {object} deps Injected catalogue and store.
 * @param {ClimbDropSweepState | null} state Stored baseline, when there is one.
 * @param {ClimbDropSweepSummary} summary Summary to record detection onto.
 * @return {Promise<void>} Resolves once detection has been recorded.
 */
async function detectClimbDrop(
  deps: {catalog: ClimbDropCatalogSource; store: ClimbDropStore},
  state: ClimbDropSweepState | null,
  summary: ClimbDropSweepSummary
): Promise<void> {
  const manifest = await deps.catalog.fetchManifest();

  // First run in an environment. Every available climb is "new" against an
  // empty baseline, so recording the catalogue is the only safe thing to do:
  // announcing the whole catalogue as a drop is the fan-out disaster this
  // function exists to avoid.
  if (!state) {
    const climbs = await deps.catalog.fetchClimbs(manifest);
    await deps.store.writeBootstrapState(
      availableClimbIds(climbs),
      manifest.catalogVersion
    );
    summary.bootstrapped = true;
    return;
  }

  if (manifest.catalogVersion === state.lastCatalogVersion) {
    return;
  }

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
  if (newlyAvailable.length === 0) {
    await deps.store.recordCatalogCheck(baseline, manifest.catalogVersion);
    return;
  }

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
 * @param {ClimbDropDispatchProgress} progress Counters the caller owns.
 * @return {Promise<boolean>} Whether the dispatch finished.
 */
async function deliverDispatch(
  deps: {sender: ClimbDropSender; store: ClimbDropStore},
  dispatch: ClimbDropDispatch,
  options: ClimbDropSweepOptions,
  progress: ClimbDropDispatchProgress
): Promise<boolean> {
  const pageSize = options.devicePageSize ?? DEVICE_PAGE_SIZE;
  const maxPages = options.maxDevicePages ?? MAX_DEVICE_PAGES_PER_RUN;
  let cursor = dispatch.deviceCursor;
  let completed = false;

  for (let page = 0; page < maxPages; page++) {
    // Counted per page, because the dispatch document is written per page and
    // its counters are Firestore increments: carrying a running total across
    // pages would add every earlier page again on every write.
    const counters = emptyCounters();
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
      // Recorded the moment it is known, not on the way out: the send below
      // may throw, and the claim pass has already committed these.
      progress.claimedCount += claim.claimed.length;
      progress.unclaimedCount += claim.unclaimedCount;
      progress.abandonedCount += claim.abandonedCount;

      if (claim.claimed.length > 0) {
        const outcomes = await sendClaimedPage(deps, dispatch, claim.claimed);

        await deps.store.recordSendOutcomes(dispatch.id, outcomes);

        const invalidTokenHashes = outcomes
          .filter((outcome) => outcome.invalidToken)
          .map((outcome) => outcome.tokenHash);
        await deps.store.pruneInvalidTokens(invalidTokenHashes);

        const sentCount = outcomes.filter((one) => one.ok).length;
        const failedCount = outcomes.filter((one) => !one.ok).length;
        counters.invalidTokenCount += invalidTokenHashes.length;
        counters.sentCount += sentCount;
        counters.failedCount += failedCount;
        progress.invalidTokenCount += invalidTokenHashes.length;
        progress.sentCount += sentCount;
        progress.failedCount += failedCount;
      }
    }

    // A device the store could not claim within its bounded attempts is left
    // behind, and the page still advances. Holding the cursor for it would
    // wedge the whole drop on one document: the same page would be re-walked
    // every run, the dispatch would never complete, and it would hold one of
    // the per-run slots for good. One device's missed alert is the smaller
    // loss, and `unclaimedCount` is what says it happened.
    if (devicePage.exhausted) {
      completed = true;
      await deps.store.completeDispatch(dispatch.id, counters);
      break;
    }

    await deps.store.advanceDispatch(dispatch.id, cursor, counters);
  }

  return completed;
}

/**
 * Sends one claimed page, marking it re-sendable when the send never landed.
 *
 * The claim is kept either way - releasing it is the ordering that costs a
 * duplicate push, and never-twice is the half of the promise that cannot be
 * recovered from. What changes is that a claimed receipt whose send *threw*
 * is written back as `unsent`, which is a state a later run can tell apart
 * from a device actually alerted, and re-send to. `sendEachForMulticast`
 * reports a per-token refusal in its response rather than throwing, so a throw
 * here means the batch never reached FCM and nothing was delivered.
 * @param {object} deps Injected store and sender.
 * @param {ClimbDropDispatch} dispatch Dispatch being sent.
 * @param {ClimbDropDevice[]} claimed Devices this page claimed.
 * @return {Promise<ClimbDropSendOutcome[]>} Per-device outcomes.
 */
async function sendClaimedPage(
  deps: {sender: ClimbDropSender; store: ClimbDropStore},
  dispatch: ClimbDropDispatch,
  claimed: ClimbDropDevice[]
): Promise<ClimbDropSendOutcome[]> {
  try {
    return await deps.sender.send({
      body: dispatch.body,
      climbIds: dispatch.climbIds,
      dispatchId: dispatch.id,
      primaryClimbId: dispatch.primaryClimbId,
      title: dispatch.title,
      tokens: claimed,
    });
  } catch (error) {
    try {
      await deps.store.recordSendFailure(
        dispatch.id,
        claimed.map((device) => device.tokenHash)
      );
    } catch (markError) {
      // The page keeps its claim and loses its retry marker, which is the
      // behavior that existed before the marker did. Never mask the send
      // failure with this one - it is the cause, and the summary needs it.
      console.error("climb drop send failure was not recorded", {
        dispatchId: dispatch.id,
        message: markError instanceof Error ?
          markError.message :
          "unknown_error",
      });
    }
    throw error;
  }
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
 * Whether a re-sendable receipt has run out of both budgets.
 *
 * Conjunctive on purpose: a device is given up on only once its sends are
 * spent AND the protected window since it was first claimed has elapsed.
 * An attempt counter alone burns through three five-minute ticks in about
 * fifteen minutes, which is short enough that an ordinary FCM incident
 * permanently writes off the one page that was in flight when it started.
 *
 * `abandonEligibleAt` is an absolute date persisted on the receipt at its
 * first claim, so the clock keeps running across restarts and redeploys
 * instead of resetting with the process. A receipt that carries no floor at
 * all falls back to the attempt term, because a bound that can never be
 * reached is not a bound.
 * @param {object} receipt The receipt's stored budgets.
 * @param {number} nowMillis Current time in epoch milliseconds.
 * @return {boolean} True when the device may be given up on.
 */
export function planReceiptAbandon(
  receipt: {abandonEligibleAt: number | null; sendAttempts: number | null},
  nowMillis: number
): boolean {
  const attemptsSpent = (receipt.sendAttempts ?? 0) >= SEND_ATTEMPT_LIMIT;
  const windowElapsed = receipt.abandonEligibleAt === null ||
    nowMillis >= receipt.abandonEligibleAt;
  return attemptsSpent && windowElapsed;
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
 * entry without a name, or without an id that can name a Firestore document,
 * is skipped, so detection - and every other drop in the same publish - still
 * runs. A skipped climb is not recorded in the baseline either, so a corrected
 * publish announces it then.
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
    if (!isUsableClimbId(id) || name.length === 0) {
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
        // A `{merge: true}` set creates what it cannot find, so an absent
        // dispatch is an operator cancelling a drop by deleting it - and the
        // document this would recreate carries counters but no `createdAt`,
        // which `listUnfinishedDispatches` orders by and could never return.
        // That is a permanently stalled drop nothing reports.
        if (!snapshot.exists) {
          return;
        }
        const data = snapshot.data() ?? {};
        const advance = planDispatchAdvance({
          deviceCursor: typeof data.deviceCursor === "string" ?
            data.deviceCursor :
            null,
          state: typeof data.state === "string" ? data.state : null,
        }, cursor);
        // An empty plan is a finished dispatch, and a lagging writer's page
        // has already been counted by the run that completed it. Applying the
        // increments anyway inflates the lifetime totals an operator sizes
        // the loss with.
        if (Object.keys(advance).length === 0) {
          return;
        }
        transaction.set(dispatchRef, {
          updatedAt: admin.firestore.Timestamp.now(),
          ...incrementCounters(counters),
          ...advance,
        }, {merge: true});
      });
    },

    async claimDevices(dispatchId, devices) {
      const dispatchRef = dispatches.doc(dispatchId);
      const receipts = dispatchRef.collection(RECEIPTS_COLLECTION);
      const now = admin.firestore.Timestamp.now();
      const claimed: ClimbDropDevice[] = [];
      let abandonedCount = 0;
      let ambiguousCount = 0;

      // A receipt names the device, never the climber. Storing the uid here
      // would put user-keyed data outside the users/{uid} subtree, which
      // account deletion would then owe its own sweep - and the ledger does
      // not need it: the send question is "has this token already been
      // alerted for this drop".
      const failures = await runWithBoundedConcurrency(
        devices,
        CLAIM_CONCURRENCY,
        async (device) => {
          const receiptRef = receipts.doc(device.tokenHash);
          const outcome = await claimReceipt(() => receiptRef.create({
            // The half of the stop rule that is a clock. Written once, at the
            // first claim, as an absolute date - a duration recomputed per run
            // would start over every time the function cold-starts.
            abandonEligibleAt: admin.firestore.Timestamp.fromMillis(
              now.toMillis() + SEND_ABANDON_MIN_ELAPSED_MS
            ),
            claimedAt: now,
            dispatchId,
            errorCode: null,
            schemaVersion: 1,
            sendAttempts: 0,
            state: "claimed",
          }));
          if (outcome === "claimed") {
            claimed.push(device);
            return;
          }

          const resolution = await resolveExistingReceipt(
            firestore,
            receiptRef
          );
          if (resolution === "reclaimed") {
            claimed.push(device);
            return;
          }
          if (resolution === "abandoned") {
            abandonedCount += 1;
            return;
          }
          // The receipt exists and is not re-sendable. When this call's own
          // earlier attempt may have written it, nothing will ever send to
          // it, so it is a device left behind rather than one already
          // alerted by another run - and it is counted as such.
          if (outcome === "ambiguous") {
            ambiguousCount += 1;
          }
        }
      );

      for (const failure of failures) {
        console.error("climb drop receipt claim failed", {
          dispatchId,
          message: failure.error instanceof Error ?
            failure.error.message :
            "unknown_error",
        });
      }

      if (ambiguousCount > 0) {
        console.error("climb drop receipt claim was ambiguous", {
          count: ambiguousCount,
          dispatchId,
        });
      }

      if (abandonedCount > 0) {
        console.error("climb drop gave up on unreachable devices", {
          count: abandonedCount,
          dispatchId,
        });
        try {
          // One write for the whole page, after the claim pass, the way every
          // other counter reaches this document. `update` refuses a document
          // that is not there, so an operator who deleted the dispatch to
          // cancel the drop does not get it recreated without a `createdAt`.
          await dispatchRef.update({
            abandonedCount: admin.firestore.FieldValue
              .increment(abandonedCount),
          });
        } catch (error) {
          console.error("climb drop abandon count was not recorded", {
            count: abandonedCount,
            dispatchId,
            message: error instanceof Error ? error.message : "unknown_error",
          });
        }
      }

      return {
        abandonedCount,
        claimed,
        unclaimedCount: failures.length + ambiguousCount,
      };
    },

    async completeDispatch(dispatchId, counters) {
      const dispatchRef = dispatches.doc(dispatchId);
      await firestore.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(dispatchRef);
        // Same guard as `advanceDispatch`: never resurrect a deleted dispatch,
        // and never count a page twice onto one already marked sent.
        if (!snapshot.exists || snapshot.get("state") === "sent") {
          return;
        }
        const now = admin.firestore.Timestamp.now();
        transaction.set(dispatchRef, {
          completedAt: now,
          state: "sent",
          updatedAt: now,
          ...incrementCounters(counters),
        }, {merge: true});
      });
    },

    async createDispatchWithBaseline(
      dispatch,
      announcedClimbIds,
      catalogVersion
    ) {
      const now = admin.firestore.Timestamp.now();
      const batch = firestore.batch();
      batch.create(dispatches.doc(dispatch.id), {
        abandonedCount: 0,
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

    async recordSendFailure(dispatchId, tokenHashes) {
      if (tokenHashes.length === 0) {
        return;
      }
      const receipts = dispatches
        .doc(dispatchId)
        .collection(RECEIPTS_COLLECTION);
      const now = admin.firestore.Timestamp.now();
      const batch = firestore.batch();
      for (const tokenHash of tokenHashes) {
        batch.set(receipts.doc(tokenHash), {
          sendAttempts: admin.firestore.FieldValue.increment(1),
          sendFailedAt: now,
          state: "unsent",
        }, {merge: true});
      }
      await batch.commit();
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
 * How an already-existing receipt resolves for the run that hit it.
 */
type ClimbDropReceiptResolution = "reclaimed" | "abandoned" | "held";

/**
 * Decides what to do with a receipt whose `create` was refused.
 *
 * Only a receipt explicitly marked `unsent` is re-sendable. That marker is
 * written when the send *threw*, which `sendEachForMulticast` does not do for
 * a per-token refusal - so the batch never reached FCM and nothing was
 * delivered. A plain `claimed` receipt is deliberately NOT re-sent: it may be
 * a page whose push landed and whose settle write did not, and a second push
 * is the one failure never-twice cannot recover from.
 *
 * Both halves of the stop rule live on the receipt - the attempts spent and
 * the absolute date before which it may not be given up on - so the bound
 * terminates no matter what kills the run in between, and the clock does not
 * restart with the process.
 *
 * The transaction touches this one receipt and nothing else. Reaching into
 * the shared dispatch document from here would put the whole page's devices
 * into optimistic contention on a single document at exactly the moment they
 * are all resolving together, and the losers would be reported as claim
 * failures rather than as the abandonments they are.
 * @param {admin.firestore.Firestore} firestore Admin Firestore instance.
 * @param {admin.firestore.DocumentReference} receiptRef Receipt document.
 * @return {Promise<ClimbDropReceiptResolution>} What the receipt resolved to.
 */
async function resolveExistingReceipt(
  firestore: admin.firestore.Firestore,
  receiptRef: admin.firestore.DocumentReference
): Promise<ClimbDropReceiptResolution> {
  return firestore.runTransaction<ClimbDropReceiptResolution>(
    async (transaction) => {
      const receipt = await transaction.get(receiptRef);
      if (receipt.get("state") !== "unsent") {
        return "held";
      }

      const now = admin.firestore.Timestamp.now();
      const attempts = receipt.get("sendAttempts");
      if (planReceiptAbandon({
        abandonEligibleAt: receiptAbandonFloorMillis(receipt),
        sendAttempts: typeof attempts === "number" ? attempts : null,
      }, now.toMillis())) {
        transaction.set(receiptRef, {
          abandonedAt: now,
          state: "abandoned",
        }, {merge: true});
        return "abandoned";
      }

      transaction.set(receiptRef, {state: "claimed"}, {merge: true});
      return "reclaimed";
    }
  );
}

/**
 * The absolute date a receipt may first be given up on.
 * @param {admin.firestore.DocumentSnapshot} receipt Receipt document.
 * @return {number | null} Epoch milliseconds, or nothing when unrecorded.
 */
function receiptAbandonFloorMillis(
  receipt: admin.firestore.DocumentSnapshot
): number | null {
  const eligible = receipt.get("abandonEligibleAt");
  if (eligible instanceof admin.firestore.Timestamp) {
    return eligible.toMillis();
  }
  const claimed = receipt.get("claimedAt");
  if (claimed instanceof admin.firestore.Timestamp) {
    return claimed.toMillis() + SEND_ABANDON_MIN_ELAPSED_MS;
  }
  return null;
}

/**
 * What one device's receipt create settled as.
 *
 * `existing` is a receipt this call did not write, so its state is the record
 * of what has already happened to that device. `ambiguous` is a receipt that
 * may well be this call's own: a `create` is not idempotent, so an attempt
 * that commits and then loses its response leaves the next attempt reading
 * ALREADY_EXISTS for a document nothing will ever send to.
 */
export type ClimbDropReceiptClaim = "claimed" | "existing" | "ambiguous";

/**
 * Claims one device's receipt, retrying a bounded number of times.
 *
 * An existing receipt is the whole no-duplicate guarantee: that device has
 * already been claimed for this drop, by an earlier run or a concurrent one.
 * Any other refusal is retried, and then given up on - the attempts are
 * bounded so one document cannot hold the drop open, and the caller counts the
 * device as left behind.
 * @param {Function} create Writes the receipt, refusing an existing one.
 * @param {object} options Attempt bound and the wait between attempts.
 * @return {Promise<ClimbDropReceiptClaim>} How the claim settled.
 */
export async function claimReceipt(
  create: () => Promise<unknown>,
  options: {
    attemptLimit?: number;
    wait?: (milliseconds: number) => Promise<void>;
  } = {}
): Promise<ClimbDropReceiptClaim> {
  const attemptLimit = options.attemptLimit ?? CLAIM_ATTEMPT_LIMIT;
  const wait = options.wait ?? delay;
  let refused = false;

  for (let attempt = 1; attempt <= attemptLimit; attempt++) {
    try {
      await create();
      return "claimed";
    } catch (error) {
      if (isAlreadyExistsError(error)) {
        return refused ? "ambiguous" : "existing";
      }
      if (attempt >= attemptLimit) {
        throw error;
      }
      refused = true;
      await wait(CLAIM_RETRY_BASE_DELAY_MS * 2 ** (attempt - 1));
    }
  }

  throw new Error("The receipt claim retry loop exited early.");
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

    // Detection failing is a drop nobody has heard about yet; delivery of the
    // drops already in flight carried on regardless, which is why this is not
    // fatal to the run.
    if (summary.detectionError !== null) {
      console.error("announceClimbDrops sweep could not read the catalogue",
        summary);
      return;
    }

    // A degraded run must not read like a clean one: these devices were left
    // behind by this drop and no later run picks them up.
    if (summary.abandonedCount > 0) {
      console.error("announceClimbDrops sweep gave up on devices", summary);
      return;
    }

    if (summary.unclaimedCount > 0) {
      console.error("announceClimbDrops sweep left devices unclaimed", summary);
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
  sendAbandonMinElapsedMs: SEND_ABANDON_MIN_ELAPSED_MS,
  sendAttemptLimit: SEND_ATTEMPT_LIMIT,
  truncate,
};
