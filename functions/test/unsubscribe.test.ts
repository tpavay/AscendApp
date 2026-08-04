import test from "node:test";
import assert from "node:assert/strict";
import {Timestamp} from "firebase-admin/firestore";
import {
  buildUnsubscribeToken,
  buildUnsubscribeUrl,
  verifyUnsubscribeToken,
} from "../src/email/unsubscribeToken";
import {buildUnsubscribeHeaders} from "../src/email/provider";
import {
  assertTransactionalEmailConfig,
  DEFAULT_MARKETING_WEBSITE_URL,
  getMarketingWebsiteUrl,
} from "../src/email/config";
import {renderUnsubscribePage} from "../src/email/unsubscribe";
import {
  buildNextCommunicationPreferences,
  isAppLifecycleEmailConsentSource,
  isEmailJobSuppressed,
  isLifecycleEmailAllowed,
} from "../src/email/preferences";
import {
  renderRatingPositiveFollowupEmail,
  renderFirstAscentClaimedEmail,
} from "../src/email/templates";

const SIGNING_KEY = "test-unsubscribe-signing-key-0123456789";
const OTHER_SIGNING_KEY = "another-unsubscribe-signing-key-987654321";

// =============================================================================
// Unsubscribe Tokens
// =============================================================================

test("unsubscribe tokens round-trip the signed uid", () => {
  const token = buildUnsubscribeToken("user_123", SIGNING_KEY);

  assert.equal(verifyUnsubscribeToken(token, SIGNING_KEY), "user_123");
});

test("unsubscribe tokens are deterministic for the same uid and key", () => {
  assert.equal(
    buildUnsubscribeToken("user_123", SIGNING_KEY),
    buildUnsubscribeToken("user_123", SIGNING_KEY)
  );
});

test("unsubscribe tokens differ per uid", () => {
  assert.notEqual(
    buildUnsubscribeToken("user_123", SIGNING_KEY),
    buildUnsubscribeToken("user_456", SIGNING_KEY)
  );
});

test("unsubscribe tokens never expose the raw uid", () => {
  const token = buildUnsubscribeToken("user_123", SIGNING_KEY);

  assert.doesNotMatch(token, /user_123/);
});

test("unsubscribe tokens require a uid and a signing key", () => {
  assert.throws(() => buildUnsubscribeToken("", SIGNING_KEY));
  assert.throws(() => buildUnsubscribeToken("user_123", ""));
});

test("unsubscribe token verification rejects a forged signature", () => {
  const token = buildUnsubscribeToken("user_123", SIGNING_KEY);
  const [version, encodedUid] = token.split(".");
  const forged = `${version}.${encodedUid}.not-a-real-signature`;

  assert.equal(verifyUnsubscribeToken(forged, SIGNING_KEY), null);
});

test("unsubscribe token verification rejects a swapped uid", () => {
  // The attack this blocks: re-encoding someone else's uid onto a signature
  // that was issued for your own token.
  const own = buildUnsubscribeToken("attacker", SIGNING_KEY);
  const signature = own.split(".")[2];
  const victimUid = Buffer.from("victim", "utf8").toString("base64url");
  const tampered = `v1.${victimUid}.${signature}`;

  assert.equal(verifyUnsubscribeToken(tampered, SIGNING_KEY), null);
});

test("unsubscribe token verification rejects another key's token", () => {
  const token = buildUnsubscribeToken("user_123", OTHER_SIGNING_KEY);

  assert.equal(verifyUnsubscribeToken(token, SIGNING_KEY), null);
});

test("unsubscribe token verification rejects malformed input", () => {
  for (const candidate of [
    undefined,
    null,
    42,
    "",
    "v1",
    "v1.abc",
    "v1.abc.def.ghi",
    "v2.abc.def",
  ]) {
    assert.equal(
      verifyUnsubscribeToken(candidate, SIGNING_KEY),
      null,
      `expected ${JSON.stringify(candidate)} to be rejected`
    );
  }
});

test("unsubscribe token verification rejects an empty signing key", () => {
  const token = buildUnsubscribeToken("user_123", SIGNING_KEY);

  assert.equal(verifyUnsubscribeToken(token, ""), null);
});

test("unsubscribe urls carry the token on the public api route", () => {
  const token = buildUnsubscribeToken("user_123", SIGNING_KEY);
  const url = new URL(
    buildUnsubscribeUrl("https://ascendstepper.com", token)
  );

  assert.equal(url.origin, "https://ascendstepper.com");
  assert.equal(url.pathname, "/api/unsubscribe");
  assert.equal(url.searchParams.get("token"), token);
});

