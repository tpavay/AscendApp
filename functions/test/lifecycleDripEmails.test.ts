import test from "node:test";
import assert from "node:assert/strict";
import {join} from "node:path";
import {pathToFileURL} from "node:url";
import {
  buildDripDedupeKey,
  DRIP_DEFAULT_HOURS,
  dripLink,
  readDripSettings,
} from "../src/lifecycleDripEmails";
import {renderEmailContentForJob} from "../src/email/catalog";
import {DRIP_EMAIL_COPY} from "../src/email/dripCopy";
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
import {
  formatChargeDate,
  formatTrialEndsIn,
  renderDripEmail,
} from "../src/email/dripTemplate";
import {processRevenueCatWebhookEvent} from "../src/revenueCat/processor";
import {reconcileAppAccessForUser} from "../src/revenueCat/reconciliation";
import type {
  AppAccessProjection,
  RevenueCatServerConfig,
  RevenueCatSubscriberResponse,
  RevenueCatWebhookEvent,
} from "../src/revenueCat/types";
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
      renewal: {periodType: "trial", willRenew: true},
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
  renewal: null,
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

test("trial reminder: only for an uncancelled welcome trial", async () => {
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
    await reason("drip_trial_reminder", {grant: {
      renewal: {periodType: "trial", willRenew: false},
    }}),
    "trial_cancelled"
  );
  for (const renewal of [
    {periodType: "normal", willRenew: true},
    {periodType: "intro", willRenew: true},
    {periodType: null, willRenew: true},
    {periodType: "trial", willRenew: null},
  ]) {
    assert.equal(
      await reason("drip_trial_reminder", {grant: {renewal}}),
      "trial_converted_or_changed",
      JSON.stringify(renewal)
    );
  }
  // The recorded renewal state decides, whatever event last wrote the grant.
  for (const sourceEventType of ["CLIENT_RECONCILIATION", "CANCELLATION", "RENEWAL"]) {
    assert.equal(
      await reason("drip_trial_reminder", {grant: {sourceEventType}}),
      null,
      sourceEventType
    );
  }
  assert.equal(
    await reason("drip_trial_reminder", {grant: {expiresAtMs: NOW.getTime() - 1}}),
    "trial_ended"
  );
  assert.equal(
    await reason("drip_trial_reminder", {grant: {}}, end + HOUR),
    "trial_moved"
  );
});

test("trial reminder: a grant from before renewal was recorded falls back to its last event", async () => {
  const legacy = (grant: Partial<DripGrantFacts>) =>
    reason("drip_trial_reminder", {grant: {renewal: null, ...grant}});
  assert.equal(await legacy({}), null);
  assert.equal(await legacy({sourceEventType: "CANCELLATION"}), "trial_cancelled");
  for (const converted of ["RENEWAL", "BILLING_ISSUE", "PRODUCT_CHANGE", "WHATEVER"]) {
    assert.equal(
      await legacy({sourceEventType: converted}),
      "trial_converted_or_changed",
      converted
    );
  }
  for (const pending of ["UNCANCELLATION", "CLIENT_RECONCILIATION"]) {
    assert.equal(await legacy({sourceEventType: pending}), null, pending);
  }
  assert.equal(
    await legacy({
      createdAtMs: NOW.getTime() + 20 * HOUR - TRIAL_MAX_GRANT_AGE_MS - 1,
    }),
    "not_first_trial"
  );
});

// -- A cancelled trial stays cancelled through reconciliation ----------------

const RC_CONFIG: RevenueCatServerConfig = {
  allowedProductIds: ["ascend_yearly_welcome"],
  apiKey: "test-api-key-123456789012345678901234",
  appId: "app123",
  entitlementId: "app_access",
  webhookAuthorization: "Bearer test-authorization-secret-1234567890",
  webhookSigningSecret: "test-signing-secret-12345678901234567890",
};
const TRIAL_ENDS = new Date(NOW.getTime() + 20 * HOUR);

