import test from "node:test";
import assert from "node:assert/strict";
import {
  buildEmailJobId,
  buildWaitlistWelcomeDedupeKey,
} from "../src/email/queue";
import {classifyResendStatus} from "../src/email/provider";
import {
  evaluateWaitlistRateLimit,
  extractRequesterIp,
  hashRateLimitIp,
} from "../src/email/rateLimit";
import {getNextRetryDelayMs} from "../src/email/retry";
import {
  renderFeedbackAdminNotifyEmail,
  renderWaitlistWelcomeEmail,
} from "../src/email/templates";

test("waitlist dedupe keys and job ids are deterministic", () => {
  const recipientHash = "abc123";
  const dedupeKey = buildWaitlistWelcomeDedupeKey(recipientHash);
  const jobId = buildEmailJobId(dedupeKey);

  assert.equal(dedupeKey, "waitlist-welcome:abc123");
  assert.equal(jobId, buildEmailJobId(dedupeKey));
});

test("retry schedule matches the waitlist welcome backoff policy", () => {
  assert.equal(getNextRetryDelayMs("waitlist_welcome", 1), 5 * 60 * 1000);
  assert.equal(getNextRetryDelayMs("waitlist_welcome", 2), 30 * 60 * 1000);
  assert.equal(getNextRetryDelayMs("waitlist_welcome", 3), 2 * 60 * 60 * 1000);
  assert.equal(
    getNextRetryDelayMs("waitlist_welcome", 4),
    12 * 60 * 60 * 1000
  );
  assert.equal(getNextRetryDelayMs("waitlist_welcome", 5), null);
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

test("rate limit helpers extract and hash requester IPs", () => {
  const requesterIp = extractRequesterIp(
    "203.0.113.1, 70.41.3.18",
    "10.0.0.1"
  );
  const hashedIp = hashRateLimitIp(requesterIp);

  assert.equal(requesterIp, "203.0.113.1");
  assert.equal(hashedIp.length, 64);
  assert.notEqual(hashedIp, requesterIp);
});

test("waitlist rate limit blocks the eleventh request in ten minutes", () => {
  let state = null;
  const nowMs = Date.parse("2026-03-24T12:00:00.000Z");

  for (let requestCount = 0; requestCount < 10; requestCount += 1) {
    const evaluation = evaluateWaitlistRateLimit(state, nowMs, "hash");
    assert.equal(evaluation.allowed, true);
    state = evaluation.state;
  }

  const blockedEvaluation = evaluateWaitlistRateLimit(state, nowMs, "hash");
  assert.equal(blockedEvaluation.allowed, false);
  assert.equal(blockedEvaluation.reason, "short_window");
});

test("waitlist template renders escaped html and text output", () => {
  const rendered = renderWaitlistWelcomeEmail({
    source: "<script>alert('xss')</script>",
  });

  assert.equal(rendered.subject, "You're on the Ascend waitlist");
  assert.match(rendered.html, /Visit ascendstepper\.com/);
  assert.match(
    rendered.html,
    /https:\/\/ascendstepper\.com\/images\/StairmasterIconAccent\.png/
  );
  assert.match(rendered.html, /https:\/\/ascendstepper\.com\/privacy/);
  assert.match(
    rendered.text,
    /Visit ascendstepper\.com: https:\/\/ascendstepper\.com/
  );
  assert.match(
    rendered.text,
    /Privacy Policy: https:\/\/ascendstepper\.com\/privacy/
  );
  assert.doesNotMatch(rendered.html, /landing_page|script/i);
  assert.doesNotMatch(rendered.text, /Signup source:/);
  assert.doesNotMatch(rendered.html, /Beta Open/);
});

test("waitlist template includes beta invite CTA when configured", () => {
  const originalConfig = process.env.TRANSACTIONAL_EMAIL_CONFIG;
  process.env.TRANSACTIONAL_EMAIL_CONFIG = JSON.stringify({
    provider: "resend",
    apiKey: "re_test",
    fromEmail: "hello@updates.ascendstepper.com",
    fromName: "Ascend",
    replyTo: "support@ascendstepper.com",
    websiteUrl: "https://ascendstepper.com",
    betaInviteUrl: "https://testflight.apple.com/join/ZZ1zUmBf",
  });

  try {
    const rendered = renderWaitlistWelcomeEmail({
      source: "landing_page",
    });

    assert.equal(
      rendered.subject,
      "You're in. Start testing Ascend on TestFlight"
    );
    assert.match(
      rendered.html,
      /START TESTING[\s\S]*TODAY\./
    );
    assert.match(
      rendered.html,
      /https:\/\/ascendstepper\.com\/images\/StairmasterIconAccent\.png/
    );
    assert.match(
      rendered.html,
      /https:\/\/testflight\.apple\.com\/join\/ZZ1zUmBf/
    );
    assert.doesNotMatch(rendered.html, /Beta Open/);
    assert.ok(
      rendered.text.includes(
        "Join the beta on TestFlight: " +
          "https://testflight.apple.com/join/ZZ1zUmBf"
      )
    );
  } finally {
    if (originalConfig === undefined) {
      delete process.env.TRANSACTIONAL_EMAIL_CONFIG;
    } else {
      process.env.TRANSACTIONAL_EMAIL_CONFIG = originalConfig;
    }
  }
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
