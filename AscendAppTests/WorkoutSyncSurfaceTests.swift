import FirebaseFirestore
import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// What the climber is told, and when it is allowed to stop being told.
///
/// The two defects the captain rejected, in test form: a warning that vanished the instant a retry
/// started, and a warning that vanished again when that retry was refused.
@MainActor
struct WorkoutSyncSurfaceTests {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    @Test
    func aFailedRetryLeavesTheWarningExactlyWhereItWas() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: start)
        modelContext.insert(workout)
        try modelContext.save()

        let repository = RefusingRepository()
        let coordinator = makeCoordinator(remoteRepository: repository, now: start)

        // Drive it to the stopped state the climber sees as `Couldn't sync this climb`.
        await coordinator.processPendingWorkouts(modelContext: modelContext, currentUserId: "user-123")
        let entry = try #require(try fetchOutboxEntry(for: workout.id, in: modelContext))
        entry.refusalCount = WorkoutSyncRetryPolicy.refusalsBeforeStopping
        entry.firstPendingAt = start.addingTimeInterval(-60 * 60)
        try modelContext.save()

        #expect(coordinator.syncPresentation(for: workout, modelContext: modelContext) == .couldNotSync)

        // The retry is refused again. This is where the old surface unmounted.
        await coordinator.retryNow(
            workoutId: workout.id,
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let after = coordinator.syncPresentation(for: workout, modelContext: modelContext)
        #expect(after == .couldNotSync)
        #expect(after.isWarning)
        #expect(after.isRetryControlEnabled, "Try again must come back live, unlimited.")
        #expect(workout.isSyncedToCloud == false)
    }

    /// Every status that is not `synced` means the same thing to the climber: this climb is not in
    /// their account. None of them may unmount the warning.
    @Test
    func noRetryMachineryStatusCanUnmountTheWarning() throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: start)
        modelContext.insert(workout)

        let entry = WorkoutSyncOutboxEntry(
            workoutId: workout.id,
            ownerUserId: "user-123",
            firstPendingAt: start.addingTimeInterval(-60 * 60)
        )
        entry.failureCategory = .refused
        modelContext.insert(entry)
        try modelContext.save()

        let coordinator = makeCoordinator(remoteRepository: RefusingRepository(), now: start)

        for status in [WorkoutRemoteSyncStatus.pendingUpsert, .failed, .rejected] {
            workout.remoteSyncStatus = status
            #expect(
                coordinator.syncPresentation(for: workout, modelContext: modelContext).isWarning,
                "\(status.rawValue) still means the climb is not in the cloud."
            )
        }
    }

    @Test
    func theQuietWindowShowsSyncingRatherThanAWarning() throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: start)
        modelContext.insert(workout)

        let entry = WorkoutSyncOutboxEntry(
            workoutId: workout.id,
            ownerUserId: "user-123",
            firstPendingAt: start
        )
        entry.failureCategory = .transient
        modelContext.insert(entry)
        try modelContext.save()

        let coordinator = makeCoordinator(remoteRepository: RefusingRepository(), now: start)

        #expect(coordinator.syncPresentation(for: workout, modelContext: modelContext) == .syncing)
    }

    /// `Synced` is the only state that disappears, and only for a climber who was told there was a
    /// problem. A climb that synced quietly shows nothing at all.
    @Test
    func syncedIsConfirmedOnlyToAClimberWhoSawTheWarning() throws {
        let modelContext = try makeModelContext()
        let quiet = makeWorkout()
        quiet.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: start)
        quiet.markRemoteSyncSucceeded(syncedAt: start, heartRateSeries: nil)
        modelContext.insert(quiet)
        try modelContext.save()

        let coordinator = makeCoordinator(remoteRepository: RefusingRepository(), now: start)

        #expect(coordinator.syncPresentation(for: quiet, modelContext: modelContext) == .hidden)
    }

    @Test
    func theControlIsDeadWhileOfflineAndTheWarningStays() throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: start)
        workout.remoteSyncStatus = .rejected
        modelContext.insert(workout)
        try modelContext.save()

        let coordinator = makeCoordinator(
            remoteRepository: RefusingRepository(),
            now: start,
            connectivityService: StubConnectivity(isConnected: false)
        )

        let presentation = coordinator.syncPresentation(for: workout, modelContext: modelContext)
        #expect(presentation == .couldNotSyncOffline)
        #expect(presentation.isWarning)
        #expect(presentation.isRetryControlEnabled == false)
    }

    /// Arbitrarily many taps stay possible - the manual path never exhausts.
    @Test
    func manualRetryNeverRunsOut() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: start)
        workout.remoteSyncStatus = .rejected
        modelContext.insert(workout)
        try modelContext.save()

        let repository = RefusingRepository()
        let coordinator = makeCoordinator(remoteRepository: repository, now: start)

        for _ in 0..<6 {
            await coordinator.retryNow(
                workoutId: workout.id,
                modelContext: modelContext,
                currentUserId: "user-123"
            )
        }

        #expect(await repository.attemptCount() == 6)
        #expect(coordinator.syncPresentation(for: workout, modelContext: modelContext).isRetryControlEnabled)
    }

    /// A tap bypasses the due date, but only for its own workout and only for one attempt - it
    /// must not launder the automatic schedule it is jumping.
    @Test
    func aManualRetryDoesNotResetTheAutomaticSeries() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: start)
        modelContext.insert(workout)
        try modelContext.save()

        let coordinator = makeCoordinator(remoteRepository: RefusingRepository(), now: start)
        await coordinator.processPendingWorkouts(modelContext: modelContext, currentUserId: "user-123")

        let entry = try #require(try fetchOutboxEntry(for: workout.id, in: modelContext))
        let countAfterAutomatic = entry.automaticAttemptCount

        await coordinator.retryNow(
            workoutId: workout.id,
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(entry.automaticAttemptCount > countAfterAutomatic)
        #expect(entry.nextEligibleAttemptAt != nil, "The schedule must still be armed.")
    }

    /// Three triggers in the same instant produce one genuine attempt, not three.
    @Test
    func aBurstOfCoordinatorTriggersProducesOneAttempt() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: start)
        modelContext.insert(workout)
        try modelContext.save()

        let repository = RefusingRepository()
        let coordinator = makeCoordinator(remoteRepository: repository, now: start)

        for _ in 0..<3 {
            await coordinator.processPendingWorkouts(modelContext: modelContext, currentUserId: "user-123")
        }

        #expect(await repository.attemptCount() == 1)
    }

    private func fetchOutboxEntry(
        for workoutId: UUID,
        in modelContext: ModelContext
    ) throws -> WorkoutSyncOutboxEntry? {
        try modelContext.fetch(
            FetchDescriptor<WorkoutSyncOutboxEntry>(
                predicate: #Predicate { $0.workoutId == workoutId }
            )
        ).first
    }

    private func makeCoordinator(
        remoteRepository: RefusingRepository,
        now: Date,
        connectivityService: any WorkoutSyncConnectivityProviding = StubConnectivity(isConnected: true)
    ) -> WorkoutSyncCoordinator {
        WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: InertHeartRateRepository(),
            operationTimeoutSeconds: 1,
            connectivityService: connectivityService,
            now: { now }
        )
    }

    private func makeWorkout() -> Workout {
        Workout(
            name: "CN Tower Live Climb",
            date: start,
            duration: 1_800,
            steps: 1_200,
            floors: 75,
            stepsPerFloor: 16,
            notes: "",
            source: .manual
        )
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            WorkoutSyncOutboxEntry.self,
            PendingWorkoutDeletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}

@MainActor
private struct StubConnectivity: WorkoutSyncConnectivityProviding {
    let isConnected: Bool
}

private struct RefusedWrite: Error, CustomNSError, Sendable {
    static var errorDomain: String { FirestoreErrorDomain }
    var errorCode: Int { FirestoreErrorCode.permissionDenied.rawValue }
    var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
    }
}

private actor RefusingRepository: WorkoutRemoteRepositoryProtocol {
    private var attempts = 0

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] { [] }

    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws {
        attempts += 1
        throw RefusedWrite()
    }

    func deleteWorkout(userId: String, workoutId: UUID) async throws {}

    func attemptCount() -> Int { attempts }
}

private actor InertHeartRateRepository: WorkoutHeartRateStorageRepositoryProtocol {
    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference {
        FirestoreWorkoutHeartRateSeriesReference(
            storagePath: WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId),
            sampleCount: blob.samples.count,
            seriesStartAt: Date(timeIntervalSince1970: 0),
            seriesEndAt: Date(timeIntervalSince1970: 0)
        )
    }

    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob {
        throw WorkoutHeartRateSidecarError.missing
    }

    func deleteHeartRateSeriesIfPresent(userId: String, workoutId: UUID) async throws {}
}