// =============================================================================
// List-Unsubscribe Headers
// =============================================================================

test("one-click unsubscribe headers travel together", () => {
  const headers = buildUnsubscribeHeaders(
    "https://ascendstepper.com/api/unsubscribe?token=abc"
  );

  assert.equal(
    headers["List-Unsubscribe"],
    "<https://ascendstepper.com/api/unsubscribe?token=abc>"
  );
  assert.equal(headers["List-Unsubscribe-Post"], "List-Unsubscribe=One-Click");
});

test("unsubscribe headers are omitted without an unsubscribe url", () => {
  for (const candidate of [null, undefined, ""]) {
    assert.deepEqual(buildUnsubscribeHeaders(candidate), {});
  }
});

// =============================================================================
// Footer Rendering
// =============================================================================

test("lifecycle emails render an unsubscribe link in the footer", () => {
  const unsubscribeUrl =
    "https://ascendstepper.com/api/unsubscribe?token=abc123";
  const rendered = renderRatingPositiveFollowupEmail({}, {unsubscribeUrl});

  assert.match(rendered.html, /<a href="[^"]*token=abc123"[^>]*>Unsubscribe/);
  assert.match(rendered.html, /Privacy Policy/);
  assert.ok(rendered.text.includes(`Unsubscribe: ${unsubscribeUrl}`));
});

test("lifecycle emails omit the unsubscribe link without a url", () => {
  const rendered = renderRatingPositiveFollowupEmail();

  assert.doesNotMatch(rendered.html, /Unsubscribe/);
  assert.doesNotMatch(rendered.text, /Unsubscribe/);
  assert.match(rendered.html, /Privacy Policy/);
});

