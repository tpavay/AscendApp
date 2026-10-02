/**
 * The drop announcement end to end against a real Firestore: who the
 * audience is, queuing it once per climber however often the operator runs
 * it, the real scheduled worker delivering it with an unsubscribe link, the
 * test send keeping out of the real send's way, and the stale-backlog skip.
 * Only the Resend HTTP call is stubbed.
 *
 * Lives under test/emulator/; `npm run test:emulator` runs it.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  buildDropDedupeKey,
  buildDropTestDedupeKey,
  enqueueDropEmails,
  enqueueDropTestEmail,
  readDropAudience,
  readDropJobStatus,
  readStaleQueuedEmailJobs,
  skipStaleQueuedEmailJobs,
} from "../../src/dropEmails.js";
import {buildDropEmailPayload} from "../../src/email/drops.js";
import {processEmailJobs} from "../../src/email/processor.js";
import {buildEmailJobId, createQueuedEmailJob} from "../../src/email/queue.js";
import type {EmailJobDocument} from "../../src/email/types.js";

const EMAIL_JOBS = "email_jobs";
const DROP_ID = "halloween-2026";

interface StubbedSend {
  headers: Record<string, string>;
  html: string;
  subject: string;
  text: string;
  to: string[];
}

let db: admin.firestore.Firestore;
let sends: StubbedSend[] = [];

before(() => {
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
  globalThis.fetch = (async (url: string, init: RequestInit) => {
    assert.equal(url, "https://api.resend.com/emails");
    sends.push(JSON.parse(String(init.body)) as StubbedSend);
    return new Response(JSON.stringify({id: `resend-${sends.length}`}), {
      headers: {"Content-Type": "application/json"},
      status: 200,
    });
  }) as unknown as typeof fetch;

  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: "demo-ascend-leaderboard-derivation"});
  }
  db = admin.firestore();
});

beforeEach(async () => {
  sends = [];
  await db.recursiveDelete(db.collection(EMAIL_JOBS));
  await db.recursiveDelete(db.collection("users"));
});

/**
 * Seeds a climber with an optional email consent answer and address.
 * @param {string} uid - Climber uid
 * @param {boolean | undefined} consent - Stored answer, undefined for none
 * @param {string | null} email - Profile address
 */
async function seedClimber(
  uid: string,
  consent: boolean | undefined,
  email: string | null
): Promise<void> {
  await db.collection("users").doc(uid).set(email ? {email} : {});
  const preferences: Record<string, unknown> = {
    pushClimbDropsEnabled: true,
    schemaVersion: 1,
  };
  if (consent !== undefined) {
    preferences.lifecycleEmailsEnabled = consent;
    preferences.lifecycleEmailsSource = "onboarding";
  }
  await db.doc(`users/${uid}/communication_preferences/current`)
    .set(preferences);
}

/**
 * Reads a stored job by dedupe key.
 * @param {string} dedupeKey - Dedupe key
 * @return {Promise<EmailJobDocument>} Stored job
 */
async function readJob(dedupeKey: string): Promise<EmailJobDocument> {
  const snapshot = await db.collection(EMAIL_JOBS)
    .doc(buildEmailJobId(dedupeKey))
    .get();
  assert.ok(snapshot.exists, `expected job ${dedupeKey}`);
  return snapshot.data() as EmailJobDocument;
}

const payload = buildDropEmailPayload(DROP_ID, "https://ascendstepper.com");

test("only a recorded yes with an address is in the audience", async () => {
  await seedClimber("yes-with-email", true, "yes@example.com");
  await seedClimber("yes-no-email", true, null);
  await seedClimber("declined", false, "no@example.com");
  await seedClimber("never-asked", undefined, "silent@example.com");

  const audience = await readDropAudience(db);

  assert.deepEqual(audience.recipients, [
    {email: "yes@example.com", uid: "yes-with-email"},
  ]);
  assert.equal(audience.skippedNoEmail, 1);
  assert.equal(audience.notOptedIn, 2);
});