function welcomeSubscriber(
  requestDateMs: number,
  unsubscribeDetectedAt: string | null
): RevenueCatSubscriberResponse {
  return {
    requestDateMs,
    subscriber: {
      entitlements: {app_access: {
        expiresDate: TRIAL_ENDS.toISOString(),
        gracePeriodExpiresDate: null,
        productIdentifier: "ascend_yearly_welcome",
      }},
      subscriptions: {ascend_yearly_welcome: {
        billingIssuesDetectedAt: null,
        expiresDate: TRIAL_ENDS.toISOString(),
        gracePeriodExpiresDate: null,
        periodType: "trial",
        unsubscribeDetectedAt,
      }},
    },
  };
}

function welcomeEvent(id: string, type: string): RevenueCatWebhookEvent {
  return {
    appId: RC_CONFIG.appId,
    appUserIds: ["u1"],
    eventTimestampMs: NOW.getTime(),
    expirationAtMs: TRIAL_ENDS.getTime(),
    gracePeriodExpirationAtMs: null,
    id,
    identityOverflowCount: 0,
    isTrialConversion: false,
    lifecycleReason: null,
    newProductId: null,
    periodType: "trial",
    productId: "ascend_yearly_welcome",
    store: "app_store",
    type,
  };
}

/**
 * The webhook and the reconciliation writing one climber's grant, the way
 * `FirestoreRevenueCatEntitlementStore` stores it, read back as drip facts.
 */
class OneClimberGrantStore {
  stored: AppAccessProjection | null = null;
  private readonly claimed = new Set<string>();

  async claimEvent(event: RevenueCatWebhookEvent) {
    const outcome = this.claimed.has(event.id) ? "duplicate" : "claimed";
    this.claimed.add(event.id);
    return {claimDigest: event.id, outcome} as const;
  }
  async completeEvent(
    _event: RevenueCatWebhookEvent,
    _digest: string,
    projections: AppAccessProjection[]
  ) {
    for (const projection of projections) {
      await this.writeProjection(projection);
    }
  }
  async failEvent() {}
  async writeProjection(projection: AppAccessProjection) {
    this.stored = projection;
    return true;
  }
  reader(): DripFactReader {
    return {
      ...readerFor({}),
      grant: async () => this.stored?.isActive ? {
        createdAtMs: NOW.getTime() - 2 * HOUR,
        expiresAtMs: this.stored.accessUntil.getTime(),
        productId: this.stored.productId,
        renewal: {
          periodType: this.stored.periodType,
          willRenew: this.stored.willRenew,
        },
        source: null,
        sourceEventType: this.stored.sourceEventType,
      } : null,
    };
  }
}

test("a trial cancelled and then reconciled on launch still gets no reminder", async () => {
  const store = new OneClimberGrantStore();
  let subscriber = welcomeSubscriber(NOW.getTime() - 3 * HOUR, null);
  const dependencies = {
    analyticsEnvironment: null,
    config: RC_CONFIG,
    now: () => NOW,
    store,
    subscriberClient: {fetchSubscriber: async () => subscriber},
    userVerifier: {isFirebaseUser: async () => true},
  };

  await processRevenueCatWebhookEvent(
    welcomeEvent("purchase", "INITIAL_PURCHASE"), "purchase", dependencies
  );
  assert.equal(
    await dripSuppressionReasonFor("drip_trial_reminder", "u1", store.reader(), {
      now: NOW,
    }),
    null
  );

  subscriber = welcomeSubscriber(
    NOW.getTime() - 2 * HOUR, new Date(NOW.getTime() - 2 * HOUR).toISOString()
  );
  await processRevenueCatWebhookEvent(
    welcomeEvent("cancel", "CANCELLATION"), "cancel", dependencies
  );
  subscriber = {...subscriber, requestDateMs: NOW.getTime() - HOUR};
  const reconciled = await reconcileAppAccessForUser("u1", dependencies);

  assert.equal(reconciled.outcome, "active");
  assert.equal(store.stored?.isActive, true);
  assert.equal(store.stored?.sourceEventType, "CLIENT_RECONCILIATION");
  assert.equal(store.stored?.willRenew, false);
  assert.equal(
    await dripSuppressionReasonFor("drip_trial_reminder", "u1", store.reader(), {
      now: NOW,
    }),
    "trial_cancelled"
  );
  assert.equal(
    await dripSuppressionReasonForJob(
      {
        payload: {trialEndsAtMs: TRIAL_ENDS.getTime()},
        recipientUid: "u1",
        type: "drip_trial_reminder",
      } as unknown as EmailJobDocument,
      NOW,
      store.reader()
    ),
    "trial_cancelled"
  );
});

