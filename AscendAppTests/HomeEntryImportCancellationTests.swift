import HealthKit
import SwiftData
import Testing

@testable import AscendApp

/// An Apple Health backfill outlives the screen that started it unless something stops it.
///
/// `refreshPendingImports` runs on an unstructured task so several surfaces can share one pass,
/// which also means it does not inherit cancellation for free. Before the ASCEND-IOS-1K fix,
/// leaving Home mid-backfill left hundreds of workouts still importing behind a screen nobody was
/// looking at. These are the contracts that stop that.
@MainActor
@Suite(.serialized)
struct HomeEntryImportCancellationTests {
    private static let candidateCount = 12
    private static let cancelAfterCandidates = 3
    private static let joinAfterCandidates = 3
    private static let cancelJoinerAfterCandidates = 6
    private static let sessionStart = Date(timeIntervalSince1970: 1_776_900_000)

    @Test
    func cancellingTheCallerStopsTheBackfillAtTheNextCandidate() async throws {
        try await HealthKitImportCoordinatorTestIsolation.shared.run {
            let modelContext = try Self.makeModelContext()
            let stateSnapshot = HealthKitSyncStateSnapshot.capture()
            let settingsSnapshot = SettingsSnapshot.capture()
            defer {
                stateSnapshot.restore()
                settingsSnapshot.restore()
            }
            Self.resetHealthKitSyncState()
            let stores = Self.makeIsolatedStores()
            defer { stores.defaults.removePersistentDomain(forName: stores.suiteName) }

            let fixture = Self.makeCandidates(count: Self.candidateCount)
            let reader = CancellingStubWorkoutReader(
                workoutsByExternalRecordID: fixture.workoutsByID,
                addedSamples: fixture.samples
            )

            SettingsManager.shared.appleHealthAutoImportEnabled = true
            SettingsManager.shared.appleHealthAutoImportActivatedAt =
                Self.sessionStart.addingTimeInterval(-86_400)

            let coordinator = WorkoutImportCoordinator(
                authorizationController: StubAuthorizationController(),
                workoutReader: reader,
                metricsReader: StubMetricsReader(),
                reviewStateStore: stores.reviewStateStore,
                ignoredAppleHealthWorkoutStore: stores.ignoredAppleHealthWorkoutStore
            )
            coordinator.configure(modelContext: modelContext)

            let refresh = Task { @MainActor in
                await coordinator.refreshPendingImports(trigger: .homeEntry)
            }
            // Stand in for Home going away: cancel once the backfill is demonstrably underway.
            reader.onWorkoutFetched = { fetchCount in
                if fetchCount == Self.cancelAfterCandidates {
                    refresh.cancel()
                }
            }
            await refresh.value

            let imported = try modelContext.fetch(FetchDescriptor<Workout>())

            #expect(
                imported.count >= 1,
                "cancellation should keep the work already committed, not roll it back"
            )
            #expect(
                imported.count < Self.candidateCount,
                """
                the backfill imported \(imported.count) of \(Self.candidateCount) candidates after \
                its owner went away; it should have stopped at the next candidate boundary
                """
            )
        }
    }

    /// Only the caller that started the pass may stop it.
    ///
    /// Several surfaces share one refresh, and the ones that merely join it come and go: the
    /// import sheet, the integrations card, the background observer. Letting a joiner's
    /// cancellation reach the shared task means dismissing the import sheet silently kills the
    /// backfill Home started and is still showing progress for.
    @Test
    func aJoiningCallerGoingAwayDoesNotStopTheOwnersBackfill() async throws {
        try await HealthKitImportCoordinatorTestIsolation.shared.run {
            let modelContext = try Self.makeModelContext()
            let stateSnapshot = HealthKitSyncStateSnapshot.capture()
            let settingsSnapshot = SettingsSnapshot.capture()
            defer {
                stateSnapshot.restore()
                settingsSnapshot.restore()
            }
            Self.resetHealthKitSyncState()
            let stores = Self.makeIsolatedStores()
            defer { stores.defaults.removePersistentDomain(forName: stores.suiteName) }

            let fixture = Self.makeCandidates(count: Self.candidateCount)
            let reader = CancellingStubWorkoutReader(
                workoutsByExternalRecordID: fixture.workoutsByID,
                addedSamples: fixture.samples
            )

            SettingsManager.shared.appleHealthAutoImportEnabled = true
            SettingsManager.shared.appleHealthAutoImportActivatedAt =
                Self.sessionStart.addingTimeInterval(-86_400)

            let coordinator = WorkoutImportCoordinator(
                authorizationController: StubAuthorizationController(),
                workoutReader: reader,
                metricsReader: StubMetricsReader(),
                reviewStateStore: stores.reviewStateStore,
                ignoredAppleHealthWorkoutStore: stores.ignoredAppleHealthWorkoutStore
            )
            coordinator.configure(modelContext: modelContext)

            // Home starts the pass and stays on screen for all of it.
            let owner = Task { @MainActor in
                await coordinator.refreshPendingImports(trigger: .homeEntry)
            }

            // The import sheet opens onto the pass already running, then dismisses - both pinned
            // to candidate boundaries so the join really happens mid-backfill.
            let joiner = JoinedRefreshHolder()
            reader.onWorkoutFetched = { fetchCount in
                switch fetchCount {
                case Self.joinAfterCandidates:
                    joiner.task = Task { @MainActor in
                        await coordinator.refreshPendingImports(trigger: .manualReview)
                    }
                case Self.cancelJoinerAfterCandidates:
                    joiner.task?.cancel()
                default:
                    break
                }
            }

            await owner.value
            await joiner.task?.value

            let imported = try modelContext.fetch(FetchDescriptor<Workout>())

            #expect(
                imported.count == Self.candidateCount,
                """
                the backfill stopped at \(imported.count) of \(Self.candidateCount) candidates \
                after a joining caller went away; only the owner may cancel the shared pass
                """
            )
        }
    }

    /// Cancellation must not leave the coordinator wedged: the next entry has to be able to pick
    /// the backfill back up.
    @Test
    func aCancelledRefreshLeavesTheCoordinatorReusable() async throws {
        try await HealthKitImportCoordinatorTestIsolation.shared.run {
            let modelContext = try Self.makeModelContext()
            let stateSnapshot = HealthKitSyncStateSnapshot.capture()
            let settingsSnapshot = SettingsSnapshot.capture()
            defer {
                stateSnapshot.restore()
                settingsSnapshot.restore()
            }
            Self.resetHealthKitSyncState()
            let stores = Self.makeIsolatedStores()
            defer { stores.defaults.removePersistentDomain(forName: stores.suiteName) }

            let fixture = Self.makeCandidates(count: Self.candidateCount)
            let reader = CancellingStubWorkoutReader(
                workoutsByExternalRecordID: fixture.workoutsByID,
                addedSamples: fixture.samples
            )

            SettingsManager.shared.appleHealthAutoImportEnabled = true
            SettingsManager.shared.appleHealthAutoImportActivatedAt =
                Self.sessionStart.addingTimeInterval(-86_400)

            let coordinator = WorkoutImportCoordinator(
                authorizationController: StubAuthorizationController(),
                workoutReader: reader,
                metricsReader: StubMetricsReader(),
                reviewStateStore: stores.reviewStateStore,
                ignoredAppleHealthWorkoutStore: stores.ignoredAppleHealthWorkoutStore
            )
            coordinator.configure(modelContext: modelContext)

            let refresh = Task { @MainActor in
                await coordinator.refreshPendingImports(trigger: .homeEntry)
            }
            reader.onWorkoutFetched = { fetchCount in
                if fetchCount == Self.cancelAfterCandidates {
                    refresh.cancel()
                }
            }
            await refresh.value

            reader.onWorkoutFetched = nil
            coordinator.resetAutomaticCheckThrottle()
            await coordinator.refreshPendingImports(trigger: .homeEntry)

            let imported = try modelContext.fetch(FetchDescriptor<Workout>())

            #expect(imported.count == Self.candidateCount)
            #expect(coordinator.pendingCandidates.isEmpty)
            #expect(coordinator.isImporting == false)
        }
    }

    // MARK: - Fixture

    private static func makeCandidates(
        count: Int
    ) -> (samples: [HealthKitWorkoutSample], workoutsByID: [String: HKWorkout]) {
        var samples: [HealthKitWorkoutSample] = []
        var workoutsByID: [String: HKWorkout] = [:]

        for index in 0..<count {
            let start = sessionStart.addingTimeInterval(TimeInterval(index) * 7_200)
            let end = start.addingTimeInterval(1_500)
            let hkWorkout = HKWorkout(activityType: .stairClimbing, start: start, end: end)
            let sample = HealthKitWorkoutSample(
                externalRecordID: hkWorkout.uuid.uuidString,
                startDate: start,
                endDate: end,
                duration: hkWorkout.duration,
                sourceName: "Apple Health",
                sourceBundleIdentifier: "com.apple.Health",
                deviceModel: "Simulator"
            )
            samples.append(sample)
            workoutsByID[sample.externalRecordID] = hkWorkout
        }

        return (samples, workoutsByID)
    }

    private static func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            LeaderboardStats.self,
            Routine.self,
            RoutineFolder.self,
            ClimbAttempt.self,
            PendingMediaUpload.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func resetHealthKitSyncState() {
        HealthKitSyncState.hasRequestedAuthorization = true
        HealthKitSyncState.hasCompletedInitialBackfill = true
        HealthKitSyncState.lastSuccessfulCheckAt = nil
        HealthKitSyncState.workoutAnchorData = nil
        HealthKitSyncState.cachedWorkoutSamples = []
    }

    private static func makeIsolatedStores() -> (
        suiteName: String,
        defaults: UserDefaults,
        reviewStateStore: WorkoutAutoImportReviewStateStore,
        ignoredAppleHealthWorkoutStore: IgnoredAppleHealthWorkoutStore
    ) {
        let suiteName = "HomeEntryImportCancellationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        return (
            suiteName,
            defaults,
            WorkoutAutoImportReviewStateStore(defaults: defaults, key: "auto-review"),
            IgnoredAppleHealthWorkoutStore(defaults: defaults, key: "ignored-apple-health")
        )
    }

    private struct HealthKitSyncStateSnapshot {
        let hasRequestedAuthorization: Bool
        let hasCompletedInitialBackfill: Bool
        let lastSuccessfulCheckAt: Date?
        let workoutAnchorData: Data?
        let cachedWorkoutSamples: [HealthKitWorkoutSample]

        static func capture() -> Self {
            HealthKitSyncStateSnapshot(
                hasRequestedAuthorization: HealthKitSyncState.hasRequestedAuthorization,
                hasCompletedInitialBackfill: HealthKitSyncState.hasCompletedInitialBackfill,
                lastSuccessfulCheckAt: HealthKitSyncState.lastSuccessfulCheckAt,
                workoutAnchorData: HealthKitSyncState.workoutAnchorData,
                cachedWorkoutSamples: HealthKitSyncState.cachedWorkoutSamples
            )
        }

        func restore() {
            HealthKitSyncState.hasRequestedAuthorization = hasRequestedAuthorization
            HealthKitSyncState.hasCompletedInitialBackfill = hasCompletedInitialBackfill
            HealthKitSyncState.lastSuccessfulCheckAt = lastSuccessfulCheckAt
            HealthKitSyncState.workoutAnchorData = workoutAnchorData
            HealthKitSyncState.cachedWorkoutSamples = cachedWorkoutSamples
        }
    }

    @MainActor
    private struct SettingsSnapshot {
        let appleHealthAutoImportEnabled: Bool
        let appleHealthAutoImportActivatedAt: Date?

        static func capture() -> Self {
            SettingsSnapshot(
                appleHealthAutoImportEnabled: SettingsManager.shared.appleHealthAutoImportEnabled,
                appleHealthAutoImportActivatedAt: SettingsManager.shared
                    .appleHealthAutoImportActivatedAt
            )
        }

        func restore() {
            SettingsManager.shared.appleHealthAutoImportEnabled = appleHealthAutoImportEnabled
            SettingsManager.shared.appleHealthAutoImportActivatedAt =
                appleHealthAutoImportActivatedAt
        }
    }
}

