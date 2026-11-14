---
name: ascend-onboarding
description: Use when working on Ascend onboarding - the welcome screen, setup questions, sign-in routing, the sign-in hand-off, paywall priming, notifications opt-in, onboarding state persistence, or bodyweight capture. Covers the one onboarding flow, what a signed-in climber meets instead of questions, and onboarding content discipline.
paths:
  - AscendApp/Features/Onboarding/**
  - AscendApp/Features/Authentication/**
  - AscendApp/Features/Monetization/**
---

# Onboarding

## The flow

There is one onboarding, and nobody reaches another: a signed-out climber gets it on every launch, on a fresh install and after every sign-out, and `AppRootRouteResolver` has no switch, hold or fallback screen behind it.
It is the selling screens, then the setup questions, then sign-in, with Skip on the screens the design gives one.
The flow ends at sign-in.
The earlier flow (landing screen, value carousel, post-sign-in survey and demographic questions) was removed in 1.3.0 together with the `onboarding_v3_enabled` rollout: a fresh install on a slow or blocked network fell back to it, and its city question could not be left when Apple Maps failed, which App Review rejected under Guideline 2.1(a) on 2026-11-14.
Do not add a signed-in question stage or a flag that chooses between flows: an iOS binary cannot be rolled back, and a screen only some climbers reach is a screen App Review may reach first.

A signed-in climber is never sent through questions.
A climber who holds no access meets the app-access gate, the Superwall paywall for the `app_access_gate` placement, like any other; one who already pays goes straight to the app.
A climber who signed in on an older build and never finished the old questions meets the same route on update: gender, birthday, height and weight and city are optional and have editors in Profile, and nothing waits on them.
`OnboardingFirstClimbHandoffStore` is the one thing kept from those questions, read only until 1.4.0, for a first climb staged on an older build and not yet carried into the app.

The decline offer a climber meets when they close that paywall is a second Superwall paywall configured in the dashboard, so the app has no screen, route or gift-specific code for it, and no native paywall is built for either (`docs/superwall-paywall-setup.md`).
What follows a climber closing that offer too depends on `free_week_after_decline_enabled`: off, the first paywall again; on, a founder letter (a third Superwall screen, placement `founder_letter`) and seven days in the app on a server-owned grant, once per account (`docs/free-week-after-decline.md`).
A climber who force-closes the app on the first paywall meets the decline offer on the next launch, once per account (`docs/free-week-after-decline.md`, "Force-closing on the first paywall"; `DeclineOfferReplayStore`).
The gate itself draws a spinner and nothing else - no plan picker, no status line, no button - so everything a climber reads or taps there is a Superwall screen (`docs/superwall-paywall-setup.md`, "The gate draws a spinner and nothing else").
The paywall's back arrow is a plain close: nothing is behind the gate to go back to.

Signing in at the end of the flow records the completed onboarding (`OnboardingCompletionRecorder`), while "Already have an account? Sign in" on the first screen gets normal routing.
A sign-out, a deleted account or a revoked session clears everything the flow kept on the device and returns it to Welcome (`OnboardingV3Coordinator.sessionEnded()`), so the next person on the phone starts clean and a climber coming back signs in through "Already have an account? Sign in".
A finished pass must never decide the signed-out route: kept across sign-out, it once sent every climber who signed out to the old onboarding for good (`AscendAppTests/OnboardingV3SignOutTests.swift`).
`OnboardingV3SignInHandOff` owns what carries over to the account and in what order.
`OnboardingV3Step` owns its screens and branches.
`OnboardingV3FlowView`'s switch is the whole map of the flow: fifteen real screens, no stub or placeholder view, each built from the coordinator alone.
The sign-in screen's saved-items list says back what the flow collected: the profile row leads with the typed name and draws the picked photo (through `ClimberAvatar`, from `OnboardingV3Coordinator.profilePhotoURL`), else the initials, else the generic person.

## No screen may trap a climber
- Any screen that asks for something that needs the network or a permission - Apple Maps city search, Health, notifications, a photo - carries a way on that does not depend on the answer.
  `OnboardingClaimCityScreen` keeps its header Skip in every state, and `OnboardingCityStepCannotTrapTests` fails the search on purpose through `PostAuthCitySuggestionSource` and holds that Skip moves the climber on with no city.
- A failed search or lookup says so beside the control, and never disables the only exit.

## Walking the flow on a simulator or a test phone
- The flow only shows to a signed-out climber. A reinstalled app restores the Keychain session, so sign out first or the launch goes straight to the account's route. Debug Tools -> `Replay New Onboarding From Welcome` clears the flow's answers and signs out.
- One phone, several accounts: the Debug replay resets the answers, not the local store, so the next account signing in meets `Account data mismatch` (the ownership guard working as designed). A new account per run needs a fresh install.
- The Debug build has no vendor keys and allows unentitled access, so it never shows a paywall: `Force App Access Gate` there shows only the gate's spinner, retrying a paywall Superwall cannot present, until the app is relaunched. Staging shows the real Superwall `app_access_gate` paywall. Whether closing it shows the decline offer depends on which Superwall campaigns are published on staging, and with no free week on offer the first paywall simply reopens. No purchase completes on a simulator without a sandbox Apple Account.
- The dev project's deployed `firestore.rules` drift behind `develop` (lanes deploy their own); a hand-off write such as `weekly_target_days` that silently stays `weeklyTarget.unsynced` on the device is the first sign. Deploy the union before reading a missing field as a defect.

## Required profile capture
- Onboarding collects declared demographics on its profile screen (08) and writes them after sign-in. It never asks for a name as a requirement.
  That screen is the one place with optional name fields, plus a photo; it is skippable and gates nothing.
  The name is resolved without asking - see the `Name - Resolved, Never Asked` section of `docs/onboarding-design-guide.md`, which owns that contract.
  `ascend-profile` owns the full demographics contract - the stored birthday, the derived age and its bounds, and the gender raw values.

## Your athlete
- A climber's athlete look is set in the athlete editor from Profile, and `users/{uid}/athlete_look/current` is owner-written without a grant, like public identity (`docs/revenuecat-server-entitlement-enforcement.md`).

## Routing
- Sign-in is a routing transition, not a sheet dismissal - auth screens should not dismiss themselves after provider sign-in; the auth surface is replaced by the authenticated root.
- `AppRootRouteResolver` is synchronous and pure: lockout, then authentication, then entitlement. There is no onboarding phase between authentication and entitlement.

## Notifications opt-in
- Notifications opt-in should be anchored to a concrete value prop: never miss a climb drop. Do not ask for notification permission as generic setup housekeeping.
- Notifications opt-in is the gateway to First Ascent opportunity.
  Climbers with notifications enabled are alerted **when a climb opens**, not before it: `announceClimbDrops` (`functions/src/climbDropNotifications.ts`) watches the hosted catalogue and sends the moment a landmark reaches `available`.
  Every shipped string says the same thing - "when new climbs open", "A new landmark opens in the catalog" - and the promise is fairness at the open, not a head start before it.
  Advance notice is not available to promise: the catalogue is a static file with no unlock timestamp, so counting back from an open would take both a catalogue schema change and a client that withholds a published climb.
  `scripts/test/climb-drop-promise-contract.test.mjs` fails any surface or document that reintroduces it.
- The primer (screen 12) also promises gear and weekly-target nudges; `docs/climb-drop-notifications.md` owns them.
- The primer also carries the email opt-in (`NotificationPrimerContent.emailOptInLabel`), ticked by default.
  It runs before sign-in, so the box waits in `PreAuthOnboardingAnswers.emailOptIn` and `OnboardingV3SignInHandOff` records it as an `onboarding` decision (an answer the account already holds wins, a failed write retries on the next launch).
  Either button saves the box, so Not now never discards a ticked one.

## Content discipline
- Survey and paywall content is product-defined. Engineers should not ship onboarding screens, copy, or content beyond what product has provided mocks for.

## State persistence
- Answers are kept on the device until sign-in (`PreAuthOnboardingStore`), survive relaunch, and are cleared on sign-out. Do not add remote onboarding fields to `users/{uid}` without updating `firestore.rules` in the same change (see `ascend-firebase-data`).

## Other
- Bodyweight is a single profile-level value editable in settings. It's the app-wide source for body-mass usage; don't introduce parallel bodyweight inputs in feature-specific flows.

## Related
- Adding, removing, reordering, or renaming an onboarding screen changes the funnel contract - the ordered screen IDs, their events, and their sub-properties are owned by `ascend-analytics`. Load it before touching a screen.
- Welcome/auth screen chrome (`OnboardingScaffold`, the Ascend wordmark) lives in `ascend-design-system`.
- Copy and empty-state voice: `ascend-brand-voice` and the `product-design-playbook` skill.

## Reference
- `docs/onboarding-design-guide.md` - the onboarding design guide. Read it when working on onboarding screens; never inline it.
- `docs/superwall-paywall-setup.md` - the authoritative launch subscription offer (products, entitlement, offering, paywall plan states), the per-environment RevenueCat/SuperWall split, and the audited Superwall IDs.
  `Staging` and `Release` require an active `app_access` entitlement and audit their environment-specific launch products.
  `Debug` ships unset vendor keys and allows unentitled access for local convenience, with the existing force-paywall control available to exercise the gate.
- `docs/revenuecat-server-entitlement-enforcement.md` - the paid gate is enforced in Firebase rules, not only on device. Adding a Firebase read or write to an onboarding screen that sits behind a paid boundary would be denied for exactly the users who have not purchased yet.
