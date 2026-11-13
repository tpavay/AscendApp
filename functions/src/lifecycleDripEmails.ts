/**
 * Lifecycle drip emails: a plain note from the founder to a climber who stopped
 * at one of three points in the first-week funnel. Each email goes only for
 * the furthest stage the climber reached, and a later stage suppresses it.
 *
 *   drip_paywall_abandoned  The first paywall appeared and was never closed:
 *                           the climber left before the welcome offer or the
 *                           founder letter could open. Default 2 hours after
 *                           the paywall was shown.
 *   drip_free_week_unused   The free week started and no climb has been
 *                           started or logged. Default 24 hours after the
 *                           week started.
 *   drip_trial_reminder     A 7-day free trial of the welcome product ends
 *                           soon. Default 24 hours before it ends. Never sent
 *                           once the trial was cancelled or converted.
 *
 * NOT BUILT, because the event is not recorded anywhere the server can read:
 *   - "saw the welcome offer, never saw the founder letter" needs the decline
 *     offer's `paywall_shown`. The client records it only to analytics
 *     (`SuperwallEventRelay`) and `DeclineOfferReplayStore` keeps it on the
 *     device; `LifecycleEventRecorder` drops the decline offer's placements.
 *   - "saw the founder letter, never got in" needs the letter's shown event,
 *     which `LifecycleEventRecorder.recordPaywallEvent` drops by design. No
 *     other event tells it from "got in": the v3 onboarding finishes before the
 *     paywall, and the week starts the moment the letter closes.
 * `docs/lifecycle-drip-emails.md` names the exact events to record.
 *
 * Every delay is a Remote Config number and every sweep sits behind its own
 * rollout switch that ships off (`remoteconfig.template.json`). The first
 * two are also off unless `free_week_after_decline_enabled` is on, because
 * their copy promises the welcome offer and the week. A template that cannot
 * be read sends nothing: an email cannot be recalled.
 *
 * Consent is `enqueueLifecycleEmailIfAllowed`'s recorded yes, one email per
 * account per type for life is the dedupe key, and suppression is decided
 * again by `processEmailJobs` at send time (`email/dripEligibility.ts`).
 * Whether an environment delivers a type at all is the secret's
 * `enabledEmailTypes`, exactly like every other lifecycle email.
 */

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {runWithBoundedConcurrency} from "./concurrency";
import {cleanFirstName} from "./email/birthday";
import {resolveClimberTimeZone} from "./email/climberTimeZone";
import type {DripEmailType} from "./email/dripCopy";
import {
  dripSuppressionReasonFor,
  FIRST_PAYWALL_SHOWN_EVENT,
  makeFirestoreDripFactReader,
  WELCOME_PRODUCT_IDS,
} from "./email/dripEligibility";
import type {DripFactReader} from "./email/dripEligibility";
import {
  buildEmailJobId,
  enqueueLifecycleEmailIfAllowed,
} from "./email/queue";
import type {EnqueueLifecycleEmailOutcome} from "./email/queue";
import type {DripEmailPayload} from "./email/types";

export const DRIP_PAYWALL_ABANDONED_SWITCH =
  "lifecycle_email_paywall_abandoned_enabled";
export const DRIP_PAYWALL_ABANDONED_DELAY_KEY =
  "lifecycle_email_paywall_abandoned_delay_hours";
export const DRIP_FREE_WEEK_UNUSED_SWITCH =
  "lifecycle_email_free_week_unused_enabled";
export const DRIP_FREE_WEEK_UNUSED_DELAY_KEY =
  "lifecycle_email_free_week_unused_delay_hours";
export const DRIP_TRIAL_REMINDER_SWITCH =
  "lifecycle_email_trial_reminder_enabled";
export const DRIP_TRIAL_REMINDER_LEAD_KEY =
  "lifecycle_email_trial_reminder_lead_hours";
export const FREE_WEEK_PROGRAM_SWITCH = "free_week_after_decline_enabled";

