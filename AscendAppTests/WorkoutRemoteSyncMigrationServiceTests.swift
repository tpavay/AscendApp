import Foundation
import SwiftData
import Testing
@testable import AscendApp

struct WorkoutRemoteSyncMigrationServiceTests {
    @Test
    func newWorkoutsDefaultToPendingRemoteSync() {
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 10, hour: 6))

        #expect(workout.ownerUserId == nil)
        #expect(workout.remoteSyncStatus == .pendingUpsert)
        #expect(workout.lastRemoteSyncAt == nil)
        #expect(workout.lastRemoteSyncError == nil)
        #expect(abs(workout.lastModifiedAt.timeIntervalSince(workout.createdAt)) < 1)
    }

    @Test
    func migrationAssignsLegacyWorkoutsToSignedInUser() throws {
        let modelContext = try makeModelContext()
        let workoutDate = makeDate(year: 2026, month: 4, day: 10, hour: 6)
        let workout = makeWorkout(date: workoutDate)
        workout.remoteSyncStatusRawValue = "unknown"
        modelContext.insert(workout)
        try modelContext.save()

        let suiteName = "WorkoutRemoteSyncMigrationServiceTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))

        try WorkoutRemoteSyncMigrationService.runIfNeeded(
            modelContext: modelContext,
            currentUserId: "user-123",
            userDefaults: userDefaults
        )

        let migratedWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(migratedWorkout.ownerUserId == "user-123")
        #expect(migratedWorkout.remoteSyncStatus == .pendingUpsert)
        #expect(migratedWorkout.lastRemoteSyncError == nil)
        #expect(migratedWorkout.lastModifiedAt == max(migratedWorkout.createdAt, workoutDate))
        #expect(
            userDefaults.bool(
                forKey: WorkoutRemoteSyncMigrationService.migrationVersionKey(for: "user-123")
            )
        )

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func migrationDoesNotReassignOwnedWorkouts() throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 10, hour: 6))
        let syncedAt = makeDate(year: 2026, month: 4, day: 12, hour: 9)
        workout.ownerUserId = "existing-owner"
        workout.remoteSyncStatus = .synced
        workout.lastRemoteSyncAt = syncedAt
        modelContext.insert(workout)
        try modelContext.save()

        let suiteName = "WorkoutRemoteSyncMigrationServiceTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))

        try WorkoutRemoteSyncMigrationService.runIfNeeded(
            modelContext: modelContext,
            currentUserId: "new-owner",
            userDefaults: userDefaults
        )

        let migratedWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(migratedWorkout.ownerUserId == "existing-owner")
        #expect(migratedWorkout.remoteSyncStatus == .synced)
        #expect(migratedWorkout.lastRemoteSyncAt == syncedAt)

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    @MainActor
    func mutationHandlerMarksChangedWorkoutsForRemoteSync() {
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 10, hour: 6))
        let modifiedAt = makeDate(year: 2026, month: 4, day: 13, hour: 8)
        workout.remoteSyncStatus = .failed
        workout.lastRemoteSyncError = "timed out"

        WorkoutMutationHandler.shared.markChangedWorkoutsForRemoteSync(
            [workout],
            userId: "user-123",
            modifiedAt: modifiedAt
        )

        #expect(workout.ownerUserId == "user-123")
        #expect(workout.remoteSyncStatus == .pendingUpsert)
        #expect(workout.lastRemoteSyncError == nil)
        #expect(workout.lastModifiedAt == modifiedAt)
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            PendingWorkoutDeletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func fetchWorkouts(in modelContext: ModelContext) throws -> [Workout] {
        try modelContext.fetch(FetchDescriptor<Workout>())
    }

    private func makeWorkout(date: Date) -> Workout {
        Workout(
            name: "Workout",
            date: date,
            duration: 1_800,
            steps: 1_000,
            floors: 63,
            stepsPerFloor: 16,
            source: .manual
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
