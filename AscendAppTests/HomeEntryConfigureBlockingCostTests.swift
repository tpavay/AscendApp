import Foundation
import HealthKit
import SwiftData
import Testing

@testable import AscendApp

/// End-to-end evidence for ASCEND-IOS-1K at the seam a user actually feels it.
///
/// `HomeEntryImportCostEvidenceTests` times the query in isolation. This one times the whole
/// synchronous call Home makes - `WorkoutImportCoordinator.configure(modelContext:)`, straight off
/// `HomeView.task` - against a store the size of a committed athlete's Apple Health history. Every
/// microsecond that call spends is a microsecond Home cannot draw in, which is why the reported
/// hang was a *fully blocked* 182 seconds rather than a slow screen.
///
/// The comparison is the pre-fix shape of the same work: `fetch(FetchDescriptor<Workout>())`, run
/// moments earlier in the same process against the same store, so runner load moves both numbers
/// together and only their separation is asserted (the house rule from
/// `HeartRateChartRenderCostEvidenceTests`).
@MainActor
@Suite(.serialized)
struct HomeEntryConfigureBlockingCostTests {
    private static let storeSize = 900
    private static let heartRateSamplesPerWorkout = 2_600
    private static let measurementRuns = 5
    private static let sessionStart = Date(timeIntervalSince1970: 1_750_000_000)

