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

## Reference
- `docs/sentry-setup.md` - Sentry role and app configuration.
- `docs/superwall-paywall-setup.md` - SuperWall placements and live IDs.

## Related
- Adding a new analytics SDK, or starting cross-app tracking, is a privacy-manifest tripwire - see `ascend-privacy-manifest`. The current manifest declares NO tracking and NO ads.
