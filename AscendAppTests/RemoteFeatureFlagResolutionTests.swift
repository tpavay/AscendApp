import Foundation
import Testing
@testable import AscendApp

/// The fetch-failure posture, pinned. Every one of these asserts the same rule from a different
/// angle: a value the backend did not supply resolves to the flag's shipped default, never to
/// "off".
struct RemoteFeatureFlagResolutionTests {
    @Test
    func shippedDefaultsLeaveEveryDataPathEnabled() {
        let snapshot = RemoteFeatureFlagSnapshot.shippedDefaults

        for flag in RemoteFeatureFlag.allCases {
            #expect(snapshot.isEnabled(flag) == true)
            #expect(snapshot.source(of: flag) == .shippedDefault)
        }
        #expect(snapshot.disabledFlagKeys.isEmpty)
    }

    @Test
    func emptyBackendResponseResolvesToShippedDefaultsRatherThanOff() {
        let snapshot = RemoteFeatureFlagSnapshot.resolving(remoteValues: [:])

        #expect(snapshot == .shippedDefaults)
    }

    @Test
    func aBackendValueOverridesOnlyItsOwnFlag() {
        let snapshot = RemoteFeatureFlagSnapshot.resolving(
            remoteValues: [RemoteFeatureFlag.workoutCloudBackupWrites.key: false]
        )

        #expect(snapshot.isEnabled(.workoutCloudBackupWrites) == false)
        #expect(snapshot.source(of: .workoutCloudBackupWrites) == .remote)
        #expect(snapshot.disabledFlagKeys == [RemoteFeatureFlag.workoutCloudBackupWrites.key])

        for flag in RemoteFeatureFlag.allCases where flag != .workoutCloudBackupWrites {
            #expect(snapshot.isEnabled(flag) == true)
            #expect(snapshot.source(of: flag) == .shippedDefault)
        }
    }

    @Test
    func aBackendValueOfTrueIsAttributedToTheBackend() {
        let snapshot = RemoteFeatureFlagSnapshot.resolving(
            remoteValues: [RemoteFeatureFlag.leaderboardPublishing.key: true]
        )

        #expect(snapshot.isEnabled(.leaderboardPublishing) == true)
        #expect(snapshot.source(of: .leaderboardPublishing) == .remote)
    }

    @Test
    func unknownBackendKeysAreIgnored() {
        let snapshot = RemoteFeatureFlagSnapshot.resolving(
            remoteValues: [
                "a_parameter_for_some_other_app_version": false,
                RemoteFeatureFlag.publicProfilePublishing.key: false
            ]
        )

        #expect(snapshot.disabledFlagKeys == [RemoteFeatureFlag.publicProfilePublishing.key])
    }

    @Test
    func everyFlagKeyIsDistinct() {
        let keys = RemoteFeatureFlag.allCases.map(\.key)

        #expect(Set(keys).count == keys.count)
    }

    @Test(arguments: [
        ("true", true), ("TRUE", true), ("True", true), ("yes", true), ("y", true), ("t", true), ("1", true),
        ("false", false), ("FALSE", false), ("no", false), ("n", false), ("f", false), ("0", false),
        ("  true  ", true), ("\nfalse\n", false)
    ])
    func booleanParserAcceptsRemoteConfigBooleanLiterals(rawValue: String, expected: Bool) {
        #expect(RemoteFeatureFlagBooleanParser.parse(rawValue) == expected)
    }

    /// A malformed template entry must not read as "off" - that would disable a data path nobody
    /// chose to disable.
    @Test(arguments: ["", "flase", "off", "on", "disabled", "2", "null"])
    func booleanParserRejectsAnythingElseRatherThanCoercingItToFalse(rawValue: String) {
        #expect(RemoteFeatureFlagBooleanParser.parse(rawValue) == nil)
    }
}

struct RemoteFeatureFlagStoreTests {
    @Test
    func storeStartsOnShippedDefaults() {
        let store = RemoteFeatureFlagStore()

        #expect(store.isEnabled(.workoutRemoteDeletes) == true)
        #expect(store.snapshot == .shippedDefaults)
    }

    @Test
    func applyingAChangedSnapshotReportsTheChange() {
        let store = RemoteFeatureFlagStore()
        let snapshot = RemoteFeatureFlagSnapshot.resolving(
            remoteValues: [RemoteFeatureFlag.workoutRemoteDeletes.key: false]
        )

        #expect(store.apply(snapshot) == true)
        #expect(store.isEnabled(.workoutRemoteDeletes) == false)
    }