    @Test
    func enteringHomeWithYearsOfHistoryDoesNotBlockOnTheWholeStore() async throws {
        try await HealthKitImportCoordinatorTestIsolation.shared.run {
            let stores = Self.makeIsolatedStores()
            defer { stores.defaults.removePersistentDomain(forName: stores.suiteName) }

            let seeded = try #require(Self.seededStore, "the seeded evidence store failed to open")
            let context = ModelContext(seeded.container)
            let reviewedWorkoutID = try #require(seeded.workoutIDs.first)

            // The state the prune exists to police: Home recorded one auto-imported workout for
            // review, and on the next entry has to find out whether it is still in the store.
            stores.reviewStateStore.recordLatestWorkout(
                id: reviewedWorkoutID,
                referenceDate: Self.sessionStart
            )

            // The pre-fix cost, measured first so the post-fix number cannot benefit from a warmer
            // page cache than the one it is being compared against.
            let scanDuration = Self.fastestOf(Self.measurementRuns) {
                _ = try ModelContext(seeded.container).fetch(
                    FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date, order: .forward)])
                ).map(\.id)
            }

            let coordinator = WorkoutImportCoordinator(
                authorizationController: OfflineAuthorizationController(),
                workoutReader: EmptyWorkoutReader(),
                metricsReader: EmptyMetricsReader(),
                reviewStateStore: stores.reviewStateStore,
                ignoredAppleHealthWorkoutStore: stores.ignoredAppleHealthWorkoutStore
            )

            // Exactly what `HomeView.task` runs before Home can draw.
            let configureDuration = Self.fastestOf(Self.measurementRuns) {
                coordinator.configure(modelContext: context)
            }

            print(
                """
                ASCEND-IOS-1K Home entry: synchronous cost of WorkoutImportCoordinator.configure
                  store                \(Self.storeSize) workouts, \
                \(Self.heartRateSamplesPerWorkout) heart-rate samples each
                  inline blob bytes    \(seeded.inlineHeartRateBytes)
                  pre-fix full scan    \(Self.milliseconds(scanDuration)) ms   \
                (what pruneAutoImportedReviewState used to do)
                  configure() blocking \(Self.milliseconds(configureDuration)) ms   (post-fix)
                  attention count      \(coordinator.attentionCount)
                """
            )

            // Home's affordance is correct on the way out: the recorded workout is still in the
            // store, so it is still waiting to be reviewed and the bell still carries it.
            #expect(stores.reviewStateStore.recordedWorkoutID() == reviewedWorkoutID)
            #expect(coordinator.attentionCount == 1)

            // The blocking call must not scale with the store. Asserted as a ratio for the same
            // reason the sibling suite does: an absolute millisecond threshold flakes on a loaded
            // runner, a same-process ratio does not.
            #expect(
                configureDuration * 10 < scanDuration,
                """
                configure() blocked for \(Self.milliseconds(configureDuration)) ms against a full \
                scan's \(Self.milliseconds(scanDuration)) ms; Home entry should not be reading the \
                whole store
                """
            )

            // And the prune still does its job: a workout that has since been deleted gets cleared
            // out of the snapshot rather than leaving the bell stuck on a phantom.
            let survivor = try #require(
                try context.fetch(
                    FetchDescriptor<Workout>(
                        predicate: #Predicate<Workout> { workout in
                            workout.id == reviewedWorkoutID
                        }
                    )
                ).first
            )
            context.delete(survivor)
            try context.save()

            coordinator.configure(modelContext: context)

            #expect(stores.reviewStateStore.recordedWorkoutID() == nil)
            #expect(coordinator.attentionCount == 0)

            // `configure` hands the legacy source-link backfill to a task that would otherwise
            // keep sweeping this store after the test returns. Stop it and give it turns to
            // unwind, so it is not still writing while the next suite runs.
            coordinator.cancelInFlightWork()
            for _ in 0..<100 {
                await Task.yield()
            }
        }
    }

    // MARK: - Fixture

    private struct SeededStore {
        let container: ModelContainer
        let workoutIDs: [UUID]
        let inlineHeartRateBytes: Int
    }

    /// Seeded once and held for the life of the process.
    ///
    /// `configure` hands the context to `LeaderboardService.shared` and starts the legacy
    /// source-link backfill on a task that outlives this test. Letting the container fall out of
    /// scope leaves both of those pointed at a store that no longer exists, and the next save
    /// *any* suite performs then traps inside SwiftData's change notification and takes the whole
    /// test process down. Holding it is cheaper than trying to prove nothing still references it.
    private static let seededStore: SeededStore? = try? makeSeededStore()

    /// A directory of this test's own, emptied on the way in - the store runs to ~90 MB, and a
    /// `ModelContainer` has no close, so last run's files are the only ones safe to unlink.
    private static func freshStoreDirectory() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "ascend-ios-1k-home-entry")
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func makeSeededStore() throws -> SeededStore {
        let url = freshStoreDirectory().appending(path: "\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            LeaderboardStats.self,
            Routine.self,
            RoutineFolder.self,
            ClimbAttempt.self,
            PendingMediaUpload.self,
            configurations: ModelConfiguration(url: url)
        )
        let seedContext = ModelContext(container)
        var workouts: [Workout] = []

        for index in 0..<storeSize {
            let workout = Workout(
                name: "Seeded \(index)",
                date: sessionStart.addingTimeInterval(TimeInterval(index) * -86_400),
                duration: 45 * 60,
                steps: 3_200,
                floors: 200,
                heartRateTimeSeries: heartRateSeries(count: heartRateSamplesPerWorkout),
                source: .appleHealth,
                healthKitUUID: UUID().uuidString
            )
            seedContext.insert(workout)
            workouts.append(workout)
        }

        try seedContext.save()

        return SeededStore(
            container: container,
            workoutIDs: workouts.map(\.id),
            inlineHeartRateBytes: workouts.reduce(0) { $0 + ($1.heartRateData?.count ?? 0) }
        )
    }

    private static func heartRateSeries(count: Int) -> [HeartRateDataPoint] {
        (0..<count).map { second in
            HeartRateDataPoint(
                timestamp: sessionStart.addingTimeInterval(TimeInterval(second)),
                heartRate: 120 + (second % 60)
            )
        }
    }

    private static func makeIsolatedStores() -> (
        suiteName: String,
        defaults: UserDefaults,
        reviewStateStore: WorkoutAutoImportReviewStateStore,
        ignoredAppleHealthWorkoutStore: IgnoredAppleHealthWorkoutStore
    ) {
        let suiteName = "HomeEntryConfigureBlockingCostTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        return (
            suiteName,
            defaults,
            WorkoutAutoImportReviewStateStore(defaults: defaults, key: "auto-review"),
            IgnoredAppleHealthWorkoutStore(defaults: defaults, key: "ignored-apple-health")
        )
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let components = duration.components
        let value = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f", value)
    }

    /// The fastest of `runs`. Noise only ever adds time, so the minimum is the honest estimate and
    /// the statistic least sensitive to a busy runner.
    private static func fastestOf(_ runs: Int, _ work: () throws -> Void) -> Duration {
        var fastest: Duration = .seconds(Int.max)

        for _ in 0..<runs {
            let start = ContinuousClock.now
            try? work()
            fastest = min(fastest, ContinuousClock.now - start)
        }

        return fastest
    }
}

@MainActor
private final class EmptyWorkoutReader: HealthKitWorkoutReading {
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
private final class EmptyMetricsReader: HealthKitMetricsReading {
    func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics {
        WorkoutMetrics(steps: 0)
    }
}

@MainActor
private final class OfflineAuthorizationController: HealthKitAuthorizationControlling {
    let isHealthDataAvailable = true
    let hasRequestedAuthorization = true
    let hasCompletedInitialBackfill = true
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var lastPermissionErrorMessage: String?
    let connectionState: AppleHealthConnectionState = .connected

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool { true }
}
