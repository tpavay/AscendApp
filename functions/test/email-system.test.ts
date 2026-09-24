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
  renderMonthlyRecapActiveEmail,
  renderMonthlyRecapActiveEmailFromPayload,
  renderMonthlyRecapInactiveEmail,
  renderOnboardingAbandonedAfterPaywallEmail,
  renderOnboardingAbandonedBeforePaywallEmail,
  renderRatingNegativeFeedbackEmail,
  renderRatingPositiveFollowupEmail,
  renderFeedbackAdminNotifyEmail,
  renderWeeklyRecapActiveEmail,
  renderWeeklyRecapActiveEmailFromPayload,
  renderWeeklyRecapInactiveEmail,
} from "../src/email/templates";
import type {
  EmailJobDocument,
  EmailJobPayload,
  EmailType,
} from "../src/email/types";

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
// Weekly / Monthly Recap Templates
// =============================================================================

const APP_STORE_TEST_URL = "https://apps.apple.com/app/id6757202987";

const baseWeeklyActivePayload = {
  calendar: [] as {dayOfMonth: number | null; level: "none"}[],
  climbsCompleted: 3,
  ctaUrl: APP_STORE_TEST_URL,
  landmarksFinished: [] as string[],
  periodLabel: "Sep 15 – Sep 21",
  totalFloors: 210,
  totalSteps: 8500,
};

test("weekly active recap states the period totals in past tense", () => {
  const rendered = renderWeeklyRecapActiveEmail(baseWeeklyActivePayload);

  assert.equal(rendered.subject, "Your week on the stair stepper");
  assert.match(rendered.text, /8,500 steps/);
  assert.match(rendered.text, /210 floors/);
  assert.match(rendered.text, /3 climbs completed/);
  assert.match(rendered.text, /Open Ascend: https:\/\/apps\.apple\.com/);
  assert.doesNotMatch(rendered.text, /Landmarks finished:/);
  assert.doesNotMatch(rendered.text, /Ranked:/);
  // Round 4: the captain removed the milestone-unlocked concept entirely.
  assert.doesNotMatch(rendered.text, /Milestone unlocked/i);
  assert.doesNotMatch(rendered.html, /Milestone unlocked/i);
  // Carried forward from the pre-redesign review: past tense, never present.
  assert.doesNotMatch(rendered.text, /this week/i);
});

test("weekly active recap surfaces deltas and streak", () => {
  const rendered = renderWeeklyRecapActiveEmail({
    ...baseWeeklyActivePayload,
    climbsDelta: {direction: "up", label: "vs last week", value: "1"},
    currentStreakWeeks: 3,
    floorsDelta: {direction: "up", label: "vs last week", value: "40"},
    landmarksFinished: ["Eiffel Tower", "Burj Khalifa"],
    stepsDelta: {direction: "up", label: "vs last week", value: "1,200"},
  });

  assert.match(rendered.text, /up 1,200 vs last week/);
  assert.match(rendered.text, /up 40 vs last week/);
  assert.match(rendered.text, /3-week streak/);
  assert.match(rendered.text, /Landmarks finished: Eiffel Tower, Burj Khalifa/);
  assert.match(rendered.html, /▲/);
});

