import Foundation

/// A bounded, per-session ceiling on how much one running app may send to Sentry.
///
/// Nothing used to limit this. One `Swift.CancellationError` loop put 497 events
/// into the project in ten minutes and stopped only because its cause stopped,
/// burying the handful of production events that were worth reading.
///
/// The arithmetic is deliberately dull: a fixed window per group key, plus a
/// whole-session total. Both are ceilings, never samplers, so the same session
/// always makes the same decision - and protected events (crashes, watchdog
/// terminations, app hangs) are answered before any counter is consulted, so no
/// budget can ever be the reason one goes missing.
final class SentryEventFloodGuard: @unchecked Sendable {
    struct Limits: Equatable {
        /// Sized against the incident this exists to prevent: 497 events in ten
        /// minutes. A session that legitimately reports 200 distinct problems is
        /// not a session whose 201st report adds anything.
        static let live = Limits(
            sessionCap: 200,
            perKeyCap: 5,
            perKeyWindow: 60,
            trackedKeyCap: 128
        )

        /// Unprotected events one process may send before the guard closes.
        let sessionCap: Int
        /// Unprotected events one group key may send per `perKeyWindow`.
        let perKeyCap: Int
        /// Length of the fixed window a key's allowance resets on.
        let perKeyWindow: TimeInterval
        /// How many keys are tracked at once. Beyond this the coldest window is
        /// evicted, so a pathological stream of distinct keys cannot grow the map.
        let trackedKeyCap: Int
    }

    /// A key's fixed window: when it opened and how much of it has been spent.
    private struct Window {
        var openedAt: Date
        var count: Int
    }

    private let limits: Limits
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var windows: [String: Window] = [:]
    private var sessionCount = 0
    private var droppedCount = 0

    /// How many events this session has dropped so far. Stamped onto the events
    /// that do get through, so a guard that fires is visible rather than silent.
    var droppedEventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return droppedCount
    }

    init(limits: Limits = .live, now: @escaping @Sendable () -> Date = { Date() }) {
        self.limits = limits
        self.now = now
    }

    /// Answers whether this event may be sent, spending its budget if so.
    func allows(_ event: SentryFloodGuardEvent) -> Bool {
        // Both answered before any counter is read, and without spending any
        // budget. The protected branch is what makes the guard incapable of
        // dropping a crash or a fatal app hang; the non-error branch keeps the
        // guard aimed at the only thing it bounds, since transactions and replay
        // segments are metered by the SDK's own sample rates.
        guard event.isErrorEvent, !event.isProtected else { return true }

        lock.lock()
        defer { lock.unlock() }

        guard sessionCount < limits.sessionCap else {
            droppedCount += 1
            return false
        }

        let timestamp = now()
        var window = windows[event.groupKey] ?? Window(openedAt: timestamp, count: 0)

        if timestamp.timeIntervalSince(window.openedAt) >= limits.perKeyWindow {
            window = Window(openedAt: timestamp, count: 0)
        }

        guard window.count < limits.perKeyCap else {
            droppedCount += 1
            return false
        }

        window.count += 1
        windows[event.groupKey] = window
        sessionCount += 1
        evictColdWindowsIfNeeded(asOf: timestamp)
        return true
    }

    /// Keeps the map bounded: expired windows first, then the coldest remaining
    /// one. Evicting a key only ever restores its full allowance, which is the
    /// safe direction - the session cap still bounds the total either way.
    private func evictColdWindowsIfNeeded(asOf timestamp: Date) {
        guard windows.count > limits.trackedKeyCap else { return }

        windows = windows.filter { timestamp.timeIntervalSince($0.value.openedAt) < limits.perKeyWindow }

        while windows.count > limits.trackedKeyCap,
              let coldest = windows.min(by: { $0.value.openedAt < $1.value.openedAt })?.key {
            windows.removeValue(forKey: coldest)
        }
    }
}
