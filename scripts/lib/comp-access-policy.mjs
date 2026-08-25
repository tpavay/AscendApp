/**
 * The decision layer for granting, revoking and listing complimentary app
 * access.
 *
 * Ascend has two access gates and a comp only works when it satisfies both.
 * The client paywall reads RevenueCat directly (`AppRootRoute.swift`), while
 * every server-guarded read is gated on the Firestore document
 * `users/{uid}/entitlements/app_access`, which the RevenueCat webhook writes
 * ONLY when the entitlement's product identifier appears in that environment's
 * `allowedProductIds`.
 *
 * RevenueCat composes a promotional product identifier as
 * `rc_promo_{entitlement}_{duration}`, so every duration produces a DIFFERENT
 * identifier and an environment allowlists them one at a time. Granting a
 * duration nobody allowlisted half-works in the worst possible way: the person
 * clears the paywall, and then every server-guarded screen fails. On
 * 2026-08-25 exactly that happened with a one-year grant.
 *
 * Everything here is pure so the safety-critical part - refusing a duration
 * whose composed identifier is not in the LIVE allowlist - is tested without
 * credentials, a network, or a real grant.
 */

// RevenueCat's `duration` enum, from the v1 "Grant a Promotional Entitlement"
// reference. The field is marked deprecated in favor of `end_time_ms`, and this
// tool deliberately keeps using it: `duration` is what composes the
// deterministic `rc_promo_{entitlement}_{duration}` identifier that an
// environment can allowlist ahead of time. What identifier an `end_time_ms`
// grant produces is not documented, and an unverified identifier is exactly the
// half-worked grant this module exists to refuse.
export const REVENUECAT_PROMOTIONAL_DURATIONS = Object.freeze([
  "daily",
  "three_day",
  "weekly",
  "two_week",
  "monthly",
  "two_month",
  "three_month",
  "six_month",
  "yearly",
  "lifetime",
]);

export const DEFAULT_COMP_DURATION = "lifetime";

// The ledger. It is deliberately NOT under `users/{uid}`: an account deletion
// recursively removes that tree, and the record of what was spent on somebody
// has to outlive the account it was spent on. No `firestore.rules` match exists
// for it, so Firestore's default deny already makes it unreachable from every
// client; it is listed in the wipe policy's protected set instead, beside
// `_migrations`, because an audit trail must survive a database reset.
export const COMP_LEDGER_COLLECTION = "comp_grants";

// Apple holds these credentials and uses this account to review submissions.
// Changing its entitlement out from under a review in flight risks the exact
// Guideline 2.1(b) rejection that #506 already cost.
export const APP_REVIEW_SUBJECT = Object.freeze({
  uid: "bbB1ot2Ix6hZi3duuGSnXbInUKK2",
  email: "ascendstepper.appreview@gmail.com",
});

// Dev has no Cloud Functions deployment and no RevenueCat webhook, so a grant
// there could never produce the server-side half. Refusing it is more useful
// than letting it half-work in the one environment nobody would check.
export const COMP_ENVIRONMENTS = Object.freeze({
  staging: "ascend-staging-fa7d5",
  prod: "ascend-prod-9c8f2",
  production: "ascend-prod-9c8f2",
});

export const PRODUCTION_PROJECT_ID = COMP_ENVIRONMENTS.prod;
export const UNSUPPORTED_COMP_ENVIRONMENTS = Object.freeze({
  dev: "ascend-f2e4f",
});

export const LOOKUP_OUTCOME = Object.freeze({
  matched: "MATCHED",
  none: "NO MATCH",
  ambiguous: "AMBIGUOUS",
});

export const ACCESS_STATE = Object.freeze({
  none: "NO ACCESS",
  trialing: "FREE TRIAL",
  paying: "PAYING",
  comped: "ALREADY COMPED",
  lapsed: "LAPSED",
  billingRetry: "BILLING RETRY",
});

export const LANDING = Object.freeze({
  landed: "LANDED",
  rejected: "REJECTED BY ALLOWLIST",
  pending: "PENDING",
});

/**
 * Resolves which Firebase project a comp command will act on.
 *
 * Production carries the project ID in its confirmation, matching
 * `deploy-remote-config.mjs` and `publish-new-kill-switches.mjs`: a
 * confirmation that has to be spelled out cannot be pasted from a different
 * command by muscle memory.
 * @param {object} options Resolution inputs.
 * @return {{projectId: string, env: string, label: string, isProduction: boolean}} Target.
 */
