import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct AccountDataOwnershipServiceTests {
    @Test
    func blocksRememberedOwnerMismatchWhenLocalDataExists() throws {
        let modelContext = try makeModelContext()
        let defaults = try makeUserDefaults()
        let sessionStore = AccountSessionStore(userDefaults: defaults)
        sessionStore.recordLocalDataOwner(userId: "user-a")

        modelContext.insert(Routine(name: "Local Routine"))
        try modelContext.save()

        let decision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: modelContext,
            signedInUserId: "user-b",
            sessionStore: sessionStore
        )

        guard case .blocked(let conflict) = decision else {
            Issue.record("Expected account data ownership to block a remembered owner mismatch.")
            return
        }

        #expect(conflict.rememberedOwnerUserId == "user-a")
        #expect(conflict.summary.routineCount == 1)
    }

    @Test
    func allowsRememberedOwnerMismatchWhenLocalStoreIsEmpty() throws {
        let modelContext = try makeModelContext()
        let defaults = try makeUserDefaults()
        let sessionStore = AccountSessionStore(userDefaults: defaults)
        sessionStore.recordLocalDataOwner(userId: "user-a")

        let decision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: modelContext,
            signedInUserId: "user-b",
            sessionStore: sessionStore
        )

        #expect(decision == .allowed)
    }

    @Test
    func blocksStoredOwnerMismatch() throws {
        let modelContext = try makeModelContext()
        let defaults = try makeUserDefaults()
        let sessionStore = AccountSessionStore(userDefaults: defaults)
        let workout = Workout(duration: 1_200, steps: 1_000, floors: 63)
        workout.markPendingRemoteUpsert(ownerUserId: "user-a")
        modelContext.insert(workout)
        try modelContext.save()

        let decision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: modelContext,
            signedInUserId: "user-b",
            sessionStore: sessionStore
        )

        guard case .blocked(let conflict) = decision else {
            Issue.record("Expected account data ownership to block stored owner mismatch.")
            return
        }

        #expect(conflict.storedOwnerUserIds == ["user-a"])
        #expect(conflict.summary.workoutCount == 1)
    }

    @Test
    func allowsLegacyOwnerlessDataForFirstPostUpgradeSignIn() throws {
        let modelContext = try makeModelContext()
        let defaults = try makeUserDefaults()
        let sessionStore = AccountSessionStore(userDefaults: defaults)
        modelContext.insert(Workout(duration: 1_200, steps: 1_000, floors: 63))
        try modelContext.save()

        let decision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: modelContext,
            signedInUserId: "user-a",
            sessionStore: sessionStore
        )

        #expect(decision == .allowed)
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            PendingWorkoutDeletion.self,
            LeaderboardStats.self,
            Routine.self,
            RoutineFolder.self,
            ClimbAttempt.self,
            PendingMediaUpload.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "AccountDataOwnershipServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
