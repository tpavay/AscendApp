import test from "node:test";
import assert from "node:assert/strict";
import {
  buildDripDedupeKey,
  DRIP_DEFAULT_HOURS,
  dripLink,
  readDripSettings,
} from "../src/lifecycleDripEmails";
import {renderEmailContentForJob} from "../src/email/catalog";
import {
  DRIP_EMAIL_COPY,
  TRIAL_PRICE_LABEL,
} from "../src/email/dripCopy";
import type {DripEmailType} from "../src/email/dripCopy";
import {
  dripSuppressionReasonFor,
  dripSuppressionReasonForJob,
  FIRST_PAYWALL_DISMISSED_EVENT,
  FIRST_PAYWALL_SHOWN_EVENT,
  TRIAL_MAX_GRANT_AGE_MS,
} from "../src/email/dripEligibility";
import type {
  DripFactReader,
  DripGrantFacts,
} from "../src/email/dripEligibility";
import {formatChargeDate} from "../src/email/dripTemplate";
import {EMAIL_TYPES} from "../src/email/types";
import type {EmailJobDocument} from "../src/email/types";

const HOUR = 60 * 60 * 1000;
const NOW = new Date("2026-11-20T15:00:00Z");
const UNSUBSCRIBE = "https://ascendstepper.com/api/unsubscribe?token=abc";

const DRIP_TYPES: DripEmailType[] = [
  "drip_paywall_abandoned",
  "drip_free_week_unused",
  "drip_trial_reminder",
];

interface World {
  climbed?: boolean;
  dismissed?: boolean;
  freeWeek?: {expiresAtMs: number | null} | null;
  grant?: Partial<DripGrantFacts> | null;
  shown?: boolean;
}

/**
 * A fact reader over a hand-built world.
 * @param {World} world - What the climber's documents say
 * @return {DripFactReader} Reader
 */
function readerFor(world: World): DripFactReader {
  return {
    grant: async () => world.grant ? {
      createdAtMs: NOW.getTime() - 2 * HOUR,
      expiresAtMs: NOW.getTime() + 20 * HOUR,
      productId: "ascend_yearly_welcome",
      source: null,
      sourceEventType: "INITIAL_PURCHASE",
      ...world.grant,
    } : null,
    freeWeek: async () => world.freeWeek ?? null,
    hasClimbActivity: async () => world.climbed === true,
    hasLifecycleEvent: async (_uid, eventDocId) =>
      eventDocId === FIRST_PAYWALL_SHOWN_EVENT ?
        world.shown !== false :
        eventDocId === FIRST_PAYWALL_DISMISSED_EVENT ?
          world.dismissed === true : false,
  };
}

const reason = (type: DripEmailType, world: World, trialEnd?: number) =>
  dripSuppressionReasonFor(type, "u1", readerFor(world), {
    now: NOW,
    ...(trialEnd === undefined ? {} : {expectedTrialEndsAtMs: trialEnd}),
  });

const week = {expiresAtMs: NOW.getTime() + 6 * 24 * HOUR};
const freeWeekGrant = {
  productId: "ascend_free_week",
  source: "trial",
  sourceEventType: "FREE_WEEK_GRANT",
};

// -- Kill switches and delays ------------------------------------------------

test("every sweep is off unless its switch is explicitly true", () => {
  for (const template of [null, undefined, {}, {parameters: {}}]) {
    const settings = readDripSettings(template);
    assert.equal(settings.paywallAbandoned.enabled, false);
    assert.equal(settings.freeWeekUnused.enabled, false);
    assert.equal(settings.trialReminder.enabled, false);
    assert.equal(settings.freeWeekProgramLive, false);
  }
  const off = readDripSettings({parameters: {
    lifecycle_email_paywall_abandoned_enabled: {defaultValue: {value: "false"}},
    lifecycle_email_free_week_unused_enabled: {defaultValue: {value: "yes"}},
    lifecycle_email_trial_reminder_enabled: {defaultValue: {}},
  }});
  assert.equal(off.paywallAbandoned.enabled, false);
  assert.equal(off.freeWeekUnused.enabled, false);
  assert.equal(off.trialReminder.enabled, false);
});

