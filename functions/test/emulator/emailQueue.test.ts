/**
 * The email queue's surviving producer, against a real Firestore.
 *
 * The unit suite proves the render map and the retry table in isolation. It
 * cannot prove the thing the waitlist removal actually has to survive: a
 * queued job written by an older build, sitting in Firestore next to live
 * work, when the worker picks the batch up. This suite runs the real
 * rating-prompt producer and the real scheduled worker against the Firestore
 * emulator, with only the Resend HTTP call stubbed.
 *
 * Lives under test/emulator/ so `npm test` (glob: lib/test/*.test.js) does not
 * pick it up without a Firestore behind it. `npm run test:emulator` runs it,
 * one file at a time: every suite in this directory shares the one emulator
 * database and wipes it between tests, so running two of them concurrently
 * would clear one suite's seed data mid-test.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  buildRatingPromptEmailDedupeKey,
  onLifecycleEventEmailAutomation,
} from "../../src/email/automation.js";
import {processEmailJobs} from "../../src/email/processor.js";
import {buildEmailJobId} from "../../src/email/queue.js";
import type {EmailJobDocument} from "../../src/email/types.js";

const EMAIL_JOBS = "email_jobs";
const RATING_PROMPT_EVENT_ID = "rating_prompt_answered_v1";
const uid = "climber-1";
const recipientEmail = "climber@example.com";
// What the deleted producer wrote: a dedupe key namespaced to the waitlist.
const RETIRED_JOB_ID = buildEmailJobId("waitlist-welcome:abc123");

interface StubbedSend {
  headers: Record<string, string>;
  html: string;
  subject: string;
  to: string[];
}

let db: admin.firestore.Firestore;
let sends: StubbedSend[] = [];

before(() => {
  // Never let this suite pass by quietly doing nothing. Without an emulator
  // the Admin SDK would reach for real credentials, and a skip here would read
  // as a green queue check that never ran.
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );

  process.env.TRANSACTIONAL_EMAIL_CONFIG = JSON.stringify({
    provider: "resend",
    apiKey: "re_emulator_only",
    fromEmail: "hello@updates.ascendstepper.com",
    fromName: "Ascend",
    replyTo: "support@ascendstepper.com",
    unsubscribeSigningKey: "emulator-unsubscribe-signing-key-0123456789",
    websiteUrl: "https://ascendstepper.com",
  });

  // The only stubbed edge. Everything between the lifecycle event and this
  // call is the shipped code path.
  globalThis.fetch = (async (url: string, init: RequestInit) => {
    assert.equal(url, "https://api.resend.com/emails");
    const body = JSON.parse(String(init.body)) as StubbedSend;
    sends.push(body);
    return new Response(JSON.stringify({id: `resend-${sends.length}`}), {
      headers: {"Content-Type": "application/json"},
      status: 200,
    });
  }) as unknown as typeof fetch;

  admin.initializeApp({projectId: "demo-ascend-leaderboard-derivation"});
  db = admin.firestore();
});

beforeEach(async () => {
  sends = [];
  await clearEmailJobs();
});

test("a climber answering the rating prompt still gets their email",
  async () => {
    await seedUser();
    const eventRef = await seedRatingPromptAnswer("yes");

    await runProducerFor(eventRef);
    await processEmailJobs.run({} as never);

    const job = await readJob(
      buildEmailJobId(buildRatingPromptEmailDedupeKey(uid))
    );

    assert.equal(job.type, "rating_positive_followup");
    assert.equal(job.status, "sent");
    assert.equal(job.provider, "resend");
    assert.equal(job.providerMessageId, "resend-1");
    assert.equal(job.lastErrorCode, null);
    assert.equal(sends.length, 1);
    assert.deepEqual(sends[0].to, [recipientEmail]);
    assert.match(sends[0].html, /\/api\/unsubscribe\?token=/);
    assert.match(
      sends[0].headers["List-Unsubscribe"],
      /^<https:\/\/ascendstepper\.com\/api\/unsubscribe\?token=/
    );
  });

test("a queued waitlist job left over from an older build fails by name",
  async () => {
    await seedUser();
    await seedRetiredWaitlistJob();

    await processEmailJobs.run({} as never);

    const job = await readJob(RETIRED_JOB_ID);

    assert.equal(job.status, "failed");
    assert.equal(job.lastErrorCode, "invalid_payload");
    assert.equal(
      job.lastErrorMessage,
      "unsupported_email_type:waitlist_welcome"
    );
    assert.equal(job.attemptCount, 1);
    assert.equal(job.sentAt, null);
    // The retired job is retired, not retried: nothing was handed to Resend.
    assert.equal(sends.length, 0);
  });

test("a retired job in the batch does not stop the live one beside it",
  async () => {
    await seedUser();
    await seedRetiredWaitlistJob();
    const eventRef = await seedRatingPromptAnswer("no");
    await runProducerFor(eventRef);

    await processEmailJobs.run({} as never);

    const retiredJob = await readJob(RETIRED_JOB_ID);
    const liveJob = await readJob(
      buildEmailJobId(buildRatingPromptEmailDedupeKey(uid))
    );

    assert.equal(retiredJob.status, "failed");
    assert.equal(liveJob.type, "rating_negative_feedback");
    assert.equal(liveJob.status, "sent");
    assert.equal(sends.length, 1);

    console.log("email_jobs after the batch: " + JSON.stringify([
      summarize(RETIRED_JOB_ID, retiredJob),
      summarize(
        buildEmailJobId(buildRatingPromptEmailDedupeKey(uid)),
        liveJob
      ),
    ], null, 2));
  });

/**
 * Reduces a stored job to the fields this suite reasons about.
 * @param {string} jobId - Firestore document ID
 * @param {EmailJobDocument} job - Stored job document
 * @return {Record<string, unknown>} Compact job summary
 */