/** Defaults, in hours. Mirrored by `remoteconfig.template.json`. */
export const DRIP_DEFAULT_HOURS = {
  freeWeekUnused: 24,
  paywallAbandoned: 2,
  trialReminder: 24,
} as const;

/** A delay outside these bounds is a typo, so the default is used instead. */
const MIN_DELAY_HOURS = 0.25;
const MAX_DELAY_HOURS = 14 * 24;

const HOUR_MS = 60 * 60 * 1000;
/**
 * How long past its delay a climber is still emailed. Bounds a sweep that was
 * down or a switch turned on late, so nobody gets a "couple of hours ago"
 * email days afterwards. Also the width of the window each run re-reads.
 */
export const DRIP_MAX_LATENESS_MS = 6 * HOUR_MS;
/** A trial reminder that would land inside this window is pointless. */
export const TRIAL_REMINDER_MIN_LEAD_MS = 2 * HOUR_MS;

const LINK_BASE = "https://ascendstepper.com/go";
const DRIP_LINK_SOURCES: Record<DripEmailType, string> = {
  drip_free_week_unused: "email-free-week-unused",
  drip_paywall_abandoned: "email-paywall-abandoned",
  drip_trial_reminder: "email-trial-reminder",
};

const RECIPIENT_CONCURRENCY = 10;

export interface DripSegmentSettings {
  enabled: boolean;
  /** The delay after the stage began, or for the reminder, the lead. */
  offsetMs: number;
}

export interface DripSettings {
  freeWeekProgramLive: boolean;
  freeWeekUnused: DripSegmentSettings;
  paywallAbandoned: DripSegmentSettings;
  trialReminder: DripSegmentSettings;
}

type RemoteConfigTemplateLike = {
  parameters?: Record<string, {defaultValue?: {value?: unknown}} | undefined>;
} | null | undefined;

function readBoolean(template: RemoteConfigTemplateLike, key: string): boolean {
  const value = template?.parameters?.[key]?.defaultValue?.value;
  // Absent means off: these are rollouts, and only an explicit true sends.
  return value !== undefined && String(value).trim().toLowerCase() === "true";
}

function readHours(
  template: RemoteConfigTemplateLike,
  key: string,
  fallbackHours: number
): number {
  const raw = template?.parameters?.[key]?.defaultValue?.value;
  const hours = typeof raw === "string" || typeof raw === "number" ?
    Number(raw) : NaN;
  const valid = Number.isFinite(hours) &&
    hours >= MIN_DELAY_HOURS && hours <= MAX_DELAY_HOURS;
  return (valid ? hours : fallbackHours) * HOUR_MS;
}

/**
 * Reads the three switches and three delays out of the Remote Config template.
 * @param {unknown} template - The template, as the Admin SDK returns it
 * @return {DripSettings} Switches (off unless explicitly true) and delays
 */
export function readDripSettings(template: unknown): DripSettings {
  const t = template as RemoteConfigTemplateLike;
  return {
    freeWeekProgramLive: readBoolean(t, FREE_WEEK_PROGRAM_SWITCH),
    freeWeekUnused: {
      enabled: readBoolean(t, DRIP_FREE_WEEK_UNUSED_SWITCH),
      offsetMs: readHours(
        t, DRIP_FREE_WEEK_UNUSED_DELAY_KEY, DRIP_DEFAULT_HOURS.freeWeekUnused
      ),
    },
    paywallAbandoned: {
      enabled: readBoolean(t, DRIP_PAYWALL_ABANDONED_SWITCH),
      offsetMs: readHours(
        t,
        DRIP_PAYWALL_ABANDONED_DELAY_KEY,
        DRIP_DEFAULT_HOURS.paywallAbandoned
      ),
    },
    trialReminder: {
      enabled: readBoolean(t, DRIP_TRIAL_REMINDER_SWITCH),
      offsetMs: readHours(
        t, DRIP_TRIAL_REMINDER_LEAD_KEY, DRIP_DEFAULT_HOURS.trialReminder
      ),
    },
  };
}