    @Test
    func reapplyingTheSameSnapshotReportsNoChange() {
        let store = RemoteFeatureFlagStore()
        let snapshot = RemoteFeatureFlagSnapshot.resolving(
            remoteValues: [RemoteFeatureFlag.workoutRemoteDeletes.key: false]
        )

        #expect(store.apply(snapshot) == true)
        #expect(store.apply(snapshot) == false)
    }
}

@MainActor
struct RemoteFeatureFlagServiceTests {
    /// The acceptance criterion: a value flipped server-side reaches a running app.
    @Test
    func aSuccessfulFetchAppliesTheBackendValue() async {
        let source = FakeRemoteFeatureFlagSource(
            fetchResult: .success([RemoteFeatureFlag.workoutCloudBackupWrites.key: false])
        )
        let store = RemoteFeatureFlagStore()
        let service = RemoteFeatureFlagService(source: source, store: store)

        await service.refreshAndWait()

        #expect(store.isEnabled(.workoutCloudBackupWrites) == false)
        #expect(service.hasCompletedInitialFetch == true)
    }

    /// The fetch-failure posture, end to end: a backend the app cannot reach changes nothing.
    @Test
    func aFailedFetchLeavesEveryFlagOnItsShippedDefault() async {
        let source = FakeRemoteFeatureFlagSource(fetchResult: .failure(RemoteFeatureFlagSourceError.fetchFailed))
        let store = RemoteFeatureFlagStore()
        let service = RemoteFeatureFlagService(source: source, store: store)

        await service.refreshAndWait()

        #expect(store.snapshot == .shippedDefaults)
        #expect(service.hasCompletedInitialFetch == false)
    }

    /// A fetch that fails *after* a good one must not roll the app back to shipped defaults - a
    /// kill switch has to survive losing the network.
    @Test
    func aFailedFetchAfterASuccessfulOneKeepsTheKillSwitchInPlace() async {
        let source = FakeRemoteFeatureFlagSource(
            fetchResult: .success([RemoteFeatureFlag.workoutCloudBackupWrites.key: false])
        )
        let store = RemoteFeatureFlagStore()
        let service = RemoteFeatureFlagService(source: source, store: store)
        await service.refreshAndWait()

        source.setFetchResult(.failure(RemoteFeatureFlagSourceError.fetchFailed))
        await service.refreshAndWait()

        #expect(store.isEnabled(.workoutCloudBackupWrites) == false)
    }

    /// A key dropped from the template resolves back to the shipped default rather than sticking on
    /// its last value, so deleting a parameter is a supported way to restore normal behaviour.
    @Test
    func aKeyRemovedFromTheTemplateReturnsToItsShippedDefault() async {
        let source = FakeRemoteFeatureFlagSource(
            fetchResult: .success([RemoteFeatureFlag.workoutCloudBackupWrites.key: false])
        )
        let store = RemoteFeatureFlagStore()
        let service = RemoteFeatureFlagService(source: source, store: store)
        await service.refreshAndWait()

        source.setFetchResult(.success([:]))
        await service.refreshAndWait()

        #expect(store.isEnabled(.workoutCloudBackupWrites) == true)
        #expect(store.snapshot == .shippedDefaults)
    }

    /// The whole point of the mechanism: a device that goes offline after a kill switch was
    /// published must still boot with it thrown. No fetch succeeds on this launch, so the only
    /// thing that can carry the `false` across the cold start is the SDK's persisted activation.
    @Test
    func aPersistedKillSwitchSurvivesALaunchWithNoSuccessfulFetch() async {
        let source = FakeRemoteFeatureFlagSource(
            fetchResult: .failure(RemoteFeatureFlagSourceError.fetchFailed),
            activatedValues: [RemoteFeatureFlag.workoutMediaUploads.key: false]
        )
        let store = RemoteFeatureFlagStore()
        let service = RemoteFeatureFlagService(source: source, store: store)

        service.configure()
        await service.refreshAndWait()

        #expect(service.hasCompletedInitialFetch == false)
        #expect(store.isEnabled(.workoutMediaUploads) == false)
        #expect(store.snapshot.source(of: .workoutMediaUploads) == .remote)
        for flag in RemoteFeatureFlag.allCases where flag != .workoutMediaUploads {
            #expect(store.isEnabled(flag) == true)
        }
    }

