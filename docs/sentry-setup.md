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

Sentry is still gated by `TelemetryManager.shouldEnableCollection()`, which forces collection off under XCTest, refuses a production build running on a simulator, and otherwise honours the debug toggles.
Because Sentry initialises in production only, that simulator refusal means a production build on a simulator sends nothing here either - reproduce on staging instead.
`.claude/skills/ascend-analytics/SKILL.md` owns that rule and why it sits above the launch-argument overrides.

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

- **A screenshot and a view hierarchy** (`attachScreenshot`, `attachViewHierarchy`), **for severe events only**. The SDK skips both for app hangs, because the main thread it would have to render on is the blocked one - so enabling them cannot cost an App Hang report.
  Producing either one renders the live UI *synchronously on the main thread* (`appScreenshotDatasFromMainThread`, `appViewHierarchyFromMainThread`), 36-160ms on the devices Ascend ships to.
  Ungated the SDK does that for every non-fatal error, and Ascend has 22 `recordError` call sites against a 200-event session ceiling - the same main-thread hazard that kept session replay out of the build, arriving through a different door.
  So `SentryCrashContextPolicy` answers both `beforeCaptureScreenshot` and `beforeCaptureViewHierarchy`, and admits only a **severe** event: `fatal` level, the `AppHang` mechanism or an `App Hang` exception type, or an unhandled exception mechanism.
  That is the same question `SentryEventClassification` already answers for the flood guard, asked once rather than in two places that would drift apart.
  **Nothing here can cost a crash its screenshot.** The crash handler writes that one itself (`sentrycrash_setSaveScreenshots`), and `SentryScreenshotIntegration` returns before consulting the policy for any event flagged fatal - so what actually reaches the callback is the ordinary non-fatal traffic it exists to decline, plus the rare severe event captured outside the crash path, which it admits.
  `SentryDiagnosticsConfigurationTests` holds both halves, and `SentryCrashContextEnvelopeEvidenceTests` is the end of that claim rather than its middle: it starts the real SDK on the shipped options and reads the envelopes off disk, so the ordinary error is proven to carry no attachment and the severe one to carry its context on the wire.
  **The picture half of that suite depends on the machine, and the tree half does not.** Each attachment makes its own read that resolves to the same `SentryApplication.getWindows()` - the screenshot through `SentryDependencyContainerSwiftHelper.windows()`, the tree through `SentryViewHierarchyProvider.appViewHierarchy()`'s own `applicationProvider()?.getWindows()` - and that call takes a scene-delegate window only from a `.foregroundActive` scene.
  A simulator booted headless under CI does not reliably stay foreground-active, and the two attachments then part ways: `SentryScreenshotSource.appScreenshots()` returns nothing for an empty window list while the view hierarchy serialises that same empty list and attaches anyway.
  So a severe event shipping `view-hierarchy.json` and no `screenshot.png` is the host having nothing to photograph, not the policy declining; the policy answers both callbacks with one function, so the tree arriving *is* the proof it admitted the event.
  The suite keys the picture on the window count in the SDK's own tree rather than on a second reading of `UIApplication`, because the tree reports what the SDK had in hand when it wrote the tree - a re-query of `UIApplication` would only be this suite's guess at a question the SDK is free to change.
  The residual, and it is a residual rather than a hole: two reads at two moments can in principle disagree within one send, so a host whose scene activates between them fails the severe-side screenshot expectation as if the policy had regressed.
  The suite asserts the absent case rather than skipping it, and prints one line per run naming the host, the windows the SDK found, and the attachments that left - read that line before concluding anything from either a green run or a red one.
- **No session replay. This is a decision, not an oversight - do not re-add it.** `sessionReplay.sessionSampleRate` and `sessionReplay.onErrorSampleRate` are both written out as `0`, and `SentryDiagnosticsConfigurationTests.sessionReplayIsOffOnBothAxes` holds them there.
  Replay was evaluated on this branch, wired up, and then removed on purpose, because `onErrorSampleRate` does not buy what its name suggests:
  - **On-error mode records the whole session *after* the first error, not the seconds before it.** `SentrySessionReplay.captureReplay(replayType:)` calls `startFullReplay()`, which flips the session to full recording for the rest of its life; the SDK then uploads a five-second segment continuously for up to `maximumDuration` - one hour, and `@_spi(Private)`, so not something the app can bound.
  - **Buffer mode runs in *every* session, error or not.** Any `onErrorSampleRate` above zero installs `SentrySessionReplayIntegration` (`SentrySessionReplayIntegration.swift:61`), which drives a `CADisplayLink` that renders and redacts a full screen on the main thread once a second for the entire foreground session, just in case an error later arrives.

  Fatal App Hangs are the top real production signal - roughly 51 events in 14 days, against 23 errors a month - so a per-second main-thread render and hierarchy walk is a cost paid squarely on the metric this project exists to protect, and the unbounded post-error upload is the cost axis the work set out to bound.
  Neither is fixable from the app's side. Re-adding replay means answering both, not just setting a rate.
- **Nothing else new.** `tracesSampleRate` is `0`, `sendDefaultPii` is `false`, and auto performance, user-interaction and file-I/O tracing all stay off.

## Masking

Ascend carries health data and account identity, so masking is a gate on shipping the crash screenshot, not a follow-up.

