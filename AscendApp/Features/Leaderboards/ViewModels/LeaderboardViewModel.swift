import Foundation
import Observation
import SwiftData
@preconcurrency import FirebaseFirestore

@MainActor
@Observable
final class LeaderboardViewModel {
    var selectedMetric: LeaderboardMetric = .climb
    var selectedTimeFrame: LeaderboardTimeFrame = .weekly
    var leaderboardEntries: [LeaderboardEntry] = []
    var userEntry: LeaderboardEntry?
    var isLoading = false
    var errorMessage: String?
    var isOffline = false

    private let service = LeaderboardService.shared
    private let repository = LeaderboardRepository.shared
    private let sessionCache: LeaderboardSessionCache
    private let pageSize = 25
    private let networkTimeoutSeconds = LeaderboardRefreshPolicy.networkTimeoutSeconds
    private(set) var visibleEntryLimit = 25
    private var currentUserId: String?

    init(sessionCache: LeaderboardSessionCache = .shared) {
        self.sessionCache = sessionCache
    }

    func configure(userId: String, modelContext: ModelContext) {
        currentUserId = userId
        service.configure(modelContext: modelContext)
    }

    var displayedEntries: [LeaderboardEntry] {
        guard !leaderboardEntries.isEmpty else { return [] }
        return Array(leaderboardEntries.prefix(min(visibleEntryLimit, leaderboardEntries.count)))
    }

    var hasCachedEntries: Bool {
        !leaderboardEntries.isEmpty
    }

    func refreshLeaderboard(
        userId: String,
        displayName: String,
        photoURL: URL?,
        isNetworkConnected: Bool
    ) async {
        isLoading = true
        errorMessage = nil
        isOffline = false
        var syncError: Error?

        if isNetworkConnected == false {
            syncError = URLError(.notConnectedToInternet)
        } else {
            do {
                try await withLeaderboardTimeout(seconds: networkTimeoutSeconds) {
                    try await LeaderboardSyncCoordinator.shared.flushNow(
                        userId: userId,
                        displayName: displayName,
                        photoURL: photoURL
                    )
                }
            } catch {
                syncError = error
            }
        }

        let refreshIssue = syncError.map(LeaderboardNetworkIssue.classify)
        let shouldForceRemoteRefresh: Bool = {
            guard let refreshIssue else { return true }
            switch refreshIssue {
            case .offline, .slowConnection:
                return false
            case .other:
                return true
            }
        }()

        await loadLeaderboard(
            userId: userId,
            forceRefresh: shouldForceRemoteRefresh,
            isNetworkConnected: isNetworkConnected
        )

        guard let syncError else { return }
        let loadFailedWithoutEntries = errorMessage != nil && leaderboardEntries.isEmpty
        guard loadFailedWithoutEntries == false else { return }

        let hasUnsyncedActivity = hasUnsyncedActivityForSelectedBoard(userId: userId)
        switch LeaderboardNetworkIssue.classify(syncError) {
        case .offline:
            isOffline = true
            errorMessage = nil
        case .slowConnection:
            guard hasUnsyncedActivity else { return }
            isOffline = false
            errorMessage = "Latest changes may take a moment to appear."
        case .other:
            guard hasUnsyncedActivity else { return }
            isOffline = false
            errorMessage = leaderboardEntries.isEmpty
                ? "Couldn’t publish your latest leaderboard stats yet."
                : "Latest changes haven’t synced yet."
        }
    }

