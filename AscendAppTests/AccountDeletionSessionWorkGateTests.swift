import HealthKit
import SwiftData
import Testing

@testable import AscendApp

/// A HealthKit observer imports on its own schedule, so account deletion cannot stop it by draining
/// the bootstrap chain alone.
///
/// An import pass that starts after the drain and lands inside deletion's staged window does two
/// things at once: it saves the context, committing a sweep that was deliberately left unsaved so
/// it could roll back, and it inserts a workout owned by the account being deleted. That leftover
/// row is exactly what the ownership guard blocks the replacement account on (#389).
@MainActor
@Suite(.serialized)
struct AccountDeletionSessionWorkGateTests {
    @Test("Suspended session work blocks a background-observer import pass", .bug(id: 389))
    func suspendedSessionWorkBlocksObserverImport() async throws {
        try await HealthKitImportCoordinatorTestIsolation.shared.run {
            let fixture = try Self.makeFixture()
            defer { fixture.teardown() }

            await fixture.gate.suspendAndDrain(autonomousWorkers: [fixture.coordinator])

            await fixture.coordinator.refreshPendingImports(trigger: .backgroundObserver)

            #expect(fixture.authorization.refreshCount == 0)
            #expect(try fixture.modelContext.fetch(FetchDescriptor<Workout>()).isEmpty)
        }
    }

    @Test("The gate reopens once deletion resolves", .bug(id: 389))
    func importResumesAfterDeletionResolves() async throws {
        try await HealthKitImportCoordinatorTestIsolation.shared.run {
            let fixture = try Self.makeFixture()
            defer { fixture.teardown() }

            await fixture.gate.suspendAndDrain(autonomousWorkers: [fixture.coordinator])
            fixture.gate.discard()

            await fixture.coordinator.refreshPendingImports(trigger: .backgroundObserver)

            #expect(fixture.authorization.refreshCount == 1)
        }
    }

    /// The media queue is the other writer the drain cannot fully stop on its own.
    ///
    /// `processUpload` saves the `ModelContext` on entry and again on its failure path, so an item
    /// the queue starts after the drain has already snapshotted its in-flight tasks writes into
    /// deletion's staged window with nobody waiting on it. The gate is what refuses to start it.
    @Test("Suspended session work holds the media upload queue", .bug(id: 389))
    func suspendedSessionWorkHoldsTheUploadQueue() async throws {
        let modelContext = try Self.makeUploadModelContext()
        let gate = AuthenticatedBootstrapCoordinator()
        let photoRepository = CountingPhotoRepository()
        let manager = MediaUploadManager(
            photoRepo: photoRepository,
            featureFlags: RemoteFeatureFlagStore(),
            sessionWorkGate: gate
        )

        let workout = Self.makeUploadWorkout()
        modelContext.insert(workout)
        modelContext.insert(
            PendingMediaUpload(
                workoutId: workout.id,
                localFileName: "held-media.jpg",
                mediaType: "photo",
                orderIndex: 0
            )
        )
        try modelContext.save()

        await gate.suspendAndDrain(autonomousWorkers: [manager])
        await manager.processPendingUploads(modelContext: modelContext)

        #expect(await photoRepository.uploadCount() == 0)
        let held = try modelContext.fetch(FetchDescriptor<PendingMediaUpload>())
        #expect(held.count == 1)
        #expect(held.first?.status == PendingUploadStatus.pending.rawValue)
        #expect(held.first?.retryCount == 0)

        // Same queue, same row, gate reopened. The row moving is the control: it proves the hold
        // above was the gate rather than a queue that had nothing to do, and the move is itself the
        // `processUpload` save that must never land inside deletion's staged window.
        gate.discard()
        await manager.processPendingUploads(modelContext: modelContext)

        let released = try modelContext.fetch(FetchDescriptor<PendingMediaUpload>())
        #expect(released.first?.status == PendingUploadStatus.failed.rawValue)
        #expect(released.first?.retryCount == 3)
    }

    // MARK: - Fixture

    private static func makeUploadModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            PendingWorkoutDeletion.self,
            PendingMediaUpload.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func makeUploadWorkout() -> Workout {
        Workout(
            name: "Workout",
            date: Date(timeIntervalSince1970: 1_780_000_000),
            duration: 1_800,
            steps: 1_000,
            floors: Workout.stepsToFloors(1_000, stepsPerFloor: 16),
            stepsPerFloor: 16,
            notes: "Test",
            source: .manual
        )
    }

    private static func makeFixture() throws -> Fixture {
        let suiteName = "AccountDeletionSessionWorkGateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

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
        let modelContext = ModelContext(container)

        let gate = AuthenticatedBootstrapCoordinator()
        let authorization = RecordingAuthorizationController()
        let coordinator = WorkoutImportCoordinator(
            authorizationController: authorization,
            workoutReader: EmptyStubWorkoutReader(),
            metricsReader: EmptyStubMetricsReader(),
            reviewStateStore: WorkoutAutoImportReviewStateStore(
                defaults: defaults,
                key: "auto-review"
            ),
            ignoredAppleHealthWorkoutStore: IgnoredAppleHealthWorkoutStore(
                defaults: defaults,
                key: "ignored-apple-health"
            ),
            sessionWorkGate: gate
        )
        coordinator.configure(modelContext: modelContext)

        return Fixture(
            container: container,
            modelContext: modelContext,
            gate: gate,
            authorization: authorization,
            coordinator: coordinator,
            teardown: {
                coordinator.cancelInFlightWork()
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let gate: AuthenticatedBootstrapCoordinator
        let authorization: RecordingAuthorizationController
        let coordinator: WorkoutImportCoordinator
        let teardown: @MainActor () -> Void
    }
}

/// Records whether the import pass got past its gate: refreshing authorization status is the first
/// thing a real pass does once it has a store to write to.
@MainActor
private final class RecordingAuthorizationController: HealthKitAuthorizationControlling {
    let isHealthDataAvailable = true
    let hasRequestedAuthorization = true
    let hasCompletedInitialBackfill = true
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var lastPermissionErrorMessage: String?
    let connectionState: AppleHealthConnectionState = .connected

    private(set) var refreshCount = 0

    func refreshAuthorizationRequestStatus() async {
        refreshCount += 1
    }

    func requestAuthorization() async -> Bool { true }
}

@MainActor
private final class EmptyStubWorkoutReader: HealthKitWorkoutReading {
    let isHealthDataAvailable = true

    func fetchAnchoredStairStepperWorkouts(anchorData: Data?) async throws
        -> HealthKitWorkoutDiscoveryResult
    {
        HealthKitWorkoutDiscoveryResult(
            addedSamples: [],
            deletedExternalRecordIDs: [],
            anchorData: anchorData
        )
    }

    func fetchWorkout(withExternalRecordID externalRecordID: String) async throws -> HKWorkout? {
        nil
    }

    func fetchStairStepperWorkouts(in dateRange: ClosedRange<Date>) async throws
        -> [HealthKitWorkoutSample]
    {
        []
    }
}

@MainActor
private final class EmptyStubMetricsReader: HealthKitMetricsReading {
    func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics {
        WorkoutMetrics(steps: 0)
    }
}

private actor CountingPhotoRepository: PhotoRepositoryProtocol {
    private var uploads = 0

    func upload(_ data: Data, filename: String) async throws -> URL {
        uploads += 1
        return URL(string: "https://example.invalid/\(filename)")!
    }

    func delete(url: URL) async throws {}

    func uploadCount() -> Int { uploads }
}
