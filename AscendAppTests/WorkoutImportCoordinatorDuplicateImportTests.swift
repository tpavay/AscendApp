import HealthKit
import SwiftData
import Testing
@testable import AscendApp

@MainActor
@Suite(.serialized)
struct WorkoutImportCoordinatorDuplicateImportTests {
    @Test
    func importingSameAppleHealthCandidateTwiceReusesExistingWorkout() async throws {
        let modelContext = try makeModelContext()
        let workout = HKWorkout(
            activityType: .stairClimbing,
            start: Date(timeIntervalSince1970: 1_776_440_000),
            end: Date(timeIntervalSince1970: 1_776_441_500)
        )
        let sample = HealthKitWorkoutSample(
            externalRecordID: workout.uuid.uuidString,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            sourceName: "Apple Health",
            sourceBundleIdentifier: "com.apple.Health",
            deviceModel: "Simulator"
        )
        let candidate = ImportedWorkoutCandidate.appleHealth(sample: sample)
        let coordinator = WorkoutImportCoordinator(
            workoutReader: StubHealthKitWorkoutReader(workout: workout),
            metricsReader: StubHealthKitMetricsReader()
        )
        coordinator.configure(modelContext: modelContext)

        let firstOutcome = await coordinator.importCandidate(candidate)
        let secondOutcome = await coordinator.importCandidate(candidate)
        let workouts = try modelContext.fetch(FetchDescriptor<Workout>())

        guard case .imported = firstOutcome else {
            Issue.record("Expected first import to insert a workout.")
            return
        }
        guard case .updatedExisting = secondOutcome else {
            Issue.record("Expected duplicate import to resolve to the existing workout.")
            return
        }
        #expect(workouts.count == 1)
        #expect(workouts.first?.healthKitUUID == sample.externalRecordID)
    }

    @Test
    func homeEntryRefreshAutoImportsEligibleAppleHealthWorkout() async throws {
        let modelContext = try makeModelContext()
        let stateSnapshot = HealthKitSyncStateSnapshot.capture()
        let settingsSnapshot = SettingsSnapshot.capture()
        defer {
            stateSnapshot.restore()
            settingsSnapshot.restore()
        }
        resetHealthKitSyncStateForTest()
        let isolatedStores = makeIsolatedImportStores(name: "home-entry")
        defer { isolatedStores.defaults.removePersistentDomain(forName: isolatedStores.suiteName) }

        let workout = HKWorkout(
            activityType: .stairClimbing,
            start: Date(timeIntervalSince1970: 1_776_530_000),
            end: Date(timeIntervalSince1970: 1_776_531_500)
        )
        let sample = HealthKitWorkoutSample(
            externalRecordID: workout.uuid.uuidString,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            sourceName: "Apple Health",
            sourceBundleIdentifier: "com.apple.Health",
            deviceModel: "Simulator"
        )
        let settingsManager = SettingsManager.shared
        settingsManager.appleHealthAutoImportEnabled = true
        settingsManager.appleHealthAutoImportActivatedAt = sample.startDate.addingTimeInterval(-60)
        let coordinator = WorkoutImportCoordinator(
            authorizationController: StubHealthKitAuthorizationController(hasCompletedInitialBackfill: false),
            workoutReader: StubHealthKitWorkoutReader(workout: workout, addedSamples: [sample]),
            metricsReader: StubHealthKitMetricsReader(),
            reviewStateStore: isolatedStores.reviewStateStore,
            ignoredAppleHealthWorkoutStore: isolatedStores.ignoredAppleHealthWorkoutStore
        )
        coordinator.configure(modelContext: modelContext)

        await coordinator.refreshPendingImports(trigger: .homeEntry)
        let workouts = try modelContext.fetch(FetchDescriptor<Workout>())

        #expect(workouts.count == 1)
        #expect(workouts.first?.healthKitUUID == sample.externalRecordID)
        #expect(coordinator.pendingCandidates.isEmpty)
        #expect(coordinator.presentPendingAutoImportedReviewOnHomeIfNeeded())
        #expect(coordinator.currentAutoImportedReviewWorkoutID == workouts.first?.id)
    }

    @Test
    func autoImportUsesPreviousHealthKitCheckWhenActivationDateIsMissing() async throws {
        let modelContext = try makeModelContext()
        let stateSnapshot = HealthKitSyncStateSnapshot.capture()
        let settingsSnapshot = SettingsSnapshot.capture()
        defer {
            stateSnapshot.restore()
            settingsSnapshot.restore()
        }
        resetHealthKitSyncStateForTest()
        let isolatedStores = makeIsolatedImportStores(name: "missing-activation")
        defer { isolatedStores.defaults.removePersistentDomain(forName: isolatedStores.suiteName) }

        let workout = HKWorkout(
            activityType: .stairClimbing,
            start: Date(timeIntervalSince1970: 1_776_620_000),
            end: Date(timeIntervalSince1970: 1_776_621_800)
        )
        let sample = HealthKitWorkoutSample(
            externalRecordID: workout.uuid.uuidString,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            sourceName: "Apple Health",
            sourceBundleIdentifier: "com.apple.Health",
            deviceModel: "Simulator"
        )
        let settingsManager = SettingsManager.shared
        settingsManager.appleHealthAutoImportEnabled = true
        settingsManager.appleHealthAutoImportActivatedAt = nil
        HealthKitSyncState.lastSuccessfulCheckAt = sample.startDate.addingTimeInterval(-60)
        let coordinator = WorkoutImportCoordinator(
            authorizationController: StubHealthKitAuthorizationController(hasCompletedInitialBackfill: true),
            workoutReader: StubHealthKitWorkoutReader(workout: workout, addedSamples: [sample]),
            metricsReader: StubHealthKitMetricsReader(),
            reviewStateStore: isolatedStores.reviewStateStore,
            ignoredAppleHealthWorkoutStore: isolatedStores.ignoredAppleHealthWorkoutStore
        )
        coordinator.configure(modelContext: modelContext)

        await coordinator.refreshPendingImports(trigger: .homeEntry)
        let workouts = try modelContext.fetch(FetchDescriptor<Workout>())

        #expect(workouts.count == 1)
        #expect(workouts.first?.healthKitUUID == sample.externalRecordID)
        #expect(coordinator.presentPendingAutoImportedReviewOnHomeIfNeeded())
    }