test("a rerun queues nobody twice, and the worker delivers one email",
  async () => {
    await seedClimber("climber-1", true, "climber@example.com");
    const {recipients} = await readDropAudience(db);

    const first = await enqueueDropEmails(db, payload, recipients);
    const second = await enqueueDropEmails(db, payload, recipients);
    assert.equal(first.queued, 1);
    assert.equal(second.queued, 0);
    assert.equal(second.alreadyQueued, 1);

    await processEmailJobs.run({} as never);

    const job = await readJob(buildDropDedupeKey(DROP_ID, "climber-1"));
    assert.equal(job.type, "drop_announcement");
    assert.equal(job.status, "sent");
    assert.equal(sends.length, 1);
    assert.equal(sends[0].subject, "Halloween is on");
    assert.deepEqual(sends[0].to, ["climber@example.com"]);
    assert.match(sends[0].html, /HALLOWEEN<br>IS ON\./);
    assert.match(sends[0].html, /\/api\/unsubscribe\?token=/);
    assert.match(sends[0].text, /Unsubscribe: https:\/\/ascendstepper\.com\/api\/unsubscribe\?token=/);
    assert.match(
      sends[0].headers["List-Unsubscribe"],
      /^<https:\/\/ascendstepper\.com\/api\/unsubscribe\?token=/
    );
    assert.deepEqual(await readDropJobStatus(db, DROP_ID), {sent: 1});
  });

test("a climber who opts out after queuing is skipped at send time",
  async () => {
    await seedClimber("climber-1", true, "climber@example.com");
    const {recipients} = await readDropAudience(db);
    await enqueueDropEmails(db, payload, recipients);
    await db.doc("users/climber-1/communication_preferences/current")
      .update({lifecycleEmailsEnabled: false});

    await processEmailJobs.run({} as never);

    const job = await readJob(buildDropDedupeKey(DROP_ID, "climber-1"));
    assert.equal(job.status, "skipped");
    assert.equal(sends.length, 0);
  });

test("a test send leaves the climber's real send untouched", async () => {
  await seedClimber("founder", true, "founder@example.com");
  const recipient = {email: "founder@example.com", uid: "founder"};

  assert.equal(
    await enqueueDropTestEmail(db, payload, recipient, "run1"),
    "queued"
  );
  const real = await enqueueDropEmails(db, payload, [recipient]);
  assert.equal(real.queued, 1);
  await readJob(buildDropTestDedupeKey(DROP_ID, "founder", "run1"));
  // Test jobs are not the drop's jobs: status counts only the real send.
  assert.deepEqual(await readDropJobStatus(db, DROP_ID), {queued: 1});
});

test("a test send to a climber who never opted in queues nothing",
  async () => {
    await seedClimber("silent", undefined, "silent@example.com");
    assert.equal(
      await enqueueDropTestEmail(
        db,
        payload,
        {email: "silent@example.com", uid: "silent"},
        "run1"
      ),
      "preferences_disabled"
    );
    assert.equal((await db.collection(EMAIL_JOBS).get()).size, 0);
  });

test("the stale backlog is skipped, and newer mail is left alone",
  async () => {
    const old = admin.firestore.Timestamp.fromDate(
      new Date("2026-08-12T00:44:47Z")
    );
    const fresh = admin.firestore.Timestamp.fromDate(
      new Date("2026-10-02T13:00:00Z")
    );
    const oldJob = createQueuedEmailJob("monthly_recap_active",
      "a@example.com", "hash-a", "monthly-recap:2026-08:a", {}, old, null, "a");
    const freshJob = createQueuedEmailJob("rating_positive_followup",
      "b@example.com", "hash-b", "rating:b", {}, fresh, null, "b");
    await db.collection(EMAIL_JOBS).doc("old").set(oldJob);
    await db.collection(EMAIL_JOBS).doc("fresh").set(freshJob);

    const cutoff = new Date("2026-10-02T12:00:00Z");
    const stale = await readStaleQueuedEmailJobs(db, cutoff);
    assert.deepEqual(stale.map((job) => job.id), ["old"]);

    assert.deepEqual(
      await skipStaleQueuedEmailJobs(db, stale.map((job) => job.id)),
      {skipped: 1, unchanged: 0}
    );
    // A second pass finds the job already settled and leaves it be.
    assert.deepEqual(
      await skipStaleQueuedEmailJobs(db, ["old"]),
      {skipped: 0, unchanged: 1}
    );
    const oldAfter = (await db.collection(EMAIL_JOBS).doc("old").get()).data();
    const freshAfter =
      (await db.collection(EMAIL_JOBS).doc("fresh").get()).data();
    assert.equal(oldAfter?.status, "skipped");
    assert.equal(oldAfter?.attemptCount, 0);
    assert.equal(freshAfter?.status, "queued");
  });