export function resolveCompTarget({env = null, confirmProduction = null} = {}) {
  if (env === null) {
    throw new Error(
      "No target. Pass --env staging, or --env prod --confirm-production " +
        `${PRODUCTION_PROJECT_ID}.`
    );
  }

  if (Object.hasOwn(UNSUPPORTED_COMP_ENVIRONMENTS, env)) {
    throw new Error(
      `${env} has no Cloud Functions deployment and no RevenueCat webhook, so ` +
        "a grant there can never produce the server-owned half of app access. " +
        "Use staging to rehearse and prod to actually comp somebody."
    );
  }

  if (!Object.hasOwn(COMP_ENVIRONMENTS, env)) {
    throw new Error(
      `Unknown environment "${env}". Use one of: ` +
        `${Object.keys(COMP_ENVIRONMENTS).join(", ")}.`
    );
  }

  const projectId = COMP_ENVIRONMENTS[env];
  if (projectId === PRODUCTION_PROJECT_ID && confirmProduction !== projectId) {
    throw new Error(
      `Production requires --confirm-production ${PRODUCTION_PROJECT_ID}.`
    );
  }

  return {
    projectId,
    env: env === "production" ? "prod" : env,
    label: `${projectId} (${env === "production" ? "prod" : env})`,
    isProduction: projectId === PRODUCTION_PROJECT_ID,
  };
}

/**
 * Composes the product identifier RevenueCat will attach to a promotional
 * grant.
 * @param {string} entitlementId Entitlement being granted.
 * @param {string} duration One of REVENUECAT_PROMOTIONAL_DURATIONS.
 * @return {string} Composed promotional product identifier.
 */
export function promotionalProductId(entitlementId, duration) {
  return `rc_promo_${entitlementId}_${duration}`;
}

/**
 * Whether a product identifier is a RevenueCat promotional grant rather than a
 * real store purchase.
 * @param {?string} productId Product identifier from a subscriber response.
 * @return {boolean} True when the identifier was composed by a promo grant.
 */
export function isPromotionalProductId(productId) {
  return typeof productId === "string" && productId.startsWith("rc_promo_");
}

/**
 * Every duration whose composed identifier this environment would honor.
 * @param {object} options Entitlement and live allowlist.
 * @return {string[]} Grantable durations, in RevenueCat's own order.
 */
export function grantableDurations({entitlementId, allowedProductIds}) {
  const allowed = new Set(allowedProductIds ?? []);
  return REVENUECAT_PROMOTIONAL_DURATIONS.filter(
    (duration) => allowed.has(promotionalProductId(entitlementId, duration))
  );
}

/**
 * Decides whether one duration may be granted against the live allowlist.
 *
 * This is the safety-critical check. A refusal here is the whole reason the
 * tool exists, so it never falls back to a default, an assumption, or a
 * remembered allowlist: an allowlist that could not be read is a refusal, not
 * a permission.
 * @param {object} options Duration, entitlement, and live allowlist.
 * @return {{ok: boolean, productId: ?string, grantable: string[], reason: ?string}} Verdict.
 */
export function evaluateDuration({
  duration,
  entitlementId,
  allowedProductIds = null,
} = {}) {
  if (!REVENUECAT_PROMOTIONAL_DURATIONS.includes(duration)) {
    return {
      ok: false,
      productId: null,
      grantable: [],
      reason:
        `"${duration}" is not a RevenueCat promotional duration. Valid ` +
        `values: ${REVENUECAT_PROMOTIONAL_DURATIONS.join(", ")}.`,
    };
  }

  if (!Array.isArray(allowedProductIds) || allowedProductIds.length === 0) {
    return {
      ok: false,
      productId: null,
      grantable: [],
      reason:
        "The live allowlist could not be read, so no duration can be shown to " +
        "work. An unreadable allowlist is a refusal, never a permission - " +
        "granting past it is how a comp half-works.",
    };
  }

  const productId = promotionalProductId(entitlementId, duration);
  const grantable = grantableDurations({entitlementId, allowedProductIds});

  if (!allowedProductIds.includes(productId)) {
    return {
      ok: false,
      productId,
      grantable,
      reason:
        `A "${duration}" grant is published as "${productId}", which is NOT in ` +
        "this environment's allowedProductIds. RevenueCat would grant it and " +
        "the paywall would open, but the webhook would refuse to write " +
        "users/{uid}/entitlements/app_access - so every server-guarded screen " +
        "would fail. " +
        (grantable.length > 0 ?
          `Grantable here right now: ${grantable.join(", ")}.` :
          "NO duration is grantable in this environment right now: its " +
            "allowedProductIds contains no rc_promo_ identifier at all. Add " +
            `"${productId}" to REVENUECAT_SERVER_CONFIG.allowedProductIds and ` +
            "redeploy functions before comping anybody here."),
    };
  }

  return {ok: true, productId, grantable, reason: null};
}