    /// The seed must not need the network at all, or an offline launch would resolve from shipped
    /// defaults for as long as the fetch took to fail.
    @Test
    func thePersistedSeedLandsBeforeAnyFetchIsAttempted() {
        let source = FakeRemoteFeatureFlagSource(
            fetchResult: .success([:]),
            activatedValues: [RemoteFeatureFlag.workoutRemoteDeletes.key: false]
        )
        let store = RemoteFeatureFlagStore()
        let service = RemoteFeatureFlagService(source: source, store: store)

        service.configure()

        #expect(store.isEnabled(.workoutRemoteDeletes) == false)
        #expect(source.fetchCallCount == 0)
    }

    /// A device the backend has never answered for has nothing persisted, and must not be nudged
    /// off its shipped defaults by the seed.
    @Test
    func aDeviceWithNothingPersistedStaysOnShippedDefaults() {
        let source = FakeRemoteFeatureFlagSource(fetchResult: .success([:]))
        let store = RemoteFeatureFlagStore()
        let service = RemoteFeatureFlagService(source: source, store: store)

        service.configure()

        #expect(store.snapshot == .shippedDefaults)
    }

    @Test
    func configureStartsTheRealTimeListenerAndARealTimeUpdateLandsWithoutAFetch() async {
        let source = FakeRemoteFeatureFlagSource(fetchResult: .success([:]))
        let store = RemoteFeatureFlagStore()
        let service = RemoteFeatureFlagService(source: source, store: store)

        service.configure()
        await service.refreshAndWait()
        #expect(source.isListening == true)

        source.emitUpdate([RemoteFeatureFlag.publicProfilePublishing.key: false])

        #expect(await waitUntil { store.isEnabled(.publicProfilePublishing) == false })
    }

    /// The listener is a long-lived connection; it must not outlive the service that opened it.
    @Test
    func teardownStopsListening() async {
        let source = FakeRemoteFeatureFlagSource(fetchResult: .success([:]))
        let service = RemoteFeatureFlagService(source: source, store: RemoteFeatureFlagStore())

        service.configure()
        #expect(source.isListening == true)

        service.teardown()
        #expect(source.isListening == false)
    }

    @Test
    func configuringTwiceOpensOnlyOneListener() async {
        let source = FakeRemoteFeatureFlagSource(fetchResult: .success([:]))
        let service = RemoteFeatureFlagService(source: source, store: RemoteFeatureFlagStore())

        service.configure()
        service.configure()

        #expect(source.startListeningCallCount == 1)
    }
}

/// Lock-guarded rather than an actor so `startListening` / `stopListening` take effect synchronously
/// - the protocol's are synchronous, and an actor hop would make the listener assertions racy.
private final class FakeRemoteFeatureFlagSource: RemoteFeatureFlagSource, @unchecked Sendable {
    private let lock = NSLock()
    private var storedFetchResult: Result<[String: Bool], any Error>
    private var storedActivatedValues: [String: Bool]
    private var onUpdate: (@Sendable ([String: Bool]) -> Void)?
    private var storedStartListeningCallCount = 0
    private var storedFetchCallCount = 0

    init(
        fetchResult: Result<[String: Bool], any Error>,
        activatedValues: [String: Bool] = [:]
    ) {
        storedFetchResult = fetchResult
        storedActivatedValues = activatedValues
    }

    var fetchCallCount: Int {
        lock.withLock { storedFetchCallCount }
    }

    var isListening: Bool {
        lock.withLock { onUpdate != nil }
    }

    var startListeningCallCount: Int {
        lock.withLock { storedStartListeningCallCount }
    }

    func setFetchResult(_ result: Result<[String: Bool], any Error>) {
        lock.withLock { storedFetchResult = result }
    }

    func emitUpdate(_ values: [String: Bool]) {
        let handler = lock.withLock { onUpdate }
        handler?(values)
    }

    func fetchAndActivate() async throws -> [String: Bool] {
        let result = lock.withLock { () -> Result<[String: Bool], any Error> in
            storedFetchCallCount += 1
            return storedFetchResult
        }
        return try result.get()
    }

    func activatedValues() -> [String: Bool] {
        lock.withLock { storedActivatedValues }
    }

    func startListening(onUpdate: @escaping @Sendable ([String: Bool]) -> Void) {
        lock.withLock {
            storedStartListeningCallCount += 1
            self.onUpdate = onUpdate
        }
    }

    func stopListening() {
        lock.withLock { onUpdate = nil }
    }
}

/// Yields until `condition` holds or the budget runs out, so a test can wait on work that hops to
/// the main actor without sleeping for a fixed duration.
@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}