test("each switch turns on only its own sweep", () => {
  const settings = readDripSettings({parameters: {
    lifecycle_email_trial_reminder_enabled: {defaultValue: {value: "true"}},
    free_week_after_decline_enabled: {defaultValue: {value: "TRUE"}},
  }});
  assert.equal(settings.trialReminder.enabled, true);
  assert.equal(settings.freeWeekProgramLive, true);
  assert.equal(settings.paywallAbandoned.enabled, false);
  assert.equal(settings.freeWeekUnused.enabled, false);
});

test("delays default to 2, 24 and 24 hours and are Remote Config numbers", () => {
  const defaults = readDripSettings({});
  assert.equal(defaults.paywallAbandoned.offsetMs, 2 * HOUR);
  assert.equal(defaults.freeWeekUnused.offsetMs, 24 * HOUR);
  assert.equal(defaults.trialReminder.offsetMs, 24 * HOUR);
  assert.deepEqual(DRIP_DEFAULT_HOURS, {
    freeWeekUnused: 24,
    paywallAbandoned: 2,
    trialReminder: 24,
  });

  const moved = readDripSettings({parameters: {
    lifecycle_email_paywall_abandoned_delay_hours: {defaultValue: {value: "1"}},
    lifecycle_email_free_week_unused_delay_hours: {defaultValue: {value: "36"}},
    lifecycle_email_trial_reminder_lead_hours: {defaultValue: {value: "48.5"}},
  }});
  assert.equal(moved.paywallAbandoned.offsetMs, HOUR);
  assert.equal(moved.freeWeekUnused.offsetMs, 36 * HOUR);
  assert.equal(moved.trialReminder.offsetMs, 48.5 * HOUR);
});

test("a delay that is a typo falls back to the default", () => {
  for (const bad of ["", "abc", "-3", "0", "99999", "NaN"]) {
    const settings = readDripSettings({parameters: {
      lifecycle_email_paywall_abandoned_delay_hours: {
        defaultValue: {value: bad},
      },
    }});
    assert.equal(settings.paywallAbandoned.offsetMs, 2 * HOUR, bad);
  }
});

// -- Dedupe and links --------------------------------------------------------

test("one key per account per type, for life", () => {
  assert.equal(
    buildDripDedupeKey("drip_paywall_abandoned", "u1"),
    "drip-email:drip_paywall_abandoned:u1"
  );
  const keys = new Set(DRIP_TYPES.map((type) => buildDripDedupeKey(type, "u1")));
  assert.equal(keys.size, 3);
  assert.notEqual(
    buildDripDedupeKey("drip_paywall_abandoned", "u1"),
    buildDripDedupeKey("drip_paywall_abandoned", "u2")
  );
  // No date, week or build in the key: it never rolls over.
  assert.doesNotMatch(buildDripDedupeKey("drip_trial_reminder", "u1"), /\d{4}/);
});

test("every link is the /go page with its own source tag and no app scheme", () => {
  assert.equal(
    dripLink("drip_paywall_abandoned"),
    "https://ascendstepper.com/go?src=email-paywall-abandoned"
  );
  assert.equal(
    dripLink("drip_free_week_unused"),
    "https://ascendstepper.com/go?src=email-free-week-unused"
  );
  assert.equal(
    dripLink("drip_trial_reminder"),
    "https://ascendstepper.com/go?src=email-trial-reminder"
  );
});

// -- Send-time and enqueue-time eligibility ---------------------------------

test("first paywall email: only for a climber who never went past the first paywall", async () => {
  assert.equal(await reason("drip_paywall_abandoned", {}), null);
  assert.equal(
    await reason("drip_paywall_abandoned", {grant: {}}), "has_access"
  );
  assert.equal(
    await reason("drip_paywall_abandoned", {grant: freeWeekGrant}),
    "has_access"
  );
  assert.equal(
    await reason("drip_paywall_abandoned", {freeWeek: week}),
    "free_week_started"
  );
  assert.equal(
    await reason("drip_paywall_abandoned", {dismissed: true}),
    "closed_first_paywall"
  );
  assert.equal(
    await reason("drip_paywall_abandoned", {shown: false}),
    "first_paywall_not_recorded"
  );
});