    func loadLeaderboard(
        userId: String,
        forceRefresh: Bool = false,
        isNetworkConnected: Bool? = nil
    ) async {
        isLoading = leaderboardEntries.isEmpty
        if forceRefresh {
            errorMessage = nil
            isOffline = false
        }

        if forceRefresh == false,
           let cachedStats = await sessionCache.detailEntries(
                for: selectedMetric,
                timeFrame: selectedTimeFrame
           ) {
            apply(stats: reconcileCurrentUserStats(cachedStats, userId: userId), userId: userId)
            errorMessage = nil
            isOffline = false
            isLoading = false
            return
        }

        if isNetworkConnected == false {
            do {
                let cacheStats = try await repository.fetchLeaderboard(
                    metric: selectedMetric,
                    timeFrame: selectedTimeFrame,
                    limit: 100,
                    source: .cache
                )
                let reconciledStats = reconcileCurrentUserStats(cacheStats, userId: userId)
                await sessionCache.setDetailEntries(
                    reconciledStats,
                    for: selectedMetric,
                    timeFrame: selectedTimeFrame
                )
                if cacheStats.isEmpty {
                    leaderboardEntries = []
                    userEntry = try? placeholderEntry(for: userId)
                    handleError(URLError(.notConnectedToInternet), context: "load")
                } else {
                    apply(stats: reconciledStats, userId: userId)
                    handleCachedFallbackError(URLError(.notConnectedToInternet))
                }
                isLoading = false
                return
            } catch {
                leaderboardEntries = []
                userEntry = try? placeholderEntry(for: userId)
                handleError(URLError(.notConnectedToInternet), context: "load")
                isLoading = false
                return
            }
        }

        do {
            let source: FirestoreSource = forceRefresh ? .server : .default
            let stats = try await withLeaderboardTimeout(seconds: networkTimeoutSeconds) {
                try await self.repository.fetchLeaderboard(
                    metric: self.selectedMetric,
                    timeFrame: self.selectedTimeFrame,
                    limit: 100,
                    source: source
                )
            }
            let reconciledStats = reconcileCurrentUserStats(stats, userId: userId)
            await sessionCache.setDetailEntries(
                reconciledStats,
                for: selectedMetric,
                timeFrame: selectedTimeFrame
            )
            apply(stats: reconciledStats, userId: userId)
            errorMessage = nil
            isOffline = false
        } catch {
            if let cachedStats = await sessionCache.detailEntries(
                for: selectedMetric,
                timeFrame: selectedTimeFrame
            ) {
                let reconciledStats = reconcileCurrentUserStats(cachedStats, userId: userId)
                if cachedStats.isEmpty {
                    leaderboardEntries = []
                    userEntry = try? placeholderEntry(for: userId)
                    handleError(error, context: "load")
                } else {
                    apply(stats: reconciledStats, userId: userId)
                    handleCachedFallbackError(error)
                }
                isLoading = false
                return
            }

            do {
                let cacheStats = try await repository.fetchLeaderboard(
                    metric: selectedMetric,
                    timeFrame: selectedTimeFrame,
                    limit: 100,
                    source: .cache
                )
                let reconciledStats = reconcileCurrentUserStats(cacheStats, userId: userId)
                await sessionCache.setDetailEntries(
                    reconciledStats,
                    for: selectedMetric,
                    timeFrame: selectedTimeFrame
                )
                if cacheStats.isEmpty {
                    leaderboardEntries = []
                    userEntry = try? placeholderEntry(for: userId)
                    handleError(error, context: "load")
                } else {
                    apply(stats: reconciledStats, userId: userId)
                    handleCachedFallbackError(error)
                }
            } catch {
                leaderboardEntries = []
                userEntry = try? placeholderEntry(for: userId)
                handleError(error, context: "load")
            }
        }

        isLoading = false
    }

    func loadMoreEntriesIfNeeded(currentEntry entry: LeaderboardEntry) {
        guard let lastVisible = displayedEntries.last, lastVisible.id == entry.id else { return }
        guard visibleEntryLimit < leaderboardEntries.count else { return }
        visibleEntryLimit = min(visibleEntryLimit + pageSize, leaderboardEntries.count)
    }

