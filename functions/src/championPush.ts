/**
 * The champion push: one `champion_crowned` alert to each climber the
 * leaderboard finalizer crowns.
 *
 * docs/champion-recognition.md owns the product rule and the data contract.
 * A `leaderboard_results/{resultId}` document is created once per closed
 * weekly, monthly or yearly Steps board, and this trigger answers that
 * creation - never an update - with one push per uid in `championUserIds`.
 *
 * NEVER TWICE. Before any send to a climber, the trigger `create`s
 * `_champion_push_deliveries/{resultId}_{uid}`. An existing marker means
 * that climber has already been claimed for this result - by an earlier
 * attempt of this same event, or a concurrent one - and they are skipped.
 * The claim comes after every read and immediately before the send, so a
 * read that fails leaves no marker and the event's retry tries again, while
 * a send that throws after its claim is recorded as `unsent` and never
 * retried: a second crown alert is the failure that cannot be taken back.
 *
 * NEVER STALE. Only a result the finalizer wrote (`source:
 * "leaderboard_finalizer"`), whose period closed within the last 48 hours,
 * pushes. A backfilled result, or an event retried long after the crowning,
 * writes nothing and sends nothing.
 *
 * WHO. The climber's own `pushChampionCrownEnabled` preference (absent
 * means on), and only their active iOS devices whose registration reports
 * an authorization iOS will actually deliver on - the same answer the
 * climb-drop audience uses. The climb-drop toggle is not consulted: the two
 * preferences are independent. A token FCM reports as dead is unregistered
 * through the same pruning helper the climb-drop sweep uses.
 */

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {claimReceipt} from "./climbDropNotifications";
import {runWithBoundedConcurrency} from "./concurrency";
import type {FinalizedTimeFrame} from "./leaderboardPeriod";
import {
  deactivatePushTokensByHash,
  fcmInvalidTokenCodes,
  isDeliverableAuthorizationStatus,
} from "./pushNotifications";

type PlainObject = Record<string, unknown>;

const RESULTS_COLLECTION = "leaderboard_results";
const PLACINGS_COLLECTION = "placings";
export const CHAMPION_PUSH_DELIVERIES_COLLECTION =
  "_champion_push_deliveries";
const USERS_COLLECTION = "users";
const NOTIFICATION_DEVICES_COLLECTION = "notification_devices";
const FINALIZER_SOURCE = "leaderboard_finalizer";
/** How long after a period closes its crowning may still push. */
const CHAMPION_PUSH_WINDOW_MS = 48 * 60 * 60 * 1000;
/** Champions processed at once. Co-champions are rare; ten is plenty. */
const CHAMPION_CONCURRENCY = 10;
/** FCM's multicast ceiling. */
const FCM_MULTICAST_LIMIT = 500;
/**
 * How long after a week or month closes the push waits for the champion's
 * recap. The alert opens the app, and the recap's last page is the
 * coronation, so a push that arrives before the 00:30 UTC compose opens to
 * nothing. Compose itself waits up to an hour for the finalizer, so after 90
 * minutes the push goes out without it rather than never.
 */
export const CHAMPION_PUSH_RECAP_WAIT_MS = 90 * 60 * 1000;

export const CHAMPION_PUSH_TITLE = "You took the crown.";

export interface ChampionPushResult {
  championUserIds: string[];
  periodEndAt: Date;
  periodKey: string;
  timeFrame: FinalizedTimeFrame;
}

export type ChampionPushEligibility =
  | {eligible: true; result: ChampionPushResult}
  | {
      eligible: false;
      reason: "not_finalizer" | "malformed" | "stale" | "not_closed";
    };

export interface ChampionPushDevice {
  fcmToken: string;
  tokenHash: string;
}

export interface ChampionPushSendRequest {
  body: string;
  data: Record<string, string>;
  title: string;
  tokens: ChampionPushDevice[];
}

export interface ChampionPushSendOutcome {
  invalidToken: boolean;
  ok: boolean;
  tokenHash: string;
}

export interface ChampionPushSender {
  send(request: ChampionPushSendRequest): Promise<ChampionPushSendOutcome[]>;
}

