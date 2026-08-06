import test from "node:test";
import assert from "node:assert/strict";
import {
  buildRatingPromptEmailDedupeKey,
  emailTypeForRatingPromptResponse,
} from "../src/email/automation";
import {isLifecycleEmailAllowed} from "../src/email/preferences";
import {buildEmailJobId} from "../src/email/queue";
import {
  emailTypeConfigs,
  renderEmailContentForJob,
} from "../src/email/catalog";
import {classifyResendStatus} from "../src/email/provider";
import {getNextRetryDelayMs} from "../src/email/retry";
import {
  renderFirstAscentClaimedEmail,
  renderFirstAscentClaimedEmailFromPayload,
  renderFirstClimbCompletedEmail,
  renderLeaderboardFirstPlaceEmail,
  renderOnboardingAbandonedAfterPaywallEmail,
  renderOnboardingAbandonedBeforePaywallEmail,
  renderRatingNegativeFeedbackEmail,
  renderRatingPositiveFollowupEmail,
  renderFeedbackAdminNotifyEmail,
} from "../src/email/templates";
import type {EmailJobDocument, EmailType} from "../src/email/types";

test("rating prompt email automation maps responses to email types", () => {
  assert.equal(
    emailTypeForRatingPromptResponse("yes"),
    "rating_positive_followup"
  );
  assert.equal(
    emailTypeForRatingPromptResponse("no"),
    "rating_negative_feedback"
  );
  assert.equal(emailTypeForRatingPromptResponse("maybe"), null);
});

test("rating prompt email automation uses one-send user dedupe", () => {
  const dedupeKey = buildRatingPromptEmailDedupeKey("user_123");

  assert.equal(dedupeKey, "rating-prompt-answer-email:user_123");
  assert.equal(buildEmailJobId(dedupeKey), buildEmailJobId(dedupeKey));
});

test("lifecycle email automation requires a recorded opt-in", () => {
  // A missing preference used to mean yes, so every address Ascend held was
  // one it could not evidence consent for. Silence is now a no.
  assert.equal(isLifecycleEmailAllowed(null), false);
  assert.equal(isLifecycleEmailAllowed({}), false);
  assert.equal(
    isLifecycleEmailAllowed({lifecycleEmailsEnabled: true}),
    true
  );
  assert.equal(
    isLifecycleEmailAllowed({lifecycleEmailsEnabled: false}),
    false
  );
});

test("a preference document about something else is not consent", () => {
  // The document is shared: a push preference write creates it without ever
  // asking the climber about email.
  assert.equal(
    isLifecycleEmailAllowed({pushClimbDropsEnabled: true, schemaVersion: 1}),
    false
  );
});

test("all email catalog entries use the standard retry policy", () => {
  const emailTypes = Object.keys(emailTypeConfigs) as EmailType[];

  assert.ok(emailTypes.length > 0);

  for (const emailType of emailTypes) {
    assert.equal(getNextRetryDelayMs(emailType, 1), 5 * 60 * 1000);
    assert.equal(getNextRetryDelayMs(emailType, 2), 30 * 60 * 1000);
    assert.equal(getNextRetryDelayMs(emailType, 3), 2 * 60 * 60 * 1000);
    assert.equal(getNextRetryDelayMs(emailType, 4), 12 * 60 * 60 * 1000);
    assert.equal(getNextRetryDelayMs(emailType, 5), null);
  }
});

test("the rating-prompt producer's email types render through the queue", () => {
  const ratingPromptTypes: EmailType[] = [
    "rating_positive_followup",
    "rating_negative_feedback",
  ];

  for (const emailType of ratingPromptTypes) {
    const job = {
      payload: {},
      type: emailType,
    } as unknown as EmailJobDocument;
    const rendered = renderEmailContentForJob(job, {
      unsubscribeUrl: "https://ascendstepper.com/api/unsubscribe?token=abc",
    });

    assert.ok(rendered.subject.length > 0);
    assert.ok(rendered.text.length > 0);
    assert.match(rendered.html, /api\/unsubscribe\?token=abc/);
  }
});

