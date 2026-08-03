import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// Reproduces and then bounds ASCEND-IOS-1K, the 182-second fully-blocked app hang whose
/// symbolicated culprit was `WorkoutImportCoordinator.fetchAllWorkouts`.
///
/// The reported stack is
/// `HomeView.body` -> `WorkoutImportCoordinator.configure` -> `pruneAutoImportedReviewState`
/// -> `fetchAllWorkouts`, and the prune only ever needs to answer *one* question: is the single
/// workout ID recorded in the auto-import review snapshot still in the store? It answered it by
/// fetching and materialising every `Workout` row, on the main thread, on every Home entry. The
/// cost is unbounded in the size of the local workout store, which is itself a mirror of the
/// user's Apple Health history.
///
/// The masking condition is measured, not assumed: `Workout` keeps its heart-rate time series
/// inline in `heartRateData` (no `@Attribute(.externalStorage)`), so a store with the same row
/// count but real sessions in it is far more expensive to scan - 900 rows take ~30 ms bare and
/// ~175 ms carrying a 45-minute series each. A small Health store produces a small local store
/// and a fetch too fast to notice, which is exactly why this survived to now.
///
/// What the measurement *disproved*: the blobs are read but not retained. Scanning 900 rows
/// holding 93.6 MB of inline heart-rate JSON grew the process footprint by single-digit MB, not
/// ~94 MB, so CoreData is faulting the binary attributes. The scan is expensive because of the
/// bytes it reads and the object graph it builds, not because it parks the history in memory.
/// Resident memory was tried as the regression signal and rejected for the same reason: warm, it
/// reads 1.7 MB where cold it reads 8 MB, which is a flake waiting to happen.
///
/// No absolute wall-clock threshold is asserted either - that would flake on a loaded runner
/// (same rule as `HeartRateChartRenderCostEvidenceTests`). What is asserted is a *ratio* between
/// two measurements taken moments apart in the same process, which runner load moves together,
/// plus the exact structural fact that the scan built one object per row.
@MainActor
@Suite(.serialized)
struct HomeEntryImportCostEvidenceTests {
    private static let storeSize = 900
    private static let measurementRuns = 5
    private static let heartRateSamplesPerWorkout = 2_600
    private static let sessionStart = Date(timeIntervalSince1970: 1_750_000_000)

