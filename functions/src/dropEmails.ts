import * as admin from "firebase-admin";
import {runWithBoundedConcurrency} from "./concurrency";
import {
  dropEmailItems,
  parseDropEmailPayload,
} from "./email/dropTemplate";
import {isLifecycleEmailAllowed} from "./email/preferences";
import {
  enqueueLifecycleEmailIfAllowed,
  type EnqueueLifecycleEmailOutcome,
} from "./email/queue";
import type {
  DropEmailPayload,
  EmailJobDocument,
  EmailJobStatus,
} from "./email/types";

/**
 * Drop announcements: who may receive one, queuing it exactly once per
 * climber, and the checks a sender runs before it queues anything. The
 * operator drives all of it from `scripts/send-drop-email.mjs`; nothing here
 * runs on a schedule or a trigger, and delivery is the ordinary
 * `processEmailJobs` worker with its send-time consent re-check.
 */

export const DROP_EMAIL_TYPE = "drop_announcement";
const USERS_COLLECTION = "users";
const PREFERENCES_COLLECTION = "communication_preferences";
const PREFERENCES_DOCUMENT = "current";
const EMAIL_JOBS_COLLECTION = "email_jobs";
const ENQUEUE_CONCURRENCY = 8;

export interface DropRecipient {
  email: string;
  uid: string;
}

export interface DropAudience {
  /** Opted in, with an address on their profile: who a send queues for. */
  recipients: DropRecipient[];
  /** Opted in, but with no address on their profile. */
  skippedNoEmail: number;
  /** Every climber whose answer is anything but an explicit yes. */
  notOptedIn: number;
}

/**
 * The dedupe key that makes a drop one email per climber, for good: a rerun,
 * a crash halfway through, or a second operator finds the job already there.
 * @param {string} dropId - Drop id
 * @param {string} uid - Recipient uid
 * @return {string} Dedupe key
 */
export function buildDropDedupeKey(dropId: string, uid: string): string {
  return `drop:${dropId}:${uid}`;
}

/**
 * A test send's dedupe key. It never collides with the real one, so a test
 * to the founder's account cannot use up the founder's real send, and each
 * test run gets a fresh key so the same address can be tested again.
 * @param {string} dropId - Drop id
 * @param {string} uid - Recipient uid
 * @param {string} runId - Unique per test run
 * @return {string} Dedupe key
 */
export function buildDropTestDedupeKey(
  dropId: string,
  uid: string,
  runId: string
): string {
  return `drop-test:${dropId}:${uid}:${runId}`;
}

/**
 * The uid a `users/{uid}/communication_preferences/current` path belongs
 * to, or null for any other document of that collection name.
 * @param {string} path - Document path
 * @return {string | null} Owner uid
 */
export function preferenceOwnerUid(path: string): string | null {
  const segments = path.split("/");
  if (
    segments.length !== 4 ||
    segments[0] !== USERS_COLLECTION ||
    segments[2] !== PREFERENCES_COLLECTION ||
    segments[3] !== PREFERENCES_DOCUMENT
  ) {
    return null;
  }
  return segments[1];
}

/**
 * Turns stored preferences and profile addresses into the audience. The
 * gate is the same `isLifecycleEmailAllowed` every lifecycle email uses:
 * only a recorded yes, never a missing answer.
 * @param {Array<{path: string, data: Record<string, unknown>}>} preferences
 *   Every communication preferences document
 * @param {Map<string, string | null>} emailByUid - Profile address per uid
 * @return {DropAudience} Audience
 */
export function selectDropAudience(
  preferences: Array<{path: string; data: Record<string, unknown>}>,
  emailByUid: Map<string, string | null>
): DropAudience {
  const audience: DropAudience = {
    notOptedIn: 0,
    recipients: [],
    skippedNoEmail: 0,
  };
  for (const {path, data} of preferences) {
    const uid = preferenceOwnerUid(path);
    if (!uid) {
      continue;
    }
    if (!isLifecycleEmailAllowed(data)) {
      audience.notOptedIn += 1;
      continue;
    }
    const email = emailByUid.get(uid) ?? null;
    if (!email || !email.includes("@")) {
      audience.skippedNoEmail += 1;
      continue;
    }
    audience.recipients.push({email, uid});
  }
  audience.recipients.sort((lhs, rhs) => lhs.uid.localeCompare(rhs.uid));
  return audience;
}

