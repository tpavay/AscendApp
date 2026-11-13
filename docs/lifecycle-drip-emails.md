# Lifecycle drip emails

A short plain note from the founder, sent to a climber who stopped at one point in the first-week funnel.
Each email goes only for the furthest stage the climber reached, and is suppressed if they reached a later one.
The emails are built switched off: every sweep ships dark, and production does not deliver the types until the captain adds them to its secret.

Code: `functions/src/lifecycleDripEmails.ts` (the sweeps), `functions/src/email/dripEligibility.ts` (who is still right for it), `functions/src/email/dripTemplate.ts` (the plain renderer and the subject's day count), `functions/src/email/dripCopy.ts` (every word).
The queue, consent rule, worker, unsubscribe and sender are the existing email system (`.claude/skills/ascend-web-email`).

## The emails

| Email type | For | Default timing | Link source tag |
|---|---|---|---|
| `drip_paywall_abandoned` | The first paywall appeared and was never closed. The climber left before the welcome offer or the founder letter could open. | 2 hours after the paywall was shown | `email-paywall-abandoned` |
| `drip_free_week_unused` | The free week started, and the climber has not started a climb or logged a workout. | 24 hours after the week started | `email-free-week-unused` |
| `drip_trial_reminder` | On the 7-day free trial of the welcome product (`ascend_yearly_welcome`), not cancelled. | 24 hours before the trial ends | `email-trial-reminder` |

Every link is `https://ascendstepper.com/go?src=<tag>`.
There is no app deep link: `/go` opens the App Store listing.
`/go` does not yet read an `email-*` source, so these tags attribute nothing until `web/src/pages/go.astro` and `docs/social-bio-link.md` learn them.

A climber who got in through the founder letter gets no "your week ends tomorrow" email, by the captain's decision: the hard paywall is already waiting.

## What is NOT built, and the exact event each needs

The captain also asked for two more segments.
Neither can be built without guessing, because the event that defines it is not recorded anywhere the server can read.

1. **Saw the welcome offer, never saw the founder letter.**
   Needs: the decline offer's `paywall_shown`.
   Today it reaches analytics only (`SuperwallEventRelay`) and the device (`DeclineOfferReplayStore.shownKey`).
   `LifecycleEventRecorder.recordPaywallEvent` returns early for `decline_offer_replay`, and the SDK-chained offer is not a placement Ascend reports (`SuperwallPlacement(reportedByAscend:)` is nil for it), so `recordLifecycleEvent` never hears of it.
   The nearest recorded fact is `paywall_dismissed` on the first paywall, which is the close that makes the SDK chain the offer.
   That is a cause, not the event: with `free_week_after_decline_enabled` off, or the decline campaign not live, a close opens no offer, and an email promising a gift would be false.
2. **Saw the founder letter, never got into the app.**
   Needs: the letter's shown event.
   `LifecycleEventRecorder.recordPaywallEvent` drops `founder_letter` by design.
   No other recorded event tells this climber from one who got in: the v3 onboarding finishes before the paywall, and the week starts the moment the letter closes (`startFreeWeek` writes `users/{uid}/trial/free_week`), so a climber who closed the letter is already "in".
   Without the letter's shown event the two cannot be separated, so there is no separate email and no fold: the free-week email goes only to a climber whose week started.

Recording either needs a client change (a new `recordLifecycleEvent` placement allowed in `functions/src/lifecycle.ts`, written by `LifecycleEventRecorder`, and `AscendApp/Shared/Services/Lifecycle`), or a Superwall server webhook into a new Cloud Function.
Both are outside "server only, no app release", so they are follow-ups.

## Who is eligible, and when it is decided

The rules live in one function, `dripSuppressionReasonFor`, and run twice: when the sweep queues, and again in `processEmailJobs` right before it sends.
A job can sit queued or retrying while the climber moves on, so the worker's read is the one that counts.
A failed read throws, so a transient error can never deliver mail that should have been held back.

- `drip_paywall_abandoned` is suppressed by any access grant (a purchase, a comp, or the free week), by a free week record, or by a recorded close of the first paywall.
  The first paywall's own `paywall_shown_app_access_gate_v1` must exist.
- `drip_free_week_unused` needs a free week record whose week is still running.
  It is suppressed by a grant that is not the free week's (a purchase or comp) and by any saved workout or started headphone session (`users/{uid}/workouts`, `users/{uid}/attempt_heartbeats`).
- `drip_trial_reminder` needs the grant `users/{uid}/entitlements/app_access` the RevenueCat webhook projects (`docs/revenuecat-server-entitlement-enforcement.md`) to be a welcome-product grant that is not the free week, not past its end, and whose recorded renewal state is a trial that will renew: `periodType` `trial` and `willRenew` `true`.
  `willRenew` `false` means the climber cancelled the trial (or billing failed) and gets no reminder.
  Any other `periodType`, or either field null, means it converted, changed, or is not known, and fails closed.
  The queued trial end must still equal the grant's, so a moved end is skipped.

Both fields come from the RevenueCat subscriber the projection is built from (the subscription's `period_type`, `unsubscribe_detected_at` and `billing_issues_detected_at`), never from the event that triggered the write.
That is what keeps a cancellation through `reconcileAppAccess`: the app reconciles on launch and foreground while a cancelled trial is still active, and reconciliation writes `sourceEventType` `CLIENT_RECONCILIATION`, but it reads the same subscriber, so `willRenew` stays `false`.
It also carries a cancellation the webhook never delivered, because a change in either field counts as a change worth rewriting the projection for.
Neither field takes part in any access decision; the rules never read them.

A grant written before the projection recorded these fields falls back to its last projected event: `INITIAL_PURCHASE`, `UNCANCELLATION` or `CLIENT_RECONCILIATION` passes, `CANCELLATION` and anything else does not, and a grant document created more than 15 days before it expires cannot be a first trial.
The next webhook or reconciliation for that climber rewrites the grant with both fields.

Known limit: a cancellation RevenueCat itself has not yet seen when the worker sends is not seen.
The welcome trial is recognised by product id, so a product that carries a trial must be listed in `WELCOME_PRODUCT_IDS`.

## Consent, dedupe, delivery

Consent is the existing rule: only a recorded `lifecycleEmailsEnabled === true` (`enqueueLifecycleEmailIfAllowed`, and `isEmailJobSuppressed` at send time).
The dedupe key is `drip-email:{type}:{uid}`, with no date in it, so each account gets each email once for life.
The sweep checks for the job document before reading anything else, so a climber who stays inside the window across several runs costs one read.

The sender, the signed unsubscribe link and the environment label are the existing ones: the renderer only draws the page, and `sendTransactionalEmail` adds the headers and the label.
Staging's `enabledEmailTypes` is `"all"`, so staging delivers all three to the captain's test accounts once their switches are on.
**Production's `enabledEmailTypes` does not list them, and must not until the captain approves a new `TRANSACTIONAL_EMAIL_CONFIG` secret version** (`docs/functions-secret-versions.md`).
Until then a production sweep that someone turned on queues jobs that the worker marks `skipped`, terminally, so they can never arrive late the day the type is enabled.

## Remote Config

All six parameters are read by the Cloud Function from the template, never by the app.
Each is a switch that ships `false`, or a number in hours.
A template that cannot be read sends nothing.

| Parameter | Type | Ships | Meaning |
|---|---|---|---|
| `lifecycle_email_paywall_abandoned_enabled` | rollout | `false` | Opens the first-paywall sweep. Also needs `free_week_after_decline_enabled`, because the copy promises a note and an offer that only exist with that rollout. |
| `lifecycle_email_paywall_abandoned_delay_hours` | number | `2` | Hours after the first paywall appeared. |
| `lifecycle_email_free_week_unused_enabled` | rollout | `false` | Opens the free-week sweep. Also needs `free_week_after_decline_enabled`. |
| `lifecycle_email_free_week_unused_delay_hours` | number | `24` | Hours after the free week started. |
| `lifecycle_email_trial_reminder_enabled` | rollout | `false` | Opens the trial reminder sweep. |
| `lifecycle_email_trial_reminder_lead_hours` | number | `24` | Hours before the trial ends. A trial with under 2 hours left is not reminded. |

A delay outside 15 minutes to 14 days, or one that is not a number, is a typo and falls back to its default.
`scripts/lib/remote-config-template.mjs` lists them in `SERVER_ONLY_PARAMETERS`: no Swift catalog names them, so the template parity check exempts exactly those keys, and `functions/test/lifecycleDripEmails.test.ts` fails if `readDripSettings` stops acting on one.
Merging to `develop` publishes them additively to dev and staging; production is a publish by hand, and none of the switches is on there.

## Windows and cost

The sweep runs every 15 minutes and reads a bounded window per segment:

- first paywall: `lifecycle_events` collection-group, `eventDocId == paywall_shown_app_access_gate_v1`, `createdAt` between `now - delay - 6h` and `now - delay`;
- free week: `trial` collection-group, `grantedAt` in the same window;
- trial: `entitlements` collection-group, `productId in (welcome products)` and `accessUntil` between `now + 2h` and `now + lead`.

The 6-hour lateness bound means a sweep that was down, or a switch turned on late, never emails someone about a moment from days ago.
Indexes are in `firestore.indexes.json` (two composites and a `trial.grantedAt` field override); they deploy before the function does.
Each segment is paged and bounded, and logs `lifecycleDripEmails.scanTruncated` at error level if the bound is hit.

## The look

The reference is a plain newsletter-style note, which the captain preferred to the earlier centered serif letter (restyled 2026-11-13).
It is one left-aligned column, 520px wide at most, in Arial/Helvetica/sans-serif at 14px with a line height of 1.5.
Each idea is its own paragraph with a 1.2em gap, so most paragraphs are one sentence, and only things that belong together share one.
A short list is a real bulleted list (`-` lines in the plain-text part).
The link is a plain text link on its own line, then the signature, then the small grey footer with why they got it, Privacy Policy and Unsubscribe.
No images, no buttons, no template chrome.
Only the three drip emails use this renderer; every other email type keeps its own.

## Editing the words

Every subject and sentence is in `functions/src/email/dripCopy.ts`, in the wording the captain approved.
It holds no logic.
A block is a string (one paragraph) or `{bullets: [...]}`.
`{chargeDate}` and `{trialEndsIn}` are the only placeholders, and only the trial reminder has them.

The trial reminder says nothing about price, renewal, how to cancel or what to do: only that the 7-day free trial ends on the date, then one friendly closing line (the alternative, "There are plenty of new features on the way.", sits in a code comment beside it).
Its subject is `Reminder: your Ascend trial ends tomorrow`, computed at render time.
`{trialEndsIn}` counts calendar days between now and the trial end in the climber's own time zone (America/Chicago when none is recorded), so it agrees with the date in the body: `tomorrow` for one day, `in N days` for more, `today` for none or a late send.
No line may name how long ago something happened, because the delays above are Remote Config numbers.

## Follow-ups, not built

- Record the decline offer's shown event and the letter's shown event, then add the two missing emails (see above).
- Teach `/go` the `email-*` source tags.
- Production: a pinned `TRANSACTIONAL_EMAIL_CONFIG` version listing the types the captain chooses, then the switches.