/**
 * Builds the one-email-per-account-per-type-for-life dedupe key.
 * @param {DripEmailType} type - Which drip email
 * @param {string} uid - Firebase Auth user ID
 * @return {string} Stable dedupe key
 */
export function buildDripDedupeKey(type: DripEmailType, uid: string): string {
  return `drip-email:${type}:${uid}`;
}

/**
 * The link every drip email carries: the site's /go page, tagged by email.
 * @param {DripEmailType} type - Which drip email
 * @return {string} The tagged link
 */
export function dripLink(type: DripEmailType): string {
  return `${LINK_BASE}?src=${DRIP_LINK_SOURCES[type]}`;
}

export interface DripSegmentSummary {
  alreadyQueued: number;
  candidates: number;
  disabled: boolean;
  errors: number;
  queued: number;
  scanTruncated: boolean;
  skippedNoEmail: number;
  suppressed: number;
  suppressedByConsent: number;
}

export type DripSweepSummary = Record<DripEmailType, DripSegmentSummary>;

export interface DripScanBound {
  maxPages: number;
  pageSize: number;
}

const DEFAULT_SCAN_BOUND: DripScanBound = {maxPages: 20, pageSize: 250};

function emptySummary(disabled: boolean): DripSegmentSummary {
  return {
    alreadyQueued: 0,
    candidates: 0,
    disabled,
    errors: 0,
    queued: 0,
    scanTruncated: false,
    skippedNoEmail: 0,
    suppressed: 0,
    suppressedByConsent: 0,
  };
}

interface Candidate {
  /** Extra payload the segment carries (the trial's end). */
  extra?: Pick<DripEmailPayload, "trialEndsAtMs">;
  uid: string;
}

function usableEmail(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const email = value.trim();
  return email.length > 0 && email.length <= 320 && email.includes("@") ?
    email : null;
}

/**
 * Pages through a bounded candidate query.
 * @param {admin.firestore.Query} query - Ordered query, no limit
 * @param {DripScanBound} bound - Page bound
 * @param {Function} onPage - Receives each page of documents
 * @return {Promise<boolean>} True when the bound cut the scan short
 */
async function scan(
  query: admin.firestore.Query,
  bound: DripScanBound,
  onPage: (docs: admin.firestore.QueryDocumentSnapshot[]) => Promise<void>
): Promise<boolean> {
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;
  for (let page = 0; page < bound.maxPages; page++) {
    const paged = cursor ?
      query.startAfter(cursor).limit(bound.pageSize) :
      query.limit(bound.pageSize);
    const snapshot = await paged.get();
    if (snapshot.empty) {
      return false;
    }
    cursor = snapshot.docs[snapshot.docs.length - 1];
    await onPage(snapshot.docs);
    if (snapshot.size < bound.pageSize) {
      return false;
    }
  }
  return true;
}

function uidOf(
  doc: admin.firestore.QueryDocumentSnapshot,
  collection: string,
  docId: string
): string | null {
  const segments = doc.ref.path.split("/");
  return segments.length === 4 && segments[0] === "users" &&
    segments[2] === collection && segments[3] === docId ?
    segments[1] : null;
}

function recordOutcome(
  summary: DripSegmentSummary,
  outcome: EnqueueLifecycleEmailOutcome
): void {
  if (outcome === "queued") {
    summary.queued += 1;
  } else if (outcome === "already_queued") {
    summary.alreadyQueued += 1;
  } else {
    summary.suppressedByConsent += 1;
  }
}

/**
 * Queues one climber's email when they are still eligible.
 * @param {DripEmailType} type - Which email
 * @param {Candidate} candidate - The climber and segment extras
 * @param {Date} now - The sweep's clock
 * @param {DripFactReader} reader - Where eligibility facts come from
 * @param {DripSegmentSummary} summary - Counters to update
 * @return {Promise<void>} Resolves when handled
 */
