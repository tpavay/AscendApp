# Sentry Setup

Ascend uses Sentry as a diagnostics companion to Firebase Crashlytics.

## Role

- **Sentry**: issue triage, breadcrumbs, handled errors, release/environment filtering, and agent-assisted debugging.
- **Crashlytics**: Firebase-native crash-free metrics and release stability.
- **Mixpanel/Firebase Analytics**: product funnels, retention, and behavior analytics.

Sentry is not used for product analytics or cross-app tracking.

## App Configuration

**Sentry initialises in production only.** All three environments used to report into the one `ascend-ios` project, and the ones nobody is paged about set the noise floor for the one that matters: over 30 days staging sent 791 events and dev 533, against production's 23 - production was 2% of the volume in its own project.
Dev builds run on the developer's own machine where the Xcode console is the better tool, and staging failures are found by the person who caused them.
`SentryReportingPolicy` is the single gate, and it reads `TelemetryBuildMetadata.appEnvironment`; `SentryOptionsFactory.makeOptions` returns `nil` for anything else, so nothing downstream can start a client.

`SentryDiagnosticsConfigurationTests` proves the dev case against `SentrySDK.isEnabled` rather than by inspection.

The app reads Sentry config from `Info.plist`:

- `ASCEND_SENTRY_DSN`: the Sentry project DSN.
- `ASCEND_SENTRY_ENABLED`: optional kill switch for the in-app SDK only. Use `false`/`0`/`no`/`off` to stop the app from initializing Sentry and sending events.
  It does not gate dSYM upload: symbols are debug metadata with no user data, and upload stays independent so a shipped build can never become permanently unsymbolicated.

Sentry is still gated by `TelemetryManager.shouldEnableCollection()`, which forces collection off under XCTest and honours the debug toggles.

Events are tagged with:

- `app_environment`: `production`
- `build_config`: `release`
- `app_version`
- `build_number`
- `ascend_error_context` and `ascend_error_code` for handled errors
- `ascend_flood_guard_dropped` when this session has already dropped events (see below)

The first four come from `TelemetryBuildMetadata`, which also supplies Sentry's release name and dist and Mixpanel's environment super-properties, so a build reports identical values to both providers.
See `.claude/skills/ascend-analytics/SKILL.md` for the Mixpanel side.

## What a production error carries

`SentryOptionsFactory` is the one place these are decided.

- **A screenshot and a view hierarchy** (`attachScreenshot`, `attachViewHierarchy`). The SDK skips both for app hangs, because the main thread it would have to render on is the blocked one - so enabling them cannot cost an App Hang report.
- **A session replay of the seconds before the error** (`sessionReplay.onErrorSampleRate = 1`). `sessionSampleRate` stays at `0` deliberately: session recording is where replay cost runs away, and production sees roughly 23 errors a month.
- **Nothing else new.** `tracesSampleRate` is `0`, `sendDefaultPii` is `false`, and auto performance, user-interaction and file-I/O tracing all stay off.

## Masking

Ascend carries health data and account identity, so masking is a gate on shipping replay, not a follow-up.

- `maskAllText` and `maskAllImages` are set **explicitly** on both the replay and screenshot options, so a future SDK default flip cannot quietly start shipping a climber's heart rate, name, or account identifier.
- The SDK's own masking covers UIKit and SwiftUI text, images and SF Symbols, `WKWebView`, `PDFView`, and `AVPlayerView`. It does **not** cover anything an app draws itself.
- Ascend does draw its own: Swift Charts renders marks *and axis labels* through drawing layers the SDK does not recognise, and `AVPlayerLayer`-backed video is neither text nor a `UIImageView`. Before this was fixed, a masked screenshot of Workout Detail still showed the whole heart-rate trace with real BPM values on the axis.
- `View.sentryMasked()` overlays `SentryMaskedRegionView`, which is registered in `maskedViewClasses` for both replay and screenshots. Apply it to any surface that renders health data, identity, or user media in a way the SDK cannot see.
- The view hierarchy attachment carries no rendered content - class name, frame, alpha, visibility, view-controller class, and `accessibilityIdentifier`, which Ascend only ever sets to static literals.

What masking does **not** hide, and no configuration can: a masked region is the covered view's own frame, so a replay still shows that a label is wide, not what it says.

`AscendAppTests/SentryReplayMaskingEvidenceTests.swift` is the evidence. It renders each surface twice with sensitive content that is a permutation of itself - a reversed name, the same digits reordered, a mirrored photograph, a heart-rate trace played backwards - and asserts the two masked renders are the same image. The masked fill is the *average colour* of what it covered rather than a fixed black, so a permutation is exactly the comparison that isolates content from layout.

## Flood guard

Nothing used to limit what one session could send. A `Swift.CancellationError` loop put 497 events into the project in ten minutes and stopped only because its cause stopped.

`SentryEventFloodGuard` runs in `beforeSend`: a fixed window per group key (5 per 60s) plus a whole-session ceiling (200). Both are ceilings, never samplers, so the same session always makes the same decision. When it drops something, the next event that gets through carries `ascend_flood_guard_dropped`, so a fired guard is visible rather than silent.

**It cannot drop a crash or an app hang.** Protected events - anything at `fatal`, anything carrying the `AppHang` mechanism or an `App Hang` exception type, and any unhandled exception - are answered before a counter is read, and spend no allowance. `beforeSend` runs for crash events too, so this branch is the only thing standing between a noise guard and a real fatal report; `SentryEventFloodGuardTests` covers both the drop path and the protected path.

## MCP Workflow

Use Sentry MCP for agent triage:

```sh
codex mcp add sentry https://mcp.sentry.dev/mcp
```

Authentication should happen through Sentry OAuth or a local token flow. Do not commit Sentry tokens, auth headers, DSNs, or MCP credentials.

Typical prompt:

```text
Assess unresolved production Sentry errors from the past 14 days. Prioritize them, explain likely root causes, and fix the top actionable issue.
```

Use `.claude/skills/sentry/SKILL.md` for the triage rubric.

## Debug Symbols

For production-quality stack traces, both signed Fastlane build lanes run `scripts/upload-sentry-dsyms.sh` immediately after the archive is created and before the IPA is exported.
The staging and production workflows install a pinned Sentry CLI before invoking Fastlane.
The upload waits for Sentry to process the files under an explicit bounded timeout, so a degraded Sentry queue fails fast with a Sentry-specific error instead of consuming the release job's timeout.
Any missing token, CLI, archive dSYM directory, or upload failure stops the CI build before an unreadable IPA can reach TestFlight.

The script takes the dSYM directory to upload as its first argument; the lanes pass the archive's `dSYMs` folder.
With no argument it falls back to `DWARF_DSYM_FOLDER_PATH`.

Required CI/build environment:

- `SENTRY_AUTH_TOKEN`: secret token used by `sentry-cli`.
- `SENTRY_ORG`: optional; defaults to `ascend-uk`.
- `SENTRY_PROJECT`: optional; defaults to `ascend-ios`.
- `SENTRY_CLI_PATH`: optional; use only when `sentry-cli` is not on `PATH`.
- `SENTRY_WAIT_TIMEOUT`: optional; seconds to wait for server-side processing before failing. Defaults to `300`.

GitHub Actions validates and passes `secrets.SENTRY_AUTH_TOKEN` into the Fastlane staging and production build steps.
This does not belong in the private `match` repo; `match` should stay limited to certificates and provisioning profiles.

Local Fastlane archives skip Sentry dSYM upload when `SENTRY_AUTH_TOKEN` is missing.
CI archives fail when the secret is missing.
Keep Sentry auth tokens out of the repo.
