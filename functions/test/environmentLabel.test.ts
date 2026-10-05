import test from "node:test";
import assert from "node:assert/strict";
import {labelMessageForEnvironment} from "../src/email/environmentLabel";
import {renderEmailContentForJob} from "../src/email/catalog";
import {buildDropEmailPayload} from "../src/email/drops";
import type {EmailJobDocument} from "../src/email/types";

const message = {
  fromName: "Ascend",
  html: "<!doctype html><html><head></head>" +
    "<body style=\"margin:0;\"><p>Your week.</p></body></html>",
  subject: "Your week on the stair stepper",
  text: "Your week.",
};

test("production mail is sent exactly as it was rendered", () => {
  assert.deepEqual(labelMessageForEnvironment(message, undefined), message);
});

test("a test environment marks the sender, the subject and the body", () => {
  // The three places a reader looks: who it is from, the subject line, and
  // the first thing in the message.
  const labelled = labelMessageForEnvironment(message, "STAGING");

  assert.equal(labelled.fromName, "Ascend STAGING");
  assert.equal(labelled.subject, "[STAGING] Your week on the stair stepper");
  assert.match(labelled.text, /^\[STAGING TEST EMAIL\] Sent by Ascend's /);
  assert.match(labelled.text, /not the live app\.\n\nYour week\.$/);
  assert.match(labelled.html, /STAGING test email/);
  assert.match(labelled.html, /not the live app\./);
});

test("the banner is the first thing inside the body", () => {
  const labelled = labelMessageForEnvironment(message, "DEV");
  const bodyOpen = "<body style=\"margin:0;\">";
  const afterBody = labelled.html.slice(
    labelled.html.indexOf(bodyOpen) + bodyOpen.length
  );

  assert.ok(afterBody.startsWith("<table role=\"presentation\""));
  assert.ok(afterBody.indexOf("DEV test email") <
    afterBody.indexOf("Your week."));
  // Drawn once, and with a solid colour Outlook cannot drop.
  assert.equal(labelled.html.split("DEV test email").length - 1, 1);
  assert.match(labelled.html, /bgcolor="#F5A623"/);
});

test("a fragment with no body tag still gets the banner", () => {
  const labelled = labelMessageForEnvironment(
    {...message, html: "<p>Plain fragment.</p>"},
    "DEV"
  );

  assert.ok(labelled.html.indexOf("DEV test email") <
    labelled.html.indexOf("Plain fragment."));
});

test("every template family opens a body the banner can sit in", () => {
  // The banner is placed after <body>. A template without one would still
  // be marked, but ahead of its doctype - so hold each family to having one.
  const jobs: Array<Pick<EmailJobDocument, "payload" | "type">> = [
    {payload: {}, type: "rating_positive_followup"},
    {
      payload: {
        calendar: [],
        climbsCompleted: 2,
        ctaUrl: "https://apps.apple.com/app/id6757202987",
        earnedBadges: [],
        landmarksFinished: [],
        periodLabel: "Sep 28 - Oct 4, 2026",
        totalFloors: 599,
        totalSteps: 9578,
      },
      type: "weekly_recap_active",
    },
    {
      payload: buildDropEmailPayload(
        "halloween-2026",
        "https://ascendstepper.com"
      ),
      type: "drop_announcement",
    },
  ];

  for (const job of jobs) {
    const rendered = renderEmailContentForJob(job as EmailJobDocument, {
      unsubscribeUrl: "https://ascendstepper.com/api/unsubscribe?token=t",
    });
    const labelled = labelMessageForEnvironment(
      {fromName: "Ascend", ...rendered},
      "STAGING"
    );

    assert.match(
      labelled.html,
      /<body\b[^>]*><table role="presentation"[^>]*bgcolor="#F5A623"/,
      job.type
    );
    assert.equal(labelled.subject, `[STAGING] ${rendered.subject}`, job.type);
  }
});
