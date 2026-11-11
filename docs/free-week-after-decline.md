# Free week after decline

A climber who closes every paid offer at the app-access gate used to land on the native plan picker, whose only other ways out were deleting the account or signing out.
With `free_week_after_decline_enabled` on, that climber is shown a letter from the founder and let into the app for seven days instead, with nothing bought, nothing charged and nothing to cancel.

This is not an Apple introductory offer.
It is a server-granted access window: Apple, StoreKit and RevenueCat never hear about it.
`docs/superwall-paywall-setup.md` owns the paid products and their Apple trials; this document owns the free week.

## What a climber sees

1. Sign-in, then the app-access gate: the Superwall paywall on `app_access_gate` (the Lifetime design).
2. They close it. Superwall's `paywall_decline` campaign shows the welcome offer.
3. They close that too. The app registers the `founder_letter` placement and Superwall shows the letter.
4. They close the letter, by its button or its X. The app calls `startFreeWeek`, shows the gate's loading state until the server answers, and opens the app.

Nothing is tapped after step 4.
The week is already running when the main app appears.

Seven days later the gate comes back, and from then on the funnel is: Lifetime paywall, decline, welcome offer, decline, Lifetime paywall again.
The hosted paywall is the floor.
It carries its own Restore, `DELETE ACCOUNT` and Sign out controls, so Guideline 5.1.1(v) is still met from it, and declining it only reopens it.
Sign out (`sign_out`) is how a climber signed into the wrong account leaves it without deleting it: the native gate's own Sign Out is no longer reachable once the floor is the hosted paywall, and Firebase Auth survives a reinstall.
Ascend answers it exactly as it answers `DELETE ACCOUNT`, from the first paywall, the decline offer, the floor, and the letter alike, and a `sign_out` from the letter signs out rather than starting the week.
Paying at that paywall restores the account exactly as it was: nothing about the climber's data is tied to the week, and a lapsed account keeps its climbs, records and history (`docs/revenuecat-server-entitlement-enforcement.md`, "Backend choke points").

The native plan picker remains for two cases only:

- Superwall could not present the paid paywall at all (`skipped`, an error, or the 8-second opening deadline).
- The free week could not be started: `startFreeWeek` failed twice, the server refused because the rollout is off, or the account's record could not be read.
  The picker opens with its usual line, `No purchase was made. Choose a plan below.`, so nobody is left on a spinner.

A pending purchase still outranks everything.
A climber Apple may already have charged is told to wait, never offered a free week on top (`PendingPurchaseHoldStore`).

## The letter is a courtesy, the access is the promise

The founder letter is a Superwall-hosted paywall with no products, on its own placement, `founder_letter`.
The app never reads a choice out of how it closed: both of its controls are plain close actions, and every terminal outcome starts the week.
If Superwall cannot present it - no campaign, no audience match, an error, or the 8-second opening deadline - the week starts anyway.

The letter is shown once per account, because it is only ever registered for an account that has no `users/{uid}/trial/free_week` record, and starting the week writes that record.
An account whose week is spent never sees it again.
An account the server could not be asked about is not shown it either, because a letter saying "here's Ascend free for 7 days" to someone who already had their week is a promise the server will refuse to keep.

### What has to exist in Superwall

Built in the dashboard for staging and production, not by this repository:

- A campaign on the `founder_letter` placement, shown to everyone, presenting the letter paywall.
  The design reference and the founder photo live with the task that built this, not in the app bundle.
- The letter paywall has no products, a close action on `Start my free trial`, and a close X. No back arrow, no `No thanks` link, no `delete_account` control.
- **The `paywall_decline` campaign must not match a close of the letter.**
  Superwall fires `paywall_decline` when any registered placement's paywall is closed, the letter included, and today's welcome-offer campaign is shown to everyone.
  Left as it is, the welcome offer would open a second time when the letter closes.
  The app survives that - it waits for the chained screen to close and then starts the week - but it is a second sales screen between the letter and the app.
  Filter the decline campaign's audience to the `app_access_gate` placement.

Until that campaign exists the app still works: the registration is skipped and the week starts without the letter.

## Server contract

### Documents

