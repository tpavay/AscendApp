import Foundation
import Testing
@preconcurrency import Sentry
@testable import AscendApp

/// Replays the incident the flood guard exists to prevent through the shipped
/// `beforeSend`, and writes down what the Sentry project would have received.
///
/// `SentryEventFloodGuardTests` proves the arithmetic and
/// `SentryDiagnosticsConfigurationTests` proves the wiring; this suite is the
/// readable artifact of both working together on one session: 497
/// `Swift.CancellationError` events in ten minutes, with the four failure
/// classes production actually needs to see interleaved through them.
///
/// The transcript lands in `ASCEND_EVIDENCE_DIR` when it is set, and in the test
/// host's temporary directory otherwise.
@Suite(.serialized)
struct SentryFloodGuardIncidentEvidenceTests {
    private static let dsn = "https://examplePublicKey@o0.ingest.sentry.io/0"
    private static let incidentDuration: TimeInterval = 600
    private static let runawayEventCount = 497

    @Test
    func theRunawayClassIsBoundedWhileEveryRealSignalStillArrives() throws {
        let clock = IncidentClock()
        let floodGuard = SentryEventFloodGuard(now: clock.now)
        let options = try #require(
            SentryOptionsFactory.makeOptions(
                configuration: SentryConfiguration(infoDictionary: [SentryConfiguration.dsnInfoKey: Self.dsn]),
                buildMetadata: TelemetryBuildMetadata(
                    appEnvironment: "production",
                    buildConfig: "Release",
                    appVersion: "1.0.0",
                    buildNumber: "42",
                    bundleIdentifier: "com.ascend.app"
                ),
                floodGuard: floodGuard
            )
        )
        let beforeSend = try #require(options.beforeSend)

        var ledger = Ledger()
        var floodTagsSeen: [String] = []

        for signal in Self.timeline() {
            clock.advance(to: signal.at)
            let delivered = beforeSend(signal.makeEvent())
            ledger.record(signal.label, delivered: delivered != nil)

            if let tag = delivered?.tags?["ascend_flood_guard_dropped"] {
                floodTagsSeen.append(tag)
            }
        }

        // The point of the guard: the runaway class is capped at its own
        // allowance - five per minute over a ten-minute incident - instead of
        // spending the whole project's attention.
        let runaway = try #require(ledger[Self.runawayLabel])
        #expect(runaway.offered == Self.runawayEventCount)
        #expect(runaway.delivered <= 50)
        #expect(runaway.dropped > 400)