    /// A directory of this test's own, emptied of whatever the previous run left in it.
    ///
    /// Cleaning up on the way *in* rather than on the way out is deliberate: these stores run to
    /// ~90 MB each so they cannot accumulate, but unlinking a store file while its
    /// `ModelContainer` still has it open is an SQLite API violation and a container has no
    /// close. Last run's files are held open by nothing.
    private static func freshStoreDirectory(named name: String) -> URL {
        let directory = URL.temporaryDirectory.appending(path: "ascend-ios-1k-evidence/\(name)")
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The reproduction. Seeds a store the size an athlete with years of Apple Health history
    /// would have, then measures the pre-fix scan - `fetch(FetchDescriptor<Workout>())`, exactly
    /// what `fetchAllWorkouts` did - against the bounded existence query that replaces it.
    @Test
    func theHomeEntryPruneNoLongerScansTheWholeWorkoutStore() throws {
        let directory = Self.freshStoreDirectory(named: "prune")
        let store = try Self.makeSeededStore(
            in: directory,
            workoutCount: Self.storeSize,
            heartRateSamples: Self.heartRateSamplesPerWorkout
        )
        let survivor = try #require(store.workoutIDs.first)
        let missing = UUID()

        // Pre-fix: hydrate every row, and every inline heart-rate blob, to answer one
        // membership question. This is the call that blocked the main thread for 182 seconds.
        var scannedIDs: Set<UUID> = []
        let scanDuration = Self.fastestOf(Self.measurementRuns) {
            scannedIDs = try Set(
                store.freshContext().fetch(
                    FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date, order: .forward)])
                ).map(\.id)
            )
        }

        // Post-fix: ask the store only about the IDs the prune actually cares about.
        var boundedIDs: Set<UUID> = []
        let boundedDuration = Self.fastestOf(Self.measurementRuns) {
            boundedIDs = try WorkoutExistenceQuery.existingIDs(
                among: [survivor, missing],
                in: store.freshContext()
            )
        }

        print(
            """
            ASCEND-IOS-1K home-entry prune cost
              store              \(Self.storeSize) workouts, \
            \(Self.heartRateSamplesPerWorkout) heart-rate samples each
              inline blob bytes  \(store.inlineHeartRateBytes)
              full scan          \(Self.milliseconds(scanDuration)) ms   (pre-fix fetchAllWorkouts)
              bounded existence  \(Self.milliseconds(boundedDuration)) ms   (post-fix)
            """
        )

        // The bounded query answers the same question the scan did.
        #expect(boundedIDs == [survivor])
        #expect(scannedIDs.contains(survivor))
        #expect(scannedIDs.contains(missing) == false)

        // The reproduction: the pre-fix path built an object for every row in the store. This one
        // is exact - you cannot hold an array of 900 workouts without having materialised 900.
        #expect(scannedIDs.count == Self.storeSize)

        // The contract that must not regress. This is a ratio, not a threshold: both numbers are
        // the fastest of five runs taken moments apart in the same process, so
        // runner load moves them together and only the separation is asserted. The measured gap is
        // ~200x; requiring 10x leaves the room a threshold could not. A reimplementation as
        // Set(fetch(all).map(\\.id)) collapses the ratio to 1 and fails here - and it fails harder
        // the larger the user's history, which is the property that actually matters.
        #expect(
            boundedDuration * 10 < scanDuration,
            """
            the bounded existence query took \(Self.milliseconds(boundedDuration)) ms against the \
            full scan's \(Self.milliseconds(scanDuration)) ms; it should not be scanning the store
            """
        )
    }

    /// The disproof check. If the hang were driven by row count rather than by the inline
    /// heart-rate blobs, holding rows fixed and dropping the blobs would leave the scan cost
    /// roughly unchanged. It does not - which is exactly why a small Health store hides this.
    @Test
    func theScanCostTracksInlineHeartRateBytesNotRowCount() throws {
        let directory = Self.freshStoreDirectory(named: "masking")
        let fat = try Self.makeSeededStore(
            in: directory,
            workoutCount: Self.storeSize,
            heartRateSamples: Self.heartRateSamplesPerWorkout
        )
        let lean = try Self.makeSeededStore(
            in: directory,
            workoutCount: Self.storeSize,
            heartRateSamples: 0
        )

        let fatDuration = Self.timeFullScan(of: fat)
        let leanDuration = Self.timeFullScan(of: lean)

        print(
            """
            ASCEND-IOS-1K masking condition: same row count, different inline blob size
              rows                \(Self.storeSize) in both stores
              with heart rate     \(fat.inlineHeartRateBytes) bytes -> \
            \(Self.milliseconds(fatDuration)) ms
              without heart rate  \(lean.inlineHeartRateBytes) bytes -> \
            \(Self.milliseconds(leanDuration)) ms
            """
        )

        #expect(lean.inlineHeartRateBytes == 0)
        #expect(fat.inlineHeartRateBytes > lean.inlineHeartRateBytes)
    }

    // MARK: - Fixture

    /// A seeded on-disk store, sized like the history of an athlete this app is built for.
    private struct SeededStore {
        let container: ModelContainer
        let workoutIDs: [UUID]
        let inlineHeartRateBytes: Int

        /// A context with a cold row cache, so a measurement does not reuse rows the seeding
        /// step already materialised.
        func freshContext() -> ModelContext {
            ModelContext(container)
        }

    }

    private static func makeSeededStore(
        in directory: URL,
        workoutCount: Int,
        heartRateSamples: Int
    ) throws -> SeededStore {
        let url = directory.appending(path: "\(UUID().uuidString).store")
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

        for index in 0..<workoutCount {
            let workout = Workout(
                name: "Seeded \(index)",
                date: sessionStart.addingTimeInterval(TimeInterval(index) * -86_400),
                duration: 45 * 60,
                steps: 3_200,
                floors: 200,
                heartRateTimeSeries: heartRateSeries(count: heartRateSamples),
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

    private static func heartRateSeries(count: Int) -> [HeartRateDataPoint]? {
        guard count > 0 else { return nil }

        return (0..<count).map { second in
            HeartRateDataPoint(
                timestamp: sessionStart.addingTimeInterval(TimeInterval(second)),
                heartRate: 120 + (second % 60)
            )
        }
    }

    private static func timeFullScan(of store: SeededStore) -> Duration {
        fastestOf(measurementRuns) {
            _ = try store.freshContext().fetch(
                FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date, order: .forward)])
            ).map(\.id)
        }
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let components = duration.components
        let value = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f", value)
    }

    /// The fastest of `runs`. Noise only ever adds time, so the minimum is the honest estimate of
    /// what the query costs and the statistic least sensitive to a busy runner.
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
