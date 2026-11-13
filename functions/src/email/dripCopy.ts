/**
 * THE WORDS OF THE LIFECYCLE DRIP EMAILS.
 *
 * Approved by the captain. Every subject and sentence below is the captain's
 * final wording for all three emails. This is the only file that holds drip
 * wording, and changing it touches no logic.
 *
 * Voice: first person from the founder, short, no exclamation marks, no hype,
 * no pressure.
 *
 * Mechanics you can rely on while editing:
 *   - `blocks` render in order, one idea per block. A string is a paragraph
 *     with a gap above and below it; `{bullets: [...]}` is a short bulleted
 *     list. Put each idea on its own line, and group only what belongs
 *     together.
 *   - `{chargeDate}` is the day the trial ends, in the climber's own time
 *     zone, e.g. "Saturday, November 21". Only the trial reminder has one.
 *   - `{trialEndsIn}` is "today", "tomorrow" or "in N days", counted in
 *     calendar days in the climber's own time zone at the moment the email is
 *     rendered, so it is never a wrong number. It works in the subject, the
 *     preheader and the blocks, and only the trial reminder has one.
 *   - The greeting line ("Hi Tyler,") and the signature are added by the
 *     renderer; do not repeat them in `blocks`.
 *   - `linkLabel` is the words on the one link, drawn on its own line. The
 *     link itself is built in `lifecycleDripEmails.ts`
 *     (`https://ascendstepper.com/go?src=...`).
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

/** A paragraph, or a short bulleted list. */
export type DripBlock = string | {bullets: string[]};

export interface DripEmailCopy {
  /** Shown in the inbox beside the subject, before the email is opened. */
  preheader: string;
  subject: string;
  blocks: DripBlock[];
  linkLabel: string;
  /** The line under the paragraphs that says why the climber got this. */
  whyReceived: string;
}

export const DRIP_SIGNATURE = {
  name: "Tyler",
  role: "Founder, Ascend",
};

export const DRIP_EMAIL_COPY: Record<DripEmailType, DripEmailCopy> = {
  // Sent after the first paywall appeared, to a climber who closed the app
  // there and has not come back: never saw the welcome offer or the founder
  // letter. The delay is a Remote Config number, so no line here may name how
  // long ago it was.
  drip_paywall_abandoned: {
    preheader: "A note from the founder, in case the first screen was all " +
      "you saw.",
    subject: "A quick note from the founder of Ascend",
    blocks: [
      "I'm Tyler, the founder of Ascend.",
      "I noticed you downloaded the app recently, but closed out before " +
        "getting past the first screen.",
      "I built Ascend because the stair stepper is the best cardio there " +
        "is, yet no app actually treated it that way. Before Ascend, I had " +
        "to log every workout by hand, and I always climbed alone.",
      "Now, your steps track automatically through your headphones, and " +
        "you have global leaderboards and a real community to race against.",
      "There is a lot more behind that first screen, including a welcome " +
        "gift I left waiting for you. Open Ascend back up to claim it and " +
        "take a look around.",
      "If it isn't for you, no hard feelings at all. You can unsubscribe " +
        "below and I won't write again.",
    ],
    linkLabel: "Open Ascend",
    whyReceived: "You get this because you chose to hear from Ascend when " +
      "you signed up.",
  },

  // Sent after the free week started, to a climber who got in and has not
  // started a climb or logged a workout since. The delay is a Remote Config
  // number, so no line here may say how many days it has been.
  drip_free_week_unused: {
    preheader: "Thanks for downloading Ascend. Your free week is running.",
    subject: "Your first climb is waiting",
    blocks: [
      "Thanks for downloading Ascend and starting your free week.",
      "I love the stair stepper, and I built this app to make your " +
        "sessions easier to track and a lot more fun. Here is how to get " +
        "the most out of your week:",
      {
        bullets: [
          "Hands-free tracking: Ascend counts your steps automatically " +
            "using compatible headphones.",
          "Flexible logging: No headphones? You can import workouts " +
            "straight from Apple Health or log them manually.",
          "Real competition: Every session is saved so you can track your " +
            "personal bests, climb real towers, and compete against " +
            "climbers around the world.",
        ],
      },
      "Your first climb is waiting whenever you're ready.",
    ],
    linkLabel: "Open Ascend",
    whyReceived: "You get this because you chose to hear from Ascend when " +
      "you signed up.",
  },

  // Sent before a 7-day free trial ends, ahead of the first charge. Never sent
  // to a climber who already cancelled the trial. The captain asked for no
  // price, no renewal text, no cancel steps and no "nothing to do" line.
  drip_trial_reminder: {
    preheader: "Your 7-day free trial ends {trialEndsIn}.",
    subject: "Reminder: your Ascend trial ends {trialEndsIn}",
    blocks: [
      "I hate forgetting about subscriptions, and I don't want you to pay " +
        "for something you don't want.",
      "Your 7-day free trial ends on {chargeDate}.",
      // Alternative closing line: "There are plenty of new features on the
      // way."
      "I hope to see you on the leaderboards.",
    ],
    linkLabel: "Open Ascend",
    whyReceived: "You get this because you chose to hear from Ascend, and " +
      "because your trial is about to end.",
  },
};