/**
 * Reads the drop audience: every opted-in climber with a profile address.
 * One collection-group read of the preferences, then one profile read per
 * opted-in climber - never a scan of every user's history.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @return {Promise<DropAudience>} Audience
 */
export async function readDropAudience(
  firestore: admin.firestore.Firestore
): Promise<DropAudience> {
  const snapshot = await firestore
    .collectionGroup(PREFERENCES_COLLECTION)
    .get();
  const preferences = snapshot.docs.map((document) => ({
    data: document.data() as Record<string, unknown>,
    path: document.ref.path,
  }));
  const optedIn = preferences
    .filter(({data}) => isLifecycleEmailAllowed(data))
    .map(({path}) => preferenceOwnerUid(path))
    .filter((uid): uid is string => uid !== null);

  const emailByUid = new Map<string, string | null>();
  const failures = await runWithBoundedConcurrency(
    optedIn,
    ENQUEUE_CONCURRENCY,
    async (uid) => {
      const profile = await firestore
        .collection(USERS_COLLECTION)
        .doc(uid)
        .get();
      const email = profile.get("email");
      emailByUid.set(
        uid,
        typeof email === "string" && email.trim().length > 0 ?
          email.trim() :
          null
      );
    }
  );
  if (failures.length > 0) {
    // An unread profile is not a climber without an address: counting it as
    // one would under-report the audience and silently skip them for good.
    throw new Error(`Could not read ${failures.length} profile(s): ` +
      String((failures[0].error as Error)?.message ?? failures[0].error));
  }

  return selectDropAudience(preferences, emailByUid);
}

export interface DropEnqueueSummary {
  alreadyQueued: number;
  failed: Array<{error: string; uid: string}>;
  preferencesDisabled: number;
  queued: number;
}

/**
 * Queues the drop for every recipient through the one consent-gated,
 * dedupe-checked enqueue every lifecycle email uses. Safe to rerun: a
 * climber already queued is counted, never queued twice.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {DropEmailPayload} payload - Validated drop payload
 * @param {DropRecipient[]} recipients - Audience
 * @return {Promise<DropEnqueueSummary>} What happened
 */
export async function enqueueDropEmails(
  firestore: admin.firestore.Firestore,
  payload: DropEmailPayload,
  recipients: DropRecipient[]
): Promise<DropEnqueueSummary> {
  const summary: DropEnqueueSummary = {
    alreadyQueued: 0,
    failed: [],
    preferencesDisabled: 0,
    queued: 0,
  };
  const failures = await runWithBoundedConcurrency(
    recipients,
    ENQUEUE_CONCURRENCY,
    async (recipient) => {
      const outcome = await enqueueLifecycleEmailIfAllowed(firestore, {
        dedupeKey: buildDropDedupeKey(payload.dropId, recipient.uid),
        emailType: DROP_EMAIL_TYPE,
        payload,
        recipientEmail: recipient.email,
        sourceRef: null,
        uid: recipient.uid,
      });
      countOutcome(summary, outcome);
    }
  );
  summary.failed = failures.map(({error, item}) => ({
    error: error instanceof Error ? error.message : String(error),
    uid: item.uid,
  }));
  return summary;
}

/**
 * Adds one enqueue outcome to a summary.
 * @param {DropEnqueueSummary} summary - Summary to update
 * @param {EnqueueLifecycleEmailOutcome} outcome - Outcome
 */
function countOutcome(
  summary: DropEnqueueSummary,
  outcome: EnqueueLifecycleEmailOutcome
): void {
  if (outcome === "queued") {
    summary.queued += 1;
  } else if (outcome === "already_queued") {
    summary.alreadyQueued += 1;
  } else {
    summary.preferencesDisabled += 1;
  }
}

/**
 * Queues one test send to one account. It goes through the same consent
 * gate and the same worker as the real send - a test that skipped either
 * would prove less than the real thing needs - under a key of its own.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {DropEmailPayload} payload - Validated drop payload
 * @param {DropRecipient} recipient - The named account
 * @param {string} runId - Unique per test run
 * @return {Promise<EnqueueLifecycleEmailOutcome>} What happened
 */
export async function enqueueDropTestEmail(
  firestore: admin.firestore.Firestore,
  payload: DropEmailPayload,
  recipient: DropRecipient,
  runId: string
): Promise<EnqueueLifecycleEmailOutcome> {
  return enqueueLifecycleEmailIfAllowed(firestore, {
    dedupeKey: buildDropTestDedupeKey(payload.dropId, recipient.uid, runId),
    emailType: DROP_EMAIL_TYPE,
    payload,
    recipientEmail: recipient.email,
    sourceRef: null,
    uid: recipient.uid,
  });
}

