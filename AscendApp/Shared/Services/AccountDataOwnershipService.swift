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
    /// Stored row counts for every model that holds user records, keyed by model type name.
    ///
    /// Schema-driven rather than a fixed set of named counters, so a model added later is counted
    /// here by default. The named-counter version knew only eight of the twelve models in the
    /// container, which is a gate that answers "no local data on this device" while another
    /// account's records are sitting on it (#348).
    ///
    /// `AscendLocalStore.derivedCacheModels` are the one thing left out, and only here: a
    /// recomputable row is nobody's data, and blocking on one would lock a legitimate account
    /// switch out of a device that holds no records at all. Deletion still sweeps them.
    let rowCountsByModelName: [String: Int]

    var hasLocalData: Bool {
        rowCountsByModelName.values.contains { $0 > 0 }
    }

    func rowCount(of model: any PersistentModel.Type) -> Int {
        rowCountsByModelName[String(describing: model)] ?? 0
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

    /// The owner ids the store can actually prove, which is only the models that carry one.
    ///
    /// Deliberately not schema-driven: there is no owner column to read on a `ClimbAttempt` or a
    /// cache entry, so this list can only grow when a model gains one. What protects the device
    /// against a model with no owner column is `summary.hasLocalData`, which covers every model
    /// holding user records - an unowned leftover blocks the remembered-owner mismatch even though
    /// it can never name its owner here.
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
        var rowCountsByModelName: [String: Int] = [:]

        for model in AscendLocalStore.userRecordModels {
            rowCountsByModelName[String(describing: model)] = try model.storedCount(in: modelContext)
        }

        return AccountDataOwnershipSummary(rowCountsByModelName: rowCountsByModelName)
    }

    private static func normalizedOwnerId(_ ownerId: String?) -> String? {
        guard let ownerId else { return nil }
        let trimmed = ownerId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
