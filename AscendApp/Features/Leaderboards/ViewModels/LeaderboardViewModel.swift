import Foundation
import Observation
import SwiftData
@preconcurrency import FirebaseFirestore

@MainActor
@Observable
final class LeaderboardViewModel {
    var selectedMetric: LeaderboardMetric = .climb
    var selectedTimeFrame: LeaderboardTimeFrame = .weekly
    var selectedAgeGroup: LeaderboardAgeGroup?
    var selectedBodyWeightFilter: LeaderboardBodyWeightFilter = .all
    var selectedLocationFilter: LeaderboardLocationFilter = .all
    var leaderboardEntries: [LeaderboardEntry] = []
    var userStanding: LeaderboardUserStanding?
    var isLoading = false
    var errorMessage: String?
    var isOffline = false

    private let service: LeaderboardService
    private let repository = LeaderboardRepository.shared
    private let sessionCache: LeaderboardSessionCache
    private let pageSize = 25
    private let networkTimeoutSeconds = LeaderboardRefreshPolicy.networkTimeoutSeconds
    private let defaultFetchLimit = 100
    private let demographicFilterFetchLimit = 1_000
    private(set) var visibleEntryLimit = 25
    private var currentUserId: String?
    private var currentUserDisplayName: String?
    private var currentUserPhotoURL: URL?
    private var currentUserProfile: LeaderboardProfileSnapshot?
    private var rawLeaderboardStats: [FirestoreLeaderboardStats] = []

    init(
        sessionCache: LeaderboardSessionCache = .shared,
        service: LeaderboardService = .shared
    ) {
        self.sessionCache = sessionCache
        self.service = service
    }

    func configure(userId: String, displayName: String?, modelContext: ModelContext) {
        currentUserId = userId
        currentUserDisplayName = displayName
        service.configure(modelContext: modelContext)
    }

    /// The window the selected board covers. Surfaced so the board can name it: weekly
    /// and monthly windows do not nest, so an unlabelled pair reads as a contradiction on
    /// any day a week straddles a month boundary.
    var selectedPeriod: LeaderboardPeriod {
        selectedTimeFrame.currentPeriod()
    }

    var displayedEntries: [LeaderboardEntry] {
        guard !leaderboardEntries.isEmpty else { return [] }
        return Array(leaderboardEntries.prefix(min(visibleEntryLimit, leaderboardEntries.count)))
    }

    var hasCachedEntries: Bool {
        !leaderboardEntries.isEmpty
    }

    var hasActiveDemographicFilters: Bool {
        selectedAgeGroup != nil ||
            selectedBodyWeightFilter != .all ||
            selectedLocationFilter != .all
    }

    var ageFilterTitle: String {
        selectedAgeGroup?.displayName ?? "Age"
    }

    var bodyWeightFilterTitle: String {
        selectedBodyWeightFilter.shortDisplayName
    }

    var locationFilterTitle: String {
        selectedLocationFilter == .all
            ? selectedLocationFilter.shortDisplayName
            : selectedLocationFilter.displayName(currentUserProfile: currentUserProfile)
    }

    var currentLocationFilterOptions: [LeaderboardLocationFilter] {
        LeaderboardLocationFilter.allCases.filter {
            $0.isAvailable(currentUserProfile: currentUserProfile)
        }
    }

    var currentUserLocationProfile: LeaderboardProfileSnapshot? {
        currentUserProfile
    }

    var filteredEmptyStateTitle: String {
        "No climbers match."
    }

    var filteredEmptyStateMessage: String {
        "Clear a filter."
    }

    func refreshLeaderboard(
        userId: String,
        isNetworkConnected: Bool
    ) async {
        isLoading = true
        errorMessage = nil
        isOffline = false

        // Refresh publishes nothing. The server derives standings from the workouts
        // the app already backs up, so pulling to refresh is a re-read - and the
        // climber's own numbers are already on screen from the local display cache
        // (LeaderboardCurrentUserReconciler) whether or not the read succeeds.
        await loadLeaderboard(
            userId: userId,
            forceRefresh: isNetworkConnected,
            isNetworkConnected: isNetworkConnected
        )
    }