/**
 * Refuses the accounts a comp must never touch.
 * @param {object} subject Resolved subject.
 * @return {?string} Refusal reason, or null when the subject may be comped.
 */
export function protectedSubjectRefusal(subject) {
  if (!subject) return null;
  const email = typeof subject.email === "string" ?
    subject.email.trim().toLowerCase() : null;
  if (subject.uid === APP_REVIEW_SUBJECT.uid ||
    email === APP_REVIEW_SUBJECT.email) {
    return (
      "This is the App Store review account " +
      `(${APP_REVIEW_SUBJECT.email}, uid ${APP_REVIEW_SUBJECT.uid}). Apple ` +
      "holds these credentials and reviews submissions with it. Its access is " +
      "managed through the review flow, never through a comp. Refusing."
    );
  }
  return null;
}

/**
 * Resolves a captain's free-text query against candidate user documents.
 *
 * Someone who signed in with Apple using Hide My Email has a
 * `@privaterelay.appleid.com` address stored here, never the address they would
 * tell the captain - so a name lookup is the path that works for them, and an
 * email that finds nothing is not evidence the person has no account.
 * @param {object} options Query and candidates.
 * @return {object} Lookup outcome.
 */
export function resolveLookup({query, candidates = [], scanTruncated = false}) {
  const needle = String(query ?? "").trim().toLowerCase();
  if (needle === "") {
    throw new Error("Look somebody up by email or display name.");
  }

  const exact = candidates.filter(
    (candidate) => fieldsOf(candidate).some((value) => value === needle)
  );
  const matches = exact.length > 0 ? exact : candidates.filter(
    (candidate) => fieldsOf(candidate).some((value) => value.includes(needle))
  );

  if (matches.length === 1) {
    return {outcome: LOOKUP_OUTCOME.matched, subject: matches[0], matches};
  }

  if (matches.length === 0) {
    return {
      outcome: LOOKUP_OUTCOME.none,
      subject: null,
      matches: [],
      scanTruncated,
      reason:
        `Nothing in this environment matches "${query}". ` +
        (needle.includes("@") ?
          "An Apple Hide My Email account stores a " +
            "@privaterelay.appleid.com address, not the one they would tell " +
            "you - search their display name instead." :
          "Try their email, or a distinctive part of the display name they " +
            "actually set in Ascend.") +
        (scanTruncated ?
          " The scan also hit its cap before reading every account, so this " +
            "is not a complete search - raise --scan-limit and re-run." :
          ""),
    };
  }

  return {
    outcome: LOOKUP_OUTCOME.ambiguous,
    subject: null,
    matches,
    reason:
      `"${query}" matches ${matches.length} accounts. Re-run with the exact ` +
      "email, or with the uid, so there is no doubt who gets the access.",
  };
}

function fieldsOf(candidate) {
  return [
    candidate.uid,
    candidate.email,
    candidate.displayName,
    [candidate.firstName, candidate.lastName].filter(Boolean).join(" "),
  ]
    .filter((value) => typeof value === "string" && value !== "")
    .map((value) => value.trim().toLowerCase());
}

/**
 * Classifies what a subscriber's live RevenueCat state actually is.
 *
 * Never inferred from Firestore, a cache, or the last thing anybody
 * remembered: whether somebody is mid-trial, actively billed, lapsed or
 * already comped changes what a grant does to them, and only RevenueCat knows.
 * @param {object} options Subscriber response, entitlement, and clock.
 * @return {object} Structured live access state.
 */
