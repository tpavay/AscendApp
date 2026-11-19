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
- **A custom message ahead of a system permission request has no way out of the request.**
  Apple rejected 1.3.0 (build 2026111701) on 2026-11-19 under Guideline 5.1.1(iv) because onboarding's Health connect screen carried a Skip: the message could be closed without reaching the iOS request.
  So screens 06 (Health), 06b (the picture of the sheet) and 12 (the notification primer) have exactly one forward action each, which leads to the request, and no Skip, Not now or X.
  The climber's no is the iOS sheet's own Don't Allow, and the flow takes any answer, or a request that cannot be made, as a reason to move on (`OnboardingHealthPermissionViewModel`, `NotificationPrimerViewModel`), which is how the no-trap rule above still holds.
  Back stays: it leaves the flow's earlier screens, not the request.
  The Connect screen opened later from the Climb sheet or Integrations follows the same rule and draws a close only after a failed request.
  `PrePermissionMessagesHaveNoWayOutTests` holds all of it, and a new permission message joins that suite.
- The sign-in screen's red line says what failed, and only a connectivity error may mention the connection.
  1.3.0 (build 2026111401) was rejected under Guideline 2.1(a) on 2026-11-16 because every Apple, Google and Firebase failure shared "Please check your connection": a reviewer on a working connection saw Apple's own authorization fail (Sentry `ASCEND-IOS-1F`) and read it as the app not recognising the internet.
  `AuthenticationFailureDiagnostics` classifies from the error's own chain (`URLError` transport codes, Firebase's `networkError`), the Apple failure points to Google one button below, and Sentry now carries `failure_kind`, `error_domain` and `error_code` - Apple's code was discarded before, so the root cause of ASCEND-IOS-1F is read from those tags on the next occurrence.
  A simulator cannot reproduce it: with no Apple Account the Authentication Services sheet never calls back.
  Production holds two failures under that one issue, and they are not the same thing.
  Apple's own test and review devices (development kernel, 21 of 26 failing devices, 0 of 46 attempts ever complete) are refused 0 seconds after the tap with no sheet; four retail customers saw the sheet open and then end in an error 1 to 12 seconds later, from 2026-11-01, and an iPad did it four times over three days.
  `AppleAuthorizationPerformer` owns the request and records `sheet_presented` (the app lost the foreground to Apple's sheet), `ms_to_result`, `scene_state`, `app_state` and `attempt_number` beside Apple's code, name and underlying chain on both Sentry and `onboarding_auth_failed`, so the two are told apart in Mixpanel without joining systems.
  The sign-in screen is never unmounted while a provider works: every authenticating state resolves to `preAuthOnboarding`, the buttons dim under a "Signing in..." line, and a refusal lands on the buttons it came from.
  After a refusal the screen says what the climber can fix (signed in to an Apple Account in Settings, two-factor authentication on), the Apple button reads `Try Apple again`, and after the second refusal in a row Google leads (`AppleRetryPresentation`).
  Nothing retries on its own, and a second tap while a sign-in is waiting starts nothing.
  The failure is not an entitlement or request-code fault: the entitlement, the App ID's Sign in with Apple capability and `AuthenticationService.swift`'s Apple request are unchanged between 1.2.4 and 1.3.0, other retail phones complete Apple on the same builds, and the Firebase exchange never ran (a Firebase failure carries Firebase's own text, not "unknown error").
  Retrying does not recover it: an iPad failed four times and an iPhone 14,6 five times in a row.
  The cause is unproven.
  In production from 2026-10-20 to 2026-11-16, 0 of 12 Apple attempts on iOS 27.2.1 (build 24B156, 6 devices) succeeded while 27.0.1 and 27.2 completed, and retail iOS 26.x phones also failed after 2026-11-14, so iOS 27.2.1 and an Apple-side fault both fit; Apple's real code, now recorded, separates them.
  Do not blame the review device's Apple Account: a review iPhone has the App Store, so one is signed in.
  Devices that failed Apple tapped Google 1 to 80 seconds later and only some finished it; the 2026-11-16 reviewer, shown a connection sentence with no way on, stopped after seven seconds.
  Never reintroduce one catch-all sentence for a provider failure.

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
  The box is saved whichever way iOS is answered, so a refusal never discards a ticked one.

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
