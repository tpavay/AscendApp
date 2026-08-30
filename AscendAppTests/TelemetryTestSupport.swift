import Foundation
@testable import AscendApp

final class IdentityAttributingTelemetrySink: TelemetrySink, @unchecked Sendable {
    struct Attribution: Equatable, Sendable {
        let name: String
        let userID: String?
        let parameters: [String: TelemetryValue]
    }

    let supportedDestinations: Set<TelemetryDestination> = [.analytics]
    private let lock = NSLock()
    private var currentUserID: String?
    private var storedAttributions: [Attribution] = []

    var attributions: [Attribution] {
        lock.withLock { storedAttributions }
    }

    func setCollectionEnabled(_ enabled: Bool) {}

    func setUserID(_ userID: String?) {
        lock.withLock { currentUserID = userID }
    }

    func record(_ record: EnvelopedTelemetryRecord) {
        lock.withLock {
            storedAttributions.append(
                Attribution(
                    name: record.name,
                    userID: currentUserID,
                    parameters: record.parameters
                )
            )
        }
    }

    func record(screen: EnvelopedTelemetryScreen) {}
}

final class BlockingIdentityAttributingTelemetrySink: TelemetrySink, @unchecked Sendable {
    enum BlockPoint: Sendable {
        case record
        case identify(userID: String)
    }

    let supportedDestinations: Set<TelemetryDestination> = [.analytics]
    private let underlying = IdentityAttributingTelemetrySink()
    private let blockPoint: BlockPoint
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didBlock = false

    init(blockPoint: BlockPoint) {
        self.blockPoint = blockPoint
    }

    var attributions: [IdentityAttributingTelemetrySink.Attribution] {
        underlying.attributions
    }

    func waitUntilBlocked() {
        entered.wait()
    }

    func releaseBlockedCall() {
        release.signal()
    }

    func setCollectionEnabled(_ enabled: Bool) {
        underlying.setCollectionEnabled(enabled)
    }

    func setUserID(_ userID: String?) {
        if case .identify(let blockedUserID) = blockPoint, userID == blockedUserID {
            blockOnce()
        }
        underlying.setUserID(userID)
    }

    func record(_ record: EnvelopedTelemetryRecord) {
        if case .record = blockPoint {
            blockOnce()
        }
        underlying.record(record)
    }

    func record(screen: EnvelopedTelemetryScreen) {}

    private func blockOnce() {
        let shouldBlock = lock.withLock { () -> Bool in
            guard !didBlock else { return false }
            didBlock = true
            return true
        }
        guard shouldBlock else { return }
        entered.signal()
        release.wait()
    }
}

final class ControlledTelemetryDeliveryLane: TelemetryDeliveryLaning, @unchecked Sendable {
    private let condition = NSCondition()
    private let armedEntryObserved = DispatchSemaphore(value: 0)
    private var isHeld = false
    private var observesNextEntry = false
    private var observedEntryWasContended: Bool?

    func armNextEntryObservation() {
        condition.withLock {
            precondition(observesNextEntry == false)
            observesNextEntry = true
            observedEntryWasContended = nil
        }
    }

    func waitForObservedEntry() -> Bool {
        armedEntryObserved.wait()
        return condition.withLock {
            precondition(observedEntryWasContended != nil)
            return observedEntryWasContended == true
        }
    }

    func withLock<Result: Sendable>(
        _ operation: @Sendable () throws -> Result
    ) rethrows -> Result {
        condition.lock()
        if observesNextEntry {
            observesNextEntry = false
            observedEntryWasContended = isHeld
            armedEntryObserved.signal()
        }
        while isHeld {
            condition.wait()
        }
        isHeld = true
        condition.unlock()

        defer {
            condition.withLock {
                isHeld = false
                condition.broadcast()
            }
        }
        return try operation()
    }
}

struct NoopCrashlyticsReporter: CrashlyticsReporting {
    func setCollectionEnabled(_ enabled: Bool) {}
    func setUserID(_ userID: String?) {}
    func setCustomValue(_ value: Bool, forKey key: String) {}
    func setCustomValue(_ value: Int, forKey key: String) {}
    func setCustomValue(_ value: String, forKey key: String) {}
    func log(_ message: String) {}
    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {}
}