export function classifySubscriberState({
  subscriber = null,
  entitlementId,
  now = new Date(),
} = {}) {
  if (subscriber === null) {
    return {
      state: ACCESS_STATE.none,
      summary:
        "No RevenueCat customer record at all - this app user id has never " +
        "reached a paywall.",
      entitlementActive: false,
      productId: null,
      isPromotional: false,
      storeSubscription: null,
      hasBillableStoreSubscription: false,
      expiresAt: null,
    };
  }

  const entitlement = subscriber.entitlements?.[entitlementId] ?? null;
  const productId = entitlement?.product_identifier ?? null;
  const effectiveExpiry = latest(
    parseDate(entitlement?.expires_date),
    parseDate(entitlement?.grace_period_expires_date)
  );
  const entitlementActive = Boolean(entitlement) &&
    (effectiveExpiry === null || effectiveExpiry.getTime() > now.getTime());
  const isPromotional = isPromotionalProductId(productId);

  // The entitlement names the product; the subscription block underneath it is
  // where the billing truth lives - trial vs normal, canceled, in retry.
  const storeSubscription = resolveStoreSubscription({
    subscriber,
    productId,
    now,
  });
  const hasBillableStoreSubscription = storeSubscription !== null &&
    storeSubscription.isBillable;

  if (!entitlement) {
    return {
      state: storeSubscription ? ACCESS_STATE.lapsed : ACCESS_STATE.none,
      summary: storeSubscription ?
        `No active ${entitlementId}. Their last store subscription ` +
          `(${storeSubscription.productId}) is no longer granting access.` :
        `No ${entitlementId} entitlement and no store subscription on record.`,
      entitlementActive: false,
      productId: null,
      isPromotional: false,
      storeSubscription,
      hasBillableStoreSubscription,
      expiresAt: null,
    };
  }

  if (!entitlementActive) {
    return {
      state: ACCESS_STATE.lapsed,
      summary:
        `Their ${entitlementId} expired ${formatInstant(effectiveExpiry)} ` +
        `(product ${productId ?? "unknown"}). They are locked out right now.`,
      entitlementActive: false,
      productId,
      isPromotional,
      storeSubscription,
      hasBillableStoreSubscription,
      expiresAt: effectiveExpiry,
    };
  }

  if (isPromotional) {
    return {
      state: ACCESS_STATE.comped,
      summary: `Already holds a comp (${productId}), ` +
        (effectiveExpiry === null ?
          "with no expiry." :
          `through ${formatInstant(effectiveExpiry)}.`),
      entitlementActive: true,
      productId,
      isPromotional: true,
      storeSubscription,
      hasBillableStoreSubscription,
      expiresAt: effectiveExpiry,
    };
  }

  if (storeSubscription?.periodType === "trial") {
    return {
      state: ACCESS_STATE.trialing,
      summary:
        `On the free trial of ${productId}. Apple converts it to a paid ` +
        `subscription ${formatInstant(effectiveExpiry)} unless they cancel.`,
      entitlementActive: true,
      productId,
      isPromotional: false,
      storeSubscription,
      hasBillableStoreSubscription,
      expiresAt: effectiveExpiry,
    };
  }

  if (storeSubscription?.hasBillingIssue) {
    return {
      state: ACCESS_STATE.billingRetry,
      summary:
        `Paying for ${productId}, but Apple has flagged a billing problem. ` +
        `Access runs to ${formatInstant(effectiveExpiry)}.`,
      entitlementActive: true,
      productId,
      isPromotional: false,
      storeSubscription,
      hasBillableStoreSubscription,
      expiresAt: effectiveExpiry,
    };
  }

  return {
    state: ACCESS_STATE.paying,
    summary: `Actively paying for ${productId}` +
      (storeSubscription?.price ?
        ` (${storeSubscription.price.amount} ${storeSubscription.price.currency})` :
        "") +
      (storeSubscription?.unsubscribeDetectedAt ?
        ", but has already turned off auto-renew - access ends " +
          `${formatInstant(effectiveExpiry)}.` :
        `, renewing ${formatInstant(effectiveExpiry)}.`),
    entitlementActive: true,
    productId,
    isPromotional: false,
    storeSubscription,
    hasBillableStoreSubscription,
    expiresAt: effectiveExpiry,
  };
}