        // The whole reason this may ship: nothing production is paged about was
        // touched, including the classes that are ordinary handled errors and
        // are metered rather than protected.
        for label in Self.realSignalLabels {
            let tally = try #require(ledger[label])
            #expect(
                tally.delivered == tally.offered,
                "\(label): \(tally.dropped) of \(tally.offered) real reports were lost to the noise guard"
            )
        }

        // A guard that fires is never silent: the next survivor carries the count.
        #expect(!floodTagsSeen.isEmpty, "the guard dropped events without stamping a single survivor")

        try Self.writeTranscript(ledger: ledger, floodTagsSeen: floodTagsSeen)
    }

    // MARK: - The session being replayed

    private static let runawayLabel = "Swift.CancellationError (the runaway class)"
    private static let realSignalLabels = [
        "Fatal App Hang",
        "AuthenticationError.noRootViewController",
        "Firebase Functions DEADLINE EXCEEDED",
        "Firestore Missing or insufficient permissions",
        "Crash (SIGSEGV)"
    ]

    private static func timeline() -> [Signal] {
        var signals: [Signal] = (0..<runawayEventCount).map { index in
            Signal(
                at: incidentDuration * Double(index) / Double(runawayEventCount),
                label: runawayLabel
            ) { handledError(type: "Swift.CancellationError", value: "The operation was cancelled.") }
        }

        signals += [120.0, 300.0, 480.0].map { at in
            Signal(at: at, label: "Fatal App Hang") { appHang() }
        }
        signals += [60.0, 180.0, 360.0, 540.0].map { at in
            Signal(at: at, label: "AuthenticationError.noRootViewController") {
                handledError(type: "AuthenticationError", value: "noRootViewController")
            }
        }
        signals += [90.0, 270.0, 450.0].map { at in
            Signal(at: at, label: "Firebase Functions DEADLINE EXCEEDED") {
                handledError(type: "FIRFunctionsErrorDomain", value: "DEADLINE EXCEEDED")
            }
        }
        signals += [150.0, 330.0, 510.0].map { at in
            Signal(at: at, label: "Firestore Missing or insufficient permissions") {
                handledError(type: "FIRFirestoreErrorDomain", value: "Missing or insufficient permissions.")
            }
        }
        signals.append(Signal(at: 595, label: "Crash (SIGSEGV)") { crash() })

        return signals.sorted { $0.at < $1.at }
    }

    private static func handledError(type: String, value: String) -> Event {
        let event = Event(level: .error)
        let exception = Exception(value: value, type: type)
        let mechanism = Mechanism(type: "generic")
        mechanism.handled = true
        exception.mechanism = mechanism
        event.exceptions = [exception]
        return event
    }

    private static func appHang() -> Event {
        let event = Event(level: .fatal)
        let exception = Exception(value: "App hanging for at least 2000 ms.", type: "Fatal App Hang Fully Blocked")
        exception.mechanism = Mechanism(type: "AppHang")
        event.exceptions = [exception]
        return event
    }

    private static func crash() -> Event {
        let event = Event(level: .fatal)
        let exception = Exception(value: "Attempted to dereference garbage pointer", type: "EXC_BAD_ACCESS")
        let mechanism = Mechanism(type: "mach")
        mechanism.handled = false
        exception.mechanism = mechanism
        event.exceptions = [exception]
        return event
    }

    private struct Signal {
        let at: TimeInterval
        let label: String
        let makeEvent: @Sendable () -> Event
    }

    // MARK: - Accounting

    private struct Tally {
        var offered = 0
        var delivered = 0
        var dropped: Int { offered - delivered }
    }

    private struct Ledger {
        private(set) var order: [String] = []
        private var tallies: [String: Tally] = [:]

        subscript(label: String) -> Tally? { tallies[label] }

        var totals: Tally {
            tallies.values.reduce(into: Tally()) { total, tally in
                total.offered += tally.offered
                total.delivered += tally.delivered
            }
        }

        mutating func record(_ label: String, delivered: Bool) {
            if tallies[label] == nil {
                order.append(label)
                tallies[label] = Tally()
            }
            tallies[label]?.offered += 1
            if delivered { tallies[label]?.delivered += 1 }
        }
    }

    // MARK: - The written record

    private static func writeTranscript(ledger: Ledger, floodTagsSeen: [String]) throws {
        let rows = ledger.order.compactMap { label -> String? in
            guard let tally = ledger[label] else { return nil }
            return "| \(label) | \(tally.offered) | \(tally.offered) | \(tally.delivered) | \(tally.dropped) |"
        }
        let totals = ledger.totals

        let transcript = """
        # Sentry flood guard: one runaway session, replayed through the shipped `beforeSend`

        Built by `SentryOptionsFactory.makeOptions(environment: production)` - the same
        `beforeSend` the app installs - over `SentryEventFloodGuard.Limits.live`
        (5 events per group key per 60s, 200 per session, 128 tracked keys).

        The session is the incident that buried the project: \(runawayEventCount)
        `Swift.CancellationError` events in \(Int(incidentDuration / 60)) minutes, with the failure
        classes production is actually paged about interleaved through them.

        | Event class | Offered by the app | Reached Sentry before this change | Reaches Sentry now | Dropped |
        | --- | --- | --- | --- | --- |
        \(rows.joined(separator: "\n"))
        | **Total** | **\(totals.offered)** | **\(totals.offered)** | **\(totals.delivered)** | **\(totals.dropped)** |

        Every dropped event is accounted for on the wire: the next event through
        carries `ascend_flood_guard_dropped`, which climbed \(floodTagsSeen.first ?? "-") -> \
        \(floodTagsSeen.last ?? "-") across this session.

        No crash and no app hang was dropped, and the three ordinary handled-error
        classes production cares about kept their own allowances while the runaway
        class spent only its own.
        """

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            .map { URL(filePath: $0) } ?? URL.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "sentry-flood-guard-incident.md")
        try Data(transcript.utf8).write(to: url)
        print("flood guard evidence: \(url.path())")
    }
}

/// A hand-wound clock, so a ten-minute incident replays in milliseconds.
private final class IncidentClock: @unchecked Sendable {
    private let start = Date(timeIntervalSince1970: 1_750_000_000)
    private let lock = NSLock()
    private var offset: TimeInterval = 0

    var now: @Sendable () -> Date {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            return start + offset
        }
    }

    func advance(to elapsed: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        offset = max(offset, elapsed)
    }
}