/**
 * Counts this drop's real (non-test) jobs by status.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} dropId - Drop id
 * @return {Promise<Record<string, number>>} Count per status
 */
export async function readDropJobStatus(
  firestore: admin.firestore.Firestore,
  dropId: string
): Promise<Record<string, number>> {
  const snapshot = await firestore.collection(EMAIL_JOBS_COLLECTION)
    .where("type", "==", DROP_EMAIL_TYPE)
    .select("dedupeKey", "status")
    .get();
  const prefix = `drop:${dropId}:`;
  const counts: Record<string, number> = {};
  for (const document of snapshot.docs) {
    const dedupeKey = document.get("dedupeKey");
    if (typeof dedupeKey !== "string" || !dedupeKey.startsWith(prefix)) {
      continue;
    }
    const status = String(document.get("status"));
    counts[status] = (counts[status] ?? 0) + 1;
  }
  return counts;
}

// -----------------------------------------------------------------------------
// Catalogue check
// -----------------------------------------------------------------------------

interface CatalogueEvent {
  endsBefore: string;
  id: string;
  monthName?: string;
  startsOn: string;
}

interface CatalogueItem {
  earn?: {event?: string; metric?: string; path?: string; threshold?: number};
  id: string;
  status?: string;
}

/**
 * "10K" for a whole thousand, otherwise the grouped number.
 * @param {number} value - Threshold
 * @return {string} Compact count
 */
function compactCount(value: number): string {
  return value >= 1000 && value % 1000 === 0 ?
    `${value / 1000}K` :
    value.toLocaleString("en-US");
}

/**
 * The requirement wording the approved Halloween redesign shows on the
 * October page for a catalogue item - bare counts ("5 climbs", "10K steps",
 * "20 days", "Oct 31"), never "save", "do" or "every day" - so the
 * email can be checked against what the app will say. The redesign
 * (`data/ascend-mountain-art-direction/halloween-build-handoff.md` in the
 * firstmate home, section 4.1) supersedes `UnlockCopy.requirement`'s older
 * upper-case wording on PR 636.
 * @param {CatalogueItem} item - Catalogue item
 * @param {CatalogueEvent} event - The item's event
 * @return {string | null} Requirement, or null for an unknown metric
 */
export function catalogueRequirement(
  item: CatalogueItem,
  event: CatalogueEvent
): string | null {
  const threshold = item.earn?.threshold;
  if (typeof threshold !== "number") {
    return null;
  }
  switch (item.earn?.metric) {
  case "visits":
    return `Open Ascend in ${event.monthName ?? "the event"}`;
  case "climbs":
    return threshold === 1 ? "1 climb" : `${threshold} climbs`;
  case "days":
    return threshold === 1 ? "1 day" : `${threshold} days`;
  case "steps":
    return `${compactCount(threshold)} steps`;
  case "onDay": {
    const start = Date.parse(`${event.startsOn}T00:00:00Z`);
    const day = new Date(start + (threshold - 1) * 86_400_000);
    const label = day.toLocaleDateString("en-US", {
      day: "numeric",
      month: "short",
      timeZone: "UTC",
    });
    return label;
  }
  default:
    return null;
  }
}

/**
 * Every way the email disagrees with the hosted unlock catalogue: an item it
 * names that the catalogue lacks, has not switched live, files under another
 * event, or earns by a different requirement. Empty means the email promises
 * exactly what that environment's app will offer.
 * @param {DropEmailPayload} payload - Drop payload
 * @param {unknown} catalogue - Parsed `unlocks/catalog.json`
 * @return {string[]} Human-readable mismatches
 */