async function enqueueCandidate(
  type: DripEmailType,
  candidate: Candidate,
  now: Date,
  reader: DripFactReader,
  summary: DripSegmentSummary
): Promise<void> {
  const firestore = admin.firestore();
  const dedupeKey = buildDripDedupeKey(type, candidate.uid);
  // A climber inside the window stays a candidate for several runs, so the
  // cheap "already queued" read comes before the eligibility reads.
  const existing = await firestore
    .collection("email_jobs").doc(buildEmailJobId(dedupeKey)).get();
  if (existing.exists) {
    summary.alreadyQueued += 1;
    return;
  }
  summary.candidates += 1;

  const reason = await dripSuppressionReasonFor(
    type, candidate.uid, reader, {
      now,
      ...(candidate.extra?.trialEndsAtMs !== undefined ?
        {expectedTrialEndsAtMs: candidate.extra.trialEndsAtMs} : {}),
    }
  );
  if (reason) {
    summary.suppressed += 1;
    return;
  }

  const user = await firestore.collection("users").doc(candidate.uid).get();
  const email = usableEmail(user.get("email"));
  if (!email) {
    summary.skippedNoEmail += 1;
    return;
  }
  const firstName = cleanFirstName(user.get("firstName"));
  const payload: DripEmailPayload = {
    ctaUrl: dripLink(type),
    ...(firstName ? {firstName} : {}),
    ...(candidate.extra ?? {}),
    ...(type === "drip_trial_reminder" ?
      {timeZone: await resolveClimberTimeZone(firestore, candidate.uid)} :
      {}),
  };

  recordOutcome(summary, await enqueueLifecycleEmailIfAllowed(firestore, {
    dedupeKey,
    emailType: type,
    payload,
    recipientEmail: email,
    sourceRef: user.ref.path,
    uid: candidate.uid,
  }));
}

async function runSegment(
  type: DripEmailType,
  query: admin.firestore.Query,
  toCandidate: (doc: admin.firestore.QueryDocumentSnapshot) => Candidate | null,
  now: Date,
  reader: DripFactReader,
  bound: DripScanBound
): Promise<DripSegmentSummary> {
  const summary = emptySummary(false);
  summary.scanTruncated = await scan(query, bound, async (docs) => {
    const candidates = docs
      .map(toCandidate)
      .filter((candidate): candidate is Candidate => candidate !== null);
    const failures = await runWithBoundedConcurrency(
      candidates,
      RECIPIENT_CONCURRENCY,
      (candidate) => enqueueCandidate(type, candidate, now, reader, summary)
    );
    for (const failure of failures) {
      summary.errors += 1;
      logger.error("lifecycleDripEmails.candidateFailed", {
        errorMessage: failure.error instanceof Error ?
          failure.error.message : "unknown_error",
        type,
        uid: failure.item.uid,
      });
    }
  });
  if (summary.scanTruncated) {
    logger.error("lifecycleDripEmails.scanTruncated", {type});
  }
  return summary;
}

/**
 * Runs the three drip sweeps.
 * @param {Date} now - The sweep's clock, injectable for tests
 * @param {DripSettings} settings - Switches and delays
 * @param {DripScanBound} bound - Candidate scan bound, injectable
 * @return {Promise<DripSweepSummary>} What each sweep did
 */
