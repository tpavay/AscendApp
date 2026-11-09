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
    /// The steps Health counted over a window, keyed by the moment the window starts. A window
    /// with no entry holds no steps, which is what Health says about most of a day.
    var windowSteps: [Date: Int] = [:]
    var windowReadError: (any Error)?
    private(set) var windowReads: [(start: Date, end: Date)] = []
    /// The most window reads that were ever out at the same moment.
    private(set) var mostWindowReadsInFlight = 0
    private var windowReadsInFlight = 0
    private(set) var changeReads: [(anchor: Data?, earliest: Date)] = []
    private(set) var snapshotReads: [UUID] = []
    private(set) var isObserving = false
    /// Parks every `snapshot` call until `releaseSnapshots()`, ignoring cancellation the way a
    /// HealthKit read in flight does.
    var holdsSnapshots = false
    private var heldSnapshots: [CheckedContinuation<Void, Never>] = []
    var heldSnapshotCount: Int { heldSnapshots.count }
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
        if holdsSnapshots {
            await withCheckedContinuation { heldSnapshots.append($0) }
        }
        return workouts.first { $0.uuid == uuid }
    }

    func stepCount(from start: Date, to end: Date) async throws -> Int? {
        windowReads.append((start, end))
        windowReadsInFlight += 1
        mostWindowReadsInFlight = max(mostWindowReadsInFlight, windowReadsInFlight)
        defer { windowReadsInFlight -= 1 }
        // A HealthKit read always suspends, which is what lets several be out at once.
        await Task.yield()
        if let windowReadError { throw windowReadError }
        return windowSteps[start]
    }

    func releaseSnapshots() {
        holdsSnapshots = false
        let held = heldSnapshots
        heldSnapshots = []
        held.forEach { $0.resume() }
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

@MainActor
final class RecordingHealthWorkoutSkipReporter: HealthWorkoutSkipReporting {
    private(set) var skips: [HealthWorkoutSkip] = []

    func report(_ skip: HealthWorkoutSkip) {
        skips.append(skip)
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
    /// What Health answers when asked, for a launch that has not heard yet.
    var importConnectionStateAfterRefresh: AppleHealthConnectionState?
    var grantsAuthorization = true
    private(set) var authorizationRequests = 0

    func refreshAuthorizationRequestStatus() async {
        if let importConnectionStateAfterRefresh {
            importConnectionState = importConnectionStateAfterRefresh
        }
    }

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
    let skipReporter = RecordingHealthWorkoutSkipReporter()
    let container: ModelContainer
    let context: ModelContext
    let defaults: UserDefaults
    let settings: AppleHealthImportSettings
    let sessionStore: AccountSessionStore
    let service: AppleHealthImportService
    private let makeService: @MainActor () -> AppleHealthImportService

    /// A new process on the same device: everything in memory is gone, and the settings and the
    /// store are what they were.
    func relaunchedService() -> AppleHealthImportService {
        let relaunched = makeService()
        relaunched.configure(modelContext: context)
        relaunched.confirmCloudClimbsRestored(for: Self.userID)
        return relaunched
    }

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
        container = try RetainedModelContainer.inMemory(schema: AscendLocalStore.schema)
        context = container.mainContext
        let suite = "AppleHealthImportHarness.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        settings = AppleHealthImportSettings(defaults: defaults)
        sessionStore = AccountSessionStore(userDefaults: defaults)
        sessionStore.recordLocalDataOwner(userId: Self.userID)

        let holder = HarnessState()
        let (reader, authorization, settings, notifier, remover) = (reader, authorization, settings, notifier, remover)
        let skipReporter = skipReporter
        let sessionStore = sessionStore
        let makeService: @MainActor () -> AppleHealthImportService = {
            AppleHealthImportService(
                reader: reader,
                authorization: authorization,
                settings: settings,
                notifier: notifier,
                remover: remover,
                skipReporter: skipReporter,
                featureFlags: featureFlags,
                sessionWorkGate: AuthenticatedBootstrapCoordinator(),
                sessionStore: sessionStore,
                currentUserID: { holder.userID },
                joinDate: { referenceNow.addingTimeInterval(-30 * 24 * 3600) },
                applyCreated: { _, workouts in holder.created.append(workouts) },
                isUpdateRequired: { holder.isUpdateRequired },
                now: { holder.clock },
                observerCompletionBound: observerCompletionBound
            )
        }
        self.makeService = makeService
        service = makeService()
        holder.userID = Self.userID
        holder.clock = referenceNow
        state = holder
        service.configure(modelContext: context)
        service.confirmCloudClimbsRestored(for: Self.userID)
    }

    /// Everything the closures above read, held by reference so a test can change it after the
    /// service captured it.
    final class HarnessState {
        var userID: String?
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

    /// What the authenticated bootstrap does on sign-in: asks the real ownership gate about this
    /// store, and remembers the climber as its owner only when the gate allows them.
    @discardableResult
    func signInThroughOwnershipGate(_ userID: String) throws -> AccountDataOwnershipDecision {
        self.userID = userID
        let decision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: context,
            signedInUserId: userID,
            sessionStore: sessionStore
        )
        if decision == .allowed {
            AccountDataOwnershipService.recordAuthorizedOwner(signedInUserId: userID, sessionStore: sessionStore)
        }
        return decision
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
        windowSteps: Int? = nil,
        activityTypeRawValue: UInt? = HKWorkoutActivityType.stairClimbing.rawValue,
        sourceBundleIdentifier: String? = "com.example.watch",
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
            sourceName: "Test Watch",
            activityTypeRawValue: activityTypeRawValue,
            sourceBundleIdentifier: sourceBundleIdentifier
        )
        reader.workouts.append(snapshot)
        // What Health's step count holds for the time the workout ran, whoever counted it.
        reader.windowSteps[start] = windowSteps
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
