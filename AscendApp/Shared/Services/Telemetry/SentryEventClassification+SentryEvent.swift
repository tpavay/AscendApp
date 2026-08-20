import Foundation
@preconcurrency import Sentry

extension SentryEventClassification {
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

    /// The wire name for an error event.
    ///
    /// sentry-cocoa 9.18 leaves `type` nil on errors and stamps it only on the
    /// payloads that are not errors, but Sentry's other SDKs already send the
    /// explicit `error` type, so both spellings are read as an error here.
    private static let errorEventType = "error"

    init(event: Event) {
        self.init(
            groupKey: Self.groupKey(for: event),
            isSevere: Self.isSevere(event),
            isErrorEvent: Self.isErrorEvent(event)
        )
    }

    /// Whether the flood guard is the right thing to meter this payload at all.
    ///
    /// Read as an allow-list of the non-error types rather than off the absence
    /// of a type: an SDK that started spelling errors explicitly would otherwise
    /// classify every event as non-error, and the guard would quietly stop
    /// bounding anything while every test still passed.
    private static func isErrorEvent(_ event: Event) -> Bool {
        guard let type = event.type else { return true }
        return type == errorEventType
    }

    /// Whether this event is severe enough that the flood guard must not touch
    /// it and a screen capture is worth taking for it.
    ///
    /// Three independent signals, any one of which is enough. `beforeSend` runs
    /// for crash events too, so this is the only thing standing between a noise
    /// guard and a real fatal report.
    private static func isSevere(_ event: Event) -> Bool {
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
    /// Only reached for error events, which are the ones `isErrorEvent` admits.
    ///
    /// The exception branch reads the **last** entry, because that is the error
    /// that was reported: `SentryClient.buildErrorEvent` flattens the
    /// `NSUnderlyingErrorKey` chain and appends it in reverse, so `first` is the
    /// innermost cause and `last` is the root. Keying on the innermost one would
    /// make every distinct error that happens to wrap the same cause share a
    /// single allowance.
    ///
    /// The domain alone is likewise too coarse. `exceptionForError` sets `type`
    /// to `error.domain` and carries the code separately in
    /// `mechanism.meta.error`, which is what Sentry's own grouping keys on - so
    /// the code joins the key whenever the SDK recorded one, and
    /// `FIRFirestoreErrorDomain` code 7 keeps its own budget while code 14
    /// floods.
    ///
    /// Every branch resolves to a bounded string in practice - an error domain,
    /// a mechanism from a fixed vocabulary, an integer code - and
    /// `SentryEventFloodGuard` bounds the tracked key count regardless.
    private static func groupKey(for event: Event) -> String {
        if let fingerprint = event.fingerprint, !fingerprint.isEmpty {
            return fingerprint.joined(separator: "|")
        }

        if let exception = event.exceptions?.last {
            let mechanism = exception.mechanism?.type ?? "none"
            let underlying = exception.mechanism?.meta?.error
            let domain = underlying?.domain ?? exception.type ?? "exception"
            let code = underlying.map { "|\($0.code)" } ?? ""
            return "\(domain)|\(mechanism)\(code)"
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