test("weekly active recap leads with rank and percentile as the hero metric", () => {
  const rendered = renderWeeklyRecapActiveEmail({
    ...baseWeeklyActivePayload,
    fieldSize: 900,
    percentileBand: "Top 10%",
    rank: 42,
  });

  assert.match(rendered.text, /You ranked #42 of 900 climbers \(Top 10%\)/);
  assert.match(rendered.html, /You ranked/);
  assert.match(rendered.html, /#42 of 900 climbers/);
  assert.match(rendered.html, /Top 10%/);
  // The hero box appears before the stat grid's "Your week in review"
  // heading - it is the lead metric, not a footnote below the fold.
  const rankIndex = rendered.html.indexOf("You ranked");
  const reviewIndex = rendered.html.indexOf("Your week in review");
  assert.ok(rankIndex > 0 && reviewIndex > 0 && rankIndex < reviewIndex);
});

test("no rank callout at all for a field too small to mean anything", () => {
  const rendered = renderWeeklyRecapActiveEmail({
    ...baseWeeklyActivePayload,
    fieldSize: 1,
    rank: 1,
  });

  assert.doesNotMatch(rendered.text, /You ranked/);
  assert.doesNotMatch(rendered.html, /You ranked/);
});

test("a rank with no qualifying percentile band still shows the concrete rank", () => {
  const rendered = renderWeeklyRecapActiveEmail({
    ...baseWeeklyActivePayload,
    fieldSize: 1000,
    rank: 900,
  });

  assert.match(rendered.text, /You ranked #900 of 1000 climbers/);
  assert.doesNotMatch(rendered.text, /Top \d+%/);
});

test("achievements reuse the app's existing tracked achievement", () => {
  const rendered = renderWeeklyRecapActiveEmail({
    ...baseWeeklyActivePayload,
    achievementLabel: "Top 10 globally",
    fieldSize: 900,
    rank: 42,
  });

  assert.match(rendered.text, /Achievement earned: Top 10 globally/);
  assert.match(rendered.html, /Achievement earned/);
  assert.match(rendered.html, /Top 10 globally/);
});

test("no achievement callout without an earned achievement", () => {
  const rendered = renderWeeklyRecapActiveEmail(baseWeeklyActivePayload);
  assert.doesNotMatch(rendered.html, /Achievement earned/);
});

test("a podium rank uses the gold medal token, not the green accent", () => {
  const rendered = renderWeeklyRecapActiveEmail({
    ...baseWeeklyActivePayload,
    fieldSize: 50,
    percentileBand: "Top 5%",
    rank: 2,
  });
  assert.match(rendered.html, /#D4AF37/);
});

test("the hero title reads 'your week on the stair stepper'", () => {
  const rendered = renderWeeklyRecapActiveEmail(baseWeeklyActivePayload);
  assert.match(rendered.html, />YOUR WEEK</);
  assert.match(rendered.html, />ON THE STAIR STEPPER\.</);
});

test("weekly active recap escapes a landmark name in html", () => {
  const rendered = renderWeeklyRecapActiveEmail({
    ...baseWeeklyActivePayload,
    landmarksFinished: ["<script>alert('xss')</script>"],
  });

  assert.doesNotMatch(rendered.html, /<script>/);
  assert.match(rendered.html, /&lt;script&gt;/);
});

test("weekly active recap is dark-themed, not the light lifecycle layout", () => {
  const rendered = renderWeeklyRecapActiveEmail(baseWeeklyActivePayload);

  assert.match(rendered.html, /#000000/);
  assert.match(rendered.html, /color-scheme/);
  assert.doesNotMatch(rendered.html, /#f4f2eb/);
});

test("weekly active recap renders an activity calendar when cells are given", () => {
  const rendered = renderWeeklyRecapActiveEmail({
    ...baseWeeklyActivePayload,
    calendar: [
      {dayOfMonth: 15, level: "peak"},
      {dayOfMonth: 16, level: "active"},
      {dayOfMonth: 17, level: "none"},
      {dayOfMonth: 18, level: "none"},
      {dayOfMonth: 19, level: "none"},
      {dayOfMonth: 20, level: "none"},
      {dayOfMonth: 21, level: "none"},
    ],
  });

  assert.match(rendered.html, />Mo</);
  assert.match(rendered.html, />15</);
  assert.match(rendered.html, /Peak day/);
  assert.match(rendered.html, /No activity/);
});

test("weekly active payload renderer requires the numeric fields", () => {
  assert.throws(
    () => renderWeeklyRecapActiveEmailFromPayload({
      ctaUrl: APP_STORE_TEST_URL,
      periodLabel: "Sep 15 – Sep 21",
    } as unknown as EmailJobPayload),
    /invalid_weekly_recap_active_payload/
  );
});

test("weekly inactive recap states the real gap, gently, in past tense", () => {
  const rendered = renderWeeklyRecapInactiveEmail({
    ctaUrl: APP_STORE_TEST_URL,
    firstAscents: [],
    gapCount: 2,
    periodLabel: "Sep 15-21, 2026",
    suggestedClimbName: "Tokyo Skytree",
  });

  assert.equal(rendered.subject, "We missed you");
  assert.match(rendered.text, /We haven't seen you in 2 weeks\./);
  assert.match(rendered.text, /get back on the stair stepper/);
  assert.match(rendered.text, /Tokyo Skytree is open and ready\./);
  assert.match(rendered.text, /Open Ascend: https:\/\/apps\.apple\.com/);
  assert.doesNotMatch(rendered.text, /didn't climb|you missed|streak.*lost/i);
  assert.doesNotMatch(rendered.text, /on the board/i);
});

test("a one-week gap is singular, not '1 weeks'", () => {
  const rendered = renderWeeklyRecapInactiveEmail({
    ctaUrl: APP_STORE_TEST_URL,
    firstAscents: [],
    gapCount: 1,
    periodLabel: "Sep 15-21, 2026",
  });
  assert.match(rendered.text, /We haven't seen you in 1 week\./);
  assert.doesNotMatch(rendered.text, /1 weeks/);
});

test("weekly inactive recap omits the suggestion line without a climb", () => {
  const rendered = renderWeeklyRecapInactiveEmail({
    ctaUrl: APP_STORE_TEST_URL,
    firstAscents: [],
    gapCount: 2,
    periodLabel: "Sep 15-21, 2026",
  });

  assert.doesNotMatch(rendered.text, /is open and ready/);
});

test("first ascents are listed instead of a suggested climb when the climber holds any", () => {
  const rendered = renderWeeklyRecapInactiveEmail({
    ctaUrl: APP_STORE_TEST_URL,
    firstAscents: ["Eiffel Tower"],
    gapCount: 3,
    periodLabel: "Sep 15-21, 2026",
    suggestedClimbName: "Tokyo Skytree",
  });

  assert.match(rendered.text, /You hold the First Ascent of Eiffel Tower\./);
  // The generic suggestion is not also shown - one clear thing to look at.
  assert.doesNotMatch(rendered.text, /Tokyo Skytree is open and ready/);
});

test("multiple first ascents are all named", () => {
  const rendered = renderWeeklyRecapInactiveEmail({
    ctaUrl: APP_STORE_TEST_URL,
    firstAscents: ["Eiffel Tower", "Burj Khalifa"],
    gapCount: 3,
    periodLabel: "Sep 15-21, 2026",
  });

  assert.match(
    rendered.text,
    /You hold 2 First Ascents: Eiffel Tower, Burj Khalifa\./
  );
});

const baseMonthlyActivePayload = {
  ...baseWeeklyActivePayload,
  periodLabel: "September 2026",
};

test("monthly active recap states month totals in past tense", () => {
  const rendered = renderMonthlyRecapActiveEmail({
    ...baseMonthlyActivePayload,
    landmarksFinished: ["Space Needle"],
    stepsDelta: {direction: "up", label: "vs last month", value: "2,000"},
  });

  assert.equal(rendered.subject, "Your month on the stair stepper");
  assert.match(rendered.text, /8,500 steps/);
  assert.match(rendered.text, /Landmarks finished: Space Needle/);
  assert.match(rendered.text, /up 2,000 vs last month/);
  assert.doesNotMatch(rendered.text, /this month/i);
  assert.match(rendered.html, />YOUR MONTH</);
  assert.match(rendered.html, />ON THE STAIR STEPPER\.</);
});

test("monthly active payload renderer validates and renders", () => {
  const rendered = renderMonthlyRecapActiveEmailFromPayload(
    baseMonthlyActivePayload
  );
  assert.equal(rendered.subject, "Your month on the stair stepper");

  assert.throws(
    () => renderMonthlyRecapActiveEmailFromPayload({
      periodLabel: "September 2026",
    } as unknown as EmailJobPayload),
    /invalid_monthly_recap_active_payload/
  );
});

test("monthly inactive recap never guilt-trips a dormant climber", () => {
  const rendered = renderMonthlyRecapInactiveEmail({
    ctaUrl: APP_STORE_TEST_URL,
    firstAscents: [],
    gapCount: 3,
    periodLabel: "September 2026",
  });

  assert.equal(rendered.subject, "We missed you");
  assert.match(rendered.text, /We haven't seen you in 3 months\./);
  assert.doesNotMatch(rendered.text, /didn't climb|you missed|streak.*lost/i);
  assert.doesNotMatch(rendered.text, /this month/i);
  assert.doesNotMatch(rendered.text, /on the board/i);
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
