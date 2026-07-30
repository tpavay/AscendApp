import Foundation
import Observation

@MainActor
@Observable
final class ModerationStore {
    static let shared = ModerationStore()

    private(set) var blockedClimbers: [BlockedClimber] = []
    private(set) var isBlockListHydrated = false
    private(set) var isHydrating = false
    private(set) var hydrationErrorMessage: String?

    private let repository: any ModerationRepositoryProtocol
    private var activeUserId: String?
    private var sessionGeneration: UInt64 = 0
    private var blocksAddedDuringHydration: [String: BlockedClimber] = [:]
    private var userIdsUnblockedDuringHydration: Set<String> = []

    init(repository: any ModerationRepositoryProtocol = ModerationRepository.shared) {
        self.repository = repository
    }

    var blockedUserIds: Set<String> {
        Set(blockedClimbers.map(\.userId))
    }

    func hydrate(for userId: String) async {
        sessionGeneration &+= 1
        let generation = sessionGeneration
        activeUserId = userId
        blockedClimbers = []
        blocksAddedDuringHydration = [:]
        userIdsUnblockedDuringHydration = []
        isBlockListHydrated = false
        isHydrating = true
        hydrationErrorMessage = nil
        defer {
            if isCurrentSession(userId: userId, generation: generation) {
                isHydrating = false
            }
        }

        do {
            let serverBlocks = try await repository.fetchBlockedClimbers(
                blockerUserId: userId
            )
            guard isCurrentSession(userId: userId, generation: generation) else {
                return
            }
            blockedClimbers = mergingHydrationResult(serverBlocks)
            blocksAddedDuringHydration = [:]
            userIdsUnblockedDuringHydration = []
            isBlockListHydrated = true
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSession(userId: userId, generation: generation) else {
                return
            }
            hydrationErrorMessage = "Couldn't load your blocked climbers. Try again."
        }
    }

    func clear() {
        sessionGeneration &+= 1
        activeUserId = nil
        blockedClimbers = []
        blocksAddedDuringHydration = [:]
        userIdsUnblockedDuringHydration = []
        isBlockListHydrated = false
        isHydrating = false
        hydrationErrorMessage = nil
    }

    func block(blockerUserId: String, blockedUserId: String) async throws {
        guard activeUserId == blockerUserId, blockerUserId != blockedUserId else {
            throw ModerationStoreError.invalidAccount
        }
        let generation = sessionGeneration

        let wasAlreadyBlocked = blockedUserIds.contains(blockedUserId)
        if !wasAlreadyBlocked {
            let optimisticBlock = BlockedClimber(
                userId: blockedUserId,
                createdAt: .now
            )
            blockedClimbers.insert(optimisticBlock, at: 0)
            if isHydrating {
                blocksAddedDuringHydration[blockedUserId] = optimisticBlock
                userIdsUnblockedDuringHydration.remove(blockedUserId)
            }
        }

        do {
            try await repository.block(
                blockerUserId: blockerUserId,
                blockedUserId: blockedUserId
            )
        } catch {
            if isCurrentSession(userId: blockerUserId, generation: generation),
               !wasAlreadyBlocked {
                blockedClimbers.removeAll { $0.userId == blockedUserId }
                blocksAddedDuringHydration[blockedUserId] = nil
            }
            throw error
        }

        guard activeUserId == blockerUserId else {
            return
        }
        guard sessionGeneration == generation else {
            await hydrate(for: blockerUserId)
            return
        }
        if !blockedUserIds.contains(blockedUserId) {
            let block = BlockedClimber(userId: blockedUserId, createdAt: .now)
            blockedClimbers.insert(block, at: 0)
            if isHydrating {
                blocksAddedDuringHydration[blockedUserId] = block
            }
        }
    }

    func unblock(blockerUserId: String, blockedUserId: String) async throws {
        guard activeUserId == blockerUserId else {
            throw ModerationStoreError.invalidAccount
        }
        let generation = sessionGeneration

        try await repository.unblock(
            blockerUserId: blockerUserId,
            blockedUserId: blockedUserId
        )
        guard activeUserId == blockerUserId else {
            return
        }
        guard sessionGeneration == generation else {
            await hydrate(for: blockerUserId)
            return
        }
        blockedClimbers.removeAll { $0.userId == blockedUserId }
        if isHydrating {
            blocksAddedDuringHydration[blockedUserId] = nil
            userIdsUnblockedDuringHydration.insert(blockedUserId)
        }
    }

    func report(
        reporterUserId: String,
        reportedUserId: String,
        reason: ModerationReportReason,
        source: ModerationSource
    ) async throws {
        guard activeUserId == reporterUserId, reporterUserId != reportedUserId else {
            throw ModerationStoreError.invalidAccount
        }

        try await repository.submitReport(
            reporterUserId: reporterUserId,
            reportedUserId: reportedUserId,
            reason: reason,
            source: source
        )
    }

    func moderate(
        _ identity: ProfileUserIdentity,
        isCurrentUser: Bool
    ) -> ResolvedUserIdentity {
        CrossUserIdentityAdapter.profileIdentity(
            identity,
            isCurrentUser: isCurrentUser,
            blockedUserIds: blockedUserIds,
            isBlockListHydrated: isBlockListHydrated
        )
    }

    func moderate(_ entry: LeaderboardEntry) -> ModeratedLeaderboardEntry {
        CrossUserIdentityAdapter.leaderboardEntry(
            entry,
            blockedUserIds: blockedUserIds,
            isBlockListHydrated: isBlockListHydrated
        )
    }

    func moderate(
        _ row: LiveReplayLeaderboardRow
    ) -> ModeratedReplayLeaderboardRow {
        CrossUserIdentityAdapter.replayRow(
            row,
            blockedUserIds: blockedUserIds,
            isBlockListHydrated: isBlockListHydrated
        )
    }

    func moderate(
        _ firstAscent: LiveReplayFirstAscent,
        currentUserId: String?
    ) -> ModeratedReplayFirstAscent {
        CrossUserIdentityAdapter.firstAscent(
            firstAscent,
            currentUserId: currentUserId,
            blockedUserIds: blockedUserIds,
            isBlockListHydrated: isBlockListHydrated
        )
    }

    private func mergingHydrationResult(
        _ serverBlocks: [BlockedClimber]
    ) -> [BlockedClimber] {
        var merged = serverBlocks.filter {
            !userIdsUnblockedDuringHydration.contains($0.userId)
        }
        let hydratedUserIds = Set(merged.map(\.userId))
        let newBlocks = blocksAddedDuringHydration.values
            .filter { !hydratedUserIds.contains($0.userId) }
            .sorted { $0.createdAt > $1.createdAt }
        merged.insert(
            contentsOf: newBlocks,
            at: 0
        )
        return merged
    }

    private func isCurrentSession(userId: String, generation: UInt64) -> Bool {
        activeUserId == userId && sessionGeneration == generation
    }
}
