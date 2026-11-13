import Foundation

/// Receives an `ascendstepper.com/go` universal link and does exactly one thing: report it.
///
/// The link opens the app to wherever the climber's launch would have taken them anyway - the
/// onboarding gate, the first paywall, the founder letter or Home. Nothing here routes, presents,
/// reads the account or writes persisted state, so there is nothing for it to race with, and the
/// remote kill switches that guard data-shaping paths have nothing to guard. The undo for the link
/// itself is on the server: take the paths out of the apple-app-site-association file.
@MainActor
final class GoLinkHandler {
    static let shared = GoLinkHandler()

    /// SwiftUI may deliver one universal link through both `onOpenURL` and
    /// `onContinueUserActivity`, so the same link inside this window is one open.
    static let duplicateWindow: TimeInterval = 5

    private let telemetry: TelemetryManager
    private let activityClock: AppActivityClock
    private let now: () -> Date
    private var lastHandled: (url: URL, at: Date)?

    init(
        telemetry: TelemetryManager = .shared,
        activityClock: AppActivityClock = .shared,
        now: @escaping () -> Date = { .now }
    ) {
        self.telemetry = telemetry
        self.activityClock = activityClock
        self.now = now
    }

    /// Returns true when `url` is a `/go` link, whether or not it was a duplicate, so the app's
    /// other URL handlers never see it.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let link = GoLink(url: url) else { return false }

        let moment = now()
        if let lastHandled,
           lastHandled.url == url,
           moment.timeIntervalSince(lastHandled.at) < Self.duplicateWindow {
            return true
        }
        lastHandled = (url, moment)

        // A process that has never been backgrounded is the one this link started. A resume from
        // the background has been backgrounded by definition.
        telemetry.track(
            GoLinkAnalyticsEvent.opened(
                source: link.source,
                sessionType: activityClock.hasEnteredBackground ? .foreground : .coldLaunch
            )
        )
        return true
    }
}
