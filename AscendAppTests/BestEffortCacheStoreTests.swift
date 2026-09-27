import Foundation
import SwiftData
import Testing
@testable import AscendApp

struct BestEffortCacheStoreTests {
    @Test
    @MainActor
    func rebuildPersistsPrimaryEffortLookup() throws {
        let modelContext = try makeModelContext()
        let referenceDate = makeDate(year: 2026, month: 5, day: 10)
        let fastWorkout = makeWorkout(
            name: "Fast Climb",
            date: referenceDate,
            duration: 600,
            steps: 1_800
        )
        let longWorkout = makeWorkout(
            name: "Long Climb",
            date: makeDate(year: 2025, month: 3, day: 1),
            duration: 3_600,
            steps: 3_000
        )

        modelContext.insert(fastWorkout)
        modelContext.insert(longWorkout)
        try modelContext.save()

        try BestEffortCacheStore.rebuild(
            modelContext: modelContext,
            referenceDate: referenceDate
        )

        let workouts = try fetchWorkouts(in: modelContext)
        let entries = try fetchCacheEntries(in: modelContext)
        let snapshot = BestEffortCacheSnapshot(entries: entries, workouts: workouts)
        let cachedPrimary = try #require(snapshot.primaryEffort(for: fastWorkout))
        let builderPrimary = try #require(BestEffortRankingBuilder.primaryEffort(
            for: fastWorkout,
            from: workouts,
            referenceDate: referenceDate
        ))

        #expect(cachedPrimary.id == builderPrimary.id)
        #expect(cachedPrimary.sentence == "Highest average SPM ever")
    }

    @Test
    @MainActor
    func rebuildPersistsRecordProgression() throws {
        let modelContext = try makeModelContext()
        let referenceDate = makeDate(year: 2026, month: 5, day: 10)
        let workouts = [
            makeWorkout(
                name: "First Record",
                date: makeDate(year: 2026, month: 1, day: 1),
                duration: 1_200,
                steps: 1_000
            ),
            makeWorkout(
                name: "Second Record",
                date: makeDate(year: 2026, month: 2, day: 1),
                duration: 1_200,
                steps: 1_500
            ),
            makeWorkout(
                name: "Not A Record",
                date: makeDate(year: 2026, month: 3, day: 1),
                duration: 1_200,
                steps: 1_300
            )
        ]

        for workout in workouts {
            modelContext.insert(workout)
        }
        try modelContext.save()

        try BestEffortCacheStore.rebuild(
            modelContext: modelContext,
            referenceDate: referenceDate
        )

        let fetchedWorkouts = try fetchWorkouts(in: modelContext)
        let entries = try fetchCacheEntries(in: modelContext)
        let snapshot = BestEffortCacheSnapshot(entries: entries, workouts: fetchedWorkouts)
        let cachedProgression = snapshot.recordProgression(
            for: .mostSteps,
            scope: .allTime,
            context: .all
        )
        let builderProgression = BestEffortRankingBuilder.recordProgression(
            for: .mostSteps,
            from: fetchedWorkouts,
            scope: .allTime,
            context: .all,
            referenceDate: referenceDate
        )

        #expect(cachedProgression.map(\.workout.id) == builderProgression.map(\.workout.id))
        #expect(cachedProgression.map(\.compactValueText) == ["1,000", "1,500"])
    }

    @Test
    @MainActor
    func rebuildWithUserIdIgnoresOtherUsersWorkouts() throws {
        let modelContext = try makeModelContext()
        let referenceDate = makeDate(year: 2026, month: 5, day: 10)
        let ownedWorkout = makeWorkout(
            name: "Owned Record",
            date: referenceDate,
            duration: 600,
            steps: 1_000,
            ownerUserId: "user-1"
        )
        let foreignWorkout = makeWorkout(
            name: "Foreign Record",
            date: referenceDate,
            duration: 600,
            steps: 4_000,
            ownerUserId: "user-2"
        )

        modelContext.insert(ownedWorkout)
        modelContext.insert(foreignWorkout)
        try modelContext.save()

        try BestEffortCacheStore.rebuild(
            modelContext: modelContext,
            userId: "user-1",
            referenceDate: referenceDate
        )

        let snapshot = BestEffortCacheSnapshot(
            entries: try fetchCacheEntries(in: modelContext),
            workouts: try fetchWorkouts(in: modelContext)
        )

        #expect(snapshot.primaryEffort(for: ownedWorkout) != nil)
        #expect(snapshot.primaryEffort(for: foreignWorkout) == nil)
    }

    @Test
    @MainActor
    func rebuildIfNeededDiscardsCacheWrittenByAnOlderVersion() throws {
        let modelContext = try makeModelContext()
        let referenceDate = makeDate(year: 2026, month: 5, day: 10)
        let workout = makeWorkout(
            name: "Owned Record",
            date: referenceDate,
            duration: 600,
            steps: 1_000
        )

        modelContext.insert(workout)
        try modelContext.save()

        try BestEffortCacheStore.rebuild(
            modelContext: modelContext,
            referenceDate: referenceDate
        )

        // An install that cached its efforts before the split-curve fix.
        let staleMetadata = try #require(try fetchCacheMetadata(in: modelContext))
        staleMetadata.cacheVersion = BestEffortCacheStore.currentVersion - 1
        for entry in try fetchCacheEntries(in: modelContext) {
            entry.cacheVersion = BestEffortCacheStore.currentVersion - 1
        }
        try modelContext.save()

        try BestEffortCacheStore.rebuildIfNeeded(
            modelContext: modelContext,
            referenceDate: referenceDate
        )

        let refreshedMetadata = try #require(try fetchCacheMetadata(in: modelContext))
        let refreshedEntries = try fetchCacheEntries(in: modelContext)

        #expect(refreshedMetadata.cacheVersion == BestEffortCacheStore.currentVersion)
        #expect(!refreshedEntries.isEmpty)
        #expect(refreshedEntries.allSatisfy { $0.cacheVersion == BestEffortCacheStore.currentVersion })
    }

    @Test
    @MainActor
    func rebuildIfNeededReplacesEffortsCachedFromAClampedCurve() throws {
        let modelContext = try makeModelContext()
        let referenceDate = makeDate(year: 2026, month: 9, day: 20)
        let workout = try makePreFixSamplerWorkout(date: referenceDate)

        modelContext.insert(workout)
        try modelContext.save()

        try BestEffortCacheStore.rebuild(
            modelContext: modelContext,
            referenceDate: referenceDate
        )
        let repairedValues = try fetchCacheEntries(in: modelContext).map { [$0.id: $0.value] }

        // What a v2 install cached for this climb: timeline efforts read off the clamped tail,
        // which put the whole last half hour inside the 50:00-1:00:00 bucket.
        let staleMetadata = try #require(try fetchCacheMetadata(in: modelContext))
        staleMetadata.cacheVersion = 2
        for entry in try fetchCacheEntries(in: modelContext) {
            entry.cacheVersion = 2
            entry.value = -1
        }
        try modelContext.save()

        try BestEffortCacheStore.rebuildIfNeeded(
            modelContext: modelContext,
            referenceDate: referenceDate
        )

        let refreshed = try fetchCacheEntries(in: modelContext)
        #expect(!refreshed.isEmpty)
        #expect(refreshed.map { [$0.id: $0.value] } == repairedValues)
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func fetchWorkouts(in modelContext: ModelContext) throws -> [Workout] {
        try modelContext.fetch(
            FetchDescriptor<Workout>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )
    }

    private func fetchCacheEntries(in modelContext: ModelContext) throws -> [BestEffortCacheEntry] {
        try modelContext.fetch(
            FetchDescriptor<BestEffortCacheEntry>(
                sortBy: [SortDescriptor(\.sortKey)]
            )
        )
    }

    private func fetchCacheMetadata(in modelContext: ModelContext) throws -> BestEffortCacheMetadata? {
        try modelContext.fetch(FetchDescriptor<BestEffortCacheMetadata>()).first
    }

    private func makeWorkout(
        name: String,
        date: Date,
        duration: TimeInterval,
        steps: Int,
        ownerUserId: String? = nil
    ) -> Workout {
        let workout = Workout(
            name: name,
            date: date,
            duration: duration,
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .manual
        )
        if let ownerUserId {
            workout.markPendingRemoteUpsert(ownerUserId: ownerUserId, modifiedAt: date)
        }
        return workout
    }

    /// The captain's 1:30:07 climb exactly as the pre-fix sampler stored it.
    private func makePreFixSamplerWorkout(date: Date) throws -> Workout {
        struct Climbs: Decodable {
            struct Climb: Decodable {
                let name: String
                let steps: Int
                let durationSeconds: Double
                let splitIntervalSeconds: Int
                let splitSteps: [Int]
            }
            let climbs: [Climb]
        }

        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: repoRoot.appending(path: "SharedTestVectors/pre-fix-sampler-long-climbs.json")
        )
        let climb = try #require(
            try JSONDecoder().decode(Climbs.self, from: data).climbs
                .first { $0.name == "steady-84-spm-1h30m" }
        )
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: climb.splitSteps.count,
            trackingMode: .justClimb,
            climbId: nil,
            targetStepCount: nil,
            stopReason: .userStopped,
            splitCurve: LiveReplaySplitCurve(
                intervalSeconds: climb.splitIntervalSeconds,
                steps: climb.splitSteps
            )
        )

        return Workout(
            name: "Just Climb",
            date: date,
            duration: climb.durationSeconds,
            steps: climb.steps,
            floors: Workout.stepsToFloors(climb.steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date ?? Date()
    }
}
