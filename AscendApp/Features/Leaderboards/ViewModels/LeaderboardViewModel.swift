//
//  LeaderboardViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
class LeaderboardViewModel {
    var selectedMetric: LeaderboardMetric = .climb
    var selectedTimeFrame: LeaderboardTimeFrame = .weekly
    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            resetPaginationForSearchChange()
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
    private let settingsManager = SettingsManager.shared
    private var currentUserId: String?
    private let pageSize = 25
    private(set) var visibleEntryLimit = 25
    
    /// The user's preferred workout metric (steps or floors)
    var preferredWorkoutMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }
    
    func configure(userId: String, modelContext: ModelContext) {
        self.currentUserId = userId
        service.configure(modelContext: modelContext)
    }

    var displayedEntries: [LeaderboardEntry] {
        let entries = filteredEntries
        guard !entries.isEmpty else { return [] }
        let limit = min(visibleEntryLimit, entries.count)
        return Array(entries.prefix(limit))
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
        photoURL: URL?,
        workouts: [Workout]
    ) async {
        isLoading = true
        errorMessage = nil
        isOffline = false

        do {
            // 1. Update local stats from workouts
            try service.updateAllTimeFrames(for: userId, workouts: workouts)

            // 2. Sync to Firestore
            try await service.syncToFirestore(
                userId: userId,
                displayName: displayName,
                photoURL: photoURL
            )

            // 3. Fetch leaderboard from Firestore
            await loadLeaderboard(userId: userId)

        } catch {
            handleError(error, context: "refresh")
        }

        isLoading = false
    }
    
    func loadLeaderboard(userId: String) async {
        isLoading = true
        errorMessage = nil
        isOffline = false

        do {
            let stats = try await repository.fetchLeaderboard(
                metric: selectedMetric,
                timeFrame: selectedTimeFrame,
                limit: 100,
                preferredWorkoutMetric: preferredWorkoutMetric
            )

            // Convert to leaderboard entries with rankings
            var entries: [LeaderboardEntry] = []
            var currentUserEntry: LeaderboardEntry?
            for (index, stat) in stats.enumerated() {
                let value = stat.value(for: selectedMetric, preferredWorkoutMetric: preferredWorkoutMetric)
                let entry = LeaderboardEntry(
                    userId: stat.userId,
                    displayName: stat.displayName,
                    photoURL: stat.photoURL.flatMap { URL(string: $0) },
                    rank: index + 1,
                    value: value,
                    formattedValue: formatValue(value, for: selectedMetric),
                    isCurrentUser: stat.userId == userId
                )

                entries.append(entry)

                if stat.userId == userId {
                    currentUserEntry = entry
                }
            }

            leaderboardEntries = entries

            // If user not in leaderboard yet, create a placeholder entry
            if currentUserEntry == nil {
                if let localStats = try service.getLocalStats(for: userId, timeFrame: selectedTimeFrame) {
                    let value = localStats.value(for: selectedMetric, preferredWorkoutMetric: preferredWorkoutMetric)
                    currentUserEntry = LeaderboardEntry(
                        userId: userId,
                        displayName: "You",
                        photoURL: nil,
                        rank: entries.count + 1,
                        value: value,
                        formattedValue: formatValue(value, for: selectedMetric),
                        isCurrentUser: true
                    )
                }
            }

            userEntry = currentUserEntry
            resetPagination()

        } catch {
            handleError(error, context: "load")
        }

        isLoading = false
    }

    private func handleError(_ error: Error, context: String) {
        let nsError = error as NSError

        // Check for network-related errors
        let networkErrorCodes = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed
        ]

        if networkErrorCodes.contains(nsError.code) || nsError.domain == NSURLErrorDomain {
            isOffline = true
            if hasCachedEntries {
                errorMessage = "Offline - showing cached data"
            } else {
                errorMessage = "No internet connection. Please check your network and try again."
            }
        } else {
            errorMessage = "Failed to \(context) leaderboard: \(error.localizedDescription)"
        }
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
    
    private func resetPagination() {
        visibleEntryLimit = min(pageSize, filteredEntries.count)
    }

    private func resetPaginationForSearchChange() {
        resetPagination()
    }

    private var filteredEntries: [LeaderboardEntry] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return leaderboardEntries }
        return leaderboardEntries.filter { entry in
            entry.displayName.range(of: trimmedQuery, options: .caseInsensitive) != nil
        }
    }
    
    private func formatValue(_ value: Double, for metric: LeaderboardMetric) -> String {
        switch metric {
        case .climb, .workouts:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .duration:
            return formatDuration(value)
        case .pace:
            return value.formatted(.number.precision(.fractionLength(1)))
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Update the current user's display info in the local cache
    func updateCurrentUserProfile(userId: String?, displayName: String, photoURL: URL?) {
        guard let userId = userId else { return }

        // Update in leaderboardEntries array
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

        // Update userEntry if it matches
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
    }
}
