import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {test} from "node:test";

import {
  ACCESS_STATE,
  APP_REVIEW_SUBJECT,
  COMP_LEDGER_COLLECTION,
  LANDING,
  LOOKUP_OUTCOME,
  PRODUCTION_PROJECT_ID,
  REVENUECAT_PROMOTIONAL_DURATIONS,
  buildGrantWarnings,
  buildLedgerEntry,
  classifySubscriberState,
  classifyWebhookLanding,
  evaluateDuration,
  evaluateGrantConfirmation,
  grantableDurations,
  isPromotionalProductId,
  promotionalProductId,
  protectedSubjectRefusal,
  resolveCompTarget,
  resolveLookup,
} from "../lib/comp-access-policy.mjs";
import {
  PROTECTED_WIPE_COLLECTION_IDS,
  classifyWipeCollections,
  reviewedWipeCollectionIds,
} from "../lib/firestore-wipe-policy.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const ENTITLEMENT = "app_access";

// The live production allowlist on 2026-08-25, read from the secret version the
// deployed revenueCatWebhook was bound to. Pinned here as a fixture only - the
// tool always reads the real one, because this copy is a snapshot and snapshots
// of an allowlist are exactly what went wrong.
const PRODUCTION_ALLOWLIST = [
  "ascend_yearly",
  "ascend_monthly",
  "rc_promo_app_access_lifetime",
];
const STAGING_ALLOWLIST = ["ascend_staging_yearly", "ascend_staging_monthly"];

// -- the safety-critical check ------------------------------------------------

test("a lifetime grant is allowed because production allowlists its id", () => {
  const verdict = evaluateDuration({
    duration: "lifetime",
    entitlementId: ENTITLEMENT,
    allowedProductIds: PRODUCTION_ALLOWLIST,
  });

  assert.equal(verdict.ok, true);
  assert.equal(verdict.productId, "rc_promo_app_access_lifetime");
  assert.equal(verdict.reason, null);
});