export function dropCatalogueMismatches(
  payload: DropEmailPayload,
  catalogue: unknown
): string[] {
  const root = catalogue as {events?: unknown; items?: unknown} | null;
  if (!root || !Array.isArray(root.events) || !Array.isArray(root.items)) {
    return ["The unlock catalogue has no events or items."];
  }
  const event = (root.events as CatalogueEvent[])
    .find((candidate) => candidate?.id === payload.dropId);
  if (!event) {
    return [`The unlock catalogue has no event "${payload.dropId}".`];
  }
  const items = new Map((root.items as CatalogueItem[])
    .filter((item) => typeof item?.id === "string")
    .map((item) => [item.id, item]));

  const mismatches: string[] = [];
  for (const emailItem of dropEmailItems(payload)) {
    const item = items.get(emailItem.catalogItemId);
    if (!item) {
      mismatches.push(`${emailItem.name}: "${emailItem.catalogItemId}" is ` +
        "not in the catalogue.");
      continue;
    }
    if (item.status !== "live") {
      mismatches.push(`${emailItem.name}: catalogue status is ` +
        `"${item.status}", not "live".`);
    }
    if (item.earn?.event !== event.id) {
      mismatches.push(`${emailItem.name}: earned in "${item.earn?.event}", ` +
        `not "${event.id}".`);
    }
    const requirement = catalogueRequirement(item, event);
    if (requirement !== emailItem.requirement) {
      mismatches.push(`${emailItem.name}: the email says ` +
        `"${emailItem.requirement}", the catalogue says "${requirement}".`);
    }
  }

  const named = new Set(
    dropEmailItems(payload).map((item) => item.catalogItemId)
  );
  for (const item of items.values()) {
    if (item.earn?.event === event.id && item.status === "live" &&
      !named.has(item.id)) {
      mismatches.push(`"${item.id}" is live in the catalogue but missing ` +
        "from the email.");
    }
  }
  return mismatches;
}

/**
 * Validates a payload exactly as the worker will before rendering it, so a
 * malformed drop fails on the operator's machine, not in 16 failed jobs.
 * @param {DropEmailPayload} payload - Built payload
 * @return {DropEmailPayload} The validated payload
 */
export function validateDropEmailPayload(
  payload: DropEmailPayload
): DropEmailPayload {
  return parseDropEmailPayload(payload);
}

// -----------------------------------------------------------------------------
// Stale backlog
// -----------------------------------------------------------------------------

export interface StaleEmailJob {
  createdAt: string;
  id: string;
  type: string;
}

/**
 * Lists queued jobs created before a cutoff - mail that waited so long it
 * would now arrive as a surprise, such as a September recap in October.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {Date} cutoff - Jobs created strictly before this are stale
 * @return {Promise<StaleEmailJob[]>} Stale jobs, oldest first
 */
export async function readStaleQueuedEmailJobs(
  firestore: admin.firestore.Firestore,
  cutoff: Date
): Promise<StaleEmailJob[]> {
  const queued: EmailJobStatus = "queued";
  const snapshot = await firestore.collection(EMAIL_JOBS_COLLECTION)
    .where("status", "==", queued)
    .select("createdAt", "type")
    .get();
  return snapshot.docs
    .map((document) => ({
      createdAt: (document.get("createdAt") as admin.firestore.Timestamp | null)
        ?.toDate() ?? null,
      id: document.id,
      type: String(document.get("type")),
    }))
    .filter((job): job is {createdAt: Date; id: string; type: string} =>
      job.createdAt !== null && job.createdAt < cutoff)
    .sort((lhs, rhs) => lhs.createdAt.getTime() - rhs.createdAt.getTime())
    .map((job) => ({...job, createdAt: job.createdAt.toISOString()}));
}

/**
 * Marks stale queued jobs `skipped`, the worker's own terminal "deliberately
 * not delivered" status. Each job is re-read in a transaction and left alone
 * unless it is still queued, so a job the worker claimed in between is never
 * yanked out from under it.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string[]} jobIds - Jobs listed by `readStaleQueuedEmailJobs`
 * @return {Promise<{skipped: number, unchanged: number}>} What happened
 */
export async function skipStaleQueuedEmailJobs(
  firestore: admin.firestore.Firestore,
  jobIds: string[]
): Promise<{skipped: number; unchanged: number}> {
  let skipped = 0;
  let unchanged = 0;
  for (const id of jobIds) {
    const reference = firestore.collection(EMAIL_JOBS_COLLECTION).doc(id);
    const didSkip = await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const job = snapshot.data() as EmailJobDocument | undefined;
      if (!job || job.status !== "queued") {
        return false;
      }
      transaction.update(reference, {
        processingStartedAt: null,
        status: "skipped",
        updatedAt: admin.firestore.Timestamp.now(),
      });
      return true;
    });
    if (didSkip) {
      skipped += 1;
    } else {
      unchanged += 1;
    }
  }
  return {skipped, unchanged};
}