    func updateCurrentUserProfile(userId: String?, displayName: String, photoURL: URL?) {
        guard let userId else { return }

        if let index = leaderboardEntries.firstIndex(where: { $0.userId == userId }) {
            let existing = leaderboardEntries[index]
            leaderboardEntries[index] = LeaderboardEntry(
                userId: existing.userId,
                displayName: displayName,
                photoURL: photoURL,
                rank: existing.rank,
                value: existing.value,
                formattedValue: existing.formattedValue,
                isCurrentUser: true
            )
        }

        if let entry = userEntry, entry.userId == userId {
            userEntry = LeaderboardEntry(
                userId: entry.userId,
                displayName: displayName,
                photoURL: photoURL,
                rank: entry.rank,
                value: entry.value,
                formattedValue: entry.formattedValue,
                isCurrentUser: true
            )
        }

        let sessionCache = sessionCache
        Task {
            await sessionCache.updateCurrentUserProfile(
                userId: userId,
                displayName: displayName,
                photoURL: photoURL
            )
        }
    }

    private func apply(stats: [FirestoreLeaderboardStats], userId: String) {
        let entries = stats.enumerated().map { index, stat in
            let value = stat.value(for: selectedMetric)
            return LeaderboardEntry(
                userId: stat.userId,
                displayName: stat.displayName,
                photoURL: stat.photoURL.flatMap(URL.init(string:)),
                rank: index + 1,
                value: value,
                formattedValue: formatValue(value, for: selectedMetric),
                isCurrentUser: stat.userId == userId
            )
        }

        leaderboardEntries = entries
        userEntry = entries.first(where: { $0.userId == userId }) ?? (try? placeholderEntry(for: userId))
        resetPagination()
    }

    private func placeholderEntry(for userId: String) throws -> LeaderboardEntry? {
        guard let localStats = try service.getLocalStats(for: userId, timeFrame: selectedTimeFrame) else {
            return nil
        }

        let value = localStats.value(for: selectedMetric)
        return LeaderboardEntry(
            userId: userId,
            displayName: "You",
            photoURL: nil,
            rank: leaderboardEntries.count + 1,
            value: value,
            formattedValue: formatValue(value, for: selectedMetric),
            isCurrentUser: true
        )
    }

    private func resetPagination() {
        visibleEntryLimit = min(pageSize, leaderboardEntries.count)
    }

    private func reconcileCurrentUserStats(
        _ stats: [FirestoreLeaderboardStats],
        userId: String
    ) -> [FirestoreLeaderboardStats] {
        guard let localStats = try? service.getLocalStats(for: userId, timeFrame: selectedTimeFrame) else {
            return stats
        }

        return LeaderboardCurrentUserReconciler.reconcileDetailStats(
            stats,
            metric: selectedMetric,
            userId: userId,
            localStats: localStats,
            displayName: userEntry?.displayName ?? "You",
            photoURL: userEntry?.photoURL
        )
    }

    private func hasUnsyncedActivityForSelectedBoard(userId: String) -> Bool {
        guard let localStats = try? service.getLocalStats(for: userId, timeFrame: selectedTimeFrame) else {
            return false
        }

        return localStats.needsSync && localStats.hasActivity
    }

    private func formatValue(_ value: Double, for metric: LeaderboardMetric) -> String {
        switch metric {
        case .climb, .workouts:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .duration:
            let totalSeconds = Int(value.rounded())
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            return "\(hours):\(Self.twoDigit(minutes)):\(Self.twoDigit(seconds))"
        case .pace:
            return value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    private static func twoDigit(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private func handleCachedFallbackError(_ error: Error) {
        switch LeaderboardNetworkIssue.classify(error) {
        case .offline:
            isOffline = true
            errorMessage = nil
        case .slowConnection:
            isOffline = false
            errorMessage = "Latest changes may take a moment to appear."
        case .other:
            isOffline = false
            errorMessage = "Showing cached data. Latest refresh failed."
        }
    }

    private func handleError(_ error: Error, context: String) {
        switch LeaderboardNetworkIssue.classify(error) {
        case .offline:
            isOffline = true
            errorMessage = "You're offline. Pull to retry."
        case .slowConnection:
            isOffline = false
            errorMessage = "Leaderboard request timed out. Pull to retry."
        case .other:
            isOffline = false
            errorMessage = context == "load"
                ? "Couldn’t load this leaderboard right now."
                : "Couldn’t refresh this leaderboard right now."
        }
    }
}
