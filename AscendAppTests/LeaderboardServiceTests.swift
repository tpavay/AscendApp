import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct LeaderboardServiceTests {
    @Test
    func incrementalMutationsUpdateCurrentPeriodsAndZeroOutDeletes() throws {
        let referenceDate = utcDate(year: 2026, month: 4, day: 10, hour: 12)
        let userId = "user-1"
        let service = LeaderboardService.shared
        let modelContext = try makeModelContext()
        service.configure(modelContext: modelContext)

        let originalWorkout = makeWorkout(
            date: utcDate(year: 2026, month: 4, day: 8, hour: 7),
            duration: 1_800,
            steps: 900,
            floors: 60,
            ownerUserId: userId
        )
        modelContext.insert(originalWorkout)
        try modelContext.save()

        try service.rebuildCurrentStats(for: userId, workouts: [originalWorkout], referenceDate: referenceDate)

        var statsByTimeFrame = try fetchStats(for: userId, in: modelContext)
        #expect(statsByTimeFrame.count == LeaderboardTimeFrame.allCases.count)
        #expect(statsByTimeFrame[.daily]?.totalSteps == 0)
        #expect(statsByTimeFrame[.daily]?.periodStartAt == utcDate(year: 2026, month: 4, day: 10))
        #expect(statsByTimeFrame[.weekly]?.totalSteps == 900)
        #expect(statsByTimeFrame[.weekly]?.periodStartAt == utcDate(year: 2026, month: 4, day: 6))
        #expect(statsByTimeFrame[.monthly]?.totalSteps == 900)
        #expect(statsByTimeFrame[.yearly]?.totalSteps == 900)
        #expect(statsByTimeFrame[.allTime]?.totalSteps == 900)

        let movedSnapshot = LeaderboardWorkoutSnapshot(
            id: originalWorkout.id,
            date: utcDate(year: 2026, month: 4, day: 4, hour: 7),
            duration: 1_800,
            steps: 900,
            floors: 60
        )

        let movedImpact = LeaderboardMutationImpact.classify(
            .updated(before: LeaderboardWorkoutSnapshot(workout: originalWorkout), after: movedSnapshot)
        )
        let movedTouchedStats = try service.applyMutationImpact(
            movedImpact,
            for: userId,
            referenceDate: referenceDate
        )

        #expect(movedTouchedStats)

        statsByTimeFrame = try fetchStats(for: userId, in: modelContext)
        #expect(statsByTimeFrame[.daily]?.totalSteps == 0)
        #expect(statsByTimeFrame[.weekly]?.totalSteps == 0)
        #expect(statsByTimeFrame[.weekly]?.totalWorkouts == 0)
        #expect(statsByTimeFrame[.weekly]?.hasActivity == false)
        #expect(statsByTimeFrame[.monthly]?.totalSteps == 900)
        #expect(statsByTimeFrame[.yearly]?.totalSteps == 900)
        #expect(statsByTimeFrame[.allTime]?.totalSteps == 900)

        let deleteImpact = LeaderboardMutationImpact.classify(.deleted([movedSnapshot]))
        let deletedTouchedStats = try service.applyMutationImpact(
            deleteImpact,
            for: userId,
            referenceDate: referenceDate
        )

        #expect(deletedTouchedStats)

        statsByTimeFrame = try fetchStats(for: userId, in: modelContext)
        for timeFrame in LeaderboardTimeFrame.allCases {
            let stats = try #require(statsByTimeFrame[timeFrame])
            #expect(stats.totalSteps == 0)
            #expect(stats.totalFloors == 0)
            #expect(stats.totalWorkouts == 0)
            #expect(stats.totalDuration == 0)
            #expect(stats.stepsPerMinute == 0)
            #expect(stats.needsSync)
        }
    }

    @Test
    func rebuildCurrentStatsIgnoresWorkoutsOwnedByOtherUsers() throws {
        let referenceDate = utcDate(year: 2026, month: 4, day: 10, hour: 12)
        let userId = "user-1"
        let service = LeaderboardService.shared
        let modelContext = try makeModelContext()
        service.configure(modelContext: modelContext)

        let ownedWorkout = makeWorkout(
            date: utcDate(year: 2026, month: 4, day: 8, hour: 7),
            duration: 1_800,
            steps: 900,
            floors: 60,
            ownerUserId: userId
        )
        let foreignWorkout = makeWorkout(
            date: utcDate(year: 2026, month: 4, day: 8, hour: 8),
            duration: 1_800,
            steps: 2_000,
            floors: 125,
            ownerUserId: "user-2"
        )

        modelContext.insert(ownedWorkout)
        modelContext.insert(foreignWorkout)
        try modelContext.save()

        try service.rebuildCurrentStats(
            for: userId,
            workouts: [ownedWorkout, foreignWorkout],
            referenceDate: referenceDate
        )

        let statsByTimeFrame = try fetchStats(for: userId, in: modelContext)
        #expect(statsByTimeFrame[.weekly]?.totalSteps == 900)
        #expect(statsByTimeFrame[.weekly]?.totalWorkouts == 1)
        #expect(statsByTimeFrame[.allTime]?.totalSteps == 900)
    }

    @Test
    func prepareSyncPayloadsSkipsNeverSyncedZeroActivityStats() throws {
        let referenceDate = utcDate(year: 2026, month: 4, day: 10, hour: 12)
        let userId = "user-1"
        let service = LeaderboardService.shared
        let modelContext = try makeModelContext()
        service.configure(modelContext: modelContext)
        let period = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: referenceDate)
        let emptyStats = LeaderboardStats(userId: userId, timeFrame: .weekly, period: period)
        modelContext.insert(emptyStats)
        try modelContext.save()

        let payloads = try service.prepareSyncPayloads(userId: userId)

        #expect(payloads.isEmpty)
        #expect(emptyStats.needsSync == false)
    }

    @Test
    func prepareSyncPayloadsKeepsDeleteForPreviouslySyncedZeroActivityStats() throws {
        let referenceDate = utcDate(year: 2026, month: 4, day: 10, hour: 12)
        let userId = "user-1"
        let service = LeaderboardService.shared
        let modelContext = try makeModelContext()
        service.configure(modelContext: modelContext)
        let period = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: referenceDate)
        let emptyStats = LeaderboardStats(userId: userId, timeFrame: .weekly, period: period)
        emptyStats.lastSyncedToFirestore = referenceDate.addingTimeInterval(-60)
        modelContext.insert(emptyStats)
        try modelContext.save()

        let payloads = try service.prepareSyncPayloads(userId: userId)

        #expect(payloads.count == 1)
        #expect(payloads.first?.operation == .delete)
        #expect(emptyStats.needsSync)
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            LeaderboardStats.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func fetchStats(for userId: String, in modelContext: ModelContext) throws -> [LeaderboardTimeFrame: LeaderboardStats] {
        let predicate = #Predicate<LeaderboardStats> { stats in
            stats.userId == userId
        }
        let stats = try modelContext.fetch(FetchDescriptor<LeaderboardStats>(predicate: predicate))
        return Dictionary(uniqueKeysWithValues: stats.compactMap { stat in
            guard let timeFrame = LeaderboardTimeFrame(rawValue: stat.timeFrame) else { return nil }
            return (timeFrame, stat)
        })
    }

    private func makeWorkout(
        date: Date,
        duration: TimeInterval,
        steps: Int,
        floors: Int,
        ownerUserId: String? = nil
    ) -> Workout {
        let workout = Workout(
            name: "Workout",
            date: date,
            duration: duration,
            steps: steps,
            floors: floors,
            stepsPerFloor: 16,
            source: .manual
        )
        if let ownerUserId {
            workout.markPendingRemoteUpsert(ownerUserId: ownerUserId, modifiedAt: date)
        }
        return workout
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = WeekConfiguration.calendar(timeZone: LeaderboardTimeFrame.canonicalTimeZone)
        components.timeZone = LeaderboardTimeFrame.canonicalTimeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
