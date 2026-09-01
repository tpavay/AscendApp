# Subscription Paywall Setup

Last verified: July 28, 2026

This file is the authoritative repository guide for Ascend's launch subscription configuration.
The repo-controlled contract is enforced by `scripts/test/subscription-launch-offer.test.mjs`.
Server-side enforcement, RevenueCat webhook setup, App Store Server Notification URLs, and the required vendor actions are owned by `docs/revenuecat-server-entitlement-enforcement.md`.

## Launch Offer

Both auto-renewing products unlock the same RevenueCat entitlement.

| Plan | Product identifier | Billing | Trial |
|---|---|---|---|
| Annual | `ascend_yearly` | `$49.99/year` | Seven days, then annual billing |
| Monthly | `ascend_monthly` | `$9.99/month`, charged immediately | None |

RevenueCat must use:

- Entitlement: `app_access`
- Current offering: `default`
- Annual package: `$rc_annual` containing `ascend_yearly`
- Monthly package: `$rc_monthly` containing `ascend_monthly`

The self-hosted Superwall paywall must bind `ascend_yearly` to product reference `yearly` and `ascend_monthly` to product reference `monthly`.

Staging and Release builds audit their configured catalog once per launch against the live RevenueCat offerings (`RevenueCatEntitlementService`).
A missing offering or product logs an error and emits the `monetization_offering_mismatch` telemetry event to Analytics and Crashlytics, so treat that event as a dashboard misconfiguration in the corresponding environment rather than a client bug.
Serving a different current offering is an experiment, not a failure, and is only logged.

The launch product IDs come from the `ASCEND_REVENUECAT_YEARLY_PRODUCT_ID` and `ASCEND_REVENUECAT_MONTHLY_PRODUCT_ID` build settings.
Staging audits `ascend_staging_yearly` and `ascend_staging_monthly`; Release audits `ascend_yearly` and `ascend_monthly`.

There is no weekly launch product and no separate discounted launch offer.
Do not add either to a Superwall campaign, Hosting content, or release checklist.

## Verified Vendor State

The July 27, 2026 audit used authenticated RevenueCat, App Store Connect, and Superwall sessions.

- App Store Connect reports `ascend_yearly` as a one-year subscription at `$49.99` in the United States with a one-week introductory trial.
- App Store Connect reports `ascend_monthly` as a one-month subscription at `$9.99` in the United States with no trial offer.
- Both App Store products are `READY_TO_SUBMIT`.
- RevenueCat has both products active and attached to `app_access`.
- RevenueCat offering `default` is current, with annual first and monthly second.
- RevenueCat has no third launch product.
- Superwall application `47442` is linked to Apple App ID `6757202987` and bundle ID `com.TylerPavay.AscendApp`.
- Superwall has imported only `ascend_yearly` and `ascend_monthly` for this launch surface, with the same prices and trial periods shown above.
- Superwall campaign `91861`, `App Access Gate V2`, targets `app_access_gate` and assigns paywall `232372` to 100 percent of its audience.
- The verified paywall `232372` draft defaults to Annual and switches its headline, CTA, and legal disclosure to immediate monthly purchase language when Monthly is selected.
- The paywall benefits include `Compete on global leaderboards` and contain no personalized-plan claim.
- The landmark benefit carries no hardcoded count. `benefit_1` ships as `Choose from real landmarks to climb` and the page resolves the number at runtime from `/climbs/manifest.json` and the catalogue it names, keyed on `catalogVersion`, so a curated catalogue cannot leave a stale promise behind. A failed fetch leaves the count-free copy standing. Never type a landmark count into the Superwall editor override for `benefit_1` - it would outlive the next catalogue change.
- The retired discount paywall `232373` is archived and is not attached to the active campaign.

The native purchase controller receives the StoreKit 2 product from Superwall and passes it to RevenueCat.
Keep localized native prices sourced from that StoreKit product.
Do not replace native StoreKit pricing with repository-hardcoded localized assumptions.

