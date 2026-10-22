/**
 * The birthday sweep end to end against a real Firestore: who is due in their
 * own zone, queuing one greeting per climber per year however often the hourly
 * sweep runs, consent and missing data, the February 29 rule, and the real
 * worker delivering it. Only the Resend HTTP call is stubbed.
 *
 * Lives under test/emulator/; `npm run test:emulator` runs it.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {runBirthdaySweep} from "../../src/birthdayEmails.js";
import {buildBirthdayDedupeKey} from "../../src/email/birthday.js";
import {processEmailJobs} from "../../src/email/processor.js";
import {buildEmailJobId} from "../../src/email/queue.js";
import type {EmailJobDocument} from "../../src/email/types.js";

const EMAIL_JOBS = "email_jobs";
// 10:00 on 2026-10-22 in Chicago (CDT), the default zone.
const NOW = new Date("2026-10-22T15:00:00Z");

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
    enabledEmailTypes: "all",
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

interface SeedOptions {
  birthDate?: string;
  consent?: boolean;
  email?: string | null;
  firstName?: string;
  timeZone?: string;
}

/**
 * Seeds one climber.
 * @param {string} uid - Climber uid
 * @param {SeedOptions} options - What the profile and preferences hold
 */
async function seedClimber(
  uid: string,
  options: SeedOptions
): Promise<void> {
  const profile: Record<string, unknown> = {};
  if (options.email !== null) {
    profile.email = options.email ?? `${uid}@example.com`;
  }
  if (options.birthDate) {
    profile.birth_date = options.birthDate;
  }
  if (options.firstName !== undefined) {
    profile.firstName = options.firstName;
  }
  await db.collection("users").doc(uid).set(profile);
  if (options.consent !== false) {
    await db.doc(`users/${uid}/communication_preferences/current`).set({
      lifecycleEmailsEnabled: true,
      lifecycleEmailsSource: "onboarding",
      schemaVersion: 1,
    });
  }
  if (options.timeZone) {
    await db.doc(`users/${uid}/notification_devices/device-1`).set({
      lastSeenAt: admin.firestore.Timestamp.fromDate(NOW),
      timeZone: options.timeZone,
    });
  }
}

/**
 * Reads a stored birthday job.
 * @param {string} uid - Climber uid
 * @param {number} year - Local year of the birthday
 * @return {Promise<EmailJobDocument | null>} The job, or null when absent
 */
async function readJob(
  uid: string,
  year: number
): Promise<EmailJobDocument | null> {
  const snapshot = await db.collection(EMAIL_JOBS)
    .doc(buildEmailJobId(buildBirthdayDedupeKey(uid, year)))
    .get();
  return snapshot.exists ? snapshot.data() as EmailJobDocument : null;
}

test("a climber whose birthday it is gets one email, however often it runs",
  async () => {
    await seedClimber("tyler", {birthDate: "1992-10-22", firstName: "Tyler"});

    const first = await runBirthdaySweep(NOW);
    const second = await runBirthdaySweep(NOW);
    const afternoon = await runBirthdaySweep(
      new Date("2026-10-22T21:00:00Z")
    );

    assert.equal(first.queued, 1);
    assert.equal(second.queued, 0);
    assert.equal(second.alreadyQueued, 1);
    assert.equal(afternoon.queued, 0);
    assert.equal(afternoon.alreadyQueued, 1);
    assert.equal(first.errors, 0);

    const jobs = await db.collection(EMAIL_JOBS).get();
    assert.equal(jobs.size, 1);
    const job = await readJob("tyler", 2026);
    assert.equal(job?.type, "birthday");
    assert.equal(job?.status, "queued");
    assert.equal(job?.recipientUid, "tyler");
    assert.equal(job?.recipientEmail, "tyler@example.com");
    assert.deepEqual(job?.payload, {
      age: 34,
      ctaUrl: "https://apps.apple.com/app/id6757202987",
      firstName: "Tyler",
    });
  });

test("next year's birthday is a new email", async () => {
  await seedClimber("tyler", {birthDate: "1992-10-22", firstName: "Tyler"});

  await runBirthdaySweep(NOW);
  await runBirthdaySweep(new Date("2027-10-22T15:00:00Z"));

  assert.ok(await readJob("tyler", 2026));
  const next = await readJob("tyler", 2027);
  assert.ok(next);
  assert.equal((next.payload as {age: number}).age, 35);
});

test("the worker delivers the greeting with the personalised subject",
  async () => {
    await seedClimber("tyler", {birthDate: "1992-10-22", firstName: "Tyler"});
    await runBirthdaySweep(NOW);

    await processEmailJobs.run({} as never);

    assert.equal((await readJob("tyler", 2026))?.status, "sent");
    assert.equal(sends.length, 1);
    assert.equal(
      sends[0].subject,
      "Happy Birthday from Ascend, Tyler! \u{1F389}"
    );
    assert.deepEqual(sends[0].to, ["tyler@example.com"]);
    assert.match(sends[0].html, /HAPPY BIRTHDAY, TYLER!/);
    assert.match(sends[0].html, /\/api\/unsubscribe\?token=/);
    assert.match(
      sends[0].headers["List-Unsubscribe"],
      /^<https:\/\/ascendstepper\.com\/api\/unsubscribe\?token=/
    );
  });