    func loadLeaderboard(
        userId: String,
        forceRefresh: Bool = false,
        isNetworkConnected: Bool? = nil
    ) async {
        await loadCurrentUserProfileIfNeeded(userId: userId)

        isLoading = leaderboardEntries.isEmpty
        if forceRefresh {
            errorMessage = nil
            isOffline = false
        }

        let fetchLimit = requiredFetchLimit
        if forceRefresh == false,
           let cachedStats = await sessionCache.detailEntries(
                for: selectedMetric,
                timeFrame: selectedTimeFrame,
                minimumLimit: fetchLimit
           ) {
            apply(stats: reconcileCurrentUserStats(cachedStats, userId: userId), userId: userId)
            if isNetworkConnected == false {
                // A warm session cache is still stale data with no connection behind it.
                // Serving it silently tells the climber the board is current when it is not.
                handleCachedFallbackError(URLError(.notConnectedToInternet))
            } else {
                errorMessage = nil
                isOffline = false
            }
            isLoading = false
            return
        }

        if isNetworkConnected == false {
            do {
                let cacheStats = try await repository.fetchLeaderboard(
                    metric: selectedMetric,
                    timeFrame: selectedTimeFrame,
                    limit: fetchLimit,
                    source: .cache
                )
                let reconciledStats = reconcileCurrentUserStats(cacheStats, userId: userId)
                await sessionCache.setDetailEntries(
                    reconciledStats,
                    for: selectedMetric,
                    timeFrame: selectedTimeFrame,
                    limit: fetchLimit
                )
                if cacheStats.isEmpty {
                    leaderboardEntries = []
                    userStanding = unrankedStanding(for: userId)
                    handleError(URLError(.notConnectedToInternet), context: "load")
                } else {
                    apply(stats: reconciledStats, userId: userId)
                    handleCachedFallbackError(URLError(.notConnectedToInternet))
                }
                isLoading = false
                return
            } catch {
                leaderboardEntries = []
                userStanding = unrankedStanding(for: userId)
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
                    limit: fetchLimit,
                    source: source
                )
            }
            let reconciledStats = reconcileCurrentUserStats(stats, userId: userId)
            await sessionCache.setDetailEntries(
                reconciledStats,
                for: selectedMetric,
                timeFrame: selectedTimeFrame,
                limit: fetchLimit
            )
            apply(stats: reconciledStats, userId: userId)
            errorMessage = nil
            isOffline = false
        } catch {
            if let cachedStats = await sessionCache.detailEntries(
                for: selectedMetric,
                timeFrame: selectedTimeFrame,
                minimumLimit: fetchLimit
            ) {
                let reconciledStats = reconcileCurrentUserStats(cachedStats, userId: userId)
                if cachedStats.isEmpty {
                    leaderboardEntries = []
                    userStanding = unrankedStanding(for: userId)
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
                    limit: fetchLimit,
                    source: .cache
                )
                let reconciledStats = reconcileCurrentUserStats(cacheStats, userId: userId)
                await sessionCache.setDetailEntries(
                    reconciledStats,
                    for: selectedMetric,
                    timeFrame: selectedTimeFrame,
                    limit: fetchLimit
                )
                if cacheStats.isEmpty {
                    leaderboardEntries = []
                    userStanding = unrankedStanding(for: userId)
                    handleError(error, context: "load")
                } else {
                    apply(stats: reconciledStats, userId: userId)
                    handleCachedFallbackError(error)
                }
            } catch {
                leaderboardEntries = []
                userStanding = unrankedStanding(for: userId)
                handleError(error, context: "load")
            }
        }