| Path | Written by | Read by | Shape |
|---|---|---|---|
| `users/{uid}/trial/free_week` | `startFreeWeek` only | Its owner (rules), and every server path that writes or removes a grant | `schemaVersion`, `grantedAt`, `expiresAt` |
| `users/{uid}/entitlements/app_access` | `startFreeWeek`, the RevenueCat webhook, `reconcileAppAccess`, the expiry sweep | Nobody on a device; the rules check that it exists | The paid projection's fields, with `productId: "ascend_free_week"` and `source: "trial"` |

The record is the durable proof that an account was given its one week.
The grant is the document `firestore.rules` and `storage.rules` already require for every paid boundary, so a climber on their week can save climbs, read leaderboards and upload media exactly as a subscriber can, with no rule changed for them.

The record is owner-readable and nothing else about the week is, because the device needs one fact - is a week running - and the grant itself stays unreadable to every client.
The record holds two timestamps and no personal data.

### One invariant, four writers

Everything that writes or removes `entitlements/app_access` holds the same rule (`functions/src/revenueCat/freeWeek.ts`):

- RevenueCat says active: the paid grant.
- Otherwise, the free week is still running: the free week grant.
- Otherwise: no grant.

So:

- An inactive RevenueCat answer never takes a running week away.
  Inactive is the normal state of a climber on their week, and both the webhook and `reconcileAppAccess` used to delete the grant on it.
  `entitlement_status/app_access` still records what RevenueCat said.
- A purchase during the week replaces the free week grant with the paid one.
  The record stays, which is what refuses a second week later.
- A purchase refunded inside the week, or a paid grant that expires inside it, hands the rest of the week back rather than locking the climber out early.
- `expireRevenueCatEntitlements` removes the free week grant within five minutes of `accessUntil`, exactly as it removes a lapsed paid grant.

`functions/test/emulator/freeWeek.test.ts` proves each of these against real Firestore.

### `startFreeWeek`

An authenticated callable that reads nothing from the request.
The account is `request.auth.uid` and the window is the server clock plus seven days, so a modified client can supply neither.
The record and the grant are written in one transaction.

| Answer | When | Writes |
|---|---|---|
| `granted` | No record and no grant, or a record whose week is still running | First call: the record and the grant. Retry: nothing, unless the grant is missing, in which case it is put back |
| `already_used` | A record whose week is over, or a record that cannot be read | Nothing |
| `paid_active` | A grant that is not a free week | Nothing. The week is not spent |
| `disabled` | The rollout is off for everybody | Nothing |

A retried call inside the week returns the same week, which is what makes the app's one retry safe.

### Capacity and cost

The week costs one callable invocation and one transaction per account, once, ever: two document reads and two document writes.
After that it costs nothing until it ends, when the existing five-minute sweep deletes the grant in one more transaction.
There is no per-user scheduled work, no fan-out, no queue and no third-party call, so there is no ceiling on how many climbers can be on a week at once.

What does grow with the audience:

- The webhook and `reconcileAppAccess` each read one more document per projection (the record), with no extra write.
- The expiry sweep's budget is 200 grants a run, 288 runs a day, so it clears 57,600 expiries a day.
  A grant waiting behind a longer queue than that stays in place past its `accessUntil` until its turn; the app stops honouring the week on its own clock regardless, so the cost of a backlog is a paid boundary staying open on the server a little longer for a climber the app has already gated.
  Raise `EXPIRATION_BATCH_SIZE` if sign-ups ever approach that rate.
- The deploy preflight lists every live grant (`scripts/verify-functions-secrets.mjs`).
  It treats `ascend_free_week` as a server-granted product: never demanded of the RevenueCat allowlist, never reported as about to be lost because the allowlist lacks it, and still reported if it vanishes while its week is running.
- `startFreeWeek` reads the Remote Config template at most once a minute per function instance, not once per call, so the switch check does not turn sign-up volume into management-API traffic.

## The switch

`free_week_after_decline_enabled` is a rollout and ships off (`docs/remote-config-kill-switches.md`).

Off is the gate exactly as it was: a decline lands on the plan picker, the app registers no letter, reads no record, calls no function, and honours no week, a running one included.
That last part is deliberate.
The switch is the only undo an iOS binary has, so off has to stop the feature's routing as well as its grants.
Nothing is deleted: the server grant stays until it expires, and turning the switch back on honours whatever is left of a week.