export async function runDripSweeps(
  now: Date,
  settings: DripSettings,
  bound: DripScanBound = DEFAULT_SCAN_BOUND
): Promise<DripSweepSummary> {
  const firestore = admin.firestore();
  const reader = makeFirestoreDripFactReader(firestore);
  const ts = (ms: number) => admin.firestore.Timestamp.fromMillis(ms);
  const summary: DripSweepSummary = {
    drip_free_week_unused: emptySummary(true),
    drip_paywall_abandoned: emptySummary(true),
    drip_trial_reminder: emptySummary(true),
  };

  const guarded = async (
    type: DripEmailType,
    run: () => Promise<DripSegmentSummary>
  ) => {
    try {
      summary[type] = await run();
    } catch (error) {
      // One segment's failure (an index still building, say) must not stop
      // the others.
      summary[type] = {...emptySummary(false), errors: 1};
      logger.error("lifecycleDripEmails.segmentFailed", {
        errorMessage: error instanceof Error ? error.message : "unknown_error",
        type,
      });
    }
  };

  const nowMs = now.getTime();

  if (settings.paywallAbandoned.enabled && settings.freeWeekProgramLive) {
    const dueBy = nowMs - settings.paywallAbandoned.offsetMs;
    await guarded("drip_paywall_abandoned", () => runSegment(
      "drip_paywall_abandoned",
      firestore.collectionGroup("lifecycle_events")
        .where("eventDocId", "==", FIRST_PAYWALL_SHOWN_EVENT)
        .where("createdAt", ">=", ts(dueBy - DRIP_MAX_LATENESS_MS))
        .where("createdAt", "<=", ts(dueBy))
        .orderBy("createdAt"),
      (doc) => {
        const uid = uidOf(doc, "lifecycle_events", FIRST_PAYWALL_SHOWN_EVENT);
        return uid ? {uid} : null;
      },
      now, reader, bound
    ));
  }

  if (settings.freeWeekUnused.enabled && settings.freeWeekProgramLive) {
    const dueBy = nowMs - settings.freeWeekUnused.offsetMs;
    await guarded("drip_free_week_unused", () => runSegment(
      "drip_free_week_unused",
      firestore.collectionGroup("trial")
        .where("grantedAt", ">=", ts(dueBy - DRIP_MAX_LATENESS_MS))
        .where("grantedAt", "<=", ts(dueBy))
        .orderBy("grantedAt"),
      (doc) => {
        const uid = uidOf(doc, "trial", "free_week");
        return uid ? {uid} : null;
      },
      now, reader, bound
    ));
  }

  if (settings.trialReminder.enabled) {
    await guarded("drip_trial_reminder", () => runSegment(
      "drip_trial_reminder",
      firestore.collectionGroup("entitlements")
        .where("productId", "in", [...WELCOME_PRODUCT_IDS])
        .where("accessUntil", ">=", ts(nowMs + TRIAL_REMINDER_MIN_LEAD_MS))
        .where("accessUntil", "<=", ts(nowMs + settings.trialReminder.offsetMs))
        .orderBy("accessUntil"),
      (doc) => {
        const uid = uidOf(doc, "entitlements", "app_access");
        const accessUntil = doc.get("accessUntil");
        return uid && accessUntil instanceof admin.firestore.Timestamp ?
          {extra: {trialEndsAtMs: accessUntil.toMillis()}, uid} : null;
      },
      now, reader, bound
    ));
  }

  return summary;
}

/**
 * Queues the drip emails that are due. Every fifteen minutes.
 */
export const lifecycleDripEmails = onSchedule(
  {
    concurrency: 1,
    maxInstances: 1,
    memory: "512MiB",
    schedule: "every 15 minutes",
    timeoutSeconds: 540,
    timeZone: "Etc/UTC",
  },
  async () => {
    let settings: DripSettings;
    try {
      settings = readDripSettings(await admin.remoteConfig().getTemplate());
    } catch (error) {
      // Fails closed: an email cannot be recalled.
      logger.error("lifecycleDripEmails.settingsUnreadable", {
        errorMessage: error instanceof Error ? error.message : "unknown_error",
      });
      return;
    }
    const summary = await runDripSweeps(new Date(), settings);
    const degraded = Object.values(summary)
      .some((segment) => segment.errors > 0 || segment.scanTruncated);
    (degraded ? logger.error : logger.log)(
      "lifecycleDripEmails sweep completed", summary
    );
  }
);
