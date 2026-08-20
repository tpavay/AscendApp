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

    private static func noise(_ key: String = "com.google.fcm|none") -> SentryEventClassification {
        SentryEventClassification(groupKey: key, isSevere: false)
    }

    private static func protected(_ key: String = "SIGSEGV|mach") -> SentryEventClassification {
        SentryEventClassification(groupKey: key, isSevere: true)
    }

    private static func nonError(_ key: String = "replay_video") -> SentryEventClassification {
        SentryEventClassification(groupKey: key, isSevere: false, isErrorEvent: false)
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

    @Test
    func aPayloadThatIsNotAnErrorIsNeitherBoundedNorCharged() {
        let clock = TestClock()
        let guardUnderTest = SentryEventFloodGuard(limits: Self.limits, now: clock.now)

        // `beforeSend` sees transactions and replay segments too. They arrive on
        // the SDK's own schedule, so throttling them would only throttle a
        // mechanism that is not flooding.
        #expect((0..<100).allSatisfy { _ in guardUnderTest.allows(Self.nonError()) })
        #expect(guardUnderTest.droppedEventCount == 0)

        // And they leave the error budget exactly where they found it.
        #expect((0..<Self.limits.perKeyCap).allSatisfy { _ in guardUnderTest.allows(Self.noise()) })
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

        #expect(SentryEventClassification(event: event).isSevere)
    }

    @Test
    func aFatalEventIsProtectedWhateverItsShape() {
        // Crash reports, watchdog terminations and fatal app hangs all arrive at
        // fatal, and a crash report carries no exception the guard could inspect.
        #expect(SentryEventClassification(event: Event(level: .fatal)).isSevere)
    }

    @Test
    func anUnhandledExceptionIsProtectedEvenUnderAMechanismNameWeDoNotKnow() {
        let event = Event(level: .error)
        let exception = Exception(value: "boom", type: "SomeFutureCrashType")
        let mechanism = Mechanism(type: "a_mechanism_from_a_later_sdk")
        mechanism.handled = false
        exception.mechanism = mechanism
        event.exceptions = [exception]

        #expect(SentryEventClassification(event: event).isSevere)
    }

    @Test(arguments: ["replay_video", "transaction", "feedback", "profile"])
    func aPayloadCarryingANonErrorTypeIsNotMeteredAsOne(type: String) {
        let event = Event(level: .info)
        event.type = type

        #expect(!SentryEventClassification(event: event).isErrorEvent)
    }

    /// sentry-cocoa 9.18 leaves `type` nil on errors, but Sentry's other SDKs
    /// spell it out. If this SDK ever followed, reading "not an error" off the
    /// mere presence of a type would exempt every event and leave the guard
    /// bounding nothing at all, with no other test noticing.
    @Test(arguments: [nil, "error"])
    func anErrorIsMeteredUnderEitherSpellingOfItsType(type: String?) {
        let event = Event(level: .error)
        event.type = type

        #expect(SentryEventClassification(event: event).isErrorEvent)
    }

    @Test
    func theGuardStillBoundsAFloodOfExplicitlyTypedErrors() {
        let clock = TestClock()
        let guardUnderTest = SentryEventFloodGuard(limits: Self.limits, now: clock.now)

        let verdicts = (0..<10).map { _ in
            let event = Event(level: .error)
            event.type = "error"
            event.fingerprint = ["com.google.fcm", "505"]
            return guardUnderTest.allows(SentryEventClassification(event: event))
        }

        #expect(verdicts.filter { $0 }.count == Self.limits.perKeyCap)
    }

    @Test
    func anOrdinaryHandledErrorIsNotProtected() {
        let event = Event(level: .error)
        let exception = Exception(value: "Code: 505", type: "com.google.fcm")
        let mechanism = Mechanism(type: "generic")
        mechanism.handled = true
        exception.mechanism = mechanism
        event.exceptions = [exception]

        let candidate = SentryEventClassification(event: event)
        #expect(!candidate.isSevere)
        #expect(candidate.isErrorEvent)
        #expect(candidate.groupKey == "com.google.fcm|generic")
    }

    @Test
    func eventsSharingSentrysOwnGroupingShareABudget() {
        let event = Event(level: .error)
        event.fingerprint = ["ascend", "workout-sync"]

        #expect(SentryEventClassification(event: event).groupKey == "ascend|workout-sync")
    }

    /// One `NSError` domain is not one problem. `SentryClient.exceptionForError`
    /// puts the domain in `type` and the code in `mechanism.meta.error`, and
    /// Sentry groups on both - so a key that read the domain alone would let an
    /// offline session flooding Firestore `unavailable` (14) silently eat the
    /// allowance of `permission-denied` (7), which is the shape of the four-day
    /// Live Climb rules outage.
    @Test
    func twoCodesInOneErrorDomainDoNotShareAnAllowance() {
        let unavailable = Self.errorEvent(domain: "FIRFirestoreErrorDomain", code: 14)
        let permissionDenied = Self.errorEvent(domain: "FIRFirestoreErrorDomain", code: 7)

        #expect(
            SentryEventClassification(event: unavailable).groupKey
                != SentryEventClassification(event: permissionDenied).groupKey
        )

        let clock = TestClock()
        let guardUnderTest = SentryEventFloodGuard(limits: Self.limits, now: clock.now)

        for _ in 0..<Self.limits.perKeyCap {
            _ = guardUnderTest.allows(SentryEventClassification(event: unavailable))
        }
        #expect(!guardUnderTest.allows(SentryEventClassification(event: unavailable)))

        #expect(
            guardUnderTest.allows(SentryEventClassification(event: permissionDenied)),
            "a flood of one code in a domain spent another code's whole budget"
        )
    }

    /// The reported error is the last exception, not the first.
    ///
    /// `SentryClient.buildErrorEvent` flattens the `NSUnderlyingErrorKey` chain
    /// and appends it in reverse, so `exceptions[0]` is the innermost cause. Two
    /// unrelated errors that wrap one shared cause - a URL error under a sync
    /// failure and under an upload failure - would otherwise share a single
    /// allowance.
    @Test
    func anErrorChainIsGroupedOnItsRootRatherThanItsInnermostCause() {
        let sharedCause = Self.exception(domain: "NSURLErrorDomain", code: -1_009)
        let syncFailure = Self.event(chain: [sharedCause, Self.exception(domain: "AscendApp.WorkoutSync", code: 17)])
        let uploadFailure = Self.event(chain: [sharedCause, Self.exception(domain: "AscendApp.MediaUpload", code: 3)])

        let syncKey = SentryEventClassification(event: syncFailure).groupKey
        let uploadKey = SentryEventClassification(event: uploadFailure).groupKey

        #expect(syncKey.contains("AscendApp.WorkoutSync"), "the key names the innermost cause instead of the root")
        #expect(uploadKey.contains("AscendApp.MediaUpload"), "the key names the innermost cause instead of the root")
        #expect(syncKey != uploadKey)
    }

    /// The chain fix may not reach past the guard's one hard rule.
    @Test
    func aSevereErrorChainIsStillExemptFromEveryBudget() {
        let event = Self.event(chain: [
            Self.exception(domain: "NSURLErrorDomain", code: -1_009),
            Self.exception(domain: "AscendApp.WorkoutSync", code: 17)
        ])
        event.exceptions?.last?.mechanism?.handled = false

        let candidate = SentryEventClassification(event: event)
        #expect(candidate.isSevere)

        let clock = TestClock()
        let guardUnderTest = SentryEventFloodGuard(limits: Self.limits, now: clock.now)
        #expect((0..<50).allSatisfy { _ in guardUnderTest.allows(candidate) })
        #expect(guardUnderTest.droppedEventCount == 0)
    }

    // MARK: - The shape the SDK builds

    /// One exception the way `SentryClient.exceptionForError` writes it: the
    /// domain in `type`, the domain *and* code again in `mechanism.meta.error`,
    /// which is the pair Sentry's own grouping reads.
    private static func exception(domain: String, code: Int) -> Exception {
        let exception = Exception(value: "Code: \(code)", type: domain)
        let mechanism = Mechanism(type: "NSError")
        let meta = MechanismContext()
        meta.error = SentryNSError(domain: domain, code: code)
        mechanism.meta = meta
        mechanism.handled = true
        exception.mechanism = mechanism
        return exception
    }

    /// `chain` is oldest-first - innermost cause at index 0, reported root last -
    /// which is the order `buildErrorEvent` appends in.
    private static func event(chain: [Exception]) -> Event {
        let event = Event(level: .error)
        event.exceptions = chain
        return event
    }

    private static func errorEvent(domain: String, code: Int) -> Event {
        event(chain: [exception(domain: domain, code: code)])
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