Superwall now recognizes the Apple App ID, but both imported products remain `Incomplete` because their App Store Connect state is only `READY_TO_SUBMIT`.
Superwall presented an invalid-product warning before publishing the verified paywall revision.
Do not bypass that warning.
After the first app version and both subscriptions complete the required App Store submission step, recheck the product status and publish paywall `232372`.

## Environment Split

RevenueCat and Superwall keys are selected per build configuration through `ASCEND_REVENUECAT_API_KEY` and `ASCEND_SUPERWALL_API_KEY`.
Access bypass, Superwall test mode, and launch product IDs are also explicit build settings.
The values reach the app through `Info.plist` substitution.

| Environment | Build configuration | Bundle ID | Monetization keys |
|---|---|---|---|
| Dev | `Debug` | `com.TylerPavay.AscendApp.dev` | Unset; no vendor project selected |
| Staging | `Staging` | `com.TylerPavay.AscendApp.staging` | Staging publishable client keys |
| Production | `Release` | `com.TylerPavay.AscendApp` | Production publishable client keys |

Debug is intentionally unset: it previously carried the real production RevenueCat and Superwall keys, which pointed the development bundle at the production vendor projects, and those keys now live only in `Release`.
No replacement dev keys were invented, so Debug tolerates absent monetization keys and simply cannot configure either vendor.
The long-term intent for Debug is a RevenueCat Test Store key through `ASCEND_REVENUECAT_TEST_API_KEY` and `ASCEND_USE_REVENUECAT_TEST_STORE`, never a real vendor key; that decision is not made here.
Staging carries the Ascend Staging publishable keys, drives the staging RevenueCat and Superwall projects, and passes the archive preflight.
Release carries the production publishable keys and passes the archive preflight.

- `MonetizationConfiguration` rejects any key with the `REPLACE_ME_` prefix.
- `scripts/ci/assert-monetization-keys-configured.mjs` fails any Staging or Release archive that still carries placeholders before Fastlane.
- Non-Debug builds refuse to launch with unreplaced placeholder keys.

### Key state

Both shippable configurations carry real publishable client keys, so no placeholder replacement remains:

1. `Staging` carries the Ascend Staging RevenueCat Apple publishable key and the Ascend Staging Superwall public key.
2. `Release` carries the production RevenueCat Apple publishable key and the production Superwall public key.

`ASCEND_REVENUECAT_TEST_API_KEY` stays empty and `ASCEND_USE_REVENUECAT_TEST_STORE` and `ASCEND_SUPERWALL_TEST_MODE` stay `NO` in every configuration.
`ASCEND_ALLOWS_UNENTITLED_APP_ACCESS` is `YES` in Debug for local convenience and `NO` in Staging and Release.
Changing Staging back to bypassed access requires no app code edit - see Tester-lockout recovery below for the two configuration steps it does require.
Debug and Staging use `ascend_staging_yearly` and `ascend_staging_monthly`; Release uses `ascend_yearly` and `ascend_monthly`.
`scripts/test/monetization-build-configuration.test.mjs` pins the shape of each configured key, the per-configuration access and launch-product values, and proves the preflight rejects a placeholder key, a reopened Release paywall, and either vendor test surface against a synthetic project; keep all of it aligned with any future setting move.
Never commit the real keys to documentation or test fixtures.
These publishable client keys are currently committed in `AscendApp.xcodeproj`.
They are intended to move into gitignored xcconfig files and CI secrets; that migration is deliberately not performed here.

Every environment that points at its own vendor projects needs the same logical configuration:

- Its own auto-renewing annual and monthly products - `ascend_yearly` and `ascend_monthly` in production, `ascend_staging_yearly` and `ascend_staging_monthly` in staging
- RevenueCat entitlement `app_access`
- RevenueCat current offering `default`
- Superwall placements `app_access_gate` and `onboarding_paywall` - staging carries only `app_access_gate` today, so the `.onboardingPaywall` placement always takes its `onSkip` path in Staging even though the hard gate is live there