test("free week email: only for a week that is running with no climb", async () => {
  assert.equal(
    await reason("drip_free_week_unused", {freeWeek: week, grant: freeWeekGrant}),
    null
  );
  assert.equal(await reason("drip_free_week_unused", {}), "no_free_week");
  assert.equal(
    await reason("drip_free_week_unused", {
      freeWeek: {expiresAtMs: NOW.getTime() - 1},
    }),
    "free_week_over"
  );
  assert.equal(
    await reason("drip_free_week_unused", {freeWeek: week, grant: {}}),
    "has_paid_access"
  );
  assert.equal(
    await reason("drip_free_week_unused", {
      climbed: true, freeWeek: week, grant: freeWeekGrant,
    }),
    "already_climbed"
  );
});

test("trial reminder: only for an uncancelled first welcome trial", async () => {
  const end = NOW.getTime() + 20 * HOUR;
  assert.equal(await reason("drip_trial_reminder", {grant: {}}, end), null);
  assert.equal(await reason("drip_trial_reminder", {}), "no_trial");
  assert.equal(
    await reason("drip_trial_reminder", {grant: freeWeekGrant}),
    "not_welcome_trial"
  );
  assert.equal(
    await reason("drip_trial_reminder", {grant: {productId: "ascend_yearly"}}),
    "not_welcome_trial"
  );
  assert.equal(
    await reason("drip_trial_reminder", {grant: {sourceEventType: "CANCELLATION"}}),
    "trial_cancelled"
  );
  for (const converted of ["RENEWAL", "BILLING_ISSUE", "PRODUCT_CHANGE", "WHATEVER"]) {
    assert.equal(
      await reason("drip_trial_reminder", {grant: {sourceEventType: converted}}),
      "trial_converted_or_changed",
      converted
    );
  }
  for (const pending of ["UNCANCELLATION", "CLIENT_RECONCILIATION"]) {
    assert.equal(
      await reason("drip_trial_reminder", {grant: {sourceEventType: pending}}),
      null,
      pending
    );
  }
  assert.equal(
    await reason("drip_trial_reminder", {grant: {expiresAtMs: NOW.getTime() - 1}}),
    "trial_ended"
  );
  assert.equal(
    await reason("drip_trial_reminder", {grant: {
      createdAtMs: NOW.getTime() + 20 * HOUR - TRIAL_MAX_GRANT_AGE_MS - 1,
    }}),
    "not_first_trial"
  );
  assert.equal(
    await reason("drip_trial_reminder", {grant: {}}, end + HOUR),
    "trial_moved"
  );
});

test("the processor's check reads the job's own type, uid and queued trial end", async () => {
  const job = (type: string, payload: object, uid: string | null = "u1") =>
    ({payload, recipientUid: uid, type}) as unknown as EmailJobDocument;
  const reader = readerFor({grant: {}});

  assert.equal(
    await dripSuppressionReasonForJob(
      job("birthday", {}), NOW, reader
    ),
    null
  );
  assert.equal(
    await dripSuppressionReasonForJob(
      job("drip_paywall_abandoned", {}), NOW, reader
    ),
    "has_access"
  );
  assert.equal(
    await dripSuppressionReasonForJob(
      job("drip_trial_reminder", {trialEndsAtMs: NOW.getTime() + 20 * HOUR}),
      NOW,
      reader
    ),
    null
  );
  assert.equal(
    await dripSuppressionReasonForJob(
      job("drip_trial_reminder", {trialEndsAtMs: NOW.getTime() + 2 * HOUR}),
      NOW,
      reader
    ),
    "trial_moved"
  );
  assert.notEqual(
    await dripSuppressionReasonForJob(
      job("drip_trial_reminder", {}, null), NOW, reader
    ),
    null
  );
});