test("a cancellation the webhook never delivered is carried by reconciliation", async () => {
  const store = new OneClimberGrantStore();
  await reconcileAppAccessForUser("u1", {
    config: RC_CONFIG,
    now: () => NOW,
    store,
    subscriberClient: {fetchSubscriber: async () => welcomeSubscriber(
      NOW.getTime(), new Date(NOW.getTime() - HOUR).toISOString()
    )},
    userVerifier: {isFirebaseUser: async () => true},
  });

  assert.equal(store.stored?.isActive, true);
  assert.equal(store.stored?.periodType, "trial");
  assert.equal(
    await dripSuppressionReasonFor("drip_trial_reminder", "u1", store.reader(), {
      now: NOW,
    }),
    "trial_cancelled"
  );
});

test("readDripSettings acts on every server-only Remote Config parameter", async () => {
  // __dirname is the compiled lib/test directory; walk up to the repo root.
  const {SERVER_ONLY_PARAMETERS} = await import(pathToFileURL(
    join(__dirname, "../../../scripts/lib/remote-config-template.mjs")
  ).href) as {SERVER_ONLY_PARAMETERS: readonly string[]};
  const baseline = readDripSettings({});

  assert.ok(SERVER_ONLY_PARAMETERS.length > 0);
  for (const key of SERVER_ONLY_PARAMETERS) {
    const value = key.endsWith("_enabled") ? "true" : "5";
    assert.notDeepEqual(
      readDripSettings({parameters: {[key]: {defaultValue: {value}}}}),
      baseline,
      `${key} is server-only but readDripSettings ignores it`
    );
  }
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
    if (type === "drip_trial_reminder") {
      assert.match(rendered.subject, /^Reminder: your Ascend trial ends /);
    } else {
      assert.equal(rendered.subject, DRIP_EMAIL_COPY[type].subject);
    }
    assert.match(rendered.html, /Hi Sam,/);
    assert.ok(rendered.html.includes(dripLink(type).replace(/&/g, "&amp;")));
    assert.ok(rendered.html.includes(UNSUBSCRIBE));
    assert.match(rendered.html, /Privacy Policy/);
    assert.ok(rendered.text.includes(`Unsubscribe: ${UNSUBSCRIBE}`));
    assert.ok(rendered.text.includes(dripLink(type)));
    assert.ok(rendered.text.includes("Founder, Ascend"));
  }
});

const BLOCK_TEXT = (type: DripEmailType): string[] =>
  DRIP_EMAIL_COPY[type].blocks.flatMap(
    (block) => typeof block === "string" ? [block] : block.bullets
  );

