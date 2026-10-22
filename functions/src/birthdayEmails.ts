/**
 * Birthday emails: one greeting per climber per year, in their own morning.
 *
 * `birthdayEmails` runs every hour. Each sweep reads the users who have a
 * stored `birth_date` and, for each whose birthday it is on their own clock
 * and whose local time is inside the 9 AM to 9 PM window, queues the
 * `birthday` email. The window rather than a single hour is deliberate: a
 * sweep that failed or was skipped is made up by the next one, and the dedupe
 * key (`birthday-email:{year}:{uid}`, enforced inside the enqueue transaction)
 * is what guarantees the climber still gets exactly one.
 *
 * Rules, all decided in `email/birthday.ts`:
 *   - the climber's zone is the one their newest registered device reported
 *     (`users/{uid}/notification_devices`), else `America/Chicago`;
 *   - a February 29 birthday is celebrated on February 28 in a year without
 *     one;
 *   - no `birth_date`, no email address, or no recorded email opt-in means no
 *     email, exactly as for the recap emails (`enqueueLifecycleEmailIfAllowed`
 *     is the one consent gate, and the processor re-checks at send time);
 *   - a name is optional, and a stored placeholder is not a name.
 *
 * Which environments actually deliver is not decided here. Like the recap
 * emails, the sweep queues and the processor sends only the types
 * `TRANSACTIONAL_EMAIL_CONFIG.enabledEmailTypes` enables for that project, so
 * a dev or staging project that does not list `birthday` marks each job
 * skipped and mails nobody.
 *
 * The sweep reads every user that has a `birth_date`: birthdays cannot be
 * range-queried because the stored string leads with the year. That is one
 * bounded, paged read per hour; a derived month-day index is the follow-up if
 * the user count ever makes it matter.
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {runWithBoundedConcurrency} from "./concurrency";
import {
  ageOnBirthday,
  buildBirthdayDedupeKey,
  celebrationDay,
  cleanFirstName,
  DEFAULT_BIRTHDAY_TIME_ZONE,
  isBirthdayOn,
  isInBirthdaySendWindow,
  isValidTimeZone,
  localMomentIn,
  parseBirthDate,
  type BirthDate,
} from "./email/birthday";
import {APP_STORE_URL} from "./email/config";
import {
  enqueueLifecycleEmailIfAllowed,
  type EnqueueLifecycleEmailOutcome,
} from "./email/queue";
import type {BirthdayEmailPayload} from "./email/types";

const USERS_COLLECTION = "users";
const NOTIFICATION_DEVICES_COLLECTION = "notification_devices";
/** The profile's validated age range (`firestore.rules`, `ProfileBirthday`). */
const MIN_BIRTHDAY_AGE = 13;
const MAX_BIRTHDAY_AGE = 120;
/** Devices read per candidate to find the newest one that reported a zone. */
const DEVICES_READ_PER_CANDIDATE = 5;
/** Candidates enqueued at once, per sweep. */
const RECIPIENT_CONCURRENCY = 10;
/** Earliest and latest UTC offsets in use, in hours. */
const MIN_UTC_OFFSET_HOURS = -12;
const MAX_UTC_OFFSET_HOURS = 14;
const HOUR_MS = 60 * 60 * 1000;

export interface BirthdayScanBound {
  maxPages: number;
  pageSize: number;
}

/** 100 pages of 500: fifty thousand climbers with a birthday on file. */
const DEFAULT_BIRTHDAY_SCAN_BOUND: BirthdayScanBound = {
  maxPages: 100,
  pageSize: 500,
};

export interface BirthdaySweepSummary {
  alreadyQueued: number;
  candidates: number;
  errors: number;
  queued: number;
  scanned: number;
  scanTruncated: boolean;
  skippedNoEmail: number;
  suppressed: number;
}

export interface BirthdayEligibility {
  age: number;
  /** The local calendar year of the birthday being celebrated. */
  year: number;
}

/**
 * Whether a birthday could be today in any time zone right now. The sweep
 * uses it to look up a climber's device zone only for the handful of
 * birthdays that might qualify, never for every climber.
 * @param {BirthDate} birth - The climber's birthday
 * @param {Date} now - The sweep's clock
 * @return {boolean} True when some zone's local date is the birthday
 */