    @Test
    func refreshPendingImportsSerializesConcurrentTriggers() async throws {
        let modelContext = try makeModelContext()
        let stateSnapshot = HealthKitSyncStateSnapshot.capture()
        let settingsSnapshot = SettingsSnapshot.capture()
        defer {
            stateSnapshot.restore()
            settingsSnapshot.restore()
        }
        resetHealthKitSyncStateForTest()

        let workout = HKWorkout(
            activityType: .stairClimbing,
            start: Date(timeIntervalSince1970: 1_776_710_000),
            end: Date(timeIntervalSince1970: 1_776_711_500)
        )
        let reader = StubHealthKitWorkoutReader(
            workout: workout,
            anchoredFetchDelay: .milliseconds(50)
        )
        let coordinator = WorkoutImportCoordinator(
            authorizationController: StubHealthKitAuthorizationController(hasCompletedInitialBackfill: true),
            workoutReader: reader,
            metricsReader: StubHealthKitMetricsReader()
        )
        SettingsManager.shared.appleHealthAutoImportEnabled = false
        coordinator.configure(modelContext: modelContext)

        async let firstRefresh: Void = coordinator.refreshPendingImports(trigger: .homeEntry)
        async let secondRefresh: Void = coordinator.refreshPendingImports(trigger: .homeEntry)
        _ = await (firstRefresh, secondRefresh)

        #expect(reader.anchoredFetchCount == 1)
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            LeaderboardStats.self,
            PersonalRecord.self,
            Routine.self,
            RoutineFolder.self,
            ClimbAttempt.self,
            WeightPersonalRecord.self,
            AggregateWeightRecord.self,
            PendingMediaUpload.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func resetHealthKitSyncStateForTest() {
        HealthKitSyncState.hasRequestedAuthorization = true
        HealthKitSyncState.hasCompletedInitialBackfill = true
        HealthKitSyncState.lastSuccessfulCheckAt = nil
        HealthKitSyncState.workoutAnchorData = nil
        HealthKitSyncState.cachedWorkoutSamples = []
    }

    private func makeIsolatedImportStores(name: String) -> (
        suiteName: String,
        defaults: UserDefaults,
        reviewStateStore: WorkoutAutoImportReviewStateStore,
        ignoredAppleHealthWorkoutStore: IgnoredAppleHealthWorkoutStore
    ) {
        let suiteName = "WorkoutImportCoordinatorDuplicateImportTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        return (
            suiteName,
            defaults,
            WorkoutAutoImportReviewStateStore(defaults: defaults, key: "auto-review"),
            IgnoredAppleHealthWorkoutStore(defaults: defaults, key: "ignored-apple-health")
        )
    }
}

@MainActor
private final class StubHealthKitWorkoutReader: HealthKitWorkoutReading {
    let isHealthDataAvailable = true
    private let workout: HKWorkout
    private let addedSamples: [HealthKitWorkoutSample]
    private let anchoredFetchDelay: Duration?
    private(set) var anchoredFetchCount = 0

    init(
        workout: HKWorkout,
        addedSamples: [HealthKitWorkoutSample] = [],
        anchoredFetchDelay: Duration? = nil
    ) {
        self.workout = workout
        self.addedSamples = addedSamples
        self.anchoredFetchDelay = anchoredFetchDelay
    }

    func fetchAnchoredStairStepperWorkouts(anchorData: Data?) async throws -> HealthKitWorkoutDiscoveryResult {
        anchoredFetchCount += 1
        if let anchoredFetchDelay {
            try? await Task.sleep(for: anchoredFetchDelay)
        }

        return HealthKitWorkoutDiscoveryResult(
            addedSamples: addedSamples,
            deletedExternalRecordIDs: [],
            anchorData: anchorData
        )
    }

    func fetchWorkout(withExternalRecordID externalRecordID: String) async throws -> HKWorkout? {
        externalRecordID == workout.uuid.uuidString ? workout : nil
    }

    func fetchStairStepperWorkouts(in dateRange: ClosedRange<Date>) async throws -> [HealthKitWorkoutSample] {
        []
    }
}

@MainActor
private final class StubHealthKitMetricsReader: HealthKitMetricsReading {
    func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics {
        WorkoutMetrics(steps: 1_500)
    }
}

@MainActor
private final class StubHealthKitAuthorizationController: HealthKitAuthorizationControlling {
    let isHealthDataAvailable = true
    let hasRequestedAuthorization = true
    let hasCompletedInitialBackfill: Bool
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var lastPermissionErrorMessage: String?
    let connectionState: AppleHealthConnectionState = .neverConnected

    init(hasCompletedInitialBackfill: Bool) {
        self.hasCompletedInitialBackfill = hasCompletedInitialBackfill
    }

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool {
        true
    }
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
            appleHealthAutoImportActivatedAt: SettingsManager.shared.appleHealthAutoImportActivatedAt
        )
    }

    func restore() {
        SettingsManager.shared.appleHealthAutoImportEnabled = appleHealthAutoImportEnabled
        SettingsManager.shared.appleHealthAutoImportActivatedAt = appleHealthAutoImportActivatedAt
    }
}
