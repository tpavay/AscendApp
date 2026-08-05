---
name: ascend-analytics
description: Use when working on Ascend analytics or telemetry - event definitions, the analytics facade, telemetry sinks (Firebase Analytics, Mixpanel, SuperWall, Crashlytics, Sentry), screen tracking, funnel/engagement/quality measurement, event parameter privacy, the server-exported subscription lifecycle events, or the debug telemetry console. Covers what is worth logging, which destination owns which job, and the low-cardinality parameter rule.
paths:
  - AscendApp/Shared/Services/Telemetry/**
  - AscendApp/Features/*/Analytics/**
  - functions/src/revenueCat/analytics*.ts
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
- **Mixpanel** - product funnel, retention, and behavior analytics.
  The client sink is `MixpanelTelemetrySink`, configured from the `AscendMixpanelToken` and `AscendMixpanelProjectID` Info.plist keys.
  Debug, Staging, and Release each report to a dedicated project, and the sink fails closed when the compiled environment and project ID disagree.
  Cloud Functions also export subscription lifecycle events straight to Mixpanel, routed per environment - see "Mixpanel environment separation and event envelope" and "Server-owned subscription lifecycle events" below.
- **SuperWall** - onboarding-flow step-level conversion + paywall presentation analytics (its specialty).
- **Crashlytics** - crashes, fatal errors, stability metrics.
- **Sentry** - error/crash diagnostics mirror alongside Crashlytics (non-fatal errors, app hangs, symbolicated traces). When reading, triaging, or updating Sentry issues/events, use the `sentry` skill.

When evaluating new providers, justify them by what they uniquely measure that the existing set doesn't.

## Mixpanel environment separation and event envelope

Debug reports to Development `4032860`, Staging reports to Staging `4051102`, and Release reports to Production `4051100`.
`ASCEND_MIXPANEL_TOKEN` and `ASCEND_MIXPANEL_PROJECT_ID` are compile-time Xcode settings expanded through Info.plist.
`scripts/ci/assert-mixpanel-build-settings.mjs` resolves all three configurations and rejects empty, incorrect, or duplicate destinations without printing token values.
Archive workflows also inspect the processed app bundle with `scripts/ci/assert-mixpanel-bundle.mjs` before upload.

Every event and screen carries `app_environment`, `build_config`, `app_version`, and `build_number` directly in its payload through `TelemetryEnvelope`.
The `TelemetrySink` boundary accepts only enveloped records, so a feature call site cannot omit those fields or spoof them with event parameters.
Mixpanel still registers the same values as super-properties before first use and after SDK state resets as defense in depth.
`AscendAppTests/TelemetryEnvelopeTests.swift`, `AscendAppTests/TelemetryManagerTests.swift`, and `AscendAppTests/MixpanelTelemetrySinkTests.swift` enforce the runtime contract.

Events recorded before this tagging shipped carry none of these properties, and that history cannot be separated retroactively.
Treat historical untagged events in Development as unattributable rather than as clean production data.

## Server-owned subscription lifecycle events

Subscription transitions mostly happen while the app is closed - renewal, cancellation, uncancellation, billing issue, expiration, refund, product change - so the client cannot observe them.
Cloud Functions export them to Mixpanel from a durable Firestore outbox filled by the RevenueCat webhook, never from device code.
Do not add a client event for a transition that stream already reports, and do not route these through `TelemetrySink`.

They carry the same `app_environment`, `build_config`, `app_version`, and `build_number` envelope as client events, with the server's own values (`build_config=server`, `app_version=cloud_functions`).
They are routed by the deployed Firebase project rather than by a compiled build setting, into the same per-environment Mixpanel project the matching client build reports to.
Pick the right project first, then separate server from client events by `build_config=server`.

`docs/revenuecat-server-entitlement-enforcement.md` owns that exporter - the exactly-once outbox contract, the destination map, the retention bound, and the captain-side Mixpanel service-account and secret setup.
`functions/src/revenueCat/analyticsEnvironment.ts` and `LifecycleAnalyticsEventName` in `functions/src/revenueCat/analyticsTypes.ts` are the executable source of truth for the destinations and the event names; read them rather than a copy.

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

Enforcement lives in `AscendAppTests/OnboardingAnalyticsEventTests.swift` (ordered screen coverage, dedupe, per-screen properties), `AscendAppTests/OnboardingAnalyticsFunnelTranscriptTests.swift` (renders the whole funnel as a transcript from real emissions, and asserts the clean-pass event counts plus the resumed and back-navigation paths), and `AscendAppTests/OnboardingFlowAnalyticsCoordinatorTests.swift` (the one lifecycle pair: pass persistence, account ownership, and completion attribution).
Those tests are the executable source of truth; this table is the readable one.

### The 21 screens, in order

`screen_id` equals `step_id` on every event.
Every event also carries `flow_id=onboarding`, `flow_version=v1`, `segment_id`, `step_index`, `step_count=21`, and `app_environment`.
The segment labels identify nested implementation sections and never replace the user-level flow ID.
`step_index` is zero-based against that ordered list, so the paywall reports `step_index` 20 with `step_count` 21.
`onboarding_flow_started` and `onboarding_screen_viewed` also carry `resume`, and `onboarding_flow_completed` carries `completion_reason`.

| # | screen_id | segment_id | Events beyond the view | Interactive sub-properties |
| --- | --- | --- | --- | --- |
| 1 | `welcome` | `pre_auth_welcome` | `onboarding_screen_completed` | `action_id` (`get_started` / `sign_in` for the returning-climber route), `input_type=button` |
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
- **`step_index` is derived from `OnboardingAnalyticsContext.orderedStepIDs`, never passed in.** Contexts are built from content arrays, so a page added to a carousel or guide can drift out of that list; onboarding is the one flow a user cannot route around, so drift asserts in development and reports `step_index` `-1` in production rather than terminating the app. A `-1` in the funnel means a screen was added without being added to the ordered list.
- **The routed `appAccessGate` joins this funnel.** `MonetizationManager.trackPaywallReached` emits `onboarding_paywall_reached` and records the `paywall` screen view through the same recorder for both `onboardingPaywall` and `appAccessGate`, so a retry through the placeholder never banks a second view.
- **The paywall is not a `PostAuthOnboardingStage`.** It is still the canonical user-level last screen through `OnboardingAnalyticsEvent.paywallContext`, which resolves its index from the same ordered list every other screen uses.
- **Only `OnboardingFlowAnalyticsCoordinator` owns the lifecycle pair.** It starts at the first onboarding screen the install shows - welcome on a clean run, the resumed step when a reinstall keeps the Keychain session but not `UserDefaults` - persists that start across relaunch, and completes only after active access routes the app to Home. A pass that opens past the first canonical step says `resume=true` on its start and on the one screen it comes back to; nothing else in the pass does.
- **A pass belongs to one account.** A pass opened before auth is adopted by the account that finishes it; a different account, a sign-out of the account that adopted it, an account deletion, or a debug replay retires it, so one climber's abandoned start can never be closed by the next climber's completion.
- **Losing the authenticated identity is not a sign-out.** Firebase reports "no user" on every signed-out cold launch too, and that report reaches `MonetizationManager.prepareIdentityReset` before any screen renders, so only `retireAdoptedPass` may run there: a pass no account has claimed survives the relaunch and re-emits nothing.
- **`completion_reason` is attributed from evidence, never from timing.** `existing_entitlement` means this pass never asked for a grant. While a paywall presentation or a restore is in flight, there is no reason to report at all - the entitlement can turn active before the outcome says how. Once the request reports, `purchase`/`restore` come from that result, and a request that reported nothing still means whatever turns access on afterwards was that grant.
- **Grant provenance is part of the pass, not of the process.** `OnboardingAccessGrantProvenance` is persisted inside the same `PassState` it describes and is retired with it, because the app can die on the StoreKit sheet between the purchase and the route to Home. A request the process died holding is settled to "reported nothing" when the next process loads the pass - it can never report, and deferring forever would cost the completion entirely.
- **Nested owners are segments.** The value carousel, auth surface, post-auth stages, and feature guide set `segment_id`; none may emit `onboarding_flow_started` or `onboarding_flow_completed`.

## Reference
- `docs/sentry-setup.md` - Sentry role and app configuration.
- `docs/superwall-paywall-setup.md` - SuperWall placements and live IDs.

## Related
- Adding a new analytics SDK, or starting cross-app tracking, is a privacy-manifest tripwire - see `ascend-privacy-manifest`. The current manifest declares NO tracking and NO ads.
- Adding a Firebase Analytics or Mixpanel **user property** is the same tripwire: `AscendAppTests/PrivacyManifestTests.swift` scans the app target for literal `setUserProperty("…")` names and fails until the new one is classified against a declared, linked, non-tracking data type carrying the Analytics purpose. New event parameters aren't scanned - classify those by hand in `AscendAppTests/PrivacyAnalyticsClassification.md`, which owns the property-and-parameter-to-data-type mapping.
