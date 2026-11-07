---
name: ascend-onboarding
description: Use when working on Ascend onboarding - the welcome screen, pre-auth value carousel, sign-in routing, the post-auth resolver, survey, paywall priming, smart-default first-climb recommendations, notifications opt-in, onboarding state persistence, or bodyweight capture. Covers the planned flow order, the three post-auth user states, and onboarding content discipline.
paths:
  - AscendApp/Features/Onboarding/**
  - AscendApp/Features/Authentication/**
  - AscendApp/Features/Monetization/**
---

# Onboarding

## Planned flow

The planned onboarding sequence, in order:
1. Welcome screen
2. Pre-auth value carousel
3. Sign-in (Apple / Google)
4. Survey
5. Paywall priming screens
6. Hard paywall
7. Home

This sequence will evolve as we learn from SuperWall and RevenueCat funnel analytics. Treat it as the current plan, not a permanent contract.

That sequence, and the `Pre-auth value screens` rules below, describe the flow with `onboarding_v3_enabled` off, which is how the switch ships.
With it on, a signed-out climber gets the 1.3.0 flow instead: selling screens, setup questions and then sign-in, with Skip on the screens the design gives one.
The flow ends at sign-in. A signed-in climber who holds no access meets the app-access gate, the Superwall paywall for the `app_access_gate` placement, like any other; one who already pays goes straight to the app.
The decline offer a climber meets when they close that paywall is a second Superwall paywall configured in the dashboard, so the app has no screen, route or gift-specific code for it, and no native paywall is built for either (`docs/superwall-paywall-setup.md`).
Signing in at the end of that flow marks post-sign-in onboarding complete, so the resolver's first-time path below does not run for that climber, while "Already have an account? Sign in" on the first screen gets normal routing.
`OnboardingV3SignInHandOff` owns what carries over to the account and in what order.
`OnboardingV3Step` owns its screens and branches, and `docs/remote-config-kill-switches.md` (Rollouts, which ship off) owns how the switch behaves.
`OnboardingV3FlowView`'s switch is the whole map of the flow: fifteen real screens, no stub or placeholder view, each built from the coordinator alone.
The sign-in screen's saved-items list says back what the flow collected: the profile row leads with the typed name and draws the picked photo (through `ClimberAvatar`, from `OnboardingV3Coordinator.profilePhotoURL`), else the initials, else the generic person.

## Walking the v3 flow on a simulator or a test phone
- The switch ships off, so a dev or staging build opens the old landing screen until the device carries the Debug-only override: Debug Tools -> `Replay New Onboarding From Welcome` sets it (and signs out), or write `onboardingV3.debugForcesFlow` = true into the app's own preferences file (`<container>/Library/Preferences/<bundle id>.plist`) before launch; `simctl spawn defaults write <bundle id>` lands in the simulator's shared domain and the app does not read it on a fresh container.
- The flow only shows to a signed-out climber. A reinstalled app restores the Keychain session, so sign out first or the launch goes straight to the account's route.
- One phone, several accounts: the Debug replay resets the answers, not the local store, so the next account signing in meets `Account data mismatch` (the ownership guard working as designed). A new account per run needs a fresh install; a returning climber needs a remote profile that `isCompletePostAuthProfile` accepts (display name, age, gender, weight, city and country) or the legacy post-auth questions resume.
- The Debug build has no vendor keys, so the paywall after sign-in is the gate's native fallback and `Force App Access Gate` is the only way to see it; Staging shows the real Superwall `app_access_gate` paywall. The decline offer is a second Superwall campaign that is not published on staging until the launch, so closing the first paywall there lands on the native plan list, and no purchase completes on a simulator without a sandbox Apple Account.
- The dev project's deployed `firestore.rules` drift behind `develop` (lanes deploy their own); a hand-off write such as `weekly_target_days` that silently stays `weeklyTarget.unsynced` on the device is the first sign. Deploy the union before reading a missing field as a defect.

## Required profile capture
- Post-auth onboarding collects declared demographics when that stage is enabled. It never asks for a name.
  The v3 flow's pre-sign-in profile screen (08) is the one place with optional name fields, plus a photo; it is skippable and gates nothing.
  The name is resolved without asking - see the `Name - Resolved, Never Asked` section of `docs/onboarding-design-guide.md`, which owns that contract.
  `ascend-profile` owns the full demographics contract - the stored birthday, the derived age and its bounds, and the gender raw values.

## Your athlete
- The `athlete` stage follows `gender`: "This is you on the Mountain", the athlete the gender answer starts the climber with (`AthleteLook.starting(for:)`), MAKE IT MINE into the editor or LOOKS GOOD. Both save the look, so other climbers see this athlete rather than a stand-in; a save that fails never holds onboarding up.
- It sits ahead of the paywall, so `users/{uid}/athlete_look/current` is owner-written without a grant, like public identity (`docs/revenuecat-server-entitlement-enforcement.md`).

## Routing & resolver
- Sign-in is a routing transition, not a sheet dismissal - auth screens should not dismiss themselves after provider sign-in; the auth surface is replaced by the authenticated root.
- The post-auth resolver distinguishes three user states: **first-time** (run full post-auth flow), **returning-complete** (skip to home), **interrupted-returning** (resume at the step where they left off, not restart from the beginning).

## Pre-auth value screens
- Follow a single shared cinematic pattern - full-bleed dark background, thin top progress indicator, one large product hero, short copy at the bottom, one CTA per screen. Don't fork the layout per screen.
- No skip affordances. No card chrome or boxed surfaces.

## Smart defaults
- Smart-default first-climb recommendations should come from the user's declared behavioral baseline: easier starters for new stair-stepper users, larger landmarks for regulars and serious athletes. Defaults route to the climb detail screen, not directly into a live attempt.

## Notifications opt-in
- Notifications opt-in should be anchored to a concrete value prop: never miss a climb drop. Do not ask for notification permission as generic setup housekeeping.
- Notifications opt-in is the gateway to First Ascent opportunity.
  Climbers with notifications enabled are alerted **when a climb opens**, not before it: `announceClimbDrops` (`functions/src/climbDropNotifications.ts`) watches the hosted catalogue and sends the moment a landmark reaches `available`.
  Every shipped string says the same thing - "Get an Ascend alert when new climbs open", "A new landmark opens in the catalog" - and the promise is fairness at the open, not a head start before it.
  Advance notice is not available to promise: the catalogue is a static file with no unlock timestamp, so counting back from an open would take both a catalogue schema change and a client that withholds a published climb.
  `scripts/test/climb-drop-promise-contract.test.mjs` fails any surface or document that reintroduces it.
- With `onboarding_v3_enabled` on, the primer (screen 12) also promises gear and weekly-target nudges; `docs/climb-drop-notifications.md` owns them.

## Content discipline
- Survey and paywall content is product-defined. Engineers should not ship onboarding screens, copy, or content beyond what product has provided mocks for.

## State persistence
- Onboarding state is local per Firebase `uid` during early testing. Do not add remote onboarding fields to `users/{uid}` without updating `firestore.rules` in the same change (see `ascend-firebase-data`).
- Progress persists locally across app restarts and backgrounding so a user who leaves mid-onboarding resumes at the exact step they left, with the same state. Uninstall/reinstall resets state via app data removal until remote onboarding state is introduced.

## Other
- Bodyweight is a single profile-level value editable in settings. It's the app-wide source for body-mass usage; don't introduce parallel bodyweight inputs in feature-specific flows.

## Related
- Adding, removing, reordering, or renaming an onboarding screen changes the funnel contract - the ordered screen IDs, their events, and their sub-properties are owned by `ascend-analytics`. Load it before touching a screen.
- Welcome/auth screen chrome (`OnboardingScaffold`, `OnboardingWelcomeBackground`, `AuthStaircaseBackground`, the Ascend wordmark) lives in `ascend-design-system`.
- Copy and empty-state voice: `ascend-brand-voice` and the `product-design-playbook` skill.

## Reference
- `docs/onboarding-design-guide.md` - the full onboarding design guide, screen by screen. Read it when working on onboarding screens; never inline it.
- `docs/superwall-paywall-setup.md` - the authoritative launch subscription offer (products, entitlement, offering, paywall plan states), the per-environment RevenueCat/SuperWall split, and the audited Superwall IDs.
  `Staging` and `Release` require an active `app_access` entitlement and audit their environment-specific launch products.
  `Debug` ships unset vendor keys and allows unentitled access for local convenience, with the existing force-paywall control available to exercise the gate.
- `docs/revenuecat-server-entitlement-enforcement.md` - the paid gate is enforced in Firebase rules, not only on device. Every pre-paywall stage, including `firstClimb` and its landmark artwork, is deliberately left ungated; adding a Firebase read or write to an onboarding stage that sits behind a paid boundary would be denied for exactly the users who have not purchased yet.