export interface ChampionPushSummary {
  /** Champions another attempt had already claimed. */
  alreadyClaimed: number;
  /** Champions whose placing is not written yet; the event retries. */
  awaitingPlacing: number;
  /**
   * Champions whose recap (and its coronation) is not composed yet; the event
   * retries.
   */
  awaitingRecap: number;
  /** Champions claimed, and sent to at least one device. */
  delivered: number;
  /** Champions whose pre-claim reads threw; the event retries. */
  errors: number;
  /** Champions claimed whose every device refused, or whose send threw. */
  failed: number;
  invalidTokenCount: number;
  /** Champions with no device iOS will alert. */
  noDevices: number;
  /** Champions who turned the crown alert off. */
  optedOut: number;
  sentCount: number;
}

// =============================================================================
// Pure helpers - unit-testable without Firestore
// =============================================================================

/**
 * Decides whether a newly created result may push, and reads it.
 * @param {PlainObject} data - The `leaderboard_results` document
 * @param {Date} now - The trigger's clock
 * @return {ChampionPushEligibility} The result to push, or why not
 */
export function evaluateChampionPushEligibility(
  data: PlainObject,
  now: Date
): ChampionPushEligibility {
  if (data.source !== FINALIZER_SOURCE) {
    return {eligible: false, reason: "not_finalizer"};
  }
  const timeFrame = data.timeFrame;
  const periodKey = data.periodKey;
  const periodEndAt = data.periodEndAt;
  if ((timeFrame !== "weekly" && timeFrame !== "monthly" &&
    timeFrame !== "yearly") ||
    typeof periodKey !== "string" ||
    !(periodEndAt instanceof admin.firestore.Timestamp) ||
    !Array.isArray(data.championUserIds) ||
    buildChampionPushMessage(timeFrame, periodKey, 0) === null) {
    return {eligible: false, reason: "malformed"};
  }

  const endAt = periodEndAt.toDate();
  const sinceClose = now.getTime() - endAt.getTime();
  if (sinceClose < 0) {
    return {eligible: false, reason: "not_closed"};
  }
  if (sinceClose > CHAMPION_PUSH_WINDOW_MS) {
    return {eligible: false, reason: "stale"};
  }

  const championUserIds = [...new Set(data.championUserIds.filter(
    (uid): uid is string => typeof uid === "string" && uid.length > 0 &&
      !uid.includes("/")
  ))];
  return {
    eligible: true,
    result: {championUserIds, periodEndAt: endAt, periodKey, timeFrame},
  };
}

/**
 * Whether the push should still hold for the champion's recap: only a week or
 * a month has one, and only within the wait after the period closed.
 * @param {ChampionPushResult} result - The result being pushed
 * @param {boolean} recapExists - Whether the champion's recap is composed
 * @param {Date} now - The trigger's clock
 * @return {boolean} True while the push should wait and retry
 */
export function shouldAwaitChampionRecap(
  result: ChampionPushResult,
  recapExists: boolean,
  now: Date
): boolean {
  if (recapExists || result.timeFrame === "yearly") {
    return false;
  }
  return now.getTime() - result.periodEndAt.getTime() <
    CHAMPION_PUSH_RECAP_WAIT_MS;
}

/**
 * Builds the crown alert's copy for one champion.
 *
 * The week number and month name come from the period key, in UTC, the same
 * key the board and the recap name the period by.
 * @param {FinalizedTimeFrame} timeFrame - The board's window
 * @param {string} periodKey - The closed period's key
 * @param {number} totalSteps - The champion's frozen period total
 * @return {{body: string, title: string} | null} The copy, or null for a key
 *   that names no period
 */
export function buildChampionPushMessage(
  timeFrame: FinalizedTimeFrame,
  periodKey: string,
  totalSteps: number
): {body: string; title: string} | null {
  const steps = formatSteps(totalSteps);
  switch (timeFrame) {
  case "weekly": {
    const match = /^\d{4}-W(\d{2})$/.exec(periodKey);
    const week = match ? Number(match[1]) : 0;
    if (week < 1 || week > 53) {
      return null;
    }
    return {
      body: `Week ${week} champion. ${steps}. Defend it this week.`,
      title: CHAMPION_PUSH_TITLE,
    };
  }
  case "monthly": {
    const match = /^(\d{4})-M(\d{2})$/.exec(periodKey);
    const month = match ? Number(match[2]) : 0;
    if (!match || month < 1 || month > 12) {
      return null;
    }
    const monthName = new Date(Date.UTC(Number(match[1]), month - 1, 1))
      .toLocaleDateString("en-US", {month: "long", timeZone: "UTC"});
    return {
      body: `${monthName} champion. ${steps}. Defend it all month.`,
      title: CHAMPION_PUSH_TITLE,
    };
  }
  case "yearly":
    if (!/^\d{4}$/.test(periodKey)) {
      return null;
    }
    return {
      body: `${periodKey} champion. ${steps}. Defend it all year.`,
      title: CHAMPION_PUSH_TITLE,
    };
  }
}