function resolveStoreSubscription({subscriber, productId, now}) {
  const subscriptions = subscriber.subscriptions ?? {};
  const named = productId && subscriptions[productId] ?
    [[productId, subscriptions[productId]]] :
    Object.entries(subscriptions);

  const ranked = named
    .filter(([, subscription]) => subscription?.store !== "promotional")
    .map(([id, subscription]) => {
      const effective = latest(
        parseDate(subscription.expires_date),
        parseDate(subscription.grace_period_expires_date)
      );
      return {
        productId: id,
        store: subscription.store ?? null,
        periodType: subscription.period_type ?? null,
        isSandbox: subscription.is_sandbox === true,
        price: subscription.price ?? null,
        managementUrl: subscription.management_url ?? null,
        expiresAt: effective,
        refundedAt: parseDate(subscription.refunded_at),
        unsubscribeDetectedAt: parseDate(subscription.unsubscribe_detected_at),
        hasBillingIssue:
          parseDate(subscription.billing_issues_detected_at) !== null,
        // "Billable" means Apple will take money from them again unless they
        // themselves cancel: an active paid term, or a trial that converts.
        isBillable: parseDate(subscription.refunded_at) === null &&
          parseDate(subscription.unsubscribe_detected_at) === null &&
          (effective === null || effective.getTime() > now.getTime()),
      };
    })
    .sort((first, second) => expiryRank(second) - expiryRank(first));

  return ranked[0] ?? null;
}

function expiryRank(subscription) {
  return subscription.expiresAt === null ?
    Number.MAX_SAFE_INTEGER : subscription.expiresAt.getTime();
}

/**
 * The warnings a grant must show before anybody confirms it.
 *
 * A RevenueCat promotional grant never cancels, charges, refunds or converts a
 * store subscription. Comping somebody who is mid-trial or actively paying
 * therefore leaves Apple billing them exactly as before, and only the customer
 * can stop that from their own iPhone settings.
 * @param {object} options Live state and the grant being planned.
 * @return {{requiresBillingAcknowledgement: boolean, warnings: string[]}} Warnings.
 */
export function buildGrantWarnings({liveState, duration}) {
  const warnings = [];
  const subscription = liveState.storeSubscription;
  const requiresBillingAcknowledgement = Boolean(
    liveState.hasBillableStoreSubscription
  );

  if (requiresBillingAcknowledgement) {
    warnings.push(
      liveState.state === ACCESS_STATE.trialing ?
        "THEY ARE MID-TRIAL ON A REAL STORE SUBSCRIPTION " +
          `(${subscription.productId}). A comp does NOT cancel it. Apple still ` +
          `converts that trial and charges them ` +
          `${formatInstant(subscription.expiresAt)}.` :
        "THEY ARE ACTIVELY PAYING FOR A REAL STORE SUBSCRIPTION " +
          `(${subscription.productId}` +
          (subscription.price ?
            `, ${subscription.price.amount} ${subscription.price.currency}` :
            "") +
          "). A comp does NOT cancel it. Apple keeps billing them on the same " +
          "schedule."
    );
    warnings.push(
      "A RevenueCat promotional entitlement never cancels, charges, refunds or " +
        "converts a store subscription. It only layers free access on top of " +
        "one. Only the customer can cancel, in Settings > Apple Account > " +
        "Subscriptions on their own iPhone" +
        (subscription.managementUrl ? ` (${subscription.managementUrl}).` : ".")
    );
    if (duration === "lifetime") {
      warnings.push(
        "A lifetime promo permanently shadows their real purchase in " +
          "reporting: RevenueCat shows this account as comped from now on, and " +
          "the revenue they keep paying gets harder to see behind it."
      );
    }
    warnings.push(
      "If the intent was to stop charging them, a comp is the wrong tool. Have " +
        "them cancel, or refund the charge through App Store Connect, and comp " +
        "only what is left."
    );
  }

  if (liveState.state === ACCESS_STATE.comped) {
    warnings.push(
      `They already hold ${liveState.productId}. Granting again re-issues the ` +
        "promotional entitlement; it does not stack and it does not extend a " +
        "lifetime grant."
    );
  }

  if (subscription?.isSandbox) {
    warnings.push(
      "Their store subscription is a SANDBOX purchase, so this is a test " +
        "account rather than a paying customer."
    );
  }

  return {requiresBillingAcknowledgement, warnings};
}

/**
 * Decides whether the operator has confirmed enough for a grant to proceed.
 *
 * The confirmation carries the resolved uid rather than being a bare `--yes`,
 * for the same reason `--confirm-production` carries the project ID: a
 * confirmation you have to spell out cannot be pasted from the run before it,
 * and it cannot be produced without having read the dossier first.
 * @param {object} options Subject and supplied confirmations.
 * @return {{ok: boolean, reason: ?string}} Verdict.
 */
