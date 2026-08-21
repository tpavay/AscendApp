import Foundation

/// What Ascend's two Sentry policies know about one event.
///
/// `SentryEventFloodGuard` reads it to decide what a runaway session may send,
/// and `SentryCrashContextPolicy` reads it to decide what earns a screenshot.
/// Both turn on the same question - is this event severe - so it is answered
/// once, here, rather than twice in two places that would drift apart.
///
/// Kept free of the Sentry SDK so both policies are testable without standing up
/// a client; `SentryEventClassification+SentryEvent` does the reading.
struct SentryEventClassification: Equatable {
    /// Events sharing a key share a budget. It approximates the grouping Sentry
    /// itself would apply, so one runaway error class spends only its own share.
    let groupKey: String

    /// A crash, a watchdog termination, or an app hang.
    ///
    /// These bypass every flood budget - losing one to a noise guard is worse
    /// than the noise it prevents - and they are the only events worth the
    /// synchronous main-thread render a screen capture costs.
    let isSevere: Bool

    /// Whether this is an error event at all. `beforeSend` sees every payload
    /// the SDK sends - transactions and replay segments included - and those
    /// arrive on the SDK's own schedule with their own sample rates, so counting
    /// them against an error-flood budget would throttle a mechanism that is not
    /// flooding and exhaust the session ceiling ahead of the errors it exists to
    /// protect.
    let isErrorEvent: Bool

    init(groupKey: String, isSevere: Bool, isErrorEvent: Bool = true) {
        self.groupKey = groupKey
        self.isSevere = isSevere
        self.isErrorEvent = isErrorEvent
    }
}
