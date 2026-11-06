import FirebaseFirestore
import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// Sign-in comes before the paywall, so onboarding's history lands while the climber holds no app
/// access, and `firestore.rules` refuses a workout from an account with no grant. Paying must be
/// what puts those climbs in the cloud, with no refusal on record and no retry to find.
@MainActor
struct WorkoutSyncAppAccessHoldTests {
    private let userId = AppleHealthImportHarness.userID
    private let buildIdentity = "test-build"

    @MainActor
    private final class Access {
        var state: WorkoutSyncCoordinator.AppAccess = .absent
    }

    private func makeDefaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: "WorkoutSyncAppAccessHoldTests.\(UUID().uuidString)"))
        // The build-or-epoch trigger re-opens every stopped series, so it is pinned out of the way:
        // what re-opens here has to be access.
        defaults.set("\(buildIdentity)|0", forKey: WorkoutSyncCoordinator.recoveryBasisDefaultsKeyPrefix + userId)
        defaults.set(userId, forKey: WorkoutSyncCoordinator.authenticatedIdentityDefaultsKey)
        return defaults
    }

    private func makeCoordinator(
        repository: RulesLikeRepository,
        access: Access,
        defaults: UserDefaults,
        featureFlags: RemoteFeatureFlagStore = RemoteFeatureFlagStore()
    ) -> WorkoutSyncCoordinator {
        WorkoutSyncCoordinator(
            remoteRepository: repository,
            heartRateStorageRepository: InertHeartRateRepository(),
            featureFlags: featureFlags,
            operationTimeoutSeconds: 1,
            connectivityService: ConnectedStub(),
            settingReader: BaselineSettingReader(),
            userDefaults: defaults,
            buildIdentity: buildIdentity,
            appAccess: { access.state }
        )
    }

    private func entries(in context: ModelContext) throws -> [WorkoutSyncOutboxEntry] {
        try context.fetch(FetchDescriptor<WorkoutSyncOutboxEntry>())
    }

    /// One climb whose upload the rules have refused until the series stopped.
    private func insertStoppedClimb(
        in context: ModelContext,
        blockedBy category: WorkoutSyncFailureCategory = .refused
    ) throws -> Workout {
        let modifiedAt = Date().addingTimeInterval(-2 * 60 * 60)
        let workout = Workout(
            name: "Stair Stepper",
            date: modifiedAt,
            duration: 1_800,
            steps: 3_000,
            floors: Workout.stepsToFloors(3_000),
            source: .manual
        )
        workout.markPendingRemoteUpsert(ownerUserId: userId, modifiedAt: modifiedAt)
        workout.markRemoteSyncRejected("Missing or insufficient permissions.")
        context.insert(workout)

        let entry = WorkoutSyncOutboxEntry(
            workoutId: workout.id,
            ownerUserId: userId,
            firstPendingAt: Date().addingTimeInterval(-48 * 60 * 60)
        )
        entry.automaticAttemptCount = WorkoutSyncRetryPolicy.maximumAutomaticAttempts
        entry.refusalCount = WorkoutSyncRetryPolicy.refusalsBeforeStopping
        entry.failureCategory = category
        entry.lastAttemptAt = Date().addingTimeInterval(-60 * 60)
        context.insert(entry)
        try context.save()
        return workout
    }

    @Test
    func historyAddedWithNoAccessGoesUpWhenAccessArrivesWithNoRetryAndNoRefusalOnRecord() async throws {
        let harness = try AppleHealthImportHarness()
        let shown = [
            harness.addWorkout(daysAgo: 60, steps: 3_000, minutes: 40),
            harness.addWorkout(daysAgo: 90, steps: 4_000, minutes: 50),
            harness.addWorkout(daysAgo: 400, steps: 5_000, minutes: 60)
        ]
        await harness.service.importHistory(matching: Set(shown.map(\.uuid.uuidString)))

        let climbs = try harness.climbs()
        #expect(climbs.count == shown.count, "history lands in the first session, paid or not")
        for climb in climbs {
            climb.markPendingRemoteUpsert(ownerUserId: userId)
        }
        try harness.context.save()

        let repository = RulesLikeRepository()
        let access = Access()
        let coordinator = makeCoordinator(repository: repository, access: access, defaults: try makeDefaults())

        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)
        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)

        #expect(await repository.attemptCount() == 0, "nothing is offered to rules that would refuse it")
        #expect(try entries(in: harness.context).isEmpty, "no attempt, no refusal, no schedule on record")
        #expect(climbs.allSatisfy { $0.remoteSyncStatus == .pendingUpsert }, "pending state survives untouched")

        access.state = .held
        await repository.grantAccess()
        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)

        #expect(climbs.allSatisfy { $0.remoteSyncStatus == .synced })
        #expect(await repository.acceptedCount() == shown.count)
        #expect(try entries(in: harness.context).isEmpty)
    }

    @Test
    func aSeriesRefusalsAlreadyStoppedResumesWhenAccessArrives() async throws {
        let harness = try AppleHealthImportHarness()
        let stopped = try insertStoppedClimb(in: harness.context)
        let repository = RulesLikeRepository()
        let access = Access()
        let coordinator = makeCoordinator(repository: repository, access: access, defaults: try makeDefaults())

        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)
        #expect(stopped.remoteSyncStatus == .rejected)

        access.state = .held
        await repository.grantAccess()
        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)

        #expect(stopped.remoteSyncStatus == .synced)
        #expect(try entries(in: harness.context).isEmpty)
    }

    @Test
    func aSeriesARefusalOnlySlowedDoesNotWaitOutItsScheduleWhenAccessArrives() async throws {
        let harness = try AppleHealthImportHarness()
        let slowed = try insertStoppedClimb(in: harness.context)
        slowed.remoteSyncStatus = .failed
        let entry = try #require(try entries(in: harness.context).first)
        entry.automaticAttemptCount = 1
        entry.refusalCount = 1
        entry.firstPendingAt = Date().addingTimeInterval(-60)
        entry.nextEligibleAttemptAt = Date().addingTimeInterval(60 * 60)
        try harness.context.save()

        let repository = RulesLikeRepository()
        let access = Access()
        let coordinator = makeCoordinator(repository: repository, access: access, defaults: try makeDefaults())

        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)
        access.state = .held
        await repository.grantAccess()
        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)

        #expect(slowed.remoteSyncStatus == .synced)
    }

    @Test
    func holdingAccessWithNoHoldOnRecordLeavesAStoppedSeriesStopped() async throws {
        let harness = try AppleHealthImportHarness()
        let stopped = try insertStoppedClimb(in: harness.context)
        let repository = RulesLikeRepository()
        await repository.grantAccess()
        let access = Access()
        access.state = .held
        let coordinator = makeCoordinator(repository: repository, access: access, defaults: try makeDefaults())

        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)

        #expect(await repository.attemptCount() == 0, "a launch must not launder a refusal into another attempt")
        #expect(stopped.remoteSyncStatus == .rejected)
    }

    @Test
    func aPayingClimbersOrdinaryLaunchHoldsUploadsWhileUnknownAndReopensNothing() async throws {
        let harness = try AppleHealthImportHarness()
        let stopped = try insertStoppedClimb(in: harness.context)
        let pending = Workout(
            name: "Stair Stepper",
            duration: 1_800,
            steps: 3_000,
            floors: Workout.stepsToFloors(3_000),
            source: .manual
        )
        pending.markPendingRemoteUpsert(ownerUserId: userId)
        harness.context.insert(pending)
        try harness.context.save()

        let repository = RulesLikeRepository()
        await repository.grantAccess()
        let access = Access()
        access.state = .unknown
        let defaults = try makeDefaults()
        let coordinator = makeCoordinator(repository: repository, access: access, defaults: defaults)

        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)

        #expect(await repository.attemptCount() == 0, "uploads wait for the answer")
        #expect(!defaults.bool(forKey: WorkoutSyncCoordinator.appAccessHoldDefaultsKeyPrefix + userId))

        access.state = .held
        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)

        #expect(pending.remoteSyncStatus == .synced, "what was waiting goes up")
        #expect(stopped.remoteSyncStatus == .rejected, "a launch must not launder a refusal into another attempt")
        #expect(await repository.attemptCount() == 1)
    }

    @Test(arguments: [WorkoutSyncFailureCategory.malformed, .authentication])
    func accessArrivingLeavesASeriesStoppedForAnotherReasonStopped(category: WorkoutSyncFailureCategory) async throws {
        let harness = try AppleHealthImportHarness()
        let stopped = try insertStoppedClimb(in: harness.context, blockedBy: category)
        let repository = RulesLikeRepository()
        let access = Access()
        let coordinator = makeCoordinator(repository: repository, access: access, defaults: try makeDefaults())

        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)
        access.state = .held
        await repository.grantAccess()
        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)

        #expect(await repository.attemptCount() == 0, "paying moves nothing about these")
        #expect(stopped.remoteSyncStatus == .rejected)
    }

    @Test
    func accessIsOnlyAbsentOnceRevenueCatHasAnsweredNo() {
        typealias Access = WorkoutSyncCoordinator.AppAccess

        #expect(Access(hasAppAccess: true, entitlementState: .unknown) == .held)
        #expect(Access(hasAppAccess: true, entitlementState: .active(["app_access"])) == .held)
        #expect(Access(hasAppAccess: false, entitlementState: .unknown) == .unknown)
        #expect(Access(hasAppAccess: false, entitlementState: .inactive) == .absent)
        #expect(Access(hasAppAccess: false, entitlementState: .active(["other"])) == .absent)
    }

    @Test
    func aDeleteStillGoesThroughWhileUploadsAreHeld() async throws {
        let harness = try AppleHealthImportHarness()
        let deletedId = UUID()
        harness.context.insert(PendingWorkoutDeletion(workoutId: deletedId, ownerUserId: userId))
        try harness.context.save()
        let repository = RulesLikeRepository()
        let coordinator = makeCoordinator(repository: repository, access: Access(), defaults: try makeDefaults())

        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)

        #expect(await repository.deletedIds() == [deletedId], "the rules let an owner delete without a grant")
    }

    @Test
    func theKillSwitchOffAttemptsTheUploadAsBeforeTheHoldExisted() async throws {
        let harness = try AppleHealthImportHarness()
        let workout = Workout(
            name: "Stair Stepper",
            duration: 1_800,
            steps: 3_000,
            floors: Workout.stepsToFloors(3_000),
            source: .manual
        )
        workout.markPendingRemoteUpsert(ownerUserId: userId)
        harness.context.insert(workout)
        try harness.context.save()

        let off = RemoteFeatureFlagStore(
            snapshot: RemoteFeatureFlagSnapshot.resolving(
                remoteValues: [RemoteFeatureFlag.workoutSyncAppAccessHold.key: false]
            )
        )
        let repository = RulesLikeRepository()
        let coordinator = makeCoordinator(
            repository: repository,
            access: Access(),
            defaults: try makeDefaults(),
            featureFlags: off
        )

        await coordinator.processPendingWorkouts(modelContext: harness.context, currentUserId: userId)

        #expect(await repository.attemptCount() == 1)
        #expect(try #require(try entries(in: harness.context).first).failureCategory == .refused)
    }
}

@MainActor
private struct ConnectedStub: WorkoutSyncConnectivityProviding {
    let isConnected = true
}

private struct BaselineSettingReader: RemoteConfigSettingReading {
    func integer(_ setting: RemoteConfigSetting) -> Int { 0 }
}

/// Answers the way `firestore.rules` does: a workout write needs a grant, an owner's delete does not.
private actor RulesLikeRepository: WorkoutRemoteRepositoryProtocol {
    private var hasGrant = false
    private var attempts = 0
    private var accepted = 0
    private var deleted: [UUID] = []

    func grantAccess() { hasGrant = true }

    func attemptCount() -> Int { attempts }

    func acceptedCount() -> Int { accepted }

    func deletedIds() -> [UUID] { deleted }

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] { [] }

    func upsertWorkout(userId: String, workoutId: UUID, document: FirestoreWorkoutDocument) async throws {
        attempts += 1
        guard hasGrant else {
            throw NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue)
        }
        accepted += 1
    }

    func deleteWorkout(userId: String, workoutId: UUID) async throws {
        deleted.append(workoutId)
    }
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
