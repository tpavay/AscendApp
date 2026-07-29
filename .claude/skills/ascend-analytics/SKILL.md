---
name: ascend-analytics
description: Use when working on Ascend analytics or telemetry - event definitions, the analytics facade, telemetry sinks (Firebase Analytics, Mixpanel, SuperWall, Crashlytics, Sentry), screen tracking, funnel/engagement/quality measurement, event parameter privacy, or the debug telemetry console. Covers what is worth logging, which destination owns which job, and the low-cardinality parameter rule.
paths:
  - AscendApp/Shared/Services/Telemetry/**
  - AscendApp/Features/*/Analytics/**
---

# Analytics Architecture

## What analytics is for
- **Funnel measurement** - where users drop off between acquisition -> activation -> trial start -> paid subscription -> renewal. This drives the business decisions.
- **Engagement** - session count, climb completions, leaderboard interactions, return rate (Day 1 / Day 7 / Day 30). Tells us if the product is working day-to-day.
- **Feature-specific signals** - First Ascent claim rate, Live Climb completion vs. abandon rate, paywall presentation outcomes, copy-variant performance. Tells us what to iterate on.
- **Quality** - crash rate, error rate, performance regressions. Stability is non-negotiable.

If an event wouldn't change a decision, don't log it. Volume of events != value of analytics.

## Providers

Multiple analytics destinations are sanctioned - each is best at a different job. Route events to the right destination through a single facade; never call providers directly from feature code.

- **Firebase Analytics** - broad funnel, cohort, retention analysis. Most product events go here.
- **Mixpanel** - product funnel, retention, and behavior analytics. Implemented as `MixpanelTelemetrySink`, configured from the `AscendMixpanelToken` Info.plist key; the sink is inert when no token is present.
- **SuperWall** - onboarding-flow step-level conversion + paywall presentation analytics (its specialty).
- **Crashlytics** - crashes, fatal errors, stability metrics.
- **Sentry** - error/crash diagnostics mirror alongside Crashlytics (non-fatal errors, app hangs, symbolicated traces). When reading, triaging, or updating Sentry issues/events, use the `sentry` skill.

When evaluating new providers, justify them by what they uniquely measure that the existing set doesn't.

## Implementation principles
- One analytics facade. Feature code never imports a provider directly; it logs through the facade, which routes to the right destination. Sinks conform to `TelemetrySink` under `AscendApp/Shared/Services/Telemetry/`.
- Event definitions are typed, discoverable, and feature-owned. Don't pass arbitrary string event names - events are values defined alongside the feature that emits them (see `AscendApp/Features/*/Analytics/`).
- Log from logic layers (view models, coordinators, services), not from view bodies. SwiftUI screen tracking is the exception - it belongs on the view via a shared modifier.
- Parameters stay low-cardinality and privacy-safe: never log raw user input, email, DOB, exact location, exact health samples, or any PII. Bucket continuous values into categories before logging.
- Event contracts are verifiable. Tests should exercise event-emission paths without requiring a live analytics runtime.
- Telemetry collection is force-disabled under XCTest (see `TelemetryManager.shouldEnableCollection`), so `TelemetryManager.shared` never emits in tests and assertions against it pass vacuously. To assert emission, build the manager with `makeTestTelemetry(sink:)` from `AscendAppTests/TelemetryTestSupport.swift` - it wires an `InMemoryTelemetrySink` with `collectionEnabledOverride: true` and calls `configure()`, which is what actually applies the override. Don't hand-roll that construction per test file. This is why emitters like `PostAuthOnboardingCoordinator` and `MonetizationManager` take an injected `TelemetryManager` instead of reaching for the singleton.

## Local inspection

DEBUG builds expose a developer-visible analytics console so events and screen views can be inspected without leaving the simulator (`DebugTelemetryConsoleSink`, `TelemetryConsoleView`).

## Onboarding funnel contract

Onboarding is the one funnel measured screen-by-screen, so it has a fixed contract: **21 visible screens, each emitting exactly one `onboarding_screen_viewed`**, plus a decision event on every interactive screen.
Read this before adding, removing, reordering, or renaming an onboarding screen - changing the flow means changing this table and the tests that enforce it.

Enforcement lives in `AscendAppTests/OnboardingAnalyticsEventTests.swift` (ordered screen coverage, dedupe, per-screen properties) and `AscendAppTests/OnboardingAnalyticsFunnelTranscriptTests.swift` (renders the whole funnel as a transcript from real emissions).
Those tests are the executable source of truth; this table is the readable one.

### The 21 screens, in order

`screen_id` equals `step_id` on every event. Every event also carries `flow_id`, `flow_version` (`v1`), `step_index`, `step_count`, and `app_environment`.

| # | screen_id | flow_id | Events beyond the view | Interactive sub-properties |
| --- | --- | --- | --- | --- |
| 1 | `welcome` | `pre_auth_welcome` | `onboarding_screen_completed` | `action_id=get_started` |
| 2 | `watch_yourself_get_better` | `pre_auth_value_onboarding` | `onboarding_screen_completed`, `onboarding_back_tapped` | `action_id` (`continue` / `swipe_forward`), `input_type` (`button` / `gesture`) |
| 3 | `reason_to_come_back` | `pre_auth_value_onboarding` | same as above | same as above |
| 4 | `auth` | `pre_auth_auth` | `onboarding_auth_started`, `onboarding_auth_completed`, `onboarding_auth_failed` | `provider` (`apple` / `google`), `reason` on failure |
| 5 | `displayName` | `post_auth_onboarding` | `onboarding_screen_completed` | `display_name_provided` |
| 6 | `stair_stepper_baseline` | `post_auth_onboarding` | `onboarding_question_answered`, `onboarding_screen_completed` | `question_id`, `answer_id`, `answer_index`, `selection_type=single_select`, `answer_count` |
| 7 | `exercise_level` | `post_auth_onboarding` | same as above | same as above |
| 8 | `goal` | `post_auth_onboarding` | same as above | same, `selection_type=multi_select` |
| 9 | `motivation` | `post_auth_onboarding` | same as above | same as above (single select) |
| 10 | `plan` | `post_auth_onboarding` | same as above | same as above (single select) |
| 11 | `summit_landmarks` | `post_auth_features` | `onboarding_screen_completed` | `action_id=continue` |
| 12 | `real_time` | `post_auth_features` | `onboarding_screen_completed` | `action_id=continue` |
| 13 | `daily_climbs` | `post_auth_features` | `onboarding_screen_completed` | `action_id=continue` |
| 14 | `gender` | `post_auth_onboarding` | `onboarding_screen_completed` | `profile_gender` (`ProfileGender` raw value) |
| 15 | `age` | `post_auth_onboarding` | `onboarding_screen_completed` | `profile_age_group` (bucket, never the birth date) |
| 16 | `weight` | `post_auth_onboarding` | `onboarding_screen_completed` | `measurement_system`, `profile_height_group`, `profile_weight_group` (buckets) |
| 17 | `location` | `post_auth_onboarding` | `onboarding_screen_completed` | `profile_country`, `selection_method` (`current_location` / `search` / `unknown`) |
| 18 | `notifications` | `post_auth_onboarding` | `onboarding_question_answered`, `onboarding_screen_completed` | `question_id=notifications`, `status`/`answer_id` (`allow` / `decline` / `skip`) |
| 19 | `loading` | `post_auth_onboarding` | `onboarding_screen_completed` | none - the only non-interactive screen |
| 20 | `first_climb` | `post_auth_onboarding` | `onboarding_question_answered` (`question_id=first_climb`), `onboarding_screen_completed` | `climb_id`, `climb_name` |
| 21 | `paywall` | `post_auth_onboarding` | `onboarding_paywall_reached`, `revenuecat_purchase_completed`, `revenuecat_restore_completed` | `placement`, `source`, `product_id`, `outcome` |

### Invariants that are easy to break

- **`displayName` and `weight` keep their historical screen IDs.** `displayName` is camelCase where every sibling is snake_case, and the `weight` screen captures both height and weight. Renaming either breaks funnel continuity in Mixpanel; they stay as-is.
- **The `features` stage is a container, not a screen.** It emits no view of its own - its three guide screens (`summit_landmarks`, `real_time`, `daily_climbs`) each report theirs, so counting the container would inflate the funnel with a screen nobody sees. `PostAuthOnboardingStage.visibleScreenAnalyticsContext` returns `nil` for it and only for it.
- **Views dedupe by `step_id`.** `OnboardingScreenViewRecorder` emits once per distinct step for the lifetime of the flow, so back-navigation and re-renders re-emit nothing. The dedupe is in-memory, so a relaunch mid-flow re-emits the current step.
- **Conditional screens report only when actually shown.** Never pre-emit a view for a screen the user may skip.
- **The routed `appAccessGate` joins this funnel.** `MonetizationManager.trackPaywallReached` emits `onboarding_paywall_reached` and records the `paywall` screen view through the same recorder for both `onboardingPaywall` and `appAccessGate`, so a retry through the placeholder never banks a second view.
- **The paywall is not a `PostAuthOnboardingStage`.** It continues the stage sequence by index and counts itself into `step_count` (`OnboardingAnalyticsEvent.paywallContext`).

## Reference
- `docs/sentry-setup.md` - Sentry role and app configuration.
- `docs/superwall-paywall-setup.md` - SuperWall placements and live IDs.

## Related
- Adding a new analytics SDK, or starting cross-app tracking, is a privacy-manifest tripwire - see `ascend-privacy-manifest`. The current manifest declares NO tracking and NO ads.
- Adding a Firebase Analytics or Mixpanel **user property** is the same tripwire: `AscendAppTests/PrivacyManifestTests.swift` scans the app target for literal `setUserProperty("…")` names and fails until the new one is classified against a declared, linked, non-tracking data type carrying the Analytics purpose. New event parameters aren't scanned - classify those by hand.