- `maskAllText` and `maskAllImages` are set **explicitly** on the screenshot options, so a future SDK default flip cannot quietly start shipping a climber's heart rate, name, or account identifier.
- The SDK's own masking covers UIKit and SwiftUI text, images and SF Symbols, `WKWebView`, `PDFView`, and `AVPlayerView`. It does **not** cover anything an app draws itself.
- Ascend does draw its own: Swift Charts renders marks *and axis labels* through drawing layers the SDK does not recognise, and `AVPlayerLayer`-backed video is neither text nor a `UIImageView`. Before this was fixed, a masked screenshot of Workout Detail still showed the whole heart-rate trace with real BPM values on the axis.
- `View.sentryMasked()` overlays `SentryMaskedRegionView`, which is registered in the screenshot options' `maskedViewClasses`. Apply it to any surface that renders health data, identity, or user media in a way the SDK cannot see.
- **The overlay reaches four points past the surface it covers, deliberately.** A layout frame is not a drawing bound: Swift Charts strokes its marks with a round cap, so the first and last point of a trend line paint about a point outside the chart's own frame. A mask sized exactly to that frame left one column of the climber's trace showing at each edge of `AscendTrendChart` - enough to read the first and last plotted value off a masked screenshot. The evidence suite is what caught it. Covering a hair more costs nothing, because the marker refuses every touch whatever its size.
- The view hierarchy attachment carries no rendered content - class name, frame, alpha, visibility, view-controller class, and `accessibilityIdentifier`, which Ascend only ever sets to static literals.

What masking does **not** hide, and no configuration can: a masked region is the covered view's own frame, so a screenshot still shows that a label is wide, not what it says.

`AscendAppTests/SentryMaskingEvidenceTests.swift` is the evidence. It renders each surface twice with sensitive content that is a permutation of itself - a reversed name, the same digits reordered, a mirrored photograph, a heart-rate trace played backwards, a fixture movie against its own mirror - and asserts the two masked renders are the same image. The masked fill is the *average colour* of what it covered rather than a fixed black, so a permutation is exactly the comparison that isolates content from layout.

The video cases render a real movie through a real `AVPlayer`, every frame of it the same picture so the comparison does not depend on two players sitting at the same playback position. Emptying `maskedViewClasses` fails the workout card and the share-composer background with a worst channel of 255: their footage really is on the wire without Ascend's marker. The full-screen player still passes under that experiment, because `SentryUIRedactBuilder` redacts `AVPlayerView` by default and `AVPlayerViewController` renders through one - so that case is evidence the footage is masked, not evidence that Ascend's mask is what masks it. Its marker stays anyway rather than resting the surface on a default list the SDK is free to change.

The masked surfaces are interactive - chart scrubbing, video transport controls, the share composer's pan and pinch - so the marker covers a region without owning it: `SentryMaskedRegionView` reports a real frame and refuses every touch that lands on it.
`AscendAppTests/SentryMaskInteractionTests.swift` holds that, asserting the refusal and the non-empty frame together so a mask cannot pass the touch test by shrinking.
Read its suite comment before treating a green run as proof a chart still scrubs: the three video surfaces are covered end to end **for touch**, the four charts structurally only.
That end-to-end claim is about touch reaching the video, and has never been about masking - the masking evidence for those surfaces is the paragraph above.
Add every new masked surface to both suites. All seven are in both today.

## Flood guard

Nothing used to limit what one session could send. A `Swift.CancellationError` loop put 497 events into the project in ten minutes and stopped only because its cause stopped.

`SentryEventFloodGuard` runs in `beforeSend`: a fixed window per group key (5 per 60s) plus a whole-session ceiling (200). Both are ceilings, never samplers, so the same session always makes the same decision. When it drops something, the next event that gets through carries `ascend_flood_guard_dropped`, so a fired guard is visible rather than silent.

**It cannot drop a crash or an app hang.** Protected events - anything at `fatal`, anything carrying the `AppHang` mechanism or an `App Hang` exception type, and any unhandled exception - are answered before a counter is read, and spend no allowance.
`beforeSend` runs for crash events too, so that branch is the only thing standing between a noise guard and a real fatal report; `SentryEventFloodGuardTests` covers both the drop path and the protected path.

**It only bounds error events.** `beforeSend` sees everything the SDK sends, and a transaction or a replay segment arrives on the SDK's own schedule under its own sample rate, so charging one to an error budget would throttle a mechanism that is not flooding and exhaust the session ceiling ahead of the errors the guard exists to protect.
Those payloads are exempted before a counter is read, on the same terms as protected events. `SentryEventClassification` reads `event.type` as an allow-list of the non-error types rather than off the absence of a type - sentry-cocoa leaves it nil on errors, other Sentry SDKs spell `error` out, and both count as an error - so an SDK that started stamping errors explicitly cannot quietly turn the guard into a no-op.

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
The upload waits for Sentry to process the files under an explicit bounded timeout, so a degraded Sentry queue fails fast instead of consuming the release job's timeout.
Any missing token, CLI, archive dSYM directory, or upload failure stops the CI build before an unreadable IPA can reach TestFlight.

`sentry-cli` cannot tell those two failures apart on its own.
When `--wait-for` expires it prints `ERROR <file>` followed by its fallback text `An unknown error occurred` for a file that was uploaded fine and is merely still queued, which is indistinguishable from a rejected symbol file - it cost staging run 33434685667 two identical failures during Sentry's US ingestion backlog on 2026-08-31.
The script therefore times the invocation and says which of the two happened, because elapsed time separates them and does not move when the pinned CLI moves.
A failure that reaches the full `SENTRY_WAIT_TIMEOUT` is a Sentry-side processing delay: the symbols are already uploaded, `https://status.sentry.io` will usually say so, and re-running the deploy once Sentry recovers is the whole fix.

The server's own reason for a genuine rejection is only reachable with `sentry-cli --log-level=debug`, which logs response bodies and request headers.
Its `Authorization` redaction keeps the token's first eight characters and this repository is public, so that flag stays out of CI and belongs in a local re-run.

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
