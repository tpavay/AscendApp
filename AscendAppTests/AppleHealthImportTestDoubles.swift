import Foundation
import HealthKit
import SwiftData
@testable import AscendApp

// Doubles and a harness for Apple Health import, so the import rules run without a device, a
// Health database or a signed-in Firebase user.

/// A Health database with exactly the workouts a test puts in it.
@MainActor
final class FakeHealthWorkoutReader: HealthWorkoutReading {
    var isHealthDataAvailable = true
    /// Everything Health holds, in the order it arrived. The anchor is how many the reader has
    /// already handed out, so a second read returns only what is new.
    var workouts: [HealthWorkoutSnapshot] = []
    var readError: (any Error)?
    /// How long a read takes, for the observer's time bound.
    var readDelay: Duration?
    private(set) var changeReads: [(anchor: Data?, earliest: Date)] = []
    private(set) var snapshotReads: [UUID] = []
    private(set) var isObserving = false
    private var observerHandler: (@MainActor (@escaping @Sendable () -> Void) -> Void)?

    func changes(since anchorData: Data?, startingOnOrAfter earliest: Date) async throws -> HealthWorkoutChanges {
        changeReads.append((anchorData, earliest))
        if let readDelay { try? await Task.sleep(for: readDelay) }
        if let readError { throw readError }

        let alreadySeen = anchorData.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init) ?? 0
        let fresh = Array(workouts.dropFirst(alreadySeen)).filter { $0.startDate >= earliest }
        return HealthWorkoutChanges(
            added: fresh,
            anchorData: Data(String(workouts.count).utf8)
        )
    }

    func snapshot(for uuid: UUID) async throws -> HealthWorkoutSnapshot? {
        snapshotReads.append(uuid)
        return workouts.first { $0.uuid == uuid }
    }

    func startObserving(onChange: @escaping @MainActor (@escaping @Sendable () -> Void) -> Void) {
        isObserving = true
        observerHandler = onChange
    }

    func stopObserving() {
        isObserving = false
        observerHandler = nil
    }

    /// What HealthKit does when a workout is saved: calls the registered handler with a
    /// completion it then waits on.
    func deliverObserverNotification(completion: @escaping @Sendable () -> Void) {
        observerHandler?(completion)
    }
}

@MainActor
final class RecordingHealthImportNotifier: HealthImportNotifying {
    private(set) var imported: [(workoutID: UUID, steps: Int?)] = []

    func climbImported(workoutID: UUID, steps: Int?) async {
        imported.append((workoutID, steps))
    }
}

/// Deletes climbs from the context and nothing else: no cloud queue, no media, no leaderboard.
@MainActor
final class InProcessHealthImportClimbRemover: HealthImportClimbRemoving {
    private(set) var removedClimbIDs: [UUID] = []

    func remove(_ climbs: [Workout], modelContext: ModelContext, fallbackUserID: String?) async throws {
        for climb in climbs {
            removedClimbIDs.append(climb.id)
            modelContext.delete(climb)
        }
        try modelContext.save()
    }
}

@MainActor
final class FakeImportAuthorization: HealthKitAuthorizationControlling {
    var isHealthDataAvailable = true
    var hasRequestedAuthorization = true
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var lastPermissionErrorMessage: String?
    var connectionState: AppleHealthConnectionState = .connected
    var importConnectionState: AppleHealthConnectionState = .connected
    var grantsAuthorization = true
    private(set) var authorizationRequests = 0

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        if grantsAuthorization {
            importConnectionState = .connected
            connectionState = .connected
        }
        return grantsAuthorization
    }
}

/// A signed-in climber, a store, and an import service wired to fakes.
@MainActor
final class AppleHealthImportHarness {
    static let userID = "import-test-user"
    /// The climber joined a month before `now`.
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let joinDate = now.addingTimeInterval(-30 * 24 * 3600)

    let reader = FakeHealthWorkoutReader()
    let authorization = FakeImportAuthorization()
    let notifier = RecordingHealthImportNotifier()
    let remover = InProcessHealthImportClimbRemover()
    let container: ModelContainer
    let context: ModelContext
    let defaults: UserDefaults
    let settings: AppleHealthImportSettings
    let service: AppleHealthImportService

