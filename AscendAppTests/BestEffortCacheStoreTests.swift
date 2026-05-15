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

    private func makeWorkout(
        name: String,
        date: Date,
        duration: TimeInterval,
        steps: Int
    ) -> Workout {
        Workout(
            name: name,
            date: date,
            duration: duration,
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .manual
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
