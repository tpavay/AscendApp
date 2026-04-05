import Foundation
import Observation
import SwiftData
@preconcurrency import FirebaseFirestore

@MainActor
@Observable
final class LeaderboardViewModel {
    var selectedMetric: LeaderboardMetric = .climb
    var selectedTimeFrame: LeaderboardTimeFrame = .weekly
    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            resetPagination()
        }
    }
    var leaderboardEntries: [LeaderboardEntry] = []
    var userEntry: LeaderboardEntry?
    var isLoading = false
    var errorMessage: String?
    var isOffline = false
    var showingTopLeaders = true

    private let service = LeaderboardService.shared
    private let repository = LeaderboardRepository.shared
    private let pageSize = 25
    private let networkTimeoutSeconds = 15.0
    private(set) var visibleEntryLimit = 25
    private var currentUserId: String?

    func configure(userId: String, modelContext: ModelContext) {
        currentUserId = userId
        service.configure(modelContext: modelContext)
    }

    var displayedEntries: [LeaderboardEntry] {
        let entries = filteredEntries
        guard !entries.isEmpty else { return [] }
        return Array(entries.prefix(min(visibleEntryLimit, entries.count)))
    }

    var resetStatusText: String {
        selectedTimeFrame.resetDescription()
    }

    var hasCachedEntries: Bool {
        !leaderboardEntries.isEmpty
    }

    func refreshLeaderboard(
        userId: String,
        displayName: String,
        photoURL: URL?
    ) async {
        isLoading = true
        errorMessage = nil
        isOffline = false
        var syncError: Error?

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

        await loadLeaderboard(userId: userId, forceRefresh: true)

        guard let syncError else { return }
        switch LeaderboardNetworkIssue.classify(syncError) {
        case .offline:
            isOffline = true
            errorMessage = "You're offline. Pull to retry."
        case .slowConnection:
            isOffline = false
            errorMessage = leaderboardEntries.isEmpty
                ? "Leaderboard sync is still timing out."
                : "Latest changes may take a moment to appear."
        case .other:
            isOffline = false
            errorMessage = leaderboardEntries.isEmpty
                ? "Couldn’t publish your latest leaderboard stats yet."
                : "Latest changes haven’t synced yet."
        }
    }

    func loadLeaderboard(userId: String, forceRefresh: Bool = false) async {
        isLoading = leaderboardEntries.isEmpty
        if forceRefresh {
            errorMessage = nil
            isOffline = false
        }

        if forceRefresh == false,
           let cachedStats = await LeaderboardSessionCache.shared.detailEntries(
                for: selectedMetric,
                timeFrame: selectedTimeFrame
           ) {
            apply(stats: cachedStats, userId: userId)
            errorMessage = nil
            isOffline = false
            isLoading = false
            return
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
            await LeaderboardSessionCache.shared.setDetailEntries(
                stats,
                for: selectedMetric,
                timeFrame: selectedTimeFrame
            )
            apply(stats: stats, userId: userId)
            errorMessage = nil
            isOffline = false
        } catch {
            if let cachedStats = await LeaderboardSessionCache.shared.detailEntries(
                for: selectedMetric,
                timeFrame: selectedTimeFrame
            ) {
                if cachedStats.isEmpty {
                    leaderboardEntries = []
                    userEntry = try? placeholderEntry(for: userId)
                    handleError(error, context: "load")
                } else {
                    apply(stats: cachedStats, userId: userId)
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
                await LeaderboardSessionCache.shared.setDetailEntries(
                    cacheStats,
                    for: selectedMetric,
                    timeFrame: selectedTimeFrame
                )
                if cacheStats.isEmpty {
                    leaderboardEntries = []
                    userEntry = try? placeholderEntry(for: userId)
                    handleError(error, context: "load")
                } else {
                    apply(stats: cacheStats, userId: userId)
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

    func toggleView() {
        showingTopLeaders.toggle()
    }

    func scrollToUser() {
        showingTopLeaders = false
    }

    func loadMoreEntriesIfNeeded(currentEntry entry: LeaderboardEntry) {
        guard let lastVisible = displayedEntries.last, lastVisible.id == entry.id else { return }
        let totalEntries = filteredEntries.count
        guard visibleEntryLimit < totalEntries else { return }
        visibleEntryLimit = min(visibleEntryLimit + pageSize, totalEntries)
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

        Task {
            await LeaderboardSessionCache.shared.updateCurrentUserProfile(
                userId: userId,
                displayName: displayName,
                photoURL: photoURL
            )
        }
    }

    private var filteredEntries: [LeaderboardEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return leaderboardEntries }
        return leaderboardEntries.filter { $0.displayName.localizedStandardContains(query) }
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
        visibleEntryLimit = min(pageSize, filteredEntries.count)
    }

    private func formatValue(_ value: Double, for metric: LeaderboardMetric) -> String {
        switch metric {
        case .climb, .workouts:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .duration:
            let totalSeconds = Int(value.rounded())
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(minutes)m"
        case .pace:
            return value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    private func handleCachedFallbackError(_ error: Error) {
        switch LeaderboardNetworkIssue.classify(error) {
        case .offline:
            isOffline = true
            errorMessage = "Offline - showing cached data"
        case .slowConnection:
            isOffline = false
            errorMessage = "Connection is slow - showing cached data"
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