    /// The moment "now" is, and the join date a month before it. Fixed by default so a test's dates
    /// never depend on the day it runs; a hosted screen that words its rows against the real clock
    /// passes `Date()` instead.
    let referenceNow: Date
    var referenceJoinDate: Date { referenceNow.addingTimeInterval(-30 * 24 * 3600) }

    init(
        referenceNow: Date = AppleHealthImportHarness.now,
        featureFlags: RemoteFeatureFlagStore = RemoteFeatureFlagStore(),
        observerCompletionBound: Duration = .seconds(25)
    ) throws {
        self.referenceNow = referenceNow
        container = try RetainedModelContainer.inMemory(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            WorkoutSyncOutboxEntry.self,
            PendingWorkoutDeletion.self,
            HealthWorkoutRecord.self,
            ActiveHeadphoneWorkoutDraft.self
        )
        context = container.mainContext
        let suite = "AppleHealthImportHarness.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        settings = AppleHealthImportSettings(defaults: defaults)

        let holder = HarnessState()
        service = AppleHealthImportService(
            reader: reader,
            authorization: authorization,
            settings: settings,
            notifier: notifier,
            remover: remover,
            featureFlags: featureFlags,
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            currentUserID: { holder.userID },
            joinDate: { referenceNow.addingTimeInterval(-30 * 24 * 3600) },
            hasRestoredCloudClimbs: { holder.restoredUserIDs.contains($0) },
            applyCreated: { _, workouts in holder.created.append(workouts) },
            isUpdateRequired: { holder.isUpdateRequired },
            now: { holder.clock },
            observerCompletionBound: observerCompletionBound
        )
        holder.userID = Self.userID
        holder.restoredUserIDs = [Self.userID]
        holder.clock = referenceNow
        state = holder
        service.configure(modelContext: context)
    }

    /// Everything the closures above read, held by reference so a test can change it after the
    /// service captured it.
    final class HarnessState {
        var userID: String?
        /// The climbers whose climbs have come back from the cloud this session.
        var restoredUserIDs: Set<String> = []
        var isUpdateRequired = false
        var clock = Date()
        var created: [[Workout]] = []
    }
    let state: HarnessState

    var created: [[Workout]] { state.created }
    var userID: String? {
        get { state.userID }
        set { state.userID = newValue }
    }
    var clock: Date {
        get { state.clock }
        set { state.clock = newValue }
    }
    var isUpdateRequired: Bool {
        get { state.isUpdateRequired }
        set { state.isUpdateRequired = newValue }
    }
    var hasRestoredCloudClimbs: Bool {
        get { state.restoredUserIDs.contains(Self.userID) }
        set {
            if newValue {
                state.restoredUserIDs.insert(Self.userID)
            } else {
                state.restoredUserIDs.remove(Self.userID)
            }
        }
    }

    /// A stair workout `daysAgo` before now, with the numbers a watch would write.
    @discardableResult
    func addWorkout(
        daysAgo: Double,
        steps: Int? = 3_000,
        minutes: Double = 30,
        averageHeartRate: Int? = 140,
        maxHeartRate: Int? = 165,
        energy: Int? = 280,
        uuid: UUID = UUID()
    ) -> HealthWorkoutSnapshot {
        let start = referenceNow.addingTimeInterval(-daysAgo * 24 * 3600)
        let snapshot = HealthWorkoutSnapshot(
            uuid: uuid,
            startDate: start,
            endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60,
            steps: steps,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            activeEnergyKilocalories: energy,
            sourceName: "Test Watch"
        )
        reader.workouts.append(snapshot)
        return snapshot
    }

    func records() throws -> [HealthWorkoutRecord] {
        try context.fetch(FetchDescriptor<HealthWorkoutRecord>())
    }

    func record(_ snapshot: HealthWorkoutSnapshot) throws -> HealthWorkoutRecord? {
        try records().first { $0.workoutUUID == snapshot.uuid.uuidString }
    }

    func climbs() throws -> [Workout] {
        try context.fetch(FetchDescriptor<Workout>())
    }
}
