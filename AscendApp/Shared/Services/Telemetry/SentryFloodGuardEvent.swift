import Foundation

/// The three facts `SentryEventFloodGuard` needs about one event.
///
/// Kept free of the Sentry SDK so the guard's arithmetic is testable without
/// standing up a client; `SentryFloodGuardEvent+SentryEvent` does the reading.
struct SentryFloodGuardEvent: Equatable {
    /// Events sharing a key share a budget. It approximates the grouping Sentry
    /// itself would apply, so one runaway error class spends only its own share.
    let groupKey: String

    /// A crash, a watchdog termination, or an app hang. These bypass every
    /// budget: losing one to a noise guard is worse than the noise it prevents.
    let isProtected: Bool

    /// Whether this is an error event at all. `beforeSend` sees every payload
    /// the SDK sends - transactions and replay segments included - and those
    /// arrive on the SDK's own schedule with their own sample rates, so counting
    /// them against an error-flood budget would throttle a mechanism that is not
    /// flooding and exhaust the session ceiling ahead of the errors it exists to
    /// protect.
    let isErrorEvent: Bool

    init(groupKey: String, isProtected: Bool, isErrorEvent: Bool = true) {
        self.groupKey = groupKey
        self.isProtected = isProtected
        self.isErrorEvent = isErrorEvent
    }
}
