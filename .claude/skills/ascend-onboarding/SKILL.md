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

## Required profile capture
- Post-auth onboarding must collect separate required first-name and last-name fields before the user reaches the main app, plus declared demographics when that stage is enabled.
  The public board name is composed from both fields, never split or inferred from a single name input.
  `ascend-profile` owns the full demographics contract - the stored birthday, the derived age and its bounds, and the gender raw values.

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
- Notifications opt-in is the gateway to First Ascent opportunity. Climbers with notifications enabled receive 24-hour advance notice of new climb drops, giving them a fair shot to claim the FA at unlock.

## Content discipline
- Survey and paywall content is product-defined. Engineers should not ship onboarding screens, copy, or content beyond what product has provided mocks for.

## State persistence
- Onboarding state is local per Firebase `uid` during early testing. Do not add remote onboarding fields to `users/{uid}` without updating `firestore.rules` in the same change (see `ascend-firebase-data`).
- Progress persists locally across app restarts and backgrounding so a user who leaves mid-onboarding resumes at the exact step they left, with the same state. Uninstall/reinstall resets state via app data removal until remote onboarding state is introduced.

## Other
- Bodyweight is a single profile-level value editable in settings. It's the app-wide source for body-mass usage; don't introduce parallel bodyweight inputs in feature-specific flows.

## Related
- Adding, removing, reordering, or renaming an onboarding screen changes the 21-screen funnel contract - the ordered screen IDs, their events, and their sub-properties are owned by `ascend-analytics`. Load it before touching a screen.
- Welcome/auth screen chrome (`OnboardingScaffold`, `OnboardingWelcomeBackground`, `AuthStaircaseBackground`, the Ascend wordmark) lives in `ascend-design-system`.
- Copy and empty-state voice: `ascend-brand-voice` and the `product-design-playbook` skill.

## Reference
- `docs/onboarding-design-guide.md` - the full onboarding design guide, screen by screen. Read it when working on onboarding screens; never inline it.
- `docs/superwall-paywall-setup.md` - the authoritative launch subscription offer (products, entitlement, offering, paywall plan states), the per-environment RevenueCat/SuperWall split, and the audited Superwall IDs.
  `Staging` and `Release` require an active `app_access` entitlement and audit their environment-specific launch products.
  `Debug` ships unset vendor keys and allows unentitled access for local convenience, with the existing force-paywall control available to exercise the gate.
- `docs/revenuecat-server-entitlement-enforcement.md` - the paid gate is enforced in Firebase rules, not only on device. Every pre-paywall stage, including `firstClimb` and its landmark artwork, is deliberately left ungated; adding a Firebase read or write to an onboarding stage that sits behind a paid boundary would be denied for exactly the users who have not purchased yet.