// A queued job outlives the build that wrote it, so a type retired since then
// is still readable off Firestore. The render must name it rather than fault
// on an undefined catalog entry.
test("a job naming a retired email type fails by name", () => {
  const job = {
    payload: {source: "landing_page"},
    type: "waitlist_welcome",
  } as unknown as EmailJobDocument;

  assert.throws(
    () => renderEmailContentForJob(job),
    /unsupported_email_type:waitlist_welcome/
  );
});

// The two guards diverge on purpose. The render path throws so the job is
// marked invalid_payload and stops; the retry path returns null because a
// missing retry schedule means there is no next delay, and the caller already
// treats null as exhausted, so the job ends as a terminal failure rather than
// crashing the worker mid-batch.
test("the retry schedule for a retired email type is exhausted, not fatal", () => {
  const retiredType = "waitlist_welcome" as EmailType;

  assert.equal(getNextRetryDelayMs(retiredType, 1), null);
  assert.equal(getNextRetryDelayMs(retiredType, 5), null);
});

test("resend status classification distinguishes retryable failures", () => {
  assert.deepEqual(classifyResendStatus(429), {
    code: "resend_rate_limited",
    retryable: true,
  });
  assert.deepEqual(classifyResendStatus(503), {
    code: "resend_server_error",
    retryable: true,
  });
  assert.deepEqual(classifyResendStatus(400), {
    code: "resend_client_error_400",
    retryable: false,
  });
});

// =============================================================================
// App-Triggered Customer Templates
// =============================================================================