The app and the server read the same parameter.
The app takes the value Remote Config resolved for that device, conditions included, so a staged rollout works.
The server cannot evaluate a condition, so it asks the one question it can: is the switch on for anybody.
Off everywhere is therefore a hard stop that reaches a build still holding a stale `true`.
A function that cannot read the template grants nothing, and logs `startFreeWeek could not read its Remote Config switch`.
It is the same template read `announceGearDrops` already makes every five minutes with the same runtime identity, which answered cleanly in staging on 2026-11-10 (`detectionError: null`), so no new IAM grant is expected; that log line is the thing to look for if every grant falls through to the plan picker.

## In the app

- `FreeWeekAccessStore` is the device's one answer, owned by `MonetizationManager` and handed every identity change.
  It caches a week it has been told about, so a running week opens the app with no network, and it reads the record once, with a deadline, when nothing is cached.
- `AppRootRouteResolver` treats a running week exactly as a paid entitlement for entry.
  A record that has not been read yet holds on `resolving` for the same reason an unknown entitlement does.
- `MonetizationManager.hasAppAccess` is true during the week, so the workout upload hold releases and climbs saved during the week reach the cloud.
- `AppAccessPaywallCoordinator.handlePaidOffersDeclined` is the one place a decline is decided.
- Settings, under Purchases, shows `Free trial, N days left` (`Free trial, 1 day left`) while a week is running.
  It is informational only: it cannot be tapped, opens nothing, and carries no disclosure chevron.
  Home shows nothing.

## Analytics

All four through `TelemetryManager`, each carrying `flow_version` (`v3` for the 1.3.0 onboarding).
The onboarding pass that led to the gate completes the moment the week lands, and a completed pass no longer says which flow it was, so the device that started a week remembers the flow beside its cached copy of the week.
The two events that arrive days later read it from there.

| Event | When | Properties |
|---|---|---|
| `free_week_letter_shown` | The founder letter reached the screen | `flow_version` |
| `free_week_granted` | The server started the week | `flow_version`, `letter_shown` |
| `free_week_expired_gated` | A climber whose week is over met the paywall. Once per account per device | `flow_version` |
| `free_week_purchase_completed` | Apple completed a purchase while the week was running | `flow_version`, `days_left` |

The production Mixpanel board (dashboard `11433611`) reads them from three cards placed after the onboarding v3 cards: a text card, the funnel `93958620` (letter shown, week granted, purchase during the week, `flow_version = v3` only) and the table `93958621` (all four events, every flow).
They stay at zero until the switch is on in production.

Also:

- `onboarding_flow_completed` reports `completion_reason: free_week` for a climber let in on the week.
- `app_access_gate_attempt_terminal` reports `provider_outcome: free_week_offered` when the letter is offered and `paywall_floor` when a spent week reopens the paywall, and `recovery_reason: free_week_unavailable` when the week could not be started.
  A `sign_out` from the hosted paywall reports `provider_outcome: sign_out_requested` with `recovery_reason: hosted_sign_out_requested`.
- The letter itself reports through `SuperwallEventRelay` like every hosted screen, as `sw_paywall_open` and `sw_paywall_close` with `placement: founder_letter`.
- The `has_app_access` user property still means a paid entitlement. A climber on their week reads `false`.

## Privacy

No new SDK, no new device data source and no App Privacy category.
The record is a server-written access status of the kind the privacy policy already describes under subscription status and entitlements, and it is deleted with the account: `accountCleanup` sweeps every subcollection under `users/{uid}`.

## Not done

- **One week per account, not per person or per device.**
  Deleting an account deletes its record, and a new account is a new week.
  Capping repeat weeks by device or by Apple ID is a follow-up, and needs a decision about what identifier Ascend is willing to keep after an account is deleted.
- **No reminder before the week ends.**
  `trial_ending_reminder_enabled` schedules a reminder for an Apple trial; the free week has none.
- **The letter is confirmed in tests, not against a live campaign.**
  The `founder_letter` campaign is built in the dashboard after this ships.
  Confirm on a staging device that the letter opens directly after the welcome offer closes, and that closing it opens the app.