test("unsubscribe urls are escaped into the footer markup", () => {
  const rendered = renderFirstAscentClaimedEmail(
    {climbName: "Everest", climbUrl: "https://ascendstepper.com/climbs/everest"},
    {unsubscribeUrl: "https://ascendstepper.com/api/unsubscribe?a=1&b=\"x\""}
  );

  assert.doesNotMatch(rendered.html, /token[^"]*"x"/);
  assert.match(rendered.html, /a=1&amp;b=&quot;x&quot;/);
});

// =============================================================================
// Unsubscribe Page
// =============================================================================

test("unsubscribe confirmation page posts the token back", () => {
  const page = renderUnsubscribePage("Unsubscribe?", "Body copy.", "v1.a.b");

  assert.match(page, /<form method="post" action="\/api\/unsubscribe\?token=/);
  assert.match(page, /v1\.a\.b/);
  assert.match(page, /<button type="submit"/);
});

test("unsubscribe result page has no confirmation form", () => {
  const page = renderUnsubscribePage("You're unsubscribed.", "Body copy.");

  assert.doesNotMatch(page, /<form/);
  assert.match(page, /You&#39;re unsubscribed\./);
});

test("unsubscribe page escapes injected content", () => {
  const page = renderUnsubscribePage(
    "<script>alert('x')</script>",
    "<img onerror=alert(1)>"
  );

  assert.doesNotMatch(page, /<script>/);
  assert.doesNotMatch(page, /<img/);
});

test("unsubscribe page keeps crawlers out", () => {
  assert.match(
    renderUnsubscribePage("Heading", "Body."),
    /<meta name="robots" content="noindex"/
  );
});

// =============================================================================
// Preference Gate
// =============================================================================

test("unsubscribing blocks further lifecycle email sends", () => {
  const preferences = buildNextCommunicationPreferences(
    {},
    {lifecycleEmailsEnabled: false},
    stubTimestamp(1000)
  );

  assert.equal(isLifecycleEmailAllowed(preferences), false);
});

test("resubscribing re-opens lifecycle email sends", () => {
  const unsubscribed = buildNextCommunicationPreferences(
    {},
    {lifecycleEmailsEnabled: false},
    stubTimestamp(1000)
  );
  const resubscribed = buildNextCommunicationPreferences(
    unsubscribed,
    {lifecycleEmailsEnabled: true},
    stubTimestamp(2000)
  );

  assert.equal(isLifecycleEmailAllowed(resubscribed), true);
});

// =============================================================================
// Website Host Config
// =============================================================================

const VALID_CONFIG = {
  provider: "resend",
  apiKey: "re_test",
  fromEmail: "hello@updates.ascendstepper.com",
  fromName: "Ascend",
  unsubscribeSigningKey: SIGNING_KEY,
  websiteUrl: "https://staging.ascendstepper.com",
};

test("the configured host drives customer-facing email links", () => {
  withTransactionalEmailConfig(VALID_CONFIG, () => {
    assert.equal(
      getMarketingWebsiteUrl(),
      "https://staging.ascendstepper.com"
    );
  });
});

test("a secret missing websiteUrl fails loudly", () => {
  // Guessing the production host would point a staging link, signed with the
  // staging key, at the production endpoint that cannot verify it.
  withTransactionalEmailConfig(
    {...VALID_CONFIG, websiteUrl: undefined},
    () => assert.throws(() => getMarketingWebsiteUrl(), /websiteUrl/)
  );
});

test("a non-https websiteUrl fails loudly", () => {
  withTransactionalEmailConfig(
    {...VALID_CONFIG, websiteUrl: "http://ascendstepper.com"},
    () => assert.throws(() => getMarketingWebsiteUrl(), /websiteUrl/)
  );
});

test("render paths with no secret fall back to the marketing host", () => {
  withTransactionalEmailConfig(undefined, () => {
    assert.equal(getMarketingWebsiteUrl(), DEFAULT_MARKETING_WEBSITE_URL);
  });
});

// =============================================================================
// Send Precondition
// =============================================================================

test("a valid secret passes the send precondition", () => {
  withTransactionalEmailConfig(VALID_CONFIG, () => {
    assert.doesNotThrow(() => assertTransactionalEmailConfig());
  });
});

test("a mis-ordered deploy trips the send precondition", () => {
  // The tripwire the required fields exist for: a sender checks this before
  // claiming work, so a bad secret fails the run instead of quietly
  // delivering nothing.
  for (const broken of [
    {...VALID_CONFIG, unsubscribeSigningKey: undefined},
    {...VALID_CONFIG, unsubscribeSigningKey: "too-short"},
    {...VALID_CONFIG, websiteUrl: undefined},
    {...VALID_CONFIG, apiKey: undefined},
  ]) {
    withTransactionalEmailConfig(broken, () => {
      assert.throws(
        () => assertTransactionalEmailConfig(),
        /TRANSACTIONAL_EMAIL_CONFIG/
      );
    });
  }
});

// =============================================================================
// Send-Time Preference Gate
// =============================================================================

test("a job unsubscribed after queueing is suppressed", async () => {
  // The queue-time gate cannot cover this: a retrying job backs off for hours,
  // and the unsubscribe click lands in that window.
  const suppressed = await isEmailJobSuppressed(
    {recipientUid: "user_123"},
    async () => ({lifecycleEmailsEnabled: false})
  );

  assert.equal(suppressed, true);
});

test("a job for a still-subscribed user sends", async () => {
  const suppressed = await isEmailJobSuppressed(
    {recipientUid: "user_123"},
    async () => ({lifecycleEmailsEnabled: true})
  );

  assert.equal(suppressed, false);
});

test("a job for a user who never chose is suppressed", async () => {
  // The send-time gate has to reach the same verdict as the queue-time one:
  // an unrecorded answer is not permission at either end of the queue.
  const suppressed = await isEmailJobSuppressed(
    {recipientUid: "user_123"},
    async () => null
  );

  assert.equal(suppressed, true);
});

test("mail with no recipient uid sends unconditionally", async () => {
  // Admin feedback notifications are not user mail, so they carry no uid to
  // gate on.
  let readCount = 0;
  const suppressed = await isEmailJobSuppressed(
    {recipientUid: null},
    async () => {
      readCount += 1;
      return {lifecycleEmailsEnabled: false};
    }
  );

  assert.equal(suppressed, false);
  assert.equal(readCount, 0);
});

test("a failed preference read never falls through to a send", async () => {
  // The job must stay claimed for reclaim and retry rather than being
  // delivered on a transient Firestore error.
  await assert.rejects(
    () => isEmailJobSuppressed(
      {recipientUid: "user_123"},
      async () => {
        throw new Error("firestore_unavailable");
      }
    ),
    /firestore_unavailable/
  );
});

// =============================================================================
// Communication Preference Merge (E6)
// =============================================================================

test("changing an email preference preserves the push preference", () => {
  // Regression: the preferences document is shared with
  // updatePushNotificationPreferences, so a non-merging write here would
  // silently opt the user out of climb-drop push notifications.
  const existing = {
    createdAt: stubTimestamp(500),
    pushClimbDropsEnabled: true,
    schemaVersion: 1,
  };

  const next = buildNextCommunicationPreferences(
    existing,
    {lifecycleEmailsEnabled: false},
    stubTimestamp(1000)
  );

  assert.equal(next.pushClimbDropsEnabled, true);
  assert.equal(next.lifecycleEmailsEnabled, false);
});

test("communication preferences keep the original createdAt", () => {
  const createdAt = stubTimestamp(500);
  const now = stubTimestamp(1000);
  const next = buildNextCommunicationPreferences(
    {createdAt, pushClimbDropsEnabled: false},
    {lifecycleEmailsEnabled: false},
    now
  );

  assert.equal(next.createdAt, createdAt);
  assert.equal(next.updatedAt, now);
});

test("communication preferences stamp createdAt on first write", () => {
  const now = stubTimestamp(1000);
  const next = buildNextCommunicationPreferences(
    {},
    {lifecycleEmailsEnabled: false},
    now
  );

  assert.equal(next.createdAt, now);
  assert.equal(next.schemaVersion, 1);
});

test("only the app's own consent sources are accepted", () => {
  assert.equal(isAppLifecycleEmailConsentSource("onboarding"), true);
  assert.equal(isAppLifecycleEmailConsentSource("settings"), true);
  // A client may not claim the unsubscribe link made the decision, nor write
  // free text into a field Ascend means to rely on as evidence.
  assert.equal(isAppLifecycleEmailConsentSource("email_link"), false);
  assert.equal(isAppLifecycleEmailConsentSource("whatever they like"), false);
  assert.equal(isAppLifecycleEmailConsentSource(true), false);
  assert.equal(isAppLifecycleEmailConsentSource(undefined), false);
});

test("unsubscribing records where the decision was made", () => {
  const now = stubTimestamp(1000);
  const next = buildNextCommunicationPreferences(
    {},
    {
      lifecycleEmailsEnabled: false,
      lifecycleEmailsSource: "email_link",
      unsubscribedAt: now,
      unsubscribedVia: "email_link",
    },
    now
  );

  assert.equal(next.lifecycleEmailsSource, "email_link");
  assert.equal(next.lifecycleEmailsDecidedAt, now);
  assert.equal(isLifecycleEmailAllowed(next), false);
});

test("a consent decision is stamped with when it was made", () => {
  // beehiiv can ask for the timestamp behind an address. updatedAt cannot
  // answer it: every other writer of this shared document moves that field.
  const now = stubTimestamp(1000);

  const next = buildNextCommunicationPreferences(
    {},
    {lifecycleEmailsEnabled: true, lifecycleEmailsSource: "onboarding"},
    now
  );

  assert.equal(next.lifecycleEmailsDecidedAt, now);
  assert.equal(next.lifecycleEmailsSource, "onboarding");
});

test("an unrelated preference write does not restamp the consent record", () => {
  // Turning climb-drop push on says nothing about email, so it must not look
  // like the climber re-answered the email question today.
  const decidedAt = stubTimestamp(1000);
  const existing = buildNextCommunicationPreferences(
    {},
    {lifecycleEmailsEnabled: true},
    decidedAt
  );

  const later = stubTimestamp(5000);
  const next = buildNextCommunicationPreferences(
    existing,
    {pushClimbDropsEnabled: true},
    later
  );

  assert.equal(next.lifecycleEmailsDecidedAt, decidedAt);
  assert.equal(next.updatedAt, later);
});

test("communication preferences only change the supplied keys", () => {
  const next = buildNextCommunicationPreferences(
    {climbDropEmailsEnabled: true, lifecycleEmailsEnabled: true},
    {lifecycleEmailsEnabled: false},
    stubTimestamp(1000)
  );

  assert.equal(next.climbDropEmailsEnabled, true);
  assert.equal(next.lifecycleEmailsEnabled, false);
});

/**
 * Builds a fixed Timestamp for pure preference merging.
 * @param {number} millis - Millisecond value
 * @return {Timestamp} Firestore timestamp
 */
function stubTimestamp(millis: number): Timestamp {
  return Timestamp.fromMillis(millis);
}

/**
 * Runs a body with a specific transactional email secret in place.
 * @param {unknown} config - Secret payload, or undefined to leave it unset
 * @param {Function} body - Test body
 */
function withTransactionalEmailConfig(
  config: unknown,
  body: () => void
): void {
  const original = process.env.TRANSACTIONAL_EMAIL_CONFIG;
  if (config === undefined) {
    delete process.env.TRANSACTIONAL_EMAIL_CONFIG;
  } else {
    process.env.TRANSACTIONAL_EMAIL_CONFIG = JSON.stringify(config);
  }

  try {
    body();
  } finally {
    if (original === undefined) {
      delete process.env.TRANSACTIONAL_EMAIL_CONFIG;
    } else {
      process.env.TRANSACTIONAL_EMAIL_CONFIG = original;
    }
  }
}