test("a climber who unsubscribed after the sweep queued it gets nothing",
  async () => {
    await seedClimber("tyler", {birthDate: "1992-10-22", firstName: "Tyler"});
    await runBirthdaySweep(NOW);
    await db.doc("users/tyler/communication_preferences/current").set({
      lifecycleEmailsEnabled: false,
      lifecycleEmailsSource: "email_link",
      schemaVersion: 1,
    });

    await processEmailJobs.run({} as never);

    assert.equal((await readJob("tyler", 2026))?.status, "skipped");
    assert.equal(sends.length, 0);
  });

test("no consent, no birthday, no email, or the wrong day queues nothing",
  async () => {
    await seedClimber("declined", {birthDate: "1992-10-22", consent: false});
    await seedClimber("no-birthday", {});
    await seedClimber("no-email", {birthDate: "1992-10-22", email: null});
    await seedClimber("other-day", {birthDate: "1992-03-14"});
    await seedClimber("tomorrow", {birthDate: "1992-10-23"});
    await seedClimber("malformed", {birthDate: "1992-13-45"});
    await seedClimber("too-young", {birthDate: "2020-10-22"});

    const summary = await runBirthdaySweep(NOW);

    assert.equal(summary.queued, 0);
    assert.equal(summary.suppressed, 1);
    assert.equal(summary.skippedNoEmail, 1);
    assert.equal(summary.errors, 0);
    assert.equal((await db.collection(EMAIL_JOBS).get()).size, 0);
  });

test("a climber with no usable name is greeted without one", async () => {
  await seedClimber("placeholder", {
    birthDate: "1992-10-22",
    firstName: "CHANGE",
  });
  await seedClimber("blank", {birthDate: "1992-10-22", firstName: "  "});
  await seedClimber("no-name", {birthDate: "1992-10-22"});

  const summary = await runBirthdaySweep(NOW);
  assert.equal(summary.queued, 3);

  for (const uid of ["placeholder", "blank", "no-name"]) {
    const job = await readJob(uid, 2026);
    assert.deepEqual(job?.payload, {
      age: 34,
      ctaUrl: "https://apps.apple.com/app/id6757202987",
    }, uid);
  }

  await processEmailJobs.run({} as never);
  assert.equal(sends.length, 3);
  for (const send of sends) {
    assert.equal(send.subject, "Happy Birthday from Ascend! \u{1F389}");
  }
});

test("the climber's own device zone decides whether it is their birthday",
  async () => {
    // 2026-10-22 15:00Z is already the 23rd in Auckland and the 22nd, 05:00,
    // in Honolulu: neither is inside the 9 AM window on the 22nd.
    await seedClimber("auckland", {
      birthDate: "1992-10-22",
      timeZone: "Pacific/Auckland",
    });
    await seedClimber("honolulu", {
      birthDate: "1992-10-22",
      timeZone: "Pacific/Honolulu",
    });
    // Los Angeles is only at 08:00, while Chicago, the default, is at 10:00.
    await seedClimber("la", {
      birthDate: "1992-10-22",
      timeZone: "America/Los_Angeles",
    });
    await seedClimber("default-zone", {birthDate: "1992-10-22"});
    await seedClimber("bad-zone", {
      birthDate: "1992-10-22",
      timeZone: "Not/AZone",
    });

    await runBirthdaySweep(NOW);

    assert.equal(await readJob("auckland", 2026), null);
    assert.equal(await readJob("honolulu", 2026), null);
    assert.equal(await readJob("la", 2026), null);
    assert.ok(await readJob("default-zone", 2026));
    assert.ok(await readJob("bad-zone", 2026));

    // An hour later Los Angeles reaches 9 AM and is greeted once.
    await runBirthdaySweep(new Date("2026-10-22T16:00:00Z"));
    assert.ok(await readJob("la", 2026));
  });

test("a February 29 birthday is greeted on February 28 in a common year",
  async () => {
    await seedClimber("leapling", {birthDate: "1996-02-29", firstName: "Lee"});

    const eve = await runBirthdaySweep(new Date("2027-02-27T16:00:00Z"));
    const day = await runBirthdaySweep(new Date("2027-02-28T16:00:00Z"));
    const after = await runBirthdaySweep(new Date("2027-03-01T16:00:00Z"));

    assert.equal(eve.queued, 0);
    assert.equal(day.queued, 1);
    assert.equal(after.queued, 0);
    assert.equal(after.alreadyQueued, 0);
    const job = await readJob("leapling", 2027);
    assert.equal((job?.payload as {age: number}).age, 31);

    // In a leap year it is the 29th, and the 28th is an ordinary day.
    const leap28 = await runBirthdaySweep(new Date("2028-02-28T16:00:00Z"));
    const leap29 = await runBirthdaySweep(new Date("2028-02-29T16:00:00Z"));
    assert.equal(leap28.queued, 0);
    assert.equal(leap29.queued, 1);
    assert.equal(
      ((await readJob("leapling", 2028))?.payload as {age: number}).age,
      32
    );
  });

test("a sweep that hits its page bound says so and still queues what it read",
  async () => {
    await seedClimber("a", {birthDate: "1990-10-22"});
    await seedClimber("b", {birthDate: "1991-10-22"});
    await seedClimber("c", {birthDate: "1992-10-22"});

    const summary = await runBirthdaySweep(NOW, {maxPages: 1, pageSize: 2});

    assert.equal(summary.scanTruncated, true);
    assert.equal(summary.scanned, 2);
    assert.equal(summary.queued, 2);
  });