/**
 * Whether a climber wants the crown alert. Absent means on: the preference
 * is only ever written by a climber turning it off, or back on.
 * @param {PlainObject | undefined} preferences - The climber's
 *   `communication_preferences/current`, if any
 * @return {boolean} False only when the climber turned it off
 */
export function isChampionPushEnabled(
  preferences: PlainObject | undefined
): boolean {
  return preferences?.pushChampionCrownEnabled !== false;
}

/**
 * Narrows a climber's registrations to the devices iOS will alert.
 *
 * Every fact is read off the root registry, not the climber's mirror: the
 * registry is the one place a re-registered token names its new owner, so a
 * token that has since moved to another account is never sent to here.
 * @param {string} uid - The champion
 * @param {Array<{tokenHash: string, data: PlainObject | undefined}>}
 *   registrations - Root `notification_devices` documents
 * @return {ChampionPushDevice[]} Devices to send to
 */
export function selectChampionPushDevices(
  uid: string,
  registrations: Array<{tokenHash: string; data: PlainObject | undefined}>
): ChampionPushDevice[] {
  const devices: ChampionPushDevice[] = [];
  for (const {data, tokenHash} of registrations) {
    if (data?.active === true &&
      data.uid === uid &&
      data.platform === "ios" &&
      isDeliverableAuthorizationStatus(data.authorizationStatus) &&
      typeof data.fcmToken === "string" &&
      data.fcmToken.length > 0) {
      devices.push({fcmToken: data.fcmToken, tokenHash});
    }
  }
  return devices;
}

/**
 * Formats a step total for the alert, e.g. "12,345 steps".
 * @param {number} totalSteps - The champion's frozen period total
 * @return {string} The count with its noun
 */
function formatSteps(totalSteps: number): string {
  const steps = Math.max(0, Math.round(totalSteps));
  return `${steps.toLocaleString("en-US")} ${steps === 1 ? "step" : "steps"}`;
}

// =============================================================================
// Firestore-backed delivery
// =============================================================================

/**
 * Builds the FCM-backed sender, with the APNs shape the climb-drop push
 * already ships. The data payload is inert to a build that does not know
 * the `champion_crowned` type: the shipped router ignores every other type.
 * @param {admin.messaging.Messaging} messaging - Admin messaging instance
 * @return {ChampionPushSender} Sender over FCM multicast
 */
export function makeFcmChampionPushSender(
  messaging: admin.messaging.Messaging
): ChampionPushSender {
  return {
    async send(request) {
      const outcomes: ChampionPushSendOutcome[] = [];
      for (let index = 0; index < request.tokens.length;
        index += FCM_MULTICAST_LIMIT) {
        const chunk = request.tokens.slice(index, index + FCM_MULTICAST_LIMIT);
        const response = await messaging.sendEachForMulticast({
          apns: {
            headers: {
              "apns-priority": "10",
              "apns-push-type": "alert",
            },
            payload: {aps: {sound: "default"}},
          },
          data: request.data,
          notification: {body: request.body, title: request.title},
          tokens: chunk.map((device) => device.fcmToken),
        });
        response.responses.forEach((sendResponse, position) => {
          const errorCode = sendResponse.error?.code;
          outcomes.push({
            invalidToken: Boolean(errorCode) &&
              fcmInvalidTokenCodes.has(errorCode as string),
            ok: sendResponse.success,
            tokenHash: chunk[position].tokenHash,
          });
        });
      }
      return outcomes;
    },
  };
}

/**
 * Reads a climber's active registrations off the root device registry.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - The champion
 * @return {Promise<ChampionPushDevice[]>} Devices iOS will alert
 */
