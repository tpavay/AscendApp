import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct HomeDashboardViewModelTests {
    @Test
    func refreshLocalDataComputesHomeSummariesFromStoredData() throws {
        let modelContext = try makeModelContext()
        let referenceDate = utcDate(year: 2026, month: 5, day: 20, hour: 12)

        modelContext.insert(makeWorkout(date: referenceDate.addingTimeInterval(-1 * day), duration: 1_800, steps: 1_000))
        modelContext.insert(makeWorkout(date: referenceDate.addingTimeInterval(-6 * day), duration: 3_600, steps: 2_000))
        modelContext.insert(makeWorkout(date: referenceDate.addingTimeInterval(-8 * day), duration: 7_200, steps: 10_000))

        modelContext.insert(ClimbAttempt(climbId: "empire-state-building", status: .completed))
        modelContext.insert(ClimbAttempt(climbId: "empire-state-building", status: .completed))
        modelContext.insert(ClimbAttempt(climbId: "burj-khalifa", status: .completed))
        modelContext.insert(ClimbAttempt(climbId: "mount-etna", status: .failed))
        try modelContext.save()

        // The array Home's `@Query` holds, newest first, handed in rather than fetched
        // again inside the refresh.
        let workouts = try modelContext.fetch(
            FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )

        let viewModel = HomeDashboardViewModel()
        viewModel.refreshLocalData(modelContext: modelContext, workouts: workouts, referenceDate: referenceDate)

        #expect(viewModel.completedClimbCount == 2)
        #expect(viewModel.workoutCount == 3)
        // 2026-05-20 is a Wednesday, so the Monday week holds only the climb one day
        // back; the climbs six and eight days back belong to the week before.
        #expect(viewModel.weekSummary?.weekWorkoutCount == 1)
        #expect(viewModel.weekSummary?.weekTotalValue == 1_000)
        #expect(viewModel.currentStreakWeeks == Workout.calculateWeeklyStreak(from: workouts))
    }

    @Test
    func refreshLocalDataDerivesTheWeekAndStreakFromTheArrayItIsGiven() throws {
        let modelContext = try makeModelContext()
        let referenceDate = utcDate(year: 2026, month: 5, day: 20, hour: 12)
        modelContext.insert(makeWorkout(date: referenceDate.addingTimeInterval(-1 * day), duration: 1_800, steps: 1_000))
        try modelContext.save()

        let viewModel = HomeDashboardViewModel()
        viewModel.refreshLocalData(modelContext: modelContext, workouts: [], referenceDate: referenceDate)

        // The store holds a climb, but the refresh reads only what it was handed.
        #expect(viewModel.workoutCount == 1)
        #expect(viewModel.weekSummary?.weekWorkoutCount == 0)
        #expect(viewModel.weekSummary?.weekTotalValue == 0)
        #expect(viewModel.currentStreakWeeks == 0)
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            LeaderboardStats.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeWorkout(date: Date, duration: TimeInterval, steps: Int) -> Workout {
        Workout(
            name: "Workout",
            date: date,
            duration: duration,
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .manual
        )
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }

    private var day: TimeInterval {
        24 * 60 * 60
    }
}