export function evaluateGrantConfirmation({
  subject,
  requiresBillingAcknowledgement = false,
  confirmGrant = null,
  acknowledgeActiveSubscription = false,
} = {}) {
  if (confirmGrant === null) {
    return {
      ok: false,
      reason:
        "Nothing was granted. This spends real access, so it takes a " +
        "deliberate second command. Show the dossier above to the captain, and " +
        "only once they say yes, re-run with --confirm-grant " +
        `${subject.uid}` +
        (requiresBillingAcknowledgement ?
          " --acknowledge-active-subscription" : ""),
    };
  }

  if (confirmGrant !== subject.uid) {
    return {
      ok: false,
      reason:
        `--confirm-grant ${confirmGrant} does not match the account this ` +
        `lookup resolved (${subject.uid}). Refusing rather than guessing which ` +
        "of the two you meant.",
    };
  }

  if (requiresBillingAcknowledgement && !acknowledgeActiveSubscription) {
    return {
      ok: false,
      reason:
        "This account is on a live store subscription that a comp will NOT " +
        "cancel - Apple keeps billing them. Confirm the captain has heard " +
        "that, then add --acknowledge-active-subscription.",
    };
  }

  return {ok: true, reason: null};
}

/**
 * Reads the two server documents and says whether the comp actually landed.
 *
 * The RevenueCat grant alone is never success. `entitlement_status` is written
 * on every webhook delivery while `entitlements/app_access` is written only for
 * an allowlisted product, so a status document that says `isActive: false`
 * beside a missing grant is not a slow webhook - it is the allowlist refusing
 * the product, which is the exact half-worked state this tool exists to
 * prevent.
 * @param {object} options The two documents and the expected product.
 * @return {{landing: string, reason: string}} Landing verdict.
 */
export function classifyWebhookLanding({
  grantDoc = null,
  statusDoc = null,
  expectedProductId,
} = {}) {
  if (grantDoc && grantDoc.isActive === true) {
    return {
      landing: LANDING.landed,
      reason:
        "users/{uid}/entitlements/app_access exists with productId " +
        `${grantDoc.productId ?? "unknown"}. Both gates are satisfied: the ` +
        "paywall opens and every server-guarded screen works.",
    };
  }

  if (statusDoc && statusDoc.isActive === false) {
    return {
      landing: LANDING.rejected,
      reason:
        "The webhook DELIVERED and refused the product. " +
        "entitlement_status/app_access says isActive: false and no grant " +
        `document was written, so "${expectedProductId}" is not in this ` +
        "environment's allowedProductIds. The paywall will open for them and " +
        "every server-guarded screen will fail. Revoke this grant, add the " +
        "product to REVENUECAT_SERVER_CONFIG.allowedProductIds, redeploy " +
        "functions, and grant again.",
    };
  }

  return {
    landing: LANDING.pending,
    reason:
      "RevenueCat accepted the grant, but " +
      "users/{uid}/entitlements/app_access has not appeared. The webhook " +
      "normally lands in seconds. Until that document exists the comp is only " +
      "half done: the paywall opens and every server-guarded screen fails. Do " +
      "not report this as success - check the RevenueCat webhook " +
      "integration's delivery log and the revenueCatWebhook function logs.",
  };
}

/**
 * Builds the durable ledger entry for one grant or revoke.
 *
 * A comp with no note of who or why is the gap the ledger exists to close, so
 * a missing reason fails the command rather than writing a blank record.
 * @param {object} options Ledger inputs.
 * @return {object} Ledger entry.
 */
export function buildLedgerEntry({
  action,
  subject,
  productId = null,
  duration = null,
  reason,
  operator,
  at,
  landing = null,
}) {
  const trimmedReason = String(reason ?? "").trim();
  if (trimmedReason === "") {
    throw new Error(
      "A comp with no recorded reason is the gap this ledger exists to close. " +
        "Pass --reason \"why this person is getting free access\"."
    );
  }
  return {
    action,
    uid: subject.uid,
    email: subject.email ?? null,
    displayName: subject.displayName ?? null,
    productId,
    duration,
    reason: trimmedReason,
    operator,
    at,
    landing,
  };
}

function parseDate(value) {
  if (value === null || value === undefined) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function latest(first, second) {
  if (first === null) return second;
  if (second === null) return first;
  return first.getTime() > second.getTime() ? first : second;
}

function formatInstant(value) {
  return value === null ? "never" : value.toISOString().replace(".000", "");
}