test("rating follow-up templates use reply-first founder copy", () => {
  const positive = renderRatingPositiveFollowupEmail();
  const negative = renderRatingNegativeFeedbackEmail();

  assert.equal(positive.subject, "Thanks for climbing with Ascend");
  assert.match(positive.text, /Tyler here/);
  assert.match(positive.text, /Reply with feedback: mailto:/);
  assert.match(positive.html, /href="mailto:/);
  assert.match(positive.text, /answered yes/);
  assert.doesNotMatch(positive.text, /rated the app/i);

  assert.equal(negative.subject, "Tell me what missed");
  assert.match(negative.text, /Ascend missed for you/);
  assert.match(negative.text, /Reply with what missed: mailto:/);
  assert.match(negative.html, /href="mailto:/);
  assert.match(negative.text, /answered no/);
  assert.doesNotMatch(negative.text, /rated the app/i);
});

test("onboarding templates render action CTAs and privacy footer", () => {
  const beforePaywall = renderOnboardingAbandonedBeforePaywallEmail({
    appUrl: "https://ascendstepper.com/app/onboarding/start",
  });
  const afterPaywall = renderOnboardingAbandonedAfterPaywallEmail({
    appUrl: "https://ascendstepper.com/app/climbs",
  });

  assert.equal(beforePaywall.subject, "Your first climb is waiting");
  assert.match(beforePaywall.text, /Start your first climb:/);
  assert.match(
    beforePaywall.html,
    /https:\/\/ascendstepper\.com\/app\/onboarding\/start/
  );
  assert.match(beforePaywall.text, /Privacy Policy:/);

  assert.equal(afterPaywall.subject, "Race real climbs");
  assert.match(afterPaywall.text, /Leaderboards, First Ascents/);
  assert.match(afterPaywall.text, /Start climbing:/);
  assert.match(
    afterPaywall.html,
    /https:\/\/ascendstepper\.com\/app\/climbs/
  );
});

test("first climb template renders optional climb name and result CTA", () => {
  const rendered = renderFirstClimbCompletedEmail({
    climbName: "Burj Khalifa",
    resultUrl: "https://ascendstepper.com/climbs/burj-khalifa/results/me",
  });

  assert.equal(rendered.subject, "First climb logged");
  assert.match(rendered.text, /Burj Khalifa/);
  assert.match(rendered.text, /View your result:/);
  assert.match(
    rendered.html,
    /https:\/\/ascendstepper\.com\/climbs\/burj-khalifa\/results\/me/
  );
});

test("achievement templates escape dynamic names in html", () => {
  const firstAscent = renderFirstAscentClaimedEmail({
    climbName: "K2 <script>alert('xss')</script>",
    climbUrl: "https://ascendstepper.com/climbs/k2",
  });
  const leaderboard = renderLeaderboardFirstPlaceEmail({
    leaderboardName: "Weekly <Top 100>",
    leaderboardUrl: "https://ascendstepper.com/leaderboards/weekly",
  });

  assert.equal(firstAscent.subject, "You claimed it first");
  assert.match(firstAscent.text, /You were first up K2/);
  assert.doesNotMatch(firstAscent.html, /<script>/);
  assert.match(firstAscent.html, /K2 &lt;script&gt;/);
  assert.match(firstAscent.html, /View the climb/);

  assert.equal(leaderboard.subject, "You own the board");
  assert.match(leaderboard.text, /You moved into #1 on Weekly/);
  assert.doesNotMatch(leaderboard.html, /Weekly <Top 100>/);
  assert.match(leaderboard.html, /Weekly &lt;Top 100&gt;/);
  assert.match(leaderboard.html, /Defend it/);
});

test("achievement payload renderers reject missing or unsafe urls", () => {
  assert.throws(
    () => renderFirstAscentClaimedEmailFromPayload({
      climbName: "Empire State Building",
      climbUrl: "javascript:alert('xss')",
    }),
    /invalid_first_ascent_claimed_payload/
  );
  assert.throws(
    () => renderFirstAscentClaimedEmailFromPayload({
      climbName: "",
      climbUrl: "https://ascendstepper.com/climbs/empire-state-building",
    }),
    /invalid_first_ascent_claimed_payload/
  );
});

// =============================================================================
// Feedback Admin Notification Template
// =============================================================================

const baseFeedbackPayload = {
  appVersion: "1.2.0",
  buildNumber: "42",
  deviceModel: "iPhone",
  feedbackId: "abc123",
  message: "The app crashes when I tap the leaderboard tab.",
  osVersion: "17.4",
  type: "bug_report",
  userEmail: "tester@example.com",
  userId: "uid_xyz",
};

test("feedback template renders correct subject per type", () => {
  const bugReport = renderFeedbackAdminNotifyEmail({
    ...baseFeedbackPayload,
    type: "bug_report",
  });
  assert.equal(bugReport.subject, "Ascend Feedback: Bug Report");

  const featureRequest = renderFeedbackAdminNotifyEmail({
    ...baseFeedbackPayload,
    type: "feature_request",
  });
  assert.equal(featureRequest.subject, "Ascend Feedback: Feature Request");

  const getHelp = renderFeedbackAdminNotifyEmail({
    ...baseFeedbackPayload,
    type: "get_help",
  });
  assert.equal(getHelp.subject, "Ascend Feedback: Help Request");
});

test("feedback template escapes html in user message and email", () => {
  const rendered = renderFeedbackAdminNotifyEmail({
    ...baseFeedbackPayload,
    message: "<script>alert('xss')</script>",
    userEmail: "user<evil>@test.com",
  });

  assert.doesNotMatch(rendered.html, /<script>/);
  assert.match(rendered.html, /&lt;script&gt;/);
  assert.doesNotMatch(rendered.html, /user<evil>/);
  assert.match(rendered.html, /user&lt;evil&gt;@test\.com/);
});

test("feedback template includes all device metadata", () => {
  const rendered = renderFeedbackAdminNotifyEmail(baseFeedbackPayload);

  assert.match(rendered.html, /iPhone/);
  assert.match(rendered.html, /17\.4/);
  assert.match(rendered.html, /1\.2\.0/);
  assert.match(rendered.html, /42/);
  assert.match(rendered.html, /abc123/);
  assert.match(rendered.html, /uid_xyz/);
});

test("feedback template plain text contains key fields", () => {
  const rendered = renderFeedbackAdminNotifyEmail(baseFeedbackPayload);

  assert.match(rendered.text, /Bug Report/);
  assert.match(rendered.text, /tester@example\.com/);
  assert.match(
    rendered.text,
    /The app crashes when I tap the leaderboard tab\./
  );
  assert.match(rendered.text, /iPhone/);
  assert.match(rendered.text, /17\.4/);
  assert.match(rendered.text, /1\.2\.0/);
  assert.match(rendered.text, /abc123/);
});

test("feedback template handles unknown type gracefully", () => {
  const rendered = renderFeedbackAdminNotifyEmail({
    ...baseFeedbackPayload,
    type: "unknown_type",
  });

  assert.equal(rendered.subject, "Ascend Feedback: unknown_type");
  assert.match(rendered.text, /unknown_type/);
});