        isLoading = false
    }

    func loadMoreEntriesIfNeeded(currentEntryID: String) {
        guard let lastVisible = displayedEntries.last, lastVisible.id == currentEntryID else { return }
        guard visibleEntryLimit < leaderboardEntries.count else { return }
        visibleEntryLimit = min(visibleEntryLimit + pageSize, leaderboardEntries.count)
    }

    func selectAgeGroup(_ ageGroup: LeaderboardAgeGroup?) {
        guard selectedAgeGroup != ageGroup else { return }
        selectedAgeGroup = ageGroup
        trackDemographicFilterChanged(
            type: .ageGroup,
            selectedValue: ageGroup?.rawValue ?? "all"
        )
    }

    func selectBodyWeightFilter(_ filter: LeaderboardBodyWeightFilter) {
        guard selectedBodyWeightFilter != filter else { return }
        selectedBodyWeightFilter = filter
        trackDemographicFilterChanged(
            type: .bodyWeight,
            selectedValue: filter.rawValue
        )
    }

    func selectLocationFilter(_ filter: LeaderboardLocationFilter) {
        guard selectedLocationFilter != filter else { return }
        selectedLocationFilter = filter
        trackDemographicFilterChanged(
            type: .location,
            selectedValue: filter.rawValue
        )
    }

    func clearDemographicFilters() {
        let shouldTrackClear = hasActiveDemographicFilters
        selectedAgeGroup = nil
        selectedBodyWeightFilter = .all
        selectedLocationFilter = .all
        if shouldTrackClear {
            TelemetryManager.shared.track(
                LeaderboardAnalyticsEvent.demographicFiltersCleared(
                    context: analyticsContext
                )
            )
        }
        reapplyCurrentStats()
    }

    func updateCurrentUserProfile(userId: String?, displayName: String?, photoURL: URL?) {
        guard let userId else { return }
        currentUserDisplayName = displayName
        currentUserPhotoURL = photoURL

        if let index = leaderboardEntries.firstIndex(where: { $0.userId == userId }) {
            leaderboardEntries[index] = leaderboardEntries[index].withProfile(
                displayName: displayName,
                photoURL: photoURL
            )
        }

        if let entry = userStanding?.rankedEntry, entry.userId == userId {
            userStanding = .ranked(entry.withProfile(displayName: displayName, photoURL: photoURL))
        }
    }

    private func apply(stats: [FirestoreLeaderboardStats], userId: String) {
        rawLeaderboardStats = stats
        reapplyCurrentStats(userId: userId)
    }

    private func reapplyCurrentStats() {
        guard let currentUserId else { return }
        reapplyCurrentStats(userId: currentUserId)
    }

    private func reapplyCurrentStats(userId: String) {
        let filteredStats = filtered(rawLeaderboardStats)
        let metric = selectedMetric
        let ranks = CompetitionRanking.ranks(for: filteredStats) { $0.value(for: metric) }
        let tieFlags = CompetitionRanking.tieFlags(for: ranks)
        let entries = filteredStats.enumerated().map { index, stat in
            let value = stat.value(for: metric)
            return CrossUserIdentityAdapter.leaderboardEntry(
                from: stat,
                rank: ranks[index],
                value: value,
                formattedValue: formatValue(value, for: metric),
                isTied: tieFlags[index],
                currentUserId: userId,
                currentUserPhotoURL: currentUserPhotoURL
            )
        }

        leaderboardEntries = entries
        userStanding = entries.first(where: { $0.userId == userId }).map(LeaderboardUserStanding.ranked) ??
            (hasActiveDemographicFilters ? nil : unrankedStanding(for: userId))
        resetPagination()
    }

    private func filtered(_ stats: [FirestoreLeaderboardStats]) -> [FirestoreLeaderboardStats] {
        stats.filter { stat in
            if let selectedAgeGroup,
               !selectedAgeGroup.contains(age: stat.age) {
                return false
            }

            if !selectedBodyWeightFilter.contains(weightKg: stat.weightKg) {
                return false
            }

            if !selectedLocationFilter.contains(
                stats: stat,
                currentUserProfile: currentUserProfile
            ) {
                return false
            }

            return true
        }
    }

    /// The climber's standing when they are not among the ranked entries.
    ///
    /// They are not there because `LeaderboardCurrentUserReconciler` drops a climber with
    /// no activity in the window - so by construction this is the zero-activity case, and
    /// the honest answer is that they hold no rank. This must never synthesise one from
    /// list position: that is what put a "rank 2, 0 steps" row directly under a podium
    /// whose second plinth read `OPEN`.
    private func unrankedStanding(for userId: String) -> LeaderboardUserStanding? {
        guard let localStats = try? service.getLocalStats(for: userId, timeFrame: selectedTimeFrame) else {
            return nil
        }

        let value = localStats.value(for: selectedMetric)
        return .unranked(value: value, formattedValue: formatValue(value, for: selectedMetric))
    }

    private func resetPagination() {
        visibleEntryLimit = min(pageSize, leaderboardEntries.count)
    }

    private func reconcileCurrentUserStats(
        _ stats: [FirestoreLeaderboardStats],
        userId: String
    ) -> [FirestoreLeaderboardStats] {
        guard let localStats = try? service.getLocalStats(for: userId, timeFrame: selectedTimeFrame) else {
            return applyCurrentUserProfile(to: stats, userId: userId)
        }

        let reconciled = LeaderboardCurrentUserReconciler.reconcileDetailStats(
            stats,
            metric: selectedMetric,
            userId: userId,
            displayName: currentUserDisplayName,
            localStats: localStats
        )
        return applyCurrentUserProfile(to: reconciled, userId: userId)
    }

    private func applyCurrentUserProfile(
        to stats: [FirestoreLeaderboardStats],
        userId: String
    ) -> [FirestoreLeaderboardStats] {
        guard let currentUserProfile else { return stats }

        return stats.map { stat in
            guard stat.userId == userId else { return stat }

            return FirestoreLeaderboardStats(
                userId: stat.userId,
                unresolvedIdentity: stat.unresolvedIdentity,
                identityPolicyVersion: stat.identityPolicyVersion,
                identityChangedAt: stat.identityChangedAt,
                timeFrame: stat.timeFrame,
                schemaVersion: stat.schemaVersion,
                periodKey: stat.periodKey,
                periodStartAt: stat.periodStartAt,
                totalSteps: stat.totalSteps,
                totalFloors: stat.totalFloors,
                totalWorkouts: stat.totalWorkouts,
                totalDuration: stat.totalDuration,
                stepsPerMinute: stat.stepsPerMinute,
                lastUpdated: stat.lastUpdated,
                age: currentUserProfile.age ?? stat.age,
                weightKg: currentUserProfile.weightKg ?? stat.weightKg,
                locationCity: currentUserProfile.locationCity ?? stat.locationCity,
                locationCountry: currentUserProfile.locationCountry ?? stat.locationCountry,
                locationRegion: currentUserProfile.locationRegion ?? stat.locationRegion
            )
        }
    }

    private var requiredFetchLimit: Int {
        hasActiveDemographicFilters ? demographicFilterFetchLimit : defaultFetchLimit
    }

    var analyticsContext: LeaderboardAnalyticsContext {
        LeaderboardAnalyticsContext(
            metric: selectedMetric,
            timeFrame: selectedTimeFrame,
            ageGroup: selectedAgeGroup,
            bodyWeightFilter: selectedBodyWeightFilter,
            locationFilter: selectedLocationFilter
        )
    }

    private func trackDemographicFilterChanged(
        type: LeaderboardAnalyticsEvent.FilterType,
        selectedValue: String
    ) {
        TelemetryManager.shared.track(
            LeaderboardAnalyticsEvent.demographicFilterChanged(
                context: analyticsContext,
                filterType: type,
                selectedValue: selectedValue
            )
        )
    }

    private func loadCurrentUserProfileIfNeeded(userId: String) async {
        guard currentUserProfile?.userId != userId else { return }

        if let userData = try? await UserDataRepository.shared.getUserFromFirestore(userId: userId) {
            currentUserProfile = LeaderboardProfileSnapshot(userId: userId, userData: userData)
        }

        if !selectedLocationFilter.isAvailable(currentUserProfile: currentUserProfile) {
            selectedLocationFilter = .all
        }
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
