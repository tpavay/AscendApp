import Foundation
@preconcurrency import Sentry

/// Builds the one `Options` object Ascend starts Sentry with.
///
/// Separate from `SentryDiagnosticsReporter` so every decision in it - which
/// environments report, what a crash carries, what masking is applied - can be
/// asserted without starting an SDK client.
enum SentryOptionsFactory {
    /// `nil` when this environment must not initialise Sentry at all.
    static func makeOptions(
        configuration: SentryConfiguration,
        buildMetadata: TelemetryBuildMetadata,
        floodGuard: SentryEventFloodGuard
    ) -> Options? {
        let policy = SentryReportingPolicy(buildMetadata: buildMetadata)
        guard policy.startsSentry, configuration.canConfigure, let dsn = configuration.dsn else {
            return nil
        }

        let options = Options()
        options.dsn = dsn
        options.environment = buildMetadata.appEnvironment
        options.releaseName = buildMetadata.releaseName
        options.dist = buildMetadata.buildNumber
        options.sendDefaultPii = false
        options.tracesSampleRate = 0
        options.enableAutoPerformanceTracing = false
        options.enableUserInteractionTracing = false
        options.enableFileIOTracing = false

        applyCrashContext(to: options)
        disableSessionReplay(on: options)
        applyFloodGuard(to: options, floodGuard: floodGuard)

        return options
    }

    /// A stack trace alone rarely says what the climber was looking at, so a
    /// crash carries a picture and the view tree with it.
    ///
    /// The screenshot is masked before it exists - the SDK routes it through
    /// `SentryViewPhotographer` with `options.screenshot` as its redaction
    /// options, so covered content is painted out before the PNG does. The view
    /// hierarchy carries no rendered content at all: class name, frame, alpha,
    /// visibility, view-controller class, and `accessibilityIdentifier`, which
    /// Ascend only ever sets to static literals.
    ///
    /// Neither attachment is taken for app hangs: the SDK skips both when the
    /// main thread is blocked, so enabling them cannot cost an App Hang report.
    private static func applyCrashContext(to options: Options) {
        options.attachScreenshot = true
        options.attachViewHierarchy = true
        options.reportAccessibilityIdentifier = true
        options.screenshot = makeScreenshotOptions()
    }

    /// The redaction applied to crash screenshots.
    ///
    /// Exposed so `SentryMaskingEvidenceTests` can prove the shipped
    /// configuration rather than a hand-rolled copy of it.
    static func makeScreenshotOptions() -> SentryViewScreenshotOptions {
        let screenshot = SentryViewScreenshotOptions()
        screenshot.maskAllText = true
        screenshot.maskAllImages = true
        screenshot.maskedViewClasses = maskedViewClasses
        return screenshot
    }

    /// Session replay is deliberately not shipped, and both rates are written
    /// out rather than left to the SDK's defaults so the decision is legible and
    /// testable.
    ///
    /// With both at zero `SentrySessionReplayIntegration` refuses to install at
    /// all, so nothing buffers, no `CADisplayLink` renders the screen once a
    /// second on the main thread, and no `replay_video` event is ever produced.
    /// The two reasons it stays off: per-session capture is where replay cost
    /// runs away, and the per-second main-thread render would land on Fatal App
    /// Hangs, which are the most important real signal production has.
    private static func disableSessionReplay(on options: Options) {
        options.sessionReplay.sessionSampleRate = 0
        options.sessionReplay.onErrorSampleRate = 0
    }

    /// What the SDK's own text and image classes cannot see.
    ///
    /// `SentryMaskedRegionView` is the marker `View.sentryMasked()` overlays on
    /// anything Ascend draws itself - the charts, chiefly, whose marks and axis
    /// labels are not text or images as far as the SDK is concerned, and the
    /// `AVPlayerLayer`-backed video views. Matching walks the superclass chain,
    /// so registering the marker covers every use of it.
    ///
    /// A crash screenshot is the only surface that needs it today; it needed it
    /// before replay was considered and still needs it now replay is not shipped.
    private static var maskedViewClasses: [AnyClass] {
        [SentryMaskedRegionView.self]
    }

    /// Bounds what one runaway session can send, and says so on the events that
    /// still get through so a fired guard is never silent.
    private static func applyFloodGuard(to options: Options, floodGuard: SentryEventFloodGuard) {
        options.beforeSend = { event in
            guard floodGuard.allows(SentryFloodGuardEvent(event: event)) else { return nil }

            let dropped = floodGuard.droppedEventCount
            if dropped > 0 {
                var tags = event.tags ?? [:]
                tags["ascend_flood_guard_dropped"] = String(dropped)
                event.tags = tags
            }

            return event
        }
    }
}