test("the layout is a plain left-aligned newsletter note, not the recap shell", () => {
  const rendered = renderEmailContentForJob(
    {payload: {ctaUrl: dripLink("drip_paywall_abandoned")},
      type: "drip_paywall_abandoned"} as unknown as EmailJobDocument,
    {unsubscribeUrl: UNSUBSCRIBE}
  );
  assert.match(rendered.html, /font-family:Arial,Helvetica,sans-serif/);
  assert.match(rendered.html, /font-size:14px/);
  assert.match(rendered.html, /line-height:1\.5/);
  assert.match(rendered.html, /max-width:520px/);
  assert.match(rendered.html, /text-align:left/);
  assert.match(rendered.html, /margin:0 0 1\.2em/);
  assert.doesNotMatch(rendered.html, /Georgia|Times New Roman|text-align:center/);
  assert.doesNotMatch(rendered.html, /<img/i);
  assert.doesNotMatch(rendered.html, /<table/i);
  assert.doesNotMatch(rendered.html, /border-radius/);
  assert.doesNotMatch(rendered.html, /background:#[0-9a-f]{6};padding:\d+px 2/i);
  assert.match(rendered.html, />Hi,</);
});

test("one idea per paragraph: every copy block is its own element and its own text paragraph", () => {
  for (const type of DRIP_TYPES) {
    const rendered = renderDripEmail(
      type,
      {ctaUrl: dripLink(type), trialEndsAtMs: Date.parse("2026-11-22T03:00:00Z")},
      {unsubscribeUrl: UNSUBSCRIBE},
      new Date("2026-11-20T20:00:00Z")
    );
    const paragraphs = rendered.text.split("\n\n");
    for (const block of DRIP_EMAIL_COPY[type].blocks) {
      if (typeof block === "string") {
        const filled = block
          .replace("{chargeDate}", "Saturday, November 21")
          .replace("{trialEndsIn}", "tomorrow");
        assert.ok(paragraphs.includes(filled), `${type}: ${filled}`);
        assert.ok(rendered.html.includes(`>${filled.replace(/'/g, "&#39;")}</p>`) ||
          rendered.html.includes(`>${filled}</p>`), `${type}: html ${filled}`);
      }
    }
  }
});

test("a bulleted block renders as a list in the html and as dashes in the text", () => {
  const rendered = renderDripEmail(
    "drip_free_week_unused",
    {ctaUrl: dripLink("drip_free_week_unused")},
    {unsubscribeUrl: UNSUBSCRIBE}
  );
  assert.match(rendered.html, /<ul style="margin:0 0 1\.2em;padding-left:22px;">/);
  assert.match(rendered.html, /<li>Walk up to any stair stepper\.<\/li>/);
  assert.match(rendered.text,
    /- Walk up to any stair stepper\.\n- Put your headphones in\.\n- Pick a tower\.\n\n/);
});

test("the draft copy keeps the founder's voice: no exclamation marks, no em dashes", () => {
  for (const type of DRIP_TYPES) {
    const copy = DRIP_EMAIL_COPY[type];
    const everything = [
      copy.subject, copy.preheader, copy.linkLabel, copy.whyReceived,
      ...BLOCK_TEXT(type),
    ].join("\n");
    assert.doesNotMatch(everything, /!/, type);
    assert.doesNotMatch(everything, /—/, type);
  }
});

test("no drip subject or line guesses what the reader did or how long ago it was", () => {
  assert.equal(DRIP_EMAIL_COPY.drip_paywall_abandoned.subject,
    "A quick note from the founder of Ascend");
  for (const type of DRIP_TYPES) {
    const everything = [DRIP_EMAIL_COPY[type].subject, ...BLOCK_TEXT(type)]
      .join("\n");
    assert.doesNotMatch(everything, /left before|couple of hours|a day since/i,
      type);
  }
});

const REMINDER_TRIAL_END = Date.parse("2026-11-22T03:00:00Z");

const renderReminder = (now: Date, timeZone = "America/Los_Angeles") =>
  renderDripEmail(
    "drip_trial_reminder",
    {
      ctaUrl: dripLink("drip_trial_reminder"),
      firstName: "Sam",
      timeZone,
      // 03:00Z on the 22nd is still the 21st on the US west coast.
      trialEndsAtMs: REMINDER_TRIAL_END,
    },
    {unsubscribeUrl: UNSUBSCRIBE},
    now
  );

test("the trial reminder is the short note the captain asked for, with no price, renewal or cancel steps", () => {
  const rendered = renderReminder(new Date("2026-11-20T20:00:00Z"));
  assert.equal(rendered.subject, "Reminder: your Ascend trial ends tomorrow");
  const body = rendered.text.split("\n\n");
  assert.deepEqual(body.slice(0, 4), [
    "Hi Sam,",
    "I hate forgetting about subscriptions, and I don't want you to pay for " +
      "something you don't want.",
    "Your 7-day free trial ends on Saturday, November 21.",
    "I hope to see you on the leaderboards.",
  ]);
  assert.doesNotMatch(rendered.text, /\{(chargeDate|trialEndsIn|price)\}/);
  assert.doesNotMatch(rendered.text, /\$|renew|cancel|Settings app|reminder, nothing more|need to do anything/i);
  assert.doesNotMatch(rendered.html, /\$|renew|cancel|Settings app/i);
  assert.equal(formatChargeDate(REMINDER_TRIAL_END, undefined),
    "Saturday, November 21");
});

test("the trial reminder subject counts calendar days in the climber's zone and is never a wrong number", () => {
  const subject = (now: string, timeZone?: string) =>
    renderReminder(new Date(now), timeZone).subject;
  // The end is Saturday Nov 21, 7:00 p.m. in Los Angeles.
  assert.equal(subject("2026-11-20T20:00:00Z"),
    "Reminder: your Ascend trial ends tomorrow");
  assert.equal(subject("2026-11-19T20:00:00Z"),
    "Reminder: your Ascend trial ends in 2 days");
  assert.equal(subject("2026-11-18T20:00:00Z"),
    "Reminder: your Ascend trial ends in 3 days");
  assert.equal(subject("2026-11-21T20:00:00Z"),
    "Reminder: your Ascend trial ends today");
  // A sweep that ran late still never says "tomorrow" for a trial that ended.
  assert.equal(subject("2026-11-23T20:00:00Z"),
    "Reminder: your Ascend trial ends today");
});

test("the trial reminder 'tomorrow' follows the climber's midnight, not UTC's", () => {
  const end = Date.parse("2026-11-22T03:00:00Z");
  const days = (now: string, zone: string | undefined) =>
    formatTrialEndsIn(end, zone, new Date(now));
  // 06:30Z on the 21st is 00:30 on Nov 21 in Chicago: the trial ends the same
  // calendar day (Nov 21, 9 p.m. Chicago), so it is today, not tomorrow.
  assert.equal(days("2026-11-21T06:30:00Z", "America/Chicago"), "today");
  // 05:30Z on the 21st is still 23:30 on Nov 20 in Chicago: tomorrow.
  assert.equal(days("2026-11-21T05:30:00Z", "America/Chicago"), "tomorrow");
  // UTC's calendar would call both of those instants the 21st.
  // No recorded zone falls back to America/Chicago.
  assert.equal(days("2026-11-21T05:30:00Z", undefined), "tomorrow");
  assert.equal(days("2026-11-21T06:30:00Z", undefined), "today");
  // A zone that is not a real one falls back the same way.
  assert.equal(days("2026-11-21T05:30:00Z", "Not/AZone"), "tomorrow");
  // Across a daylight-saving change the day count stays a whole number.
  assert.equal(
    formatTrialEndsIn(Date.parse("2026-11-03T15:00:00Z"), "America/Chicago",
      new Date("2026-10-31T15:00:00Z")),
    "in 3 days"
  );
});

test("the trial reminder preheader and subject both fill {trialEndsIn}", () => {
  const rendered = renderReminder(new Date("2026-11-20T20:00:00Z"));
  assert.match(rendered.html, />Your 7-day free trial ends tomorrow\.</);
});

test("a trial reminder with no trial end is refused rather than printing a blank", () => {
  assert.throws(() => renderEmailContentForJob(
    {payload: {ctaUrl: dripLink("drip_trial_reminder")},
      type: "drip_trial_reminder"} as unknown as EmailJobDocument
  ), /trialEndsAtMs/);
});
