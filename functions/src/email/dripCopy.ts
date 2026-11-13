/**
 * THE WORDS OF THE LIFECYCLE DRIP EMAILS.
 *
 * DRAFT, AWAITING THE CAPTAIN'S EDIT. Every subject and sentence below was
 * written by an agent in the voice of the founder letter
 * (`docs/free-week-after-decline.md`) so there is something to react to. None
 * of it has been read or approved by the captain. Edit freely: this is the
 * only file that holds drip wording, and changing it touches no logic.
 *
 * Voice: first person from the founder, short, no exclamation marks, no hype,
 * no pressure.
 *
 * Mechanics you can rely on while editing:
 *   - `paragraphs` render in order as plain paragraphs.
 *   - `{chargeDate}` is the day the trial ends, in the climber's own time
 *     zone, e.g. "Saturday, November 21". Only the trial reminder has one.
 *   - `{price}` is `TRIAL_PRICE_LABEL`. It is a literal, not read from the App
 *     Store, so change it here whenever the welcome product's price changes
 *     in App Store Connect.
 *   - The greeting line ("Hi Tyler,") and the signature are added by the
 *     renderer; do not repeat them in `paragraphs`.
 *   - `linkLabel` is the words on the one link. The link itself is built in
 *     `lifecycleDripEmails.ts` (`https://ascendstepper.com/go?src=...`).
 *   - The footer (why they got it, Privacy Policy, Unsubscribe) is the shared
 *     shell's and is not edited here.
 *
 * Which email goes to whom, and when, is decided in
 * `lifecycleDripEmails.ts` and documented in `docs/lifecycle-drip-emails.md`.
 */

import type {EmailType} from "./types";

export type DripEmailType = Extract<
  EmailType,
  "drip_paywall_abandoned" | "drip_free_week_unused" | "drip_trial_reminder"
>;

export interface DripEmailCopy {
  /** Shown in the inbox beside the subject, before the email is opened. */
  preheader: string;
  subject: string;
  paragraphs: string[];
  linkLabel: string;
  /** The line under the paragraphs that says why the climber got this. */
  whyReceived: string;
}

/** What the welcome product costs after its free week. See the header note. */
export const TRIAL_PRICE_LABEL = "$9.99 for the first year";

export const DRIP_SIGNATURE = {
  name: "Tyler",
  role: "Founder, Ascend",
};

export const DRIP_EMAIL_COPY: Record<DripEmailType, DripEmailCopy> = {
  // Sent 2 hours after the first paywall appeared, to a climber who closed the
  // app there and has not come back: never saw the welcome offer or the
  // founder letter.
  drip_paywall_abandoned: {
    preheader: "A note from the founder, in case the first screen was all " +
      "you saw.",
    subject: "You left before the climb started",
    paragraphs: [
      "I'm Tyler, the founder of Ascend. You downloaded the app a couple of " +
        "hours ago and closed it on the first screen, before you saw " +
        "anything else.",
      "I built Ascend because the stair stepper is the best cardio there is " +
        "and no app treated it that way. Every workout is a climb up a real " +
        "tower, and it lands on that tower's leaderboard.",
      "There's more behind that first screen, and a note from me waiting " +
        "there. If you open Ascend again you'll find it.",
      "If it isn't for you, no hard feelings. You can unsubscribe below and " +
        "I won't write again.",
    ],
    linkLabel: "Open Ascend",
    whyReceived: "You get this because you chose to hear from Ascend when " +
      "you signed up.",
  },

  // Sent 24 hours after the free week started, to a climber who got in and has
  // not started a climb or logged a workout since.
  drip_free_week_unused: {
    preheader: "Your free week is running. Here is the easiest way to use it.",
    subject: "Your first climb is waiting",
    paragraphs: [
      "It's been a day since your free week started, and you haven't climbed " +
        "yet. That's fine. The first one is the hardest to start.",
      "Walk up to any stair stepper, put your headphones in and pick a " +
        "tower. Whatever you climb goes on that tower's leaderboard. No " +
        "headphones? You can type in a climb you already did.",
      "The week is yours to use however you like. If something got in the " +
        "way, reply to this email and tell me. I read every one.",
    ],
    linkLabel: "Open Ascend",
    whyReceived: "You get this because you chose to hear from Ascend when " +
      "you signed up.",
  },

  // Sent 24 hours before a 7-day free trial ends, ahead of the first charge.
  // Never sent to a climber who already cancelled the trial.
  drip_trial_reminder: {
    preheader: "A reminder, so you are never charged for something you did " +
      "not mean to keep.",
    subject: "A reminder about your Ascend trial",
    paragraphs: [
      "This is a reminder, nothing more. I hate forgetting about " +
        "subscriptions, and I don't want you to pay for something you don't " +
        "want.",
      "Your 7-day free trial ends on {chargeDate}. If you keep it, Apple " +
        "charges {price} on or just before that day, and it renews each " +
        "year until you cancel.",
      "To cancel, open the Settings app on your iPhone, tap your name, tap " +
        "Subscriptions, choose Ascend and tap Cancel Subscription. You keep " +
        "your access until the trial ends.",
      "If you want to keep climbing, you don't need to do anything.",
    ],
    linkLabel: "Open Ascend",
    whyReceived: "You get this because you chose to hear from Ascend, and " +
      "because your trial is about to end.",
  },
};
