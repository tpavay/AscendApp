import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// What happens to the climbs that failing credentials stopped, once the climber signs back in.
///
/// An `authentication` series spends more than twenty-four hours before it exhausts, so by the time
/// the sign-in is repaired the affected climbs have scrolled far into the climber's history. A
/// manual-only recovery would ask them to go hunting for something they do not know is broken, so
/// the automatic trigger is the point of this file rather than a nicety.
///
/// Every test seeds its own `UserDefaults` suite and pins the recovery basis to the value the
/// coordinator would record, so the build-or-epoch trigger - which re-opens *every* stopped series -
/// cannot do this trigger's work for it and make a passing assertion meaningless.
@MainActor
struct WorkoutSyncAuthenticationRecoveryTests {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)
    private let buildIdentity = "test-build"

    /// The whole point, end to end: the climb lands on its own, with nobody hunting for it.
    @Test
    func signingBackInResumesAClimbStoppedByFailingCredentials() async throws {
        let modelContext = try makeModelContext()
        let defaults = try makeDefaults()
        pinRecoveryBasis(in: defaults, for: "user-a")

        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(
            ownerUserId: "user-a",
            modifiedAt: start.addingTimeInterval(-2 * 60 * 60)
        )
        workout.markRemoteSyncRejected("The user is not authenticated.")
        modelContext.insert(workout)
        modelContext.insert(
            makeStoppedEntry(for: workout, ownerUserId: "user-a", blockedBy: .authentication)
        )
        try modelContext.save()

        let repository = AcceptingRepository()
        let coordinator = makeCoordinator(repository: repository, defaults: defaults)

        // Firebase signing the climber out is the half of the transition the coordinator itself
        // cannot see, so it is the half the test has to stage.
        coordinator.forgetAuthenticatedIdentity()

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-a"
        )

        #expect(await repository.upsertCount() == 1)
        #expect(try #require(try fetchWorkouts(in: modelContext).first).remoteSyncStatus == .synced)
        #expect(try fetchEntries(in: modelContext).isEmpty)
    }

    /// Signing in as somebody else says nothing about this climber's backlog.
    @Test
    func anUnrelatedIdentityChangeLeavesTheStoppedSeriesAlone() async throws {
        let modelContext = try makeModelContext()
        let defaults = try makeDefaults()
        pinRecoveryBasis(in: defaults, for: "user-b")

        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(
            ownerUserId: "user-a",
            modifiedAt: start.addingTimeInterval(-2 * 60 * 60)
        )
        workout.markRemoteSyncRejected("The user is not authenticated.")
        modelContext.insert(workout)
        modelContext.insert(
            makeStoppedEntry(for: workout, ownerUserId: "user-a", blockedBy: .authentication)
        )
        try modelContext.save()

        let repository = AcceptingRepository()
        let coordinator = makeCoordinator(repository: repository, defaults: defaults)

        coordinator.forgetAuthenticatedIdentity()

        // Sign-out does not empty the local store, so this device still holds user-a's stopped
        // climbs while user-b is the one signed in.
        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-b"
        )

        let entry = try #require(try fetchEntries(in: modelContext).first)
        #expect(entry.automaticAttemptCount == WorkoutSyncRetryPolicy.maximumAutomaticAttempts)
        #expect(entry.failureCategory == .authentication)
        #expect(entry.hasStoppedAutomaticAttempts(now: start))
        #expect(await repository.upsertCount() == 0)
    }

    /// A sign-in that fails repairs nothing, so it must buy nothing.
    ///
    /// Also the guard against the naive implementation: a trigger that re-opened on every pass
    /// would pass every other test in this file and quietly restore the unbounded retry loop the
    /// persisted schedule exists to make impossible.
    @Test
    func aFailedSignInBuysNoAttemptAndNeitherDoesAnyLaterPass() async throws {
        let modelContext = try makeModelContext()
        let defaults = try makeDefaults()
        pinRecoveryBasis(in: defaults, for: "user-a")
        // The climber is already signed in and stays signed in: a failed attempt never reaches the
        // sign-out branch, so the recorded identity is untouched.
        defaults.set("user-a", forKey: WorkoutSyncCoordinator.authenticatedIdentityDefaultsKey)

        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(
            ownerUserId: "user-a",
            modifiedAt: start.addingTimeInterval(-2 * 60 * 60)
        )
        workout.markRemoteSyncRejected("The user is not authenticated.")
        modelContext.insert(workout)
        modelContext.insert(
            makeStoppedEntry(for: workout, ownerUserId: "user-a", blockedBy: .authentication)
        )
        try modelContext.save()

        let repository = AcceptingRepository()
        let coordinator = makeCoordinator(repository: repository, defaults: defaults)

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-a"
        )
        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-a"
        )

        let entry = try #require(try fetchEntries(in: modelContext).first)
        #expect(entry.automaticAttemptCount == WorkoutSyncRetryPolicy.maximumAutomaticAttempts)
        #expect(entry.failureCategory == .authentication)
        #expect(await repository.upsertCount() == 0)
    }

    /// Repairing a sign-in is a statement about credentials, never about the bytes on offer.
    @Test
    func signingBackInDoesNotReopenARefusedOrMalformedSeries() async throws {
        let modelContext = try makeModelContext()
        let defaults = try makeDefaults()
        pinRecoveryBasis(in: defaults, for: "user-a")

        let refusedWorkout = makeWorkout()
        refusedWorkout.markPendingRemoteUpsert(
            ownerUserId: "user-a",
            modifiedAt: start.addingTimeInterval(-2 * 60 * 60)
        )
        refusedWorkout.markRemoteSyncRejected("Missing or insufficient permissions.")
        let refusedEntry = makeStoppedEntry(
            for: refusedWorkout,
            ownerUserId: "user-a",
            blockedBy: .refused
        )
        refusedEntry.automaticAttemptCount = WorkoutSyncRetryPolicy.refusalsBeforeStopping
        refusedEntry.refusalCount = WorkoutSyncRetryPolicy.refusalsBeforeStopping

        let malformedWorkout = makeWorkout()
        malformedWorkout.markPendingRemoteUpsert(
            ownerUserId: "user-a",
            modifiedAt: start.addingTimeInterval(-2 * 60 * 60)
        )
        malformedWorkout.markRemoteSyncRejected("Invalid argument.")
        let malformedEntry = makeStoppedEntry(
            for: malformedWorkout,
            ownerUserId: "user-a",
            blockedBy: .malformed
        )
        malformedEntry.automaticAttemptCount = 1

        modelContext.insert(refusedWorkout)
        modelContext.insert(malformedWorkout)
        modelContext.insert(refusedEntry)
        modelContext.insert(malformedEntry)
        try modelContext.save()

        let repository = AcceptingRepository()
        let coordinator = makeCoordinator(repository: repository, defaults: defaults)

        coordinator.forgetAuthenticatedIdentity()

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-a"
        )

        let refused = try #require(try fetchEntry(for: refusedWorkout.id, in: modelContext))
        #expect(refused.failureCategory == .refused)
        #expect(refused.refusalCount == WorkoutSyncRetryPolicy.refusalsBeforeStopping)
        #expect(refused.hasStoppedAutomaticAttempts(now: start))

        let malformed = try #require(try fetchEntry(for: malformedWorkout.id, in: modelContext))
        #expect(malformed.failureCategory == .malformed)
        #expect(malformed.automaticAttemptCount == 1)
        #expect(malformed.hasStoppedAutomaticAttempts(now: start))

        #expect(await repository.upsertCount() == 0)
    }

    // MARK: - Fixtures

    /// A series that has walked the whole schedule and outlived its final offset.
    private func makeStoppedEntry(
        for workout: Workout,
        ownerUserId: String,
        blockedBy category: WorkoutSyncFailureCategory
    ) -> WorkoutSyncOutboxEntry {
        let entry = WorkoutSyncOutboxEntry(
            workoutId: workout.id,
            ownerUserId: ownerUserId,
            firstPendingAt: start.addingTimeInterval(-48 * 60 * 60)
        )
        entry.automaticAttemptCount = WorkoutSyncRetryPolicy.maximumAutomaticAttempts
        entry.failureCategory = category
        // Later than the workout's last modification, so the pass reads the schedule as armed
        // against the bytes on offer rather than restarting the series it is measuring.
        entry.lastAttemptAt = start.addingTimeInterval(-60 * 60)
        return entry
    }

    private func makeCoordinator(
        repository: AcceptingRepository,
        defaults: UserDefaults
    ) -> WorkoutSyncCoordinator {
        // Frozen: every deadline in these tests is staged relative to it, so nothing depends on
        // wall-clock time passing between the seed and the pass.
        let now = start
        return WorkoutSyncCoordinator(
            remoteRepository: repository,
            heartRateStorageRepository: InertHeartRateRepository(),
            operationTimeoutSeconds: 1,
            connectivityService: StubConnectivity(isConnected: true),
            // The baseline an unfetched device reads, so nothing here depends on a live backend.
            settingReader: StubSettingReader(epoch: 0),
            userDefaults: defaults,
            buildIdentity: buildIdentity,
            now: { now }
        )
    }

    /// Records the basis the coordinator would have recorded, so only the identity trigger can move
    /// anything in these tests.
    private func pinRecoveryBasis(in defaults: UserDefaults, for userId: String) {
        defaults.set(
            "\(buildIdentity)|0",
            forKey: WorkoutSyncCoordinator.recoveryBasisDefaultsKeyPrefix + userId
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "WorkoutSyncAuthenticationRecoveryTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
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

    private func fetchWorkouts(in modelContext: ModelContext) throws -> [Workout] {
        try modelContext.fetch(FetchDescriptor<Workout>())
    }

    private func fetchEntries(
        in modelContext: ModelContext
    ) throws -> [WorkoutSyncOutboxEntry] {
        try modelContext.fetch(FetchDescriptor<WorkoutSyncOutboxEntry>())
    }

    private func fetchEntry(
        for workoutId: UUID,
        in modelContext: ModelContext
    ) throws -> WorkoutSyncOutboxEntry? {
        try modelContext.fetch(
            FetchDescriptor<WorkoutSyncOutboxEntry>(
                predicate: #Predicate { $0.workoutId == workoutId }
            )
        ).first
    }
}

@MainActor
private struct StubConnectivity: WorkoutSyncConnectivityProviding {
    let isConnected: Bool
}

private struct StubSettingReader: RemoteConfigSettingReading {
    let epoch: Int

    func integer(_ setting: RemoteConfigSetting) -> Int { epoch }
}

/// Accepts every write, so a re-opened climb is observably in the cloud and one that was never
/// re-opened is observably still waiting.
private actor AcceptingRepository: WorkoutRemoteRepositoryProtocol {
    private var upserts: [UUID] = []

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] { [] }

    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws {
        upserts.append(workoutId)
    }

    func deleteWorkout(userId: String, workoutId: UUID) async throws {}

    func upsertCount() -> Int { upserts.count }
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
