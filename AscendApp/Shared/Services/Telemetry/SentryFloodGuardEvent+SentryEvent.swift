import Foundation
@preconcurrency import Sentry

extension SentryFloodGuardEvent {
    /// The exception mechanism the SDK stamps on every app hang, fatal or not.
    ///
    /// Verified against sentry-cocoa 9.18.0 `SentryHangTrackingIntegration`.
    private static let appHangMechanism = "AppHang"

    /// Substring shared by all five app-hang exception types the SDK emits
    /// (`App Hanging`, `App Hang Fully Blocked`, `App Hang Non Fully Blocked`,
    /// and the two `Fatal App Hang ...` variants in `SentryAppHangTypeMapper`).
    /// Matching the family rather than the five literals keeps a renamed variant
    /// protected instead of silently demoting it to droppable noise.
    private static let appHangExceptionMarker = "App Hang"

    init(event: Event) {
        self.init(
            groupKey: Self.groupKey(for: event),
            isProtected: Self.isProtected(event),
            isErrorEvent: event.type == nil
        )
    }

    /// Whether the flood guard must not be allowed to touch this event.
    ///
    /// Three independent signals, any one of which is enough. `beforeSend` runs
    /// for crash events too, so this is the only thing standing between a noise
    /// guard and a real fatal report.
    private static func isProtected(_ event: Event) -> Bool {
        // Crash reports, watchdog terminations and fatal app hangs all arrive at
        // fatal (`SentryCrashReportConverter`, `SentryHangTrackingIntegration`).
        if event.level == .fatal { return true }

        guard let exceptions = event.exceptions else { return false }

        return exceptions.contains { exception in
            if exception.mechanism?.type == appHangMechanism { return true }
            if exception.type?.contains(appHangExceptionMarker) == true { return true }
            // An unhandled exception is by definition something that ended the
            // process, whatever mechanism name a future SDK gives it.
            return exception.mechanism?.handled?.boolValue == false
        }
    }

    /// The budget an event spends from, closest-to-Sentry's-own-grouping first.
    ///
    /// Only reached for error events: the SDK leaves `type` nil on those and
    /// stamps it on everything else (`transaction`, `replay_video`), which is
    /// what `isErrorEvent` reads.
    ///
    /// Every branch resolves to a bounded string in practice - an exception type
    /// is an error domain, a mechanism a fixed vocabulary - and
    /// `SentryEventFloodGuard` bounds the tracked key count regardless.
    private static func groupKey(for event: Event) -> String {
        if let fingerprint = event.fingerprint, !fingerprint.isEmpty {
            return fingerprint.joined(separator: "|")
        }

        if let exception = event.exceptions?.first {
            let mechanism = exception.mechanism?.type ?? "none"
            return "\(exception.type ?? "exception")|\(mechanism)"
        }

        if let error = event.error as NSError? {
            return "\(error.domain)|\(error.code)"
        }

        if let message = event.message?.message ?? event.message?.formatted {
            return message
        }

        return event.type ?? "unknown"
    }
}