/// Serves a whole Apple Health history and reports each workout it hands out, so a test can cut
/// the import off at a known candidate rather than at a wall-clock guess.
@MainActor
private final class CancellingStubWorkoutReader: HealthKitWorkoutReading {
    let isHealthDataAvailable = true
    var onWorkoutFetched: (@MainActor (Int) -> Void)?

    private let workoutsByExternalRecordID: [String: HKWorkout]
    private let addedSamples: [HealthKitWorkoutSample]
    private var workoutFetchCount = 0

    init(
        workoutsByExternalRecordID: [String: HKWorkout],
        addedSamples: [HealthKitWorkoutSample]
    ) {
        self.workoutsByExternalRecordID = workoutsByExternalRecordID
        self.addedSamples = addedSamples
    }

    func fetchAnchoredStairStepperWorkouts(anchorData: Data?) async throws
        -> HealthKitWorkoutDiscoveryResult
    {
        HealthKitWorkoutDiscoveryResult(
            addedSamples: addedSamples,
            deletedExternalRecordIDs: [],
            anchorData: anchorData
        )
    }

    func fetchWorkout(withExternalRecordID externalRecordID: String) async throws -> HKWorkout? {
        workoutFetchCount += 1
        onWorkoutFetched?(workoutFetchCount)
        return workoutsByExternalRecordID[externalRecordID]
    }

    func fetchStairStepperWorkouts(in dateRange: ClosedRange<Date>) async throws
        -> [HealthKitWorkoutSample]
    {
        []
    }
}

/// Holds the refresh a second surface joined, so the test can start it at one candidate boundary
/// and cancel it at a later one.
@MainActor
private final class JoinedRefreshHolder {
    var task: Task<Void, Never>?
}

@MainActor
private final class StubMetricsReader: HealthKitMetricsReading {
    func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics {
        WorkoutMetrics(steps: 1_500)
    }
}

@MainActor
private final class StubAuthorizationController: HealthKitAuthorizationControlling {
    let isHealthDataAvailable = true
    let hasRequestedAuthorization = true
    let hasCompletedInitialBackfill = true
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var lastPermissionErrorMessage: String?
    let connectionState: AppleHealthConnectionState = .connected

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool { true }
}
