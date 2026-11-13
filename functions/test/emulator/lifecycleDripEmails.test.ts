/**
 * The three lifecycle drip sweeps and the real worker against a real
 * Firestore: who is due, one email per account per type for life, the consent
 * rule, suppression again at send time, the kill switches, and the type
 * allowlist. Only the Resend HTTP call is stubbed.
 *
 * Lives under test/emulator/; `npm run test:emulator` runs it.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  buildDripDedupeKey,
  readDripSettings,
  runDripSweeps,
} from "../../src/lifecycleDripEmails.js";
import type {DripSettings} from "../../src/lifecycleDripEmails.js";
import type {DripEmailType} from "../../src/email/dripCopy.js";
import {processEmailJobs} from "../../src/email/processor.js";
import {buildEmailJobId} from "../../src/email/queue.js";
import type {EmailJobDocument} from "../../src/email/types.js";

const HOUR = 60 * 60 * 1000;
const EMAIL_JOBS = "email_jobs";

interface StubbedSend {
  subject: string;
  text: string;
  to: string[];
}

let db: admin.firestore.Firestore;
let sends: StubbedSend[] = [];
let now = new Date();

const allOn: DripSettings = readDripSettings({parameters: {
  free_week_after_decline_enabled: {defaultValue: {value: "true"}},
  lifecycle_email_free_week_unused_enabled: {defaultValue: {value: "true"}},
  lifecycle_email_paywall_abandoned_enabled: {defaultValue: {value: "true"}},
  lifecycle_email_trial_reminder_enabled: {defaultValue: {value: "true"}},
}});

function configure(enabledEmailTypes: unknown): void {
  process.env.TRANSACTIONAL_EMAIL_CONFIG = JSON.stringify({
    provider: "resend",
    apiKey: "re_emulator_only",
    enabledEmailTypes,
    fromEmail: "hello@updates.ascendstepper.com",
    fromName: "Ascend",
    replyTo: "support@ascendstepper.com",
    unsubscribeSigningKey: "emulator-unsubscribe-signing-key-0123456789",
    websiteUrl: "https://ascendstepper.com",
  });
}

before(() => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );
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
  now = new Date();
  configure("all");
  await db.recursiveDelete(db.collection(EMAIL_JOBS));
  await db.recursiveDelete(db.collection("users"));
});

const ts = (ms: number) => admin.firestore.Timestamp.fromMillis(ms);
const ago = (ms: number) => ts(now.getTime() - ms);
const ahead = (ms: number) => ts(now.getTime() + ms);

async function seedClimber(
  uid: string,
  options: {consent?: boolean; email?: string | null; firstName?: string} = {}
): Promise<void> {
  const profile: Record<string, unknown> = {};
  if (options.email !== null) {
    profile.email = options.email ?? `${uid}@example.com`;
  }
  if (options.firstName) {
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
}

async function seedPaywallShown(uid: string, sinceMs: number): Promise<void> {
  await db.doc(`users/${uid}/lifecycle_events/paywall_shown_app_access_gate_v1`)
    .set({
      createdAt: ago(sinceMs),
      eventDocId: "paywall_shown_app_access_gate_v1",
    });
}

async function seedFreeWeek(uid: string, sinceMs: number): Promise<void> {
  await db.doc(`users/${uid}/trial/free_week`).set({
    expiresAt: ahead(7 * 24 * HOUR - sinceMs),
    grantedAt: ago(sinceMs),
    schemaVersion: 1,
  });
  await db.doc(`users/${uid}/entitlements/app_access`).set({
    accessUntil: ahead(7 * 24 * HOUR - sinceMs),
    productId: "ascend_free_week",
    source: "trial",
    sourceEventType: "FREE_WEEK_GRANT",
  });
}

async function seedTrial(
  uid: string,
  endsInMs: number,
  sourceEventType = "INITIAL_PURCHASE",
  productId = "ascend_yearly_welcome"
): Promise<void> {
  await db.doc(`users/${uid}/entitlements/app_access`).set({
    accessUntil: ahead(endsInMs),
    expiresAt: ahead(endsInMs),
    productId,
    sourceEventType,
  });
}

async function readJob(
  type: DripEmailType,
  uid: string
): Promise<EmailJobDocument | null> {
  const snapshot = await db.collection(EMAIL_JOBS)
    .doc(buildEmailJobId(buildDripDedupeKey(type, uid))).get();
  return snapshot.exists ? snapshot.data() as EmailJobDocument : null;
}

// -- First paywall -----------------------------------------------------------

test("a climber who left on the first paywall gets one email, however often it runs", async () => {
  await seedClimber("sam", {firstName: "Sam"});
  await seedPaywallShown("sam", 2.5 * HOUR);

  const first = await runDripSweeps(now, allOn);
  const second = await runDripSweeps(now, allOn);

  assert.equal(first.drip_paywall_abandoned.queued, 1);
  assert.equal(second.drip_paywall_abandoned.queued, 0);
  assert.equal(second.drip_paywall_abandoned.alreadyQueued, 1);
  assert.equal((await db.collection(EMAIL_JOBS).get()).size, 1);
  const job = await readJob("drip_paywall_abandoned", "sam");
  assert.equal(job?.status, "queued");
  assert.equal(job?.recipientUid, "sam");
  assert.deepEqual(job?.payload, {
    ctaUrl: "https://ascendstepper.com/go?src=email-paywall-abandoned",
    firstName: "Sam",
  });
});

test("the worker sends it once, with an unsubscribe link, and a rerun sends nothing more", async () => {
  await seedClimber("sam", {firstName: "Sam"});
  await seedPaywallShown("sam", 2.5 * HOUR);
  await runDripSweeps(now, allOn);

  await processEmailJobs.run({} as never);
  await runDripSweeps(now, allOn);
  await processEmailJobs.run({} as never);

  assert.equal(sends.length, 1);
  assert.equal(sends[0].subject, "You left before the climb started");
  assert.deepEqual(sends[0].to, ["sam@example.com"]);
  assert.match(sends[0].text, /Unsubscribe: https:\/\/ascendstepper\.com\/api\/unsubscribe/);
  assert.match(sends[0].text, /go\?src=email-paywall-abandoned/);
  assert.equal((await readJob("drip_paywall_abandoned", "sam"))?.status, "sent");
});

test("not yet due, too stale, or already past the first paywall queues nothing", async () => {
  await seedClimber("too-early");
  await seedPaywallShown("too-early", 1 * HOUR);
  await seedClimber("too-late");
  await seedPaywallShown("too-late", 12 * HOUR);
  await seedClimber("closed-it");
  await seedPaywallShown("closed-it", 2.5 * HOUR);
  await db.doc("users/closed-it/lifecycle_events/paywall_dismissed_app_access_gate_v1")
    .set({createdAt: ago(2 * HOUR)});
  await seedClimber("bought");
  await seedPaywallShown("bought", 2.5 * HOUR);
  await seedTrial("bought", 20 * HOUR);
  await seedClimber("has-week");
  await seedPaywallShown("has-week", 2.5 * HOUR);
  await seedFreeWeek("has-week", 2.4 * HOUR);

  const summary = await runDripSweeps(now, allOn);

  assert.equal(summary.drip_paywall_abandoned.queued, 0);
  assert.equal(summary.drip_paywall_abandoned.suppressed, 3);
  assert.equal(summary.drip_paywall_abandoned.errors, 0);
  assert.equal(
    (await db.collection(EMAIL_JOBS).where("type", "==", "drip_paywall_abandoned").get()).size,
    0
  );
});

test("no recorded yes, or no email address, queues nothing", async () => {
  await seedClimber("declined", {consent: false});
  await seedPaywallShown("declined", 2.5 * HOUR);
  await seedClimber("no-email", {email: null});
  await seedPaywallShown("no-email", 2.5 * HOUR);
  await seedClimber("undecided", {consent: false});
  await db.doc("users/undecided/communication_preferences/current")
    .set({pushClimbDropsEnabled: true, schemaVersion: 1});
  await seedPaywallShown("undecided", 2.5 * HOUR);

  const summary = await runDripSweeps(now, allOn);

  assert.equal(summary.drip_paywall_abandoned.queued, 0);
  assert.equal(summary.drip_paywall_abandoned.suppressedByConsent, 2);
  assert.equal(summary.drip_paywall_abandoned.skippedNoEmail, 1);
  assert.equal((await db.collection(EMAIL_JOBS).get()).size, 0);
});

test("a climber who bought after it was queued is skipped at send time", async () => {
  await seedClimber("sam");
  await seedPaywallShown("sam", 2.5 * HOUR);
  await runDripSweeps(now, allOn);
  await seedTrial("sam", 6 * 24 * HOUR, "INITIAL_PURCHASE", "ascend_yearly");

  await processEmailJobs.run({} as never);

  assert.equal((await readJob("drip_paywall_abandoned", "sam"))?.status, "skipped");
  assert.equal(sends.length, 0);
});

test("a climber who closed the paywall after it was queued is skipped at send time", async () => {
  await seedClimber("sam");
  await seedPaywallShown("sam", 2.5 * HOUR);
  await runDripSweeps(now, allOn);
  await db.doc("users/sam/lifecycle_events/paywall_dismissed_app_access_gate_v1")
    .set({createdAt: ts(now.getTime())});

  await processEmailJobs.run({} as never);

  assert.equal((await readJob("drip_paywall_abandoned", "sam"))?.status, "skipped");
  assert.equal(sends.length, 0);
});

test("a climber who unsubscribed after it was queued is skipped at send time", async () => {
  await seedClimber("sam");
  await seedPaywallShown("sam", 2.5 * HOUR);
  await runDripSweeps(now, allOn);
  await db.doc("users/sam/communication_preferences/current").set({
    lifecycleEmailsEnabled: false,
    lifecycleEmailsSource: "email_link",
    schemaVersion: 1,
  });

  await processEmailJobs.run({} as never);

  assert.equal((await readJob("drip_paywall_abandoned", "sam"))?.status, "skipped");
  assert.equal(sends.length, 0);
});

// -- Free week ---------------------------------------------------------------

test("a climber in the free week with no climb gets the email a day in", async () => {
  await seedClimber("sam", {firstName: "Sam"});
  await seedFreeWeek("sam", 25 * HOUR);
  await seedClimber("too-early");
  await seedFreeWeek("too-early", 10 * HOUR);

  const summary = await runDripSweeps(now, allOn);

  assert.equal(summary.drip_free_week_unused.queued, 1);
  assert.equal(await readJob("drip_free_week_unused", "too-early"), null);
  await processEmailJobs.run({} as never);
  assert.equal(sends.length, 1);
  assert.equal(sends[0].subject, "Your first climb is waiting");
  assert.match(sends[0].text, /go\?src=email-free-week-unused/);
});

test("a climber who already saved a climb or started a session gets no free week email", async () => {
  await seedClimber("saved");
  await seedFreeWeek("saved", 25 * HOUR);
  await db.doc("users/saved/workouts/w1").set({startedAt: ago(HOUR)});
  await seedClimber("started");
  await seedFreeWeek("started", 25 * HOUR);
  await db.doc("users/started/attempt_heartbeats/s1")
    .set({lastSeenAt: ago(HOUR), state: "open"});
  await seedClimber("bought");
  await seedFreeWeek("bought", 25 * HOUR);
  await seedTrial("bought", 20 * HOUR, "INITIAL_PURCHASE", "ascend_yearly");

  const summary = await runDripSweeps(now, allOn);

  assert.equal(summary.drip_free_week_unused.queued, 0);
  assert.equal(summary.drip_free_week_unused.suppressed, 3);
});

test("a climber who climbs after the free week email was queued is skipped at send time", async () => {
  await seedClimber("sam");
  await seedFreeWeek("sam", 25 * HOUR);
  await runDripSweeps(now, allOn);
  await db.doc("users/sam/workouts/w1").set({startedAt: ts(now.getTime())});

  await processEmailJobs.run({} as never);

  assert.equal((await readJob("drip_free_week_unused", "sam"))?.status, "skipped");
  assert.equal(sends.length, 0);
});

// -- Trial reminder ----------------------------------------------------------

test("a climber whose welcome trial ends within a day gets the reminder with the charge date", async () => {
  await seedClimber("sam", {firstName: "Sam"});
  await seedTrial("sam", 20 * HOUR);
  await db.doc("users/sam/notification_devices/d1")
    .set({lastSeenAt: ts(now.getTime()), timeZone: "Pacific/Auckland"});
  await seedClimber("far-off");
  await seedTrial("far-off", 3 * 24 * HOUR);
  await seedClimber("minutes-left");
  await seedTrial("minutes-left", 30 * 60 * 1000);
  await seedClimber("other-product");
  await seedTrial("other-product", 20 * HOUR, "INITIAL_PURCHASE", "ascend_yearly");

  const summary = await runDripSweeps(now, allOn);

  assert.equal(summary.drip_trial_reminder.queued, 1);
  const job = await readJob("drip_trial_reminder", "sam");
  const payload = job?.payload as {timeZone?: string; trialEndsAtMs?: number};
  assert.equal(payload.timeZone, "Pacific/Auckland");
  assert.ok(typeof payload.trialEndsAtMs === "number");

  await processEmailJobs.run({} as never);
  assert.equal(sends.length, 1);
  assert.equal(sends[0].subject, "A reminder about your Ascend trial");
  assert.match(sends[0].text, /This is a reminder/);
  assert.match(sends[0].text, /Cancel Subscription/);
  assert.match(sends[0].text, /go\?src=email-trial-reminder/);
});

test("a cancelled or converted trial gets no reminder, at sweep or at send time", async () => {
  await seedClimber("cancelled");
  await seedTrial("cancelled", 20 * HOUR, "CANCELLATION");
  await seedClimber("converted");
  await seedTrial("converted", 20 * HOUR, "RENEWAL");
  await seedClimber("later-cancels");
  await seedTrial("later-cancels", 20 * HOUR);

  const summary = await runDripSweeps(now, allOn);
  assert.equal(summary.drip_trial_reminder.queued, 1);
  assert.equal(summary.drip_trial_reminder.suppressed, 2);
  assert.equal(await readJob("drip_trial_reminder", "cancelled"), null);

  await seedTrial("later-cancels", 20 * HOUR, "CANCELLATION");
  await processEmailJobs.run({} as never);

  assert.equal(
    (await readJob("drip_trial_reminder", "later-cancels"))?.status,
    "skipped"
  );
  assert.equal(sends.length, 0);
});

test("a trial whose end moved after queueing is skipped at send time", async () => {
  await seedClimber("sam");
  await seedTrial("sam", 20 * HOUR);
  await runDripSweeps(now, allOn);
  await seedTrial("sam", 6 * 24 * HOUR);

  await processEmailJobs.run({} as never);

  assert.equal((await readJob("drip_trial_reminder", "sam"))?.status, "skipped");
  assert.equal(sends.length, 0);
});

// -- Kill switches and the type allowlist ------------------------------------

test("every sweep ships off: with the shipped settings nothing is queued", async () => {
  await seedClimber("a");
  await seedPaywallShown("a", 2.5 * HOUR);
  await seedClimber("b");
  await seedFreeWeek("b", 25 * HOUR);
  await seedClimber("c");
  await seedTrial("c", 20 * HOUR);

  const summary = await runDripSweeps(now, readDripSettings({}));

  for (const segment of Object.values(summary)) {
    assert.equal(segment.disabled, true);
    assert.equal(segment.queued, 0);
  }
  assert.equal((await db.collection(EMAIL_JOBS).get()).size, 0);
});

test("each switch opens only its own sweep, and two need the rollout", async () => {
  await seedClimber("a");
  await seedPaywallShown("a", 2.5 * HOUR);
  await seedClimber("b");
  await seedFreeWeek("b", 25 * HOUR);
  await seedClimber("c");
  await seedTrial("c", 20 * HOUR);

  const onlyTrial = await runDripSweeps(now, readDripSettings({parameters: {
    lifecycle_email_trial_reminder_enabled: {defaultValue: {value: "true"}},
  }}));
  assert.equal(onlyTrial.drip_trial_reminder.queued, 1);
  assert.equal(onlyTrial.drip_paywall_abandoned.disabled, true);
  assert.equal(onlyTrial.drip_free_week_unused.disabled, true);

  const noProgram = await runDripSweeps(now, readDripSettings({parameters: {
    lifecycle_email_paywall_abandoned_enabled: {defaultValue: {value: "true"}},
    lifecycle_email_free_week_unused_enabled: {defaultValue: {value: "true"}},
  }}));
  assert.equal(noProgram.drip_paywall_abandoned.disabled, true);
  assert.equal(noProgram.drip_free_week_unused.disabled, true);

  const onlyAbandoned = await runDripSweeps(now, readDripSettings({parameters: {
    free_week_after_decline_enabled: {defaultValue: {value: "true"}},
    lifecycle_email_paywall_abandoned_enabled: {defaultValue: {value: "true"}},
  }}));
  assert.equal(onlyAbandoned.drip_paywall_abandoned.queued, 1);
  assert.equal(onlyAbandoned.drip_free_week_unused.disabled, true);
});

test("a delay moved in Remote Config moves the window without a release", async () => {
  await seedClimber("sam");
  await seedPaywallShown("sam", 30 * 60 * 1000);
  const settings = (hours: string) => readDripSettings({parameters: {
    free_week_after_decline_enabled: {defaultValue: {value: "true"}},
    lifecycle_email_paywall_abandoned_delay_hours: {
      defaultValue: {value: hours},
    },
    lifecycle_email_paywall_abandoned_enabled: {defaultValue: {value: "true"}},
  }});

  assert.equal((await runDripSweeps(now, settings("2"))).drip_paywall_abandoned.queued, 0);
  assert.equal((await runDripSweeps(now, settings("0.25"))).drip_paywall_abandoned.queued, 1);
});

test("an environment that does not list a drip type queues it but never delivers it", async () => {
  configure(["drop_announcement"]);
  await seedClimber("sam");
  await seedPaywallShown("sam", 2.5 * HOUR);
  await runDripSweeps(now, allOn);

  await processEmailJobs.run({} as never);

  assert.equal((await readJob("drip_paywall_abandoned", "sam"))?.status, "skipped");
  assert.equal(sends.length, 0);
});
