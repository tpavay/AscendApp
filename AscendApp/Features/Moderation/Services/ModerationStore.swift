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
    private let serverSyncMarker: any BlockListServerSyncMarking
    private var activeUserId: String?
    private var sessionGeneration: UInt64 = 0
    private var blocksAddedDuringHydration: [String: BlockedClimber] = [:]
    private var userIdsUnblockedDuringHydration: Set<String> = []

    @ObservationIgnored
    private var leaderboardEntryMemo =
        ModeratedCollectionMemo<LeaderboardEntry, ModeratedLeaderboardEntry>()
    @ObservationIgnored
    private var replayRowMemo =
        ModeratedCollectionMemo<LiveReplayLeaderboardRow, ModeratedReplayLeaderboardRow>()

    init(
        repository: any ModerationRepositoryProtocol = ModerationRepository.shared,
        serverSyncMarker: any BlockListServerSyncMarking =
            UserDefaultsBlockListServerSyncMarker()
    ) {
        self.repository = repository
        self.serverSyncMarker = serverSyncMarker
    }

    var blockedUserIds: Set<String> {
        Set(blockedClimbers.map(\.userId))
    }

    /// Loads the block list from the server, refreshing an already-hydrated
    /// session in place.
    ///
    /// Only a user change (or `clear()`) re-arms `isBlockListHydrated`. Dropping
    /// back to un-hydrated on an ordinary refresh - which runs on every
    /// foreground - would re-mask every climber app-wide until the round trip
    /// finished, and would leave the app fully masked for the rest of the
    /// session whenever the refresh failed offline. A failed refresh keeps the
    /// last known good list instead of falling back to empty.
    ///
    /// A first hydration that cannot reach the server falls back to Firestore's
    /// local persistence, because a cold launch offline would otherwise mask
    /// every climber on a device that already knows this user's blocks. A
    /// refresh never falls back: the list already in memory is at least as
    /// fresh.
    ///
    /// An empty cache read is only trusted once `serverSyncMarker` says this
    /// account has synced here before, since an unsynced collection query
    /// returns an empty snapshot rather than an error. Without that proof the
    /// session stays un-hydrated and every cross-user identity stays masked.
    func hydrate(for userId: String) async {
        sessionGeneration &+= 1
        let generation = sessionGeneration
        let isUserChange = activeUserId != userId
        activeUserId = userId
        blocksAddedDuringHydration = [:]
        userIdsUnblockedDuringHydration = []
        if isUserChange {
            blockedClimbers = []
            isBlockListHydrated = false
        }
        isHydrating = true
        hydrationErrorMessage = nil
        defer {
            if isCurrentSession(userId: userId, generation: generation) {
                isHydrating = false
            }
        }

        do {
            let serverBlocks = try await repository.fetchBlockedClimbers(
                blockerUserId: userId,
                source: .server
            )
            serverSyncMarker.recordServerSync(userId: userId)
            guard isCurrentSession(userId: userId, generation: generation) else {
                return
            }
            applyHydrationResult(serverBlocks)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSession(userId: userId, generation: generation) else {
                return
            }
            guard !isBlockListHydrated else {
                hydrationErrorMessage = Self.hydrationFailureMessage
                return
            }
            await hydrateFromCache(for: userId, generation: generation)
        }
    }

    private func hydrateFromCache(for userId: String, generation: UInt64) async {
        do {
            let cachedBlocks = try await repository.fetchBlockedClimbers(
                blockerUserId: userId,
                source: .cache
            )
            guard isCurrentSession(userId: userId, generation: generation) else {
                return
            }
            guard !cachedBlocks.isEmpty ||
                serverSyncMarker.hasSyncedFromServer(userId: userId) else {
                hydrationErrorMessage = Self.hydrationFailureMessage
                return
            }
            applyHydrationResult(cachedBlocks)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSession(userId: userId, generation: generation) else {
                return
            }
            hydrationErrorMessage = Self.hydrationFailureMessage
        }
    }

    private func applyHydrationResult(_ blocks: [BlockedClimber]) {
        blockedClimbers = mergingHydrationResult(blocks)
        blocksAddedDuringHydration = [:]
        userIdsUnblockedDuringHydration = []
        isBlockListHydrated = true
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
        guard activeUserId == blockerUserId,
              blockerUserId != blockedUserId,
              Self.isUsableUserId(blockerUserId),
              Self.isUsableUserId(blockedUserId) else {
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
        guard activeUserId == blockerUserId,
              Self.isUsableUserId(blockerUserId),
              Self.isUsableUserId(blockedUserId) else {
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
        guard activeUserId == reporterUserId,
              reporterUserId != reportedUserId,
              Self.isUsableUserId(reporterUserId),
              Self.isUsableUserId(reportedUserId) else {
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

    /// Moderates a whole collection, reusing the previous result while neither
    /// the rows nor the block list have changed.
    ///
    /// Views read these from `body`, and every `moderate` call trims strings,
    /// resolves a presentation, and hashes a uid, so deriving per render made an
    /// unrelated state change re-moderate the entire board.
    func moderate(_ entries: [LeaderboardEntry]) -> [ModeratedLeaderboardEntry] {
        leaderboardEntryMemo.resolve(
            entries,
            blocks: blockedClimbers,
            isHydrated: isBlockListHydrated
        ) { [self] sources in
            let blockedUserIds = blockedUserIds
            return sources.map {
                CrossUserIdentityAdapter.leaderboardEntry(
                    $0,
                    blockedUserIds: blockedUserIds,
                    isBlockListHydrated: isBlockListHydrated
                )
            }
        }
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
        _ rows: [LiveReplayLeaderboardRow]
    ) -> [ModeratedReplayLeaderboardRow] {
        replayRowMemo.resolve(
            rows,
            blocks: blockedClimbers,
            isHydrated: isBlockListHydrated
        ) { [self] sources in
            let blockedUserIds = blockedUserIds
            return sources.map {
                CrossUserIdentityAdapter.replayRow(
                    $0,
                    blockedUserIds: blockedUserIds,
                    isBlockListHydrated: isBlockListHydrated
                )
            }
        }
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

    private static let hydrationFailureMessage =
        "Couldn't load your blocked climbers. Try again."

    private static func isUsableUserId(_ userId: String) -> Bool {
        !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Caches moderated collections so repeated renders of unchanged rows are free.
///
/// Several screens moderate more than one collection of the same element type,
/// so entries are matched on their source rows rather than a caller-supplied
/// key. Any block-list change drops every entry.
private struct ModeratedCollectionMemo<Source: Equatable, Output> {
    private struct Entry {
        let source: [Source]
        let output: [Output]
    }

    private static var capacity: Int { 4 }

    private var blocks: [BlockedClimber]?
    private var isHydrated = false
    private var entries: [Entry] = []

    mutating func resolve(
        _ source: [Source],
        blocks currentBlocks: [BlockedClimber],
        isHydrated currentIsHydrated: Bool,
        transform: ([Source]) -> [Output]
    ) -> [Output] {
        if blocks != currentBlocks || isHydrated != currentIsHydrated {
            blocks = currentBlocks
            isHydrated = currentIsHydrated
            entries = []
        }

        if let match = entries.first(where: { $0.source == source }) {
            return match.output
        }

        let output = transform(source)
        entries.insert(Entry(source: source, output: output), at: 0)
        if entries.count > Self.capacity {
            entries.removeLast()
        }
        return output
    }
}
