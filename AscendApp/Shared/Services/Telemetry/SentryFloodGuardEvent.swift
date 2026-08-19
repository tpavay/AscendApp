import Foundation

/// The two facts `SentryEventFloodGuard` needs about one event.
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

    init(groupKey: String, isProtected: Bool) {
        self.groupKey = groupKey
        self.isProtected = isProtected
    }
}