test("a failed fact read throws instead of letting mail through", async () => {
  const broken: DripFactReader = {
    ...readerFor({}),
    grant: async () => {
      throw new Error("unavailable");
    },
  };
  await assert.rejects(
    dripSuppressionReasonFor("drip_paywall_abandoned", "u1", broken, {now: NOW}),
    /unavailable/
  );
});

// -- Types, copy and rendering ----------------------------------------------

test("the three drip types are registered and rendered by the catalog", () => {
  for (const type of DRIP_TYPES) {
    assert.ok((EMAIL_TYPES as readonly string[]).includes(type), type);
    const rendered = renderEmailContentForJob(
      {
        payload: {
          ctaUrl: dripLink(type),
          firstName: "Sam",
          timeZone: "America/Los_Angeles",
          trialEndsAtMs: Date.parse("2026-11-22T03:00:00Z"),
        },
        type,
      } as unknown as EmailJobDocument,
      {unsubscribeUrl: UNSUBSCRIBE}
    );
    assert.equal(rendered.subject, DRIP_EMAIL_COPY[type].subject);
    assert.match(rendered.html, /Hi Sam,/);
    assert.ok(rendered.html.includes(dripLink(type).replace(/&/g, "&amp;")));
    assert.ok(rendered.html.includes(UNSUBSCRIBE));
    assert.match(rendered.html, /Privacy Policy/);
    assert.ok(rendered.text.includes(`Unsubscribe: ${UNSUBSCRIBE}`));
    assert.ok(rendered.text.includes(dripLink(type)));
    assert.ok(rendered.text.includes("Founder, Ascend"));
  }
});

test("the layout is one narrow plain column, not the recap shell", () => {
  const rendered = renderEmailContentForJob(
    {payload: {ctaUrl: dripLink("drip_paywall_abandoned")},
      type: "drip_paywall_abandoned"} as unknown as EmailJobDocument,
    {unsubscribeUrl: UNSUBSCRIBE}
  );
  assert.match(rendered.html, /max-width:480px/);
  assert.doesNotMatch(rendered.html, /<img/i);
  assert.doesNotMatch(rendered.html, /border-radius/);
  assert.match(rendered.html, />Hi,</);
});

test("the draft copy keeps the founder's voice: no exclamation marks, no em dashes", () => {
  for (const type of DRIP_TYPES) {
    const copy = DRIP_EMAIL_COPY[type];
    const everything = [
      copy.subject, copy.preheader, copy.linkLabel, copy.whyReceived,
      ...copy.paragraphs,
    ].join("\n");
    assert.doesNotMatch(everything, /!/, type);
    assert.doesNotMatch(everything, /—/, type);
  }
});

test("the trial reminder says it is a reminder, how to cancel and when the charge is", () => {
  const rendered = renderEmailContentForJob(
    {
      payload: {
        ctaUrl: dripLink("drip_trial_reminder"),
        timeZone: "America/Los_Angeles",
        // 03:00Z on the 22nd is still the 21st on the US west coast.
        trialEndsAtMs: Date.parse("2026-11-22T03:00:00Z"),
      },
      type: "drip_trial_reminder",
    } as unknown as EmailJobDocument,
    {unsubscribeUrl: UNSUBSCRIBE}
  );
  assert.match(rendered.text, /This is a reminder/);
  assert.match(rendered.text, /Settings app/);
  assert.match(rendered.text, /Cancel Subscription/);
  assert.match(rendered.text, /Saturday, November 21/);
  assert.ok(rendered.text.includes(TRIAL_PRICE_LABEL));
  assert.doesNotMatch(rendered.text, /\{(chargeDate|price)\}/);
  assert.equal(formatChargeDate(Date.parse("2026-11-22T03:00:00Z"), undefined),
    "Saturday, November 21");
});

test("a trial reminder with no trial end is refused rather than printing a blank", () => {
  assert.throws(() => renderEmailContentForJob(
    {payload: {ctaUrl: dripLink("drip_trial_reminder")},
      type: "drip_trial_reminder"} as unknown as EmailJobDocument
  ), /trialEndsAtMs/);
});
