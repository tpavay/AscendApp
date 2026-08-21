import Foundation

/// Which events earn the picture and the view tree that go beside a stack trace.
///
/// Both attachments are produced by rendering the live UI **synchronously on the
/// main thread** - `appScreenshotDatasFromMainThread()` and
/// `appViewHierarchyFromMainThread()` - which measures 36-160ms on the devices
/// Ascend ships to. Left ungated the SDK does that for every non-fatal error, and
/// Ascend has 22 `recordError` call sites feeding a session ceiling of 200
/// events: a bad afternoon of retryable network failures would spend seconds of
/// main thread on pictures of a spinner. That is the same hazard that kept
/// session replay out of the build, arriving through a different door.
///
/// So a capture is taken only for a severe event - a crash, a watchdog
/// termination, or an app hang - which is what `SentryEventClassification`
/// already answers for the flood guard.
///
/// Nothing here can cost a crash its screenshot. A crash's picture is written by
/// the crash handler itself (`sentrycrash_setSaveScreenshots`), and
/// `SentryScreenshotIntegration` returns before consulting this policy for any
/// event flagged fatal or for an app hang, whose main thread is by definition
/// already blocked. What reaches this policy is therefore the ordinary
/// non-fatal traffic it exists to decline, plus the rare severe event captured
/// outside the crash path - which it admits.
enum SentryCrashContextPolicy {
    /// `true` only for events severe enough to be worth a main-thread render.
    static func attachesScreenCapture(for classification: SentryEventClassification) -> Bool {
        classification.isSevere
    }
}