function summarize(
  jobId: string,
  job: EmailJobDocument
): Record<string, unknown> {
  return {
    id: jobId,
    attemptCount: job.attemptCount,
    lastErrorCode: job.lastErrorCode,
    lastErrorMessage: job.lastErrorMessage,
    provider: job.provider,
    providerMessageId: job.providerMessageId,
    status: job.status,
    type: job.type,
  };
}

/**
 * Reads a stored email job.
 * @param {string} jobId - Firestore document ID
 * @return {Promise<EmailJobDocument>} Stored job document
 */
async function readJob(jobId: string): Promise<EmailJobDocument> {
  const snapshot = await db.collection(EMAIL_JOBS).doc(jobId).get();
  assert.ok(snapshot.exists, `expected email job ${jobId}`);
  return snapshot.data() as EmailJobDocument;
}

/**
 * Seeds the signed-in climber the lifecycle event belongs to.
 * @return {Promise<void>}
 */
async function seedUser(): Promise<void> {
  await db.collection("users").doc(uid).set({email: recipientEmail});
}

/**
 * Records the in-app rating prompt answer the producer listens for.
 * @param {string} response - Prompt answer, "yes" or "no"
 * @return {Promise<DocumentReference>} Lifecycle event reference
 */
async function seedRatingPromptAnswer(
  response: string
): Promise<admin.firestore.DocumentReference> {
  const eventRef = db
    .collection("users")
    .doc(uid)
    .collection("lifecycle_events")
    .doc(RATING_PROMPT_EVENT_ID);

  await eventRef.set({
    payload: {response},
    recordedAt: admin.firestore.Timestamp.now(),
    type: "rating_prompt_answered",
  });

  return eventRef;
}

/**
 * Runs the lifecycle-event producer over a written event document.
 * @param {DocumentReference} eventRef - Lifecycle event reference
 * @return {Promise<void>}
 */
async function runProducerFor(
  eventRef: admin.firestore.DocumentReference
): Promise<void> {
  const after = await eventRef.get();
  await onLifecycleEventEmailAutomation.run({
    data: {after},
    params: {eventId: RATING_PROMPT_EVENT_ID, uid},
  } as never);
}

/**
 * Writes the job the deleted waitlist producer used to queue.
 *
 * Deliberately not built through createQueuedEmailJob: the point is a document
 * this build can no longer produce but can still read.
 * @return {Promise<void>}
 */
async function seedRetiredWaitlistJob(): Promise<void> {
  const now = admin.firestore.Timestamp.now();

  await db.collection(EMAIL_JOBS).doc(RETIRED_JOB_ID).set({
    attemptCount: 0,
    createdAt: now,
    dedupeKey: "waitlist-welcome:abc123",
    lastErrorCode: null,
    lastErrorMessage: null,
    payload: {source: "landing_page"},
    processingStartedAt: null,
    provider: null,
    providerMessageId: null,
    readyAt: now,
    recipientEmail: "early-signup@example.com",
    recipientHash: "abc123",
    recipientUid: null,
    scheduledFor: now,
    sentAt: null,
    sourceRef: "waitlist/abc123",
    status: "queued",
    type: "waitlist_welcome",
    updatedAt: now,
  });
}

/**
 * Clears every job between tests so batches never leak across them.
 * @return {Promise<void>}
 */
async function clearEmailJobs(): Promise<void> {
  const snapshot = await db.collection(EMAIL_JOBS).get();
  await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
}