export function couldBeBirthdayInAnyZone(
  birth: BirthDate,
  now: Date
): boolean {
  const earliest = new Date(now.getTime() + MIN_UTC_OFFSET_HOURS * HOUR_MS);
  const latest = new Date(now.getTime() + MAX_UTC_OFFSET_HOURS * HOUR_MS);
  return [earliest, now, latest].some((instant) => {
    const utc = localMomentIn(instant, "Etc/UTC");
    const target = celebrationDay(birth, utc.year);
    return target.month === utc.month && target.day === utc.day;
  });
}

/**
 * Decides whether a climber's birthday email is due at this instant.
 * @param {BirthDate} birth - The climber's birthday
 * @param {string} timeZone - The climber's IANA zone
 * @param {Date} now - The sweep's clock
 * @return {BirthdayEligibility | null} The age and year, or null when not due
 */
export function birthdayEligibility(
  birth: BirthDate,
  timeZone: string,
  now: Date
): BirthdayEligibility | null {
  const local = localMomentIn(now, timeZone);
  if (!isBirthdayOn(birth, local) || !isInBirthdaySendWindow(local)) {
    return null;
  }
  const age = ageOnBirthday(birth, local.year);
  if (age < MIN_BIRTHDAY_AGE || age > MAX_BIRTHDAY_AGE) {
    return null;
  }
  return {age, year: local.year};
}

/**
 * Builds the stored payload for one climber's birthday email.
 * @param {number} age - Age on this birthday
 * @param {unknown} rawFirstName - The profile's stored first name
 * @return {BirthdayEmailPayload} Email payload, name omitted when unusable
 */
export function buildBirthdayEmailPayload(
  age: number,
  rawFirstName: unknown
): BirthdayEmailPayload {
  const firstName = cleanFirstName(rawFirstName);
  return {
    age,
    ctaUrl: APP_STORE_URL,
    ...(firstName ? {firstName} : {}),
  };
}

/**
 * Finds the zone a climber's newest device reported.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @return {Promise<string>} A valid IANA zone, or the default
 */
async function resolveTimeZone(
  firestore: admin.firestore.Firestore,
  uid: string
): Promise<string> {
  const devices = await firestore
    .collection(USERS_COLLECTION)
    .doc(uid)
    .collection(NOTIFICATION_DEVICES_COLLECTION)
    .orderBy("lastSeenAt", "desc")
    .limit(DEVICES_READ_PER_CANDIDATE)
    .get();
  for (const device of devices.docs) {
    const zone = device.get("timeZone");
    if (typeof zone === "string" && isValidTimeZone(zone)) {
      return zone;
    }
  }
  return DEFAULT_BIRTHDAY_TIME_ZONE;
}

/**
 * Reads a trimmed, plausible email address from a user document.
 * @param {unknown} value - Stored `email`
 * @return {string | null} The address, or null
 */
function usableEmail(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const email = value.trim();
  return email.length > 0 && email.length <= 320 && email.includes("@") ?
    email :
    null;
}

/**
 * Applies one enqueue outcome to the sweep summary.
 * @param {BirthdaySweepSummary} summary - Sweep counters to update
 * @param {EnqueueLifecycleEmailOutcome} outcome - What the enqueue did
 * @return {void}
 */
function recordOutcome(
  summary: BirthdaySweepSummary,
  outcome: EnqueueLifecycleEmailOutcome
): void {
  if (outcome === "queued") {
    summary.queued += 1;
  } else if (outcome === "already_queued") {
    summary.alreadyQueued += 1;
  } else {
    summary.suppressed += 1;
  }
}

/**
 * Queues the birthday email for one climber when it is due.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {admin.firestore.QueryDocumentSnapshot} user - The user document
 * @param {BirthDate} birth - The climber's parsed birthday
 * @param {Date} now - The sweep's clock
 * @param {BirthdaySweepSummary} summary - Sweep counters to update
 * @return {Promise<void>} Resolves when the climber has been handled
 */