async function loadChampionPushDevices(
  firestore: admin.firestore.Firestore,
  uid: string
): Promise<ChampionPushDevice[]> {
  const mirrors = await firestore
    .collection(USERS_COLLECTION)
    .doc(uid)
    .collection(NOTIFICATION_DEVICES_COLLECTION)
    .where("active", "==", true)
    .get();
  if (mirrors.empty) {
    return [];
  }
  const registrations = await firestore.getAll(
    ...mirrors.docs.map((mirror) => firestore
      .collection(NOTIFICATION_DEVICES_COLLECTION)
      .doc(mirror.id))
  );
  return selectChampionPushDevices(uid, registrations.map((registration) => ({
    data: registration.data(),
    tokenHash: registration.id,
  })));
}

type ChampionOutcome =
  | "already_claimed"
  | "awaiting_placing"
  | "awaiting_recap"
  | "delivered"
  | "failed"
  | "no_devices"
  | "opted_out";

/**
 * Delivers one champion's crown alert, at most once.
 * @param {object} params - Firestore, sender, the result, and the champion
 * @return {Promise<object>} What happened, and any dead tokens
 */
async function deliverToChampion(params: {
  firestore: admin.firestore.Firestore;
  now: Date;
  result: ChampionPushResult;
  resultId: string;
  sender: ChampionPushSender;
  uid: string;
}): Promise<{
  invalidTokenHashes: string[];
  outcome: ChampionOutcome;
  sentCount: number;
}> {
  const {firestore, now, result, resultId, sender, uid} = params;
  const none = {invalidTokenHashes: [], sentCount: 0};

  const [preferences, placing, recap] = await Promise.all([
    firestore
      .collection(USERS_COLLECTION)
      .doc(uid)
      .collection("communication_preferences")
      .doc("current")
      .get(),
    firestore
      .collection(RESULTS_COLLECTION)
      .doc(resultId)
      .collection(PLACINGS_COLLECTION)
      .doc(uid)
      .get(),
    firestore
      .collection(USERS_COLLECTION)
      .doc(uid)
      .collection("recaps")
      .doc(`${result.timeFrame}_${result.periodKey}`)
      .get(),
  ]);
  if (!isChampionPushEnabled(preferences.data())) {
    return {...none, outcome: "opted_out"};
  }
  if (shouldAwaitChampionRecap(result, recap.exists, now)) {
    return {...none, outcome: "awaiting_recap"};
  }
  const totalSteps = placing.get("totalSteps");
  if (!placing.exists || typeof totalSteps !== "number") {
    return {...none, outcome: "awaiting_placing"};
  }
  const message = buildChampionPushMessage(
    result.timeFrame,
    result.periodKey,
    totalSteps
  );
  if (!message) {
    // Unreachable: eligibility already refused a key that names no period.
    return {...none, outcome: "no_devices"};
  }
  const devices = await loadChampionPushDevices(firestore, uid);
  if (devices.length === 0) {
    return {...none, outcome: "no_devices"};
  }

  const markerRef = firestore
    .collection(CHAMPION_PUSH_DELIVERIES_COLLECTION)
    .doc(`${resultId}_${uid}`);
  const claim = await claimReceipt(() => markerRef.create({
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    resultId,
    sentCount: 0,
    status: "claimed",
    userId: uid,
  }));
  if (claim !== "claimed") {
    return {...none, outcome: "already_claimed"};
  }

  let outcomes: ChampionPushSendOutcome[];
  try {
    outcomes = await sender.send({
      ...message,
      data: {
        periodKey: result.periodKey,
        timeFrame: result.timeFrame,
        type: "champion_crowned",
      },
      tokens: devices,
    });
  } catch (error) {
    logger.error("championPush.sendThrew", {
      errorMessage: error instanceof Error ? error.message : "unknown_error",
      resultId,
      uid,
    });
    await markerRef.update({status: "unsent"});
    return {...none, outcome: "failed"};
  }

  const sentCount = outcomes.filter((outcome) => outcome.ok).length;
  await markerRef.update({
    sentCount,
    status: sentCount > 0 ? "sent" : "failed",
  });
  return {
    invalidTokenHashes: outcomes
      .filter((outcome) => outcome.invalidToken)
      .map((outcome) => outcome.tokenHash),
    outcome: sentCount > 0 ? "delivered" : "failed",
    sentCount,
  };
}