Staging and Release both require an active `app_access` entitlement and audit the launch catalog for their configured RevenueCat environment.
Staging is therefore a real paywall QA surface for the hard gate, and a staging tester reaches the app by completing a sandbox purchase of `ascend_staging_yearly` or `ascend_staging_monthly` through campaign `99059`, or by restoring one.
Debug allows unentitled app access for local convenience, while its existing force-paywall control can still exercise the gate.

### Tester-lockout recovery

If the staging campaign, the sandbox purchase, or the RevenueCat catalog leaves testers stuck at the gate, recovery needs no app code change and no in-app escape - the app deliberately ships no bypass, sign-out affordance, or debug control at the Staging gate.
That rule covers the paywall gate, which is only reached once entitlement state is a confirmed `.inactive`.
An entitlement state that never resolves is a different route: `AppAccessResolvingView` waits there and, once identity resolution has failed, offers a caller-driven Try Again plus Sign Out so a provider outage cannot strand a subscriber.
See `docs/quality/contracts/returning-subscriber.md` for that contract.
Recovery from a real lockout is a deliberate two-step configuration diff:

1. Set `ASCEND_ALLOWS_UNENTITLED_APP_ACCESS` to `YES` in the `Staging` build configuration.
2. Update the pinned Staging expectation in `scripts/test/monetization-build-configuration.test.mjs` to match, in the same PR.

Step 2 is required, not incidental. That suite runs on every PR touching `AscendApp.xcodeproj/**`, and it hard-asserts Staging is `NO`, so step 1 alone goes red.
Pinning it that way is the point: reopening staging access cannot be a one-line build-setting flip that slips through review unnoticed, and the two-step diff states plainly in the PR that the staging gate is temporarily off.
Revert both steps once the gate is healthy.

The archive preflight deliberately permits step 1 so a stranded TestFlight group can be unblocked by a staging build.
Release carries no lever at all: `scripts/ci/assert-monetization-keys-configured.mjs` fails any production archive whose `ASCEND_ALLOWS_UNENTITLED_APP_ACCESS` is not `NO`, and fails either shippable archive whose `ASCEND_SUPERWALL_TEST_MODE` or `ASCEND_USE_REVENUECAT_TEST_STORE` is not `NO`.

## Authenticated Superwall References

### Production

These IDs identify the production application audited on July 27, 2026:

- Organization project: `24464`
- iOS application: `47442`
- Active campaign: `91861`
- Active campaign paywall: `232372`
- Archived discount paywall: `232373`
- Hard-gate placement: `app_access_gate`

### Staging

These IDs identify the staging application audited on July 28, 2026, when its keys landed:

- iOS application: `51938`
- Active campaign: `99059`, targeting `app_access_gate`
- Active campaign paywall: `249435`, published, binding `ascend_staging_yearly` to `yearly` and `ascend_staging_monthly` to `monthly`
- RevenueCat: entitlement `app_access` served through current offering `default`

Staging has no `onboarding_paywall` campaign.

Environment keys still determine which Superwall application each build reaches.
Do not copy either set of IDs into another environment without first proving that it uses that application.

## Self-Hosted Paywall

The only launch paywall page copied into `web/dist` by the Astro build is:

- Source: `web/public/superwall/onboarding-paywall.html`
- Shared styles: `web/public/superwall/ascend-paywall.css`
- Production URL: `https://ascendstepper.com/superwall/onboarding-paywall`

Hosting runs with `cleanUrls`, so the `.html` form answers every request with a redirect.
Configure Superwall with the extensionless URL above.

The document must keep its inline `<style>` block ahead of both the Superwall runtime script and the stylesheet link.
It paints the black canvas and `color-scheme: dark` on the first frame, so the paywall never flashes white on a black app while `ascend-paywall.css` loads.
`scripts/test/superwall-first-paint.test.mjs` fails if that ordering is lost.

The page defaults to Annual.
Its visible state must remain:

### Annual selected

