import Foundation
import SwiftData

struct AccountDataOwnershipConflict: Equatable {
    let signedInUserId: String
    let rememberedOwnerUserId: String?
    let storedOwnerUserIds: [String]
    let summary: AccountDataOwnershipSummary

    var hasLocalData: Bool {
        summary.hasLocalData
    }
}

struct AccountDataOwnershipSummary: Equatable {
    let workoutCount: Int
    let pendingDeletionCount: Int
    let leaderboardStatsCount: Int
    let routineCount: Int
    let routineFolderCount: Int
    let climbAttemptCount: Int
    let pendingMediaUploadCount: Int
    let bestEffortCacheEntryCount: Int

    var hasLocalData: Bool {
        [
            workoutCount,
            pendingDeletionCount,
            leaderboardStatsCount,
            routineCount,
            routineFolderCount,
            climbAttemptCount,
            pendingMediaUploadCount,
            bestEffortCacheEntryCount
        ].contains { $0 > 0 }
    }
}

enum AccountDataOwnershipDecision: Equatable {
    case allowed
    case blocked(AccountDataOwnershipConflict)
}

@MainActor
enum AccountDataOwnershipService {
    static func evaluateAccess(
        modelContext: ModelContext,
        signedInUserId: String,
        sessionStore: AccountSessionStore = .shared
    ) throws -> AccountDataOwnershipDecision {
        let normalizedSignedInUserId = signedInUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSignedInUserId.isEmpty else {
            return .blocked(
                AccountDataOwnershipConflict(
                    signedInUserId: signedInUserId,
                    rememberedOwnerUserId: sessionStore.localDataOwnerUserId,
                    storedOwnerUserIds: [],
                    summary: try summary(modelContext: modelContext)
                )
            )
        }

        let rememberedOwnerUserId = sessionStore.localDataOwnerUserId
        let storedOwnerUserIds = try storedOwnerUserIds(modelContext: modelContext)
        let summary = try summary(modelContext: modelContext)

        if summary.hasLocalData,
           let rememberedOwnerUserId,
           rememberedOwnerUserId != normalizedSignedInUserId {
            return .blocked(
                AccountDataOwnershipConflict(
                    signedInUserId: normalizedSignedInUserId,
                    rememberedOwnerUserId: rememberedOwnerUserId,
                    storedOwnerUserIds: storedOwnerUserIds,
                    summary: summary
                )
            )
        }

        let foreignOwnerIds = storedOwnerUserIds.filter { $0 != normalizedSignedInUserId }
        guard foreignOwnerIds.isEmpty else {
            return .blocked(
                AccountDataOwnershipConflict(
                    signedInUserId: normalizedSignedInUserId,
                    rememberedOwnerUserId: rememberedOwnerUserId,
                    storedOwnerUserIds: storedOwnerUserIds,
                    summary: summary
                )
            )
        }

        return .allowed
    }

    static func recordAuthorizedOwner(
        signedInUserId: String,
        sessionStore: AccountSessionStore = .shared
    ) {
        sessionStore.recordLocalDataOwner(userId: signedInUserId)
    }

    private static func storedOwnerUserIds(modelContext: ModelContext) throws -> [String] {
        var ownerIds = Set<String>()

        let workouts = try modelContext.fetch(FetchDescriptor<Workout>())
        ownerIds.formUnion(workouts.compactMap { normalizedOwnerId($0.ownerUserId) })

        let pendingDeletions = try modelContext.fetch(FetchDescriptor<PendingWorkoutDeletion>())
        ownerIds.formUnion(pendingDeletions.compactMap { normalizedOwnerId($0.ownerUserId) })

        let leaderboardStats = try modelContext.fetch(FetchDescriptor<LeaderboardStats>())
        ownerIds.formUnion(leaderboardStats.compactMap { normalizedOwnerId($0.userId) })

        return ownerIds.sorted()
    }

    private static func summary(modelContext: ModelContext) throws -> AccountDataOwnershipSummary {
        AccountDataOwnershipSummary(
            workoutCount: try modelContext.fetchCount(FetchDescriptor<Workout>()),
            pendingDeletionCount: try modelContext.fetchCount(FetchDescriptor<PendingWorkoutDeletion>()),
            leaderboardStatsCount: try modelContext.fetchCount(FetchDescriptor<LeaderboardStats>()),
            routineCount: try modelContext.fetchCount(FetchDescriptor<Routine>()),
            routineFolderCount: try modelContext.fetchCount(FetchDescriptor<RoutineFolder>()),
            climbAttemptCount: try modelContext.fetchCount(FetchDescriptor<ClimbAttempt>()),
            pendingMediaUploadCount: try modelContext.fetchCount(FetchDescriptor<PendingMediaUpload>()),
            bestEffortCacheEntryCount: try modelContext.fetchCount(FetchDescriptor<BestEffortCacheEntry>())
        )
    }

    private static func normalizedOwnerId(_ ownerId: String?) -> String? {
        guard let ownerId else { return nil }
        let trimmed = ownerId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