/**
 * Sends the crown alert for one newly created result.
 * @param {object} params - Firestore, sender, the result, and the clock
 * @return {Promise<ChampionPushSummary | ChampionPushEligibility>} What the
 *   delivery did, or why the result does not push
 */
export async function deliverChampionPush(params: {
  data: PlainObject;
  firestore: admin.firestore.Firestore;
  now: Date;
  pruneInvalidTokens?: (tokenHashes: string[]) => Promise<void>;
  resultId: string;
  sender: ChampionPushSender;
}): Promise<
  {eligible: true; summary: ChampionPushSummary} |
  Extract<ChampionPushEligibility, {eligible: false}>
> {
  const eligibility = evaluateChampionPushEligibility(params.data, params.now);
  if (!eligibility.eligible) {
    return eligibility;
  }
  const {result} = eligibility;
  const summary: ChampionPushSummary = {
    alreadyClaimed: 0,
    awaitingPlacing: 0,
    awaitingRecap: 0,
    delivered: 0,
    errors: 0,
    failed: 0,
    invalidTokenCount: 0,
    noDevices: 0,
    optedOut: 0,
    sentCount: 0,
  };
  const invalidTokenHashes: string[] = [];

  const failures = await runWithBoundedConcurrency(
    result.championUserIds,
    CHAMPION_CONCURRENCY,
    async (uid) => {
      const delivery = await deliverToChampion({
        firestore: params.firestore,
        now: params.now,
        result,
        resultId: params.resultId,
        sender: params.sender,
        uid,
      });
      summary.sentCount += delivery.sentCount;
      invalidTokenHashes.push(...delivery.invalidTokenHashes);
      switch (delivery.outcome) {
      case "already_claimed":
        summary.alreadyClaimed += 1;
        break;
      case "awaiting_placing":
        summary.awaitingPlacing += 1;
        break;
      case "awaiting_recap":
        summary.awaitingRecap += 1;
        break;
      case "delivered":
        summary.delivered += 1;
        break;
      case "failed":
        summary.failed += 1;
        break;
      case "no_devices":
        summary.noDevices += 1;
        break;
      case "opted_out":
        summary.optedOut += 1;
        break;
      }
    }
  );
  for (const failure of failures) {
    summary.errors += 1;
    logger.error("championPush.deliveryFailed", {
      errorMessage: failure.error instanceof Error ?
        failure.error.message :
        "unknown_error",
      resultId: params.resultId,
      uid: failure.item,
    });
  }

  summary.invalidTokenCount = invalidTokenHashes.length;
  await (params.pruneInvalidTokens ?? deactivatePushTokensByHash)(
    invalidTokenHashes
  );
  return {eligible: true, summary};
}

/**
 * Pushes the crown to each champion when the finalizer writes a result.
 *
 * Retried on failure. A retry is safe by construction - every champion
 * already claimed is skipped by their marker - so the trigger throws
 * whenever a champion is still owed a push it could not attempt yet: their
 * placing is not written, or a read before their claim failed. The 48-hour
 * window ends the retries of a result that can never complete.
 */
export const onLeaderboardResultCreatedChampionPush = onDocumentCreated(
  {document: `${RESULTS_COLLECTION}/{resultId}`, retry: true},
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }
    const resultId = event.params.resultId;
    const delivery = await deliverChampionPush({
      data: snapshot.data() as PlainObject,
      firestore: admin.firestore(),
      now: new Date(),
      resultId,
      sender: makeFcmChampionPushSender(admin.messaging()),
    });
    if (!delivery.eligible) {
      logger.log("championPush.skipped", {reason: delivery.reason, resultId});
      return;
    }

    const {summary} = delivery;
    const retry = summary.awaitingPlacing > 0 ||
      summary.awaitingRecap > 0 ||
      summary.errors > 0;
    const write = retry || summary.failed > 0 ? logger.error : logger.log;
    write("championPush.completed", {...summary, resultId});
    if (retry) {
      throw new Error(
        `championPush ${resultId}: ${summary.awaitingPlacing} awaiting ` +
          `placing, ${summary.awaitingRecap} awaiting recap, ` +
          `${summary.errors} failed before claim`
      );
    }
  }
);