- Headline: `Try 7 Days Free`
- Price: `$49.99/year`
- Plan disclosure: `$49.99/year, billed annually`
- CTA: `Try 7 Days Free`
- Legal disclosure: `7 days free, then $49.99/year. Auto-renews until canceled.`
- Product reference: `yearly`

### Monthly selected

- Headline: `Climb With Full Access`
- Price: `$9.99/month`
- Plan disclosure: `Charged immediately, then monthly`
- CTA: `Subscribe for $9.99/month`
- Legal disclosure: `$9.99 charged now, then monthly. Auto-renews until canceled.`
- Product reference: `monthly`
- No trial badge, promise, CTA, or disclosure

Both states show `Compete on global leaderboards`, preserve Restore, Terms, Privacy, VoiceOver selection state, and use the same purchase analytics path through Superwall and RevenueCat.
The unsupported personalized climbing-plan claim must not return.

### Localized pricing and trial eligibility

The literal strings above are United States fallbacks that the static page renders before Superwall substitutes product values.
Every price-bearing and trial-bearing string sits inside an element that carries a `data-pw-var` name, so Superwall can replace all of them.
Bind each name to the localized StoreKit product value in the Superwall paywall editor:

| `data-pw-var` | Bound product value |
|---|---|
| `yearly_price`, `yearly_subtitle` | `yearly` localized price and billing period |
| `monthly_price`, `monthly_subtitle`, `monthly_cta` | `monthly` localized price and billing period |
| `yearly_headline`, `yearly_badge`, `yearly_cta`, `yearly_disclosure` | `yearly` localized price and introductory-offer state |
| `monthly_disclosure` | `monthly` localized price with no introductory offer |

Never hardcode a localized price or a trial promise that Superwall cannot override.
A price literal that sits outside a `data-pw-var` element is a defect, and `scripts/test/subscription-launch-offer.test.mjs` fails on one.

Apple grants one introductory offer per subscription group per Apple account and Family Sharing group, so the annual trial promise is not true for every account.
Bind the annual trial surfaces to Superwall's free-trial-eligibility state so an account that already used the offer sees immediate-charge annual copy instead of the trial promise.
`PaywallAnalyticsContext.isFreeTrialAvailable` records which state each presentation actually showed.

### Paywall chrome, the back control, and DELETE ACCOUNT

The paywall carries one chrome control: a back arrow in the top-left that returns the climber to the last onboarding step.
It carries no close or X control at all.
Ascend has no free tier, so there is nothing behind the paywall for a close to dismiss to - close and back would land in the same place.

Two controls on the paywall are custom actions rather than plain closes: the back arrow (`back`) and the footer's `DELETE ACCOUNT` (`delete_account`).
The custom action name is the only thing that can distinguish either control from any other dismissal: SuperwallKit reports every user-driven close as the same `PaywallResult.declined` with `PaywallCloseReason.manualClose`, and the close message carries no payload, so two controls both wired to a close action are indistinguishable to the app.

**A custom action never dismisses the paywall and carries no outcome of its own**, so every control has to be dismissed by *somebody*.
There are exactly two arrangements and they are mutually exclusive - `SuperwallCustomAction.isDismissedByAscend` is the executable answer for which one a name uses:

| Control | Editor wiring | Who dismisses |
|---|---|---|
| back arrow (`back`) | `Custom action` **chained ahead of a close action** | the paywall |
| `DELETE ACCOUNT` (`delete_account`) | `Custom action` **only, with no close after it** | Ascend |

A control Ascend dismisses must **not** also chain a close, and a control the paywall dismisses must chain one.
Get it backwards in either direction and the control misbehaves: with no close and no app handling it does nothing at all, not even close the paywall (the shipped state of `DELETE ACCOUNT` in staging build 2026083101), and with both, the editor's close races Ascend's own dismissal and hands the app a dismissal it did not cause.

`SuperwallCustomAction` is the one place those strings become intents and `PaywallDismissIntent` resolves them; any name the app does not model degrades to an ordinary dismissal rather than borrowing a modelled control's behaviour.
The enum is `CaseIterable` and `AscendAppTests/PaywallDeleteAccountFromHostedPaywallTests.swift` derives the recognised set from it, so an editor control added without teaching the app its name fails there rather than in a climber's hands.