/// Captures the non-fatals a caller recorded.
///
/// Breadcrumbs and the diagnostics ring buffer cannot stand in for this: only a recorded error
/// uploads on its own, without waiting for a later crash to carry it.
final class RecordingCrashlyticsReporter: CrashlyticsReporting, @unchecked Sendable {
    struct RecordedError {
        let context: String
        let code: String
        let additionalInfo: [String: String]?
    }

    private let lock = NSLock()
    private var recorded: [RecordedError] = []

    var recordedErrors: [RecordedError] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func setCollectionEnabled(_ enabled: Bool) {}
    func setUserID(_ userID: String?) {}
    func setCustomValue(_ value: Bool, forKey key: String) {}
    func setCustomValue(_ value: Int, forKey key: String) {}
    func setCustomValue(_ value: String, forKey key: String) {}
    func log(_ message: String) {}

    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {
        lock.lock()
        recorded.append(
            RecordedError(context: context, code: code, additionalInfo: additionalInfo)
        )
        lock.unlock()
    }
}

/// The identity record a relaunch would find, without touching the installation suite the shipped
/// app writes to. Hold one across two `TelemetryManager`s to stand in for a cold launch;
/// `TelemetryIdentityStoreTests` covers the persistence the shipped store actually provides.
final class InMemoryTelemetryIdentityStore: TelemetryIdentityStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedUserID: String?

    init(identifiedUserID: String? = nil) {
        storedUserID = identifiedUserID
    }

    var identifiedUserID: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedUserID
    }

    func store(_ userID: String) {
        lock.lock()
        storedUserID = userID
        lock.unlock()
    }

    func clear() {
        lock.lock()
        storedUserID = nil
        lock.unlock()
    }
}

func makeTestIdentityStore() -> any TelemetryIdentityStoring {
    InMemoryTelemetryIdentityStore()
}

func makeTestTelemetry(
    reporter: any CrashlyticsReporting,
    collectionEnabled: Bool = true
) -> TelemetryManager {
    let telemetry = TelemetryManager(
        sinks: [],
        crashlyticsReporter: reporter,
        collectionEnabledOverride: collectionEnabled,
        identityStore: makeTestIdentityStore()
    )
    telemetry.configure()
    return telemetry
}

func makeTestTelemetryEnvelope() throws -> TelemetryEnvelope {
    try TelemetryEnvelope(
        validating: TelemetryBuildMetadata(
            appEnvironment: "staging",
            buildConfig: "staging",
            appVersion: "1.2.3",
            buildNumber: "456",
            bundleIdentifier: "com.tylerpavay.AscendApp.tests"
        )
    )
}

func makeEnvelopedTestRecord(_ record: TelemetryRecord) throws -> EnvelopedTelemetryRecord {
    EnvelopedTelemetryRecord(record: record, envelope: try makeTestTelemetryEnvelope())
}

func makeEnvelopedTestScreen(_ screen: TelemetryScreen) throws -> EnvelopedTelemetryScreen {
    EnvelopedTelemetryScreen(screen: screen, envelope: try makeTestTelemetryEnvelope())
}

/// `configure()` is what applies the override; without it collection stays off and every
/// emission assertion would pass vacuously against an empty sink.
func makeTestTelemetry(
    sinks: [InMemoryTelemetrySink],
    collectionEnabled: Bool = true,
    identityStore: any TelemetryIdentityStoring = makeTestIdentityStore()
) -> TelemetryManager {
    let telemetry = TelemetryManager(
        sinks: sinks,
        crashlyticsReporter: NoopCrashlyticsReporter(),
        collectionEnabledOverride: collectionEnabled,
        identityStore: identityStore
    )
    telemetry.configure()
    return telemetry
}

func makeTestTelemetry(
    sink: InMemoryTelemetrySink,
    collectionEnabled: Bool = true,
    identityStore: any TelemetryIdentityStoring = makeTestIdentityStore()
) -> TelemetryManager {
    makeTestTelemetry(
        sinks: [sink],
        collectionEnabled: collectionEnabled,
        identityStore: identityStore
    )
}
