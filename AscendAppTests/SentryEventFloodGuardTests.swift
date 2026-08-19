import Foundation
import Testing
@preconcurrency import Sentry
@testable import AscendApp

/// The flood guard exists because one runaway error class buried the project:
/// a `Swift.CancellationError` loop sent 497 events in ten minutes and stopped
/// only when its cause did. It is a ceiling, and the one thing it must never do
/// is take a crash or an app hang down with the noise.
@Suite
struct SentryEventFloodGuardTests {
    private static let limits = SentryEventFloodGuard.Limits(
        sessionCap: 10,
        perKeyCap: 3,
        perKeyWindow: 60,
        trackedKeyCap: 4
    )

    private static func noise(_ key: String = "com.google.fcm|none") -> SentryFloodGuardEvent {
        SentryFloodGuardEvent(groupKey: key, isProtected: false)
    }

    private static func protected(_ key: String = "SIGSEGV|mach") -> SentryFloodGuardEvent {
        SentryFloodGuardEvent(groupKey: key, isProtected: true)
    }

    // MARK: - The drop path

    @Test
    func oneRunawayErrorClassSpendsOnlyItsOwnAllowance() {
        let clock = TestClock()
        let guardUnderTest = SentryEventFloodGuard(limits: Self.limits, now: clock.now)

        let verdicts = (0..<10).map { _ in guardUnderTest.allows(Self.noise()) }

        #expect(verdicts.prefix(3).allSatisfy { $0 })
        #expect(verdicts.dropFirst(3).allSatisfy { !$0 })
        #expect(guardUnderTest.droppedEventCount == 7)
        // A different error class is untouched by the first one's flood.
        #expect(guardUnderTest.allows(Self.noise("AuthenticationError|none")))
    }

    @Test
    func anAllowanceReopensOnceItsWindowHasPassed() {
        let clock = TestClock()
        let guardUnderTest = SentryEventFloodGuard(limits: Self.limits, now: clock.now)

        for _ in 0..<3 { _ = guardUnderTest.allows(Self.noise()) }
        #expect(!guardUnderTest.allows(Self.noise()))

        clock.advance(by: Self.limits.perKeyWindow)

        #expect(guardUnderTest.allows(Self.noise()))
    }

    @Test
    func theSessionCapStopsAFloodSpreadAcrossManyErrorClasses() {
        let clock = TestClock()
        let guardUnderTest = SentryEventFloodGuard(limits: Self.limits, now: clock.now)

        // A fresh key every time defeats the per-key allowance entirely, which is
        // exactly what the session cap is for.
        let verdicts = (0..<20).map { guardUnderTest.allows(Self.noise("error-\($0)")) }

        #expect(verdicts.filter { $0 }.count == Self.limits.sessionCap)
        #expect(guardUnderTest.droppedEventCount == 20 - Self.limits.sessionCap)
    }

    // MARK: - The protected path

    @Test
    func aCrashIsSentNoMatterHowFarPastEveryCeilingTheSessionIs() {
        let clock = TestClock()
        let guardUnderTest = SentryEventFloodGuard(limits: Self.limits, now: clock.now)

        // Exhaust the session cap several times over.
        for index in 0..<200 { _ = guardUnderTest.allows(Self.noise("error-\(index)")) }
        #expect(!guardUnderTest.allows(Self.noise("error-0")))

        #expect(guardUnderTest.allows(Self.protected()))
        // Repeatedly, and without ever spending an allowance of its own.
        #expect((0..<50).allSatisfy { _ in guardUnderTest.allows(Self.protected()) })
    }

    @Test
    func aProtectedEventNeverConsumesTheBudgetItBypasses() {
        let clock = TestClock()
        let guardUnderTest = SentryEventFloodGuard(limits: Self.limits, now: clock.now)

        for _ in 0..<50 { _ = guardUnderTest.allows(Self.protected("AppHang|AppHang")) }

        // The noise budget is untouched: protected events are answered before any
        // counter is read.
        #expect((0..<Self.limits.perKeyCap).allSatisfy { _ in guardUnderTest.allows(Self.noise()) })
        #expect(guardUnderTest.droppedEventCount == 0)
    }

    // MARK: - Classification

    @Test(arguments: [
        "App Hanging",
        "App Hang Fully Blocked",
        "App Hang Non Fully Blocked",
        "Fatal App Hang Fully Blocked",
        "Fatal App Hang Non Fully Blocked"
    ])
    func everyAppHangTheSDKEmitsIsProtected(exceptionType: String) {
        let event = Event(level: .error)
        let exception = Exception(value: "App hanging for at least 2000 ms.", type: exceptionType)
        exception.mechanism = Mechanism(type: "AppHang")
        event.exceptions = [exception]

        #expect(SentryFloodGuardEvent(event: event).isProtected)
    }

    @Test
    func aFatalEventIsProtectedWhateverItsShape() {
        // Crash reports, watchdog terminations and fatal app hangs all arrive at
        // fatal, and a crash report carries no exception the guard could inspect.
        #expect(SentryFloodGuardEvent(event: Event(level: .fatal)).isProtected)
    }

    @Test
    func anUnhandledExceptionIsProtectedEvenUnderAMechanismNameWeDoNotKnow() {
        let event = Event(level: .error)
        let exception = Exception(value: "boom", type: "SomeFutureCrashType")
        let mechanism = Mechanism(type: "a_mechanism_from_a_later_sdk")
        mechanism.handled = false
        exception.mechanism = mechanism
        event.exceptions = [exception]

        #expect(SentryFloodGuardEvent(event: event).isProtected)
    }

    @Test
    func anOrdinaryHandledErrorIsNotProtected() {
        let event = Event(level: .error)
        let exception = Exception(value: "Code: 505", type: "com.google.fcm")
        let mechanism = Mechanism(type: "generic")
        mechanism.handled = true
        exception.mechanism = mechanism
        event.exceptions = [exception]

        let candidate = SentryFloodGuardEvent(event: event)
        #expect(!candidate.isProtected)
        #expect(candidate.groupKey == "com.google.fcm|generic")
    }

    @Test
    func eventsSharingSentrysOwnGroupingShareABudget() {
        let event = Event(level: .error)
        event.fingerprint = ["ascend", "workout-sync"]

        #expect(SentryFloodGuardEvent(event: event).groupKey == "ascend|workout-sync")
    }
}

/// A hand-wound clock, so the window arithmetic is tested rather than waited on.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_750_000_000)

    var now: @Sendable () -> Date {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            return current
        }
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current += interval
    }
}