`DELETE ACCOUNT` matters beyond convenience: with no close control on the paywall, it is the account-deletion route Guideline 5.1.1(v) requires for a climber who is locked out and cannot pay, and it opens the same confirmation dialog the native gate's own `Delete account` control opens - the identical closure, so the two can never diverge.
Ascend owns that dismissal because the dialog cannot be shown while the paywall is up; see below.

The staging editor already carries `DELETE ACCOUNT` and already emits `delete_account` - a control firing with nothing answering it is exactly what #558 was - so that route is live rather than hypothetical, and step 13 below is how each environment's paywall is confirmed to carry it on the wiring above.
For a control an editor does not yet carry, nothing emits its action, so the matching app route stays inert and paywall behaviour is unchanged.
Adding the back control, deleting the `CLOSE` node, and enlarging the footer tap target are editor edits this repository deliberately does not make.

### Nothing the app presents can appear over a live paywall

**A presented Superwall paywall sits in its own `UIWindow`, above the app's, so any sheet, alert, or dialog the app raises while it is up renders underneath it and is invisible.**
This has now cost two features, so it is written down rather than re-derived: it is why the hard-update lockout had to become a route instead of a sheet (#429), and why the paywall's `DELETE ACCOUNT` control is dismissed by Ascend rather than opening the deletion dialog over the paywall.

The mechanism, verified in the pinned SuperwallKit source:

- `getPresenterIfNecessary` calls `createPresentingWindowIfNeeded()`, which builds a **new `UIWindow`** in the active window scene whenever the presentation request carries no presenter of its own - which is every Ascend presentation, since `register(placement:params:handler:feature:)` supplies none.
- `PaywallViewController.present(on:)` then calls `presentationItems.window?.makeKeyAndVisible()` before presenting itself on that window's root view controller.
- Neither window sets `windowLevel`, so both sit at `.normal` and the later one - Superwall's - wins.

So a surface that must be reachable *while* a paywall is up has exactly two honest shapes:

1. **The paywall draws the control itself** and fires a `Custom action`; Ascend answers it, dismisses the paywall, and then presents its own UI. This is what `delete_account` does.
2. **Ascend dismisses the paywall first**, then presents. Same thing, initiated from the app side.

What does not work, and must not be attempted again: presenting a SwiftUI `.sheet` from `RootView` and expecting it to cover the paywall.
Raising the app window's level or hosting Ascend UI on Superwall's window would technically layer, but both are a second presentation path for a surface that already has one, so neither is sanctioned.

Once the paywall is gone, the sheet Ascend raises still has to win at its own modifier level.
Two `.sheet` modifiers on the same view defer one another, which is the second half of the #429 mechanism, and `RootView` carries both the soft update nudge and the account-deletion dialog there.
A climber asking to delete their account outranks a recommended update, so the nudge yields: `presentGateAccountDeletion()` calls `dismissRecommended()` and hands the request to the nudge sheet's own `onDismiss`, which raises the deletion dialog only once the nudge is provably gone.
The yield is keyed to `isNudgeSheetPresented`, written by the nudge sheet's own body, never to `nudgePresentation != nil` - a non-nil item is a request to present, which is precisely the state #429 shows SwiftUI can leave unhonoured, and waiting on a dismissal that can never arrive would swallow the deletion request.
A nudge that was never presented is cleared on the way past, and the item reaching `nil` hands the request on as a second, idempotent continuation.
Detecting the clash and reporting a refusal instead is not an option - the gate has already dismissed its hosted paywall by the time it asks, so it has nowhere to render one.

## Superwall Verification Checklist

Complete these steps in each authenticated Superwall project without bypassing product validation or publishing an unverified campaign.
Substitute that environment's own product identifiers throughout - `ascend_yearly` / `ascend_monthly` in production, `ascend_staging_yearly` / `ascend_staging_monthly` in staging - while the reference names stay `yearly` and `monthly` everywhere:

1. Confirm the project has only that environment's annual and monthly products in the launch paywall.
2. Bind the annual product to `yearly`.
3. Bind the monthly product to `monthly`.
4. Confirm the paywall benefits say `Compete on global leaderboards`, make no personalized-plan claim, and leave `benefit_1` without a hardcoded landmark count.
5. Point a self-hosted paywall at `https://ascendstepper.com/superwall/onboarding-paywall` only after the Hosting deployment serves this repository revision.
6. Confirm Annual is selected when `Try 7 Days Free` is visible.
7. Switch to Monthly and confirm the headline, CTA, price, and legal disclosure all describe an immediate monthly charge with no trial.
8. Bind every `data-pw-var` in the localized-pricing table to its product value, then preview a non-United States storefront and confirm each price renders in that storefront's currency.
9. Preview with an Apple account that already used the introductory offer and confirm no annual surface promises a free trial.
10. Confirm Restore, Terms, and Privacy still work.
11. Confirm a sandbox annual purchase and monthly purchase each grant `app_access`.
12. Confirm the only chrome control is the top-left back arrow, that it fires a `Custom action` named `back` ahead of its close action, and that no `CLOSE` node remains - see Paywall chrome, the back control, and DELETE ACCOUNT above.
13. Confirm the footer's `DELETE ACCOUNT` control fires a `Custom action` named `delete_account` and that **no close action is chained after it** - Ascend dismisses the paywall itself for this control, and an editor close would race that dismissal.
14. Wire the verified paywall to `app_access_gate`.
15. Keep onboarding experiments on `onboarding_paywall`.
16. Publish only after Superwall accepts both product states and editor and device previews match the two states above.

## Release Gate

Before the first review submission:

1. Verify the configured Staging and Release keys still reach their own vendor projects.
2. Run `node --test scripts/test/*.test.mjs` (needs `npm --prefix scripts ci` first).
3. Run `node scripts/validate-superwall-live-artifact.mjs staging` and `node scripts/validate-superwall-live-artifact.mjs production`.
4. Do not reconstruct the runtime URL.
   The validator selects the 100 percent `TREATMENT` for `app_access_gate` from the public `.me` static config, then fetches the selected response's complete runtime URL unchanged.
5. Treat a validator failure as a provider publication gate.
   Do not convert it to a warning or validate an unused paywall response instead.
6. Run the Staging iOS test suite.
7. Build the unsigned Release configuration.
8. Build the website and confirm the retired discount page returns 404.
9. Complete the real-device canary in `docs/quality/evidence/issue-554-release-canary.md`.
10. Verify the enabled Superwall campaign targets `app_access_gate` and contains no weekly or separate discount variant.
11. Complete the required App Store submission step for both subscriptions, verify Superwall no longer reports them as `Incomplete`, and publish the verified paywall `232372` revision.

### Published artifact status on August 29, 2026

The versioned captures under `scripts/test/fixtures/superwall` contain no SDK keys or user data.
They record only the selected placement, response, product and entitlement mapping, runtime document, action graph, and state references needed for deterministic validation.

Staging currently selects response `249435` and runtime document `pj6GhBq8K0IxskBJ7ui6z`.
Its annual and monthly products grant `app_access`, but the purchase abandon action references missing state `state:`.

Production currently selects response `232372` and runtime document `odpvyL4GHznbb1E4cghT4`.
Its annual and monthly products grant `ascend_membership` instead of the app contract's exact `app_access`, and its purchase abandon action also references missing state `state:`.

Both live checks intentionally fail until a human approves and publishes corrected Editor artifacts.
This repository change does not mutate either dashboard.

The static Editor store can prove that purchase and Close are not sibling actions on one click behavior.
It cannot prove rendered hit-region geometry because final frames depend on the runtime layout engine, device viewport, safe areas, and dynamic product copy.
The signed real-device canary is therefore the required evidence that a distinct rendered Close control does not cover the purchase CTA and that tapping the CTA reaches Apple's transaction sheet.