async function sendBirthdayEmail(
  firestore: admin.firestore.Firestore,
  user: admin.firestore.QueryDocumentSnapshot,
  birth: BirthDate,
  now: Date,
  summary: BirthdaySweepSummary
): Promise<void> {
  const timeZone = await resolveTimeZone(firestore, user.id);
  const eligibility = birthdayEligibility(birth, timeZone, now);
  if (!eligibility) {
    return;
  }
  summary.candidates += 1;

  const email = usableEmail(user.get("email"));
  if (!email) {
    summary.skippedNoEmail += 1;
    return;
  }

  const outcome = await enqueueLifecycleEmailIfAllowed(firestore, {
    dedupeKey: buildBirthdayDedupeKey(user.id, eligibility.year),
    emailType: "birthday",
    payload: buildBirthdayEmailPayload(eligibility.age, user.get("firstName")),
    recipientEmail: email,
    sourceRef: user.ref.path,
    uid: user.id,
  });
  recordOutcome(summary, outcome);
}

/**
 * Runs one birthday sweep.
 * @param {Date} now - The sweep's clock, injectable for tests
 * @param {BirthdayScanBound} scanBound - User scan page bound, injectable
 * @return {Promise<BirthdaySweepSummary>} What the sweep did
 */
export async function runBirthdaySweep(
  now: Date,
  scanBound: BirthdayScanBound = DEFAULT_BIRTHDAY_SCAN_BOUND
): Promise<BirthdaySweepSummary> {
  const firestore = admin.firestore();
  const summary: BirthdaySweepSummary = {
    alreadyQueued: 0,
    candidates: 0,
    errors: 0,
    queued: 0,
    scanned: 0,
    scanTruncated: false,
    skippedNoEmail: 0,
    suppressed: 0,
  };

  // A range on `birth_date` leaves out every user without one, so the scan
  // reads only climbers who shared a birthday.
  const baseQuery = firestore.collection(USERS_COLLECTION)
    .where("birth_date", ">", "")
    .orderBy("birth_date")
    .orderBy(admin.firestore.FieldPath.documentId())
    .select("birth_date", "email", "firstName");
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;
  let exhausted = false;

  for (let page = 0; page < scanBound.maxPages; page++) {
    const query = cursor ?
      baseQuery.startAfter(cursor).limit(scanBound.pageSize) :
      baseQuery.limit(scanBound.pageSize);
    const snapshot = await query.get();
    if (snapshot.empty) {
      exhausted = true;
      break;
    }
    cursor = snapshot.docs[snapshot.docs.length - 1];
    summary.scanned += snapshot.size;

    const due: Array<{birth: BirthDate; user: typeof snapshot.docs[number]}> =
      [];
    for (const user of snapshot.docs) {
      const birth = parseBirthDate(user.get("birth_date"));
      if (birth && couldBeBirthdayInAnyZone(birth, now)) {
        due.push({birth, user});
      }
    }

    const failures = await runWithBoundedConcurrency(
      due,
      RECIPIENT_CONCURRENCY,
      ({birth, user}) =>
        sendBirthdayEmail(firestore, user, birth, now, summary)
    );
    for (const failure of failures) {
      summary.errors += 1;
      logger.error("birthdayEmails.sendFailed", {
        errorMessage: failure.error instanceof Error ?
          failure.error.message :
          "unknown_error",
        path: failure.item.user.ref.path,
      });
    }

    if (snapshot.size < scanBound.pageSize) {
      exhausted = true;
      break;
    }
  }

  if (!exhausted) {
    summary.scanTruncated = true;
    logger.error("birthdayEmails.scanTruncated", {
      pagesRead: scanBound.maxPages,
      usersRead: summary.scanned,
    });
  }
  return summary;
}

/**
 * Queues today's birthday emails. Hourly, on the hour, so every time zone's
 * morning window is covered.
 */
export const birthdayEmails = onSchedule(
  {
    memory: "512MiB",
    schedule: "0 * * * *",
    timeoutSeconds: 540,
    timeZone: "Etc/UTC",
  },
  async () => {
    const summary = await runBirthdaySweep(new Date());
    const degraded = summary.errors > 0 || summary.scanTruncated;
    const write = degraded ? logger.error : logger.log;
    write("birthdayEmails sweep completed", summary);
  }
);
