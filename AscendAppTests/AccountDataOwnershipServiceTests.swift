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
        #expect(conflict.summary.rowCount(of: Routine.self) == 1)
    }

    @Test("Counts every model in the live schema as local data", .bug(id: 348))
    func blocksARememberedOwnerMismatchForAnyModelInTheLiveSchema() throws {
        let modelContext = try AscendLocalStoreFixture.makeModelContext()
        let defaults = try makeUserDefaults()
        let sessionStore = AccountSessionStore(userDefaults: defaults)
        sessionStore.recordLocalDataOwner(userId: "user-a")

        // An in-progress session draft was in the container and outside the gate's fixed list of
        // counters, so on its own it read as an empty device (#348).
        modelContext.insert(
            ActiveHeadphoneWorkoutDraft(
                sessionID: "user-a-session",
                kind: .justClimb,
                title: "Session",
                subtitle: "In progress",
                workoutName: "Session",
                targetStepCount: nil,
                targetDurationSeconds: nil
            )
        )
        try modelContext.save()

        let decision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: modelContext,
            signedInUserId: "user-b",
            sessionStore: sessionStore
        )

        guard case .blocked(let conflict) = decision else {
            Issue.record("Expected leftover data in any live model to block a different account.")
            return
        }

        #expect(conflict.summary.rowCount(of: ActiveHeadphoneWorkoutDraft.self) == 1)
    }

    @Test("Lets a different account sign in over a derived Best Effort cache", .bug(id: 348))
    func allowsRememberedOwnerMismatchWhenOnlyDerivedCacheRowsRemain() throws {
        let modelContext = try makeModelContext()
        let defaults = try makeUserDefaults()
        let sessionStore = AccountSessionStore(userDefaults: defaults)
        sessionStore.recordLocalDataOwner(userId: "user-a")

        // What every entitled climber writes on their first trip to the main tab, workouts logged
        // or not. Blocking on a row Ascend generated itself would make the gate an unrecoverable
        // lockout - the conflict screen's only action is Sign Out.
        try BestEffortCacheStore.rebuildIfNeeded(modelContext: modelContext)
        #expect(try modelContext.fetchCount(FetchDescriptor<BestEffortCacheMetadata>()) == 1)

        let decision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: modelContext,
            signedInUserId: "user-b",
            sessionStore: sessionStore
        )

        #expect(decision == .allowed)
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
        #expect(conflict.summary.rowCount(of: Workout.self) == 1)
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
        try AscendLocalStoreFixture.makeModelContext()
    }

    private func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "AccountDataOwnershipServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