test("a yearly grant is refused - it composes an id nobody allowlisted", () => {
  const verdict = evaluateDuration({
    duration: "yearly",
    entitlementId: ENTITLEMENT,
    allowedProductIds: PRODUCTION_ALLOWLIST,
  });

  assert.equal(verdict.ok, false);
  assert.equal(verdict.productId, "rc_promo_app_access_yearly");
  assert.match(verdict.reason, /NOT in this environment's allowedProductIds/);
  assert.match(verdict.reason, /Grantable here right now: lifetime\./);
});

test("every duration but lifetime is refused against the production allowlist", () => {
  for (const duration of REVENUECAT_PROMOTIONAL_DURATIONS) {
    const verdict = evaluateDuration({
      duration,
      entitlementId: ENTITLEMENT,
      allowedProductIds: PRODUCTION_ALLOWLIST,
    });
    assert.equal(
      verdict.ok,
      duration === "lifetime",
      `${duration} should be ${duration === "lifetime" ? "allowed" : "refused"}`
    );
  }
});

test("the real subscription products never make a duration grantable", () => {
  // ascend_yearly is in the allowlist, but a "yearly" comp is not published as
  // ascend_yearly - it is rc_promo_app_access_yearly. Confusing the two is the
  // whole failure.
  assert.deepEqual(
    grantableDurations({
      entitlementId: ENTITLEMENT,
      allowedProductIds: PRODUCTION_ALLOWLIST,
    }),
    ["lifetime"]
  );
});

test("staging allowlists no promotional id at all, so nothing is grantable", () => {
  assert.deepEqual(
    grantableDurations({
      entitlementId: ENTITLEMENT,
      allowedProductIds: STAGING_ALLOWLIST,
    }),
    []
  );

  const verdict = evaluateDuration({
    duration: "lifetime",
    entitlementId: ENTITLEMENT,
    allowedProductIds: STAGING_ALLOWLIST,
  });
  assert.equal(verdict.ok, false);
  assert.match(verdict.reason, /NO duration is grantable/);
  assert.match(verdict.reason, /redeploy functions/);
});

test("an unreadable allowlist refuses rather than permits", () => {
  for (const allowedProductIds of [null, undefined, []]) {
    const verdict = evaluateDuration({
      duration: "lifetime",
      entitlementId: ENTITLEMENT,
      allowedProductIds,
    });
    assert.equal(verdict.ok, false);
    assert.match(verdict.reason, /refusal, never a permission/);
  }
});

test("a duration RevenueCat does not define is refused before anything else", () => {
  const verdict = evaluateDuration({
    duration: "forever",
    entitlementId: ENTITLEMENT,
    allowedProductIds: PRODUCTION_ALLOWLIST,
  });

  assert.equal(verdict.ok, false);
  assert.equal(verdict.productId, null);
  assert.match(verdict.reason, /not a RevenueCat promotional duration/);
});

test("promotional identifiers are composed exactly as RevenueCat composes them", () => {
  assert.equal(
    promotionalProductId("app_access", "six_month"),
    "rc_promo_app_access_six_month"
  );
  assert.equal(isPromotionalProductId("rc_promo_app_access_lifetime"), true);
  assert.equal(isPromotionalProductId("ascend_yearly"), false);
  assert.equal(isPromotionalProductId(null), false);
});

// -- the accounts that must never be touched ---------------------------------

test("the App Store review account is refused by uid and by email", () => {
  assert.match(
    protectedSubjectRefusal({uid: APP_REVIEW_SUBJECT.uid}),
    /App Store review account/
  );
  assert.match(
    protectedSubjectRefusal({uid: "someone-else", email: "  ASCENDSTEPPER.APPREVIEW@GMAIL.COM "}),
    /App Store review account/
  );
  assert.equal(
    protectedSubjectRefusal({uid: "abc", email: "bob@gmail.com"}),
    null
  );
});

// -- environment resolution ---------------------------------------------------

test("production needs its project id spelled out in the confirmation", () => {
  assert.throws(
    () => resolveCompTarget({env: "prod"}),
    /--confirm-production ascend-prod-9c8f2/
  );
  assert.throws(
    () => resolveCompTarget({env: "prod", confirmProduction: "yes"}),
    /--confirm-production ascend-prod-9c8f2/
  );

  const target = resolveCompTarget({
    env: "prod",
    confirmProduction: PRODUCTION_PROJECT_ID,
  });
  assert.equal(target.projectId, PRODUCTION_PROJECT_ID);
  assert.equal(target.isProduction, true);
});

test("staging needs no production confirmation and is not production", () => {
  const target = resolveCompTarget({env: "staging"});
  assert.equal(target.projectId, "ascend-staging-fa7d5");
  assert.equal(target.isProduction, false);
});

test("dev is refused: it has no webhook, so a grant there cannot land", () => {
  assert.throws(
    () => resolveCompTarget({env: "dev"}),
    /no Cloud Functions deployment and no RevenueCat webhook/
  );
});

test("an absent or unknown environment never resolves to a default", () => {
  assert.throws(() => resolveCompTarget({}), /No target/);
  assert.throws(() => resolveCompTarget({env: "qa"}), /Unknown environment/);
});

// -- lookup -------------------------------------------------------------------

const CANDIDATES = [
  {uid: "u1", email: "bob@gmail.com", displayName: "Bob Smith"},
  {uid: "u2", email: "bobby@example.com", displayName: "Bobby Tables"},
  {
    uid: "u3",
    email: "xyz@privaterelay.appleid.com",
    displayName: "Dana Reyes",
    firstName: "Dana",
    lastName: "Reyes",
  },
];

test("an exact email or display name resolves to one account", () => {
  assert.equal(
    resolveLookup({query: "bob@gmail.com", candidates: CANDIDATES}).subject.uid,
    "u1"
  );
  assert.equal(
    resolveLookup({query: "Bob Smith", candidates: CANDIDATES}).subject.uid,
    "u1"
  );
  assert.equal(
    resolveLookup({query: "  BOB SMITH  ", candidates: CANDIDATES}).subject.uid,
    "u1"
  );
});

test("an exact match wins over the accounts it is a prefix of", () => {
  // "Bob Smith" also appears inside nothing else here, but "bob" does - an
  // exact hit must not be dragged into an ambiguity by its own substrings.
  const exact = resolveLookup({query: "u1", candidates: CANDIDATES});
  assert.equal(exact.outcome, LOOKUP_OUTCOME.matched);
});

test("an ambiguous name refuses and lists who it matched", () => {
  const lookup = resolveLookup({query: "bob", candidates: CANDIDATES});

  assert.equal(lookup.outcome, LOOKUP_OUTCOME.ambiguous);
  assert.equal(lookup.subject, null);
  assert.equal(lookup.matches.length, 2);
  assert.match(lookup.reason, /matches 2 accounts/);
});

test("a display name finds the Hide My Email account an address never would", () => {
  const byName = resolveLookup({query: "Dana Reyes", candidates: CANDIDATES});
  assert.equal(byName.subject.uid, "u3");

  const byRealAddress = resolveLookup({
    query: "dana@gmail.com",
    candidates: CANDIDATES,
  });
  assert.equal(byRealAddress.outcome, LOOKUP_OUTCOME.none);
  assert.match(byRealAddress.reason, /privaterelay\.appleid\.com/);
  assert.match(byRealAddress.reason, /search their display name instead/);
});

test("a no-match off a truncated scan says the search was incomplete", () => {
  const lookup = resolveLookup({
    query: "nobody",
    candidates: CANDIDATES,
    scanTruncated: true,
  });

  assert.equal(lookup.outcome, LOOKUP_OUTCOME.none);
  assert.match(lookup.reason, /not a complete search/);
  assert.match(lookup.reason, /--scan-limit/);
});

test("an empty query is rejected rather than matching everybody", () => {
  assert.throws(
    () => resolveLookup({query: "   ", candidates: CANDIDATES}),
    /Look somebody up/
  );
});

// -- live state classification -----------------------------------------------

const NOW = new Date("2026-08-25T12:00:00Z");

function subscriberWith(entitlement, subscriptions = {}) {
  return {
    entitlements: entitlement ? {[ENTITLEMENT]: entitlement} : {},
    subscriptions,
  };
}

test("no customer record at all reads as no access", () => {
  const state = classifySubscriberState({
    subscriber: null,
    entitlementId: ENTITLEMENT,
    now: NOW,
  });
  assert.equal(state.state, ACCESS_STATE.none);
  assert.equal(state.hasBillableStoreSubscription, false);
});

test("an active normal subscription reads as paying", () => {
  const state = classifySubscriberState({
    subscriber: subscriberWith(
      {product_identifier: "ascend_yearly", expires_date: "2027-08-25T12:00:00Z"},
      {
        ascend_yearly: {
          store: "app_store",
          period_type: "normal",
          expires_date: "2027-08-25T12:00:00Z",
          price: {amount: 49.99, currency: "USD"},
        },
      }
    ),
    entitlementId: ENTITLEMENT,
    now: NOW,
  });

  assert.equal(state.state, ACCESS_STATE.paying);
  assert.equal(state.hasBillableStoreSubscription, true);
  assert.match(state.summary, /49\.99 USD/);
});

test("a trial reads as a trial and still counts as billable", () => {
  const state = classifySubscriberState({
    subscriber: subscriberWith(
      {product_identifier: "ascend_yearly", expires_date: "2026-09-01T12:00:00Z"},
      {
        ascend_yearly: {
          store: "app_store",
          period_type: "trial",
          expires_date: "2026-09-01T12:00:00Z",
        },
      }
    ),
    entitlementId: ENTITLEMENT,
    now: NOW,
  });

  assert.equal(state.state, ACCESS_STATE.trialing);
  assert.equal(state.hasBillableStoreSubscription, true);
  assert.match(state.summary, /converts it to a paid subscription/);
});

test("an existing comp reads as comped, not as paying", () => {
  const state = classifySubscriberState({
    subscriber: subscriberWith({
      product_identifier: "rc_promo_app_access_lifetime",
      expires_date: null,
    }),
    entitlementId: ENTITLEMENT,
    now: NOW,
  });

  assert.equal(state.state, ACCESS_STATE.comped);
  assert.equal(state.isPromotional, true);
  assert.equal(state.hasBillableStoreSubscription, false);
  assert.match(state.summary, /with no expiry/);
});

test("an expired entitlement reads as lapsed", () => {
  const state = classifySubscriberState({
    subscriber: subscriberWith(
      {product_identifier: "ascend_monthly", expires_date: "2026-08-01T12:00:00Z"},
      {
        ascend_monthly: {
          store: "app_store",
          period_type: "normal",
          expires_date: "2026-08-01T12:00:00Z",
        },
      }
    ),
    entitlementId: ENTITLEMENT,
    now: NOW,
  });

  assert.equal(state.state, ACCESS_STATE.lapsed);
  assert.equal(state.entitlementActive, false);
  assert.equal(state.hasBillableStoreSubscription, false);
});

test("a flagged billing problem reads as billing retry, not plain paying", () => {
  const state = classifySubscriberState({
    subscriber: subscriberWith(
      {product_identifier: "ascend_yearly", expires_date: "2026-09-25T12:00:00Z"},
      {
        ascend_yearly: {
          store: "app_store",
          period_type: "normal",
          expires_date: "2026-09-25T12:00:00Z",
          billing_issues_detected_at: "2026-08-20T12:00:00Z",
        },
      }
    ),
    entitlementId: ENTITLEMENT,
    now: NOW,
  });

  assert.equal(state.state, ACCESS_STATE.billingRetry);
});

test("a canceled subscription still running is not billable", () => {
  const state = classifySubscriberState({
    subscriber: subscriberWith(
      {product_identifier: "ascend_yearly", expires_date: "2026-09-25T12:00:00Z"},
      {
        ascend_yearly: {
          store: "app_store",
          period_type: "normal",
          expires_date: "2026-09-25T12:00:00Z",
          unsubscribe_detected_at: "2026-08-21T12:00:00Z",
        },
      }
    ),
    entitlementId: ENTITLEMENT,
    now: NOW,
  });

  assert.equal(state.state, ACCESS_STATE.paying);
  assert.equal(state.hasBillableStoreSubscription, false);
  assert.match(state.summary, /turned off auto-renew/);
});

test("a grace period keeps access alive past the expiry date", () => {
  const state = classifySubscriberState({
    subscriber: subscriberWith(
      {
        product_identifier: "ascend_yearly",
        expires_date: "2026-08-20T12:00:00Z",
        grace_period_expires_date: "2026-09-20T12:00:00Z",
      },
      {
        ascend_yearly: {
          store: "app_store",
          period_type: "normal",
          expires_date: "2026-08-20T12:00:00Z",
          grace_period_expires_date: "2026-09-20T12:00:00Z",
          billing_issues_detected_at: "2026-08-20T12:00:00Z",
        },
      }
    ),
    entitlementId: ENTITLEMENT,
    now: NOW,
  });

  assert.equal(state.entitlementActive, true);
  assert.equal(state.state, ACCESS_STATE.billingRetry);
});

// -- the billing warning ------------------------------------------------------

function payingState(overrides = {}) {
  return classifySubscriberState({
    subscriber: subscriberWith(
      {product_identifier: "ascend_yearly", expires_date: "2027-08-25T12:00:00Z"},
      {
        ascend_yearly: {
          store: "app_store",
          period_type: "normal",
          expires_date: "2027-08-25T12:00:00Z",
          management_url: "https://apps.apple.com/account/subscriptions",
          price: {amount: 49.99, currency: "USD"},
          ...overrides,
        },
      }
    ),
    entitlementId: ENTITLEMENT,
    now: NOW,
  });
}

test("comping a paying customer warns that Apple keeps billing them", () => {
  const {requiresBillingAcknowledgement, warnings} = buildGrantWarnings({
    liveState: payingState(),
    duration: "lifetime",
  });

  assert.equal(requiresBillingAcknowledgement, true);
  const joined = warnings.join(" ");
  assert.match(joined, /ACTIVELY PAYING FOR A REAL STORE SUBSCRIPTION/);
  assert.match(joined, /never cancels, charges, refunds or converts/);
  assert.match(joined, /Only the customer can cancel/);
  assert.match(joined, /permanently shadows their real purchase in reporting/);
});

test("comping a trial warns that the trial still converts and charges", () => {
  const liveState = classifySubscriberState({
    subscriber: subscriberWith(
      {product_identifier: "ascend_yearly", expires_date: "2026-09-01T12:00:00Z"},
      {
        ascend_yearly: {
          store: "app_store",
          period_type: "trial",
          expires_date: "2026-09-01T12:00:00Z",
        },
      }
    ),
    entitlementId: ENTITLEMENT,
    now: NOW,
  });

  const {requiresBillingAcknowledgement, warnings} = buildGrantWarnings({
    liveState,
    duration: "lifetime",
  });

  assert.equal(requiresBillingAcknowledgement, true);
  assert.match(warnings.join(" "), /MID-TRIAL/);
  assert.match(warnings.join(" "), /still converts that trial and charges them/);
});

test("a non-lifetime comp skips the reporting-shadow warning", () => {
  const {warnings} = buildGrantWarnings({
    liveState: payingState(),
    duration: "monthly",
  });
  assert.equal(
    warnings.some((warning) => warning.includes("permanently shadows")),
    false
  );
});

test("comping somebody with nothing raises no billing warning", () => {
  const {requiresBillingAcknowledgement, warnings} = buildGrantWarnings({
    liveState: classifySubscriberState({
      subscriber: null,
      entitlementId: ENTITLEMENT,
      now: NOW,
    }),
    duration: "lifetime",
  });

  assert.equal(requiresBillingAcknowledgement, false);
  assert.deepEqual(warnings, []);
});

test("comping a lapsed subscriber raises no billing warning", () => {
  const liveState = classifySubscriberState({
    subscriber: subscriberWith(null, {
      ascend_yearly: {
        store: "app_store",
        period_type: "normal",
        expires_date: "2026-08-01T12:00:00Z",
      },
    }),
    entitlementId: ENTITLEMENT,
    now: NOW,
  });

  assert.equal(
    buildGrantWarnings({liveState, duration: "lifetime"})
      .requiresBillingAcknowledgement,
    false
  );
});

// -- confirmation -------------------------------------------------------------

const SUBJECT = {uid: "u1", email: "bob@gmail.com", displayName: "Bob Smith"};

test("nothing is granted without an explicit confirmation", () => {
  const verdict = evaluateGrantConfirmation({subject: SUBJECT});

  assert.equal(verdict.ok, false);
  assert.match(verdict.reason, /--confirm-grant u1/);
});

test("a confirmation for a different account is refused, not guessed at", () => {
  const verdict = evaluateGrantConfirmation({
    subject: SUBJECT,
    confirmGrant: "u2",
  });

  assert.equal(verdict.ok, false);
  assert.match(verdict.reason, /does not match the account this lookup resolved/);
});

test("a paying customer additionally needs the billing acknowledgement", () => {
  const withoutAck = evaluateGrantConfirmation({
    subject: SUBJECT,
    requiresBillingAcknowledgement: true,
    confirmGrant: "u1",
  });
  assert.equal(withoutAck.ok, false);
  assert.match(withoutAck.reason, /--acknowledge-active-subscription/);

  const withAck = evaluateGrantConfirmation({
    subject: SUBJECT,
    requiresBillingAcknowledgement: true,
    confirmGrant: "u1",
    acknowledgeActiveSubscription: true,
  });
  assert.equal(withAck.ok, true);
});

test("the first-run message names both flags a paying customer will need", () => {
  const verdict = evaluateGrantConfirmation({
    subject: SUBJECT,
    requiresBillingAcknowledgement: true,
  });

  assert.match(verdict.reason, /--confirm-grant u1 --acknowledge-active-subscription/);
});

test("a matching confirmation on a clean account proceeds", () => {
  assert.equal(
    evaluateGrantConfirmation({subject: SUBJECT, confirmGrant: "u1"}).ok,
    true
  );
});

// -- did it actually land? ----------------------------------------------------

test("the grant document existing is the only thing that counts as landed", () => {
  const verdict = classifyWebhookLanding({
    grantDoc: {isActive: true, productId: "rc_promo_app_access_lifetime"},
    statusDoc: {isActive: true},
    expectedProductId: "rc_promo_app_access_lifetime",
  });

  assert.equal(verdict.landing, LANDING.landed);
  assert.match(verdict.reason, /Both gates are satisfied/);
});

test("a delivered webhook with no grant document is an allowlist rejection", () => {
  const verdict = classifyWebhookLanding({
    grantDoc: null,
    statusDoc: {isActive: false, productId: null},
    expectedProductId: "rc_promo_app_access_yearly",
  });

  assert.equal(verdict.landing, LANDING.rejected);
  assert.match(verdict.reason, /The webhook DELIVERED and refused the product/);
  assert.match(verdict.reason, /rc_promo_app_access_yearly/);
  assert.match(verdict.reason, /Revoke this grant/);
});

test("neither document yet is pending, and pending is never reported as done", () => {
  const verdict = classifyWebhookLanding({
    expectedProductId: "rc_promo_app_access_lifetime",
  });

  assert.equal(verdict.landing, LANDING.pending);
  assert.match(verdict.reason, /Do not report this as success/);
  assert.match(verdict.reason, /only half done/);
});

test("a grant document that exists but is inactive is not landed", () => {
  const verdict = classifyWebhookLanding({
    grantDoc: {isActive: false},
    statusDoc: {isActive: false},
    expectedProductId: "rc_promo_app_access_lifetime",
  });

  assert.notEqual(verdict.landing, LANDING.landed);
});

// -- the ledger ---------------------------------------------------------------

test("a comp with no reason fails before anything is written", () => {
  for (const reason of [null, undefined, "", "   "]) {
    assert.throws(
      () => buildLedgerEntry({
        action: "grant",
        subject: SUBJECT,
        reason,
        operator: "tyler",
        at: NOW,
      }),
      /--reason/
    );
  }
});

test("a ledger entry records who, when, why, and what was granted", () => {
  const entry = buildLedgerEntry({
    action: "grant",
    subject: SUBJECT,
    productId: "rc_promo_app_access_lifetime",
    duration: "lifetime",
    reason: "  podcast guest  ",
    operator: "tyler",
    at: NOW,
  });

  assert.deepEqual(entry, {
    action: "grant",
    uid: "u1",
    email: "bob@gmail.com",
    displayName: "Bob Smith",
    productId: "rc_promo_app_access_lifetime",
    duration: "lifetime",
    reason: "podcast guest",
    operator: "tyler",
    at: NOW,
    landing: null,
  });
});

test("the comp ledger survives a database reset", () => {
  assert.ok(PROTECTED_WIPE_COLLECTION_IDS.includes(COMP_LEDGER_COLLECTION));

  const plan = classifyWipeCollections(
    ["users", COMP_LEDGER_COLLECTION],
    reviewedWipeCollectionIds(REPO_ROOT)
  );

  assert.deepEqual(plan.collectionsToDelete, ["users"]);
  assert.deepEqual(plan.protectedCollections, [COMP_LEDGER_COLLECTION]);
  assert.deepEqual(plan.unknownCollections, []);
});

// -- the command line ---------------------------------------------------------

function runCompAccess(...args) {
  return spawnSync(
    process.execPath,
    [resolve(REPO_ROOT, "scripts", "comp-access.mjs"), ...args],
    {encoding: "utf8"}
  );
}

test("production is refused before any credential is read", () => {
  const result = runCompAccess("find", "bob@gmail.com", "--env", "prod");

  assert.equal(result.status, 2);
  assert.match(result.stderr, /--confirm-production ascend-prod-9c8f2/);
});

test("granting with no environment refuses instead of picking one", () => {
  const result = runCompAccess("grant", "bob@gmail.com", "--reason", "x");

  assert.equal(result.status, 2);
  assert.match(result.stderr, /No target/);
});

test("a command with nobody to act on is refused", () => {
  const result = runCompAccess("grant", "--env", "staging");

  assert.equal(result.status, 2);
  assert.match(result.stderr, /needs somebody to act on/);
});

test("there is no --yes and no batch mode", () => {
  const help = runCompAccess("--help");

  assert.equal(help.status, 0);
  assert.doesNotMatch(help.stdout, /--yes\b/);
  assert.doesNotMatch(help.stdout, /--all\b/);
  assert.doesNotMatch(help.stdout, /--force\b/);
  assert.match(help.stdout, /--confirm-grant <uid>/);
});
