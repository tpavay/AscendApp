import Foundation
import Observation
import SwiftData

struct HomeRecentPRRecord: Identifiable, Equatable {
    let id: String
    let metric: BestEffortMetric
    let label: String
    let value: String
    let isNew: Bool
}

@MainActor
@Observable
final class HomeDashboardViewModel {
    var weeklyStats: HomeWeeklyStats = .zero
    var completedClimbCount: Int = 0
    var weeklyRank: Int?
    var rankPercentile: Int?
    var workoutCount: Int = 0
    var isRankLoading = false
    var recentPersonalRecords: [HomeRecentPRRecord] = []

    private let leaderboardRepository: LeaderboardRepository
    private let leaderboardSessionCache: LeaderboardSessionCache
    private let leaderboardService: LeaderboardService
    private var lastRankRequest: RankRequest?
    private var lastRankRefreshAt: Date?
    private var rankTask: Task<Void, Never>?

    init(
        leaderboardRepository: LeaderboardRepository = .shared,
        leaderboardSessionCache: LeaderboardSessionCache = .shared,
        leaderboardService: LeaderboardService = .shared
    ) {
        self.leaderboardRepository = leaderboardRepository
        self.leaderboardSessionCache = leaderboardSessionCache
        self.leaderboardService = leaderboardService
    }

    func refreshLocalData(modelContext: ModelContext, referenceDate: Date = Date()) {
        let weeklyStats = fetchWeeklyStats(modelContext: modelContext, referenceDate: referenceDate)
        if self.weeklyStats != weeklyStats {
            self.weeklyStats = weeklyStats
        }

        let completedClimbCount = fetchCompletedClimbCount(modelContext: modelContext)
        if self.completedClimbCount != completedClimbCount {
            self.completedClimbCount = completedClimbCount
        }

        let workoutCount = fetchWorkoutCount(modelContext: modelContext)
        if self.workoutCount != workoutCount {
            self.workoutCount = workoutCount
        }

        let recentPRs = fetchRecentPersonalRecords(modelContext: modelContext, referenceDate: referenceDate)
        if self.recentPersonalRecords != recentPRs {
            self.recentPersonalRecords = recentPRs
        }
    }

    func refreshWeeklyRank(
        userId: String?,
        displayName: String,
        photoURL: URL?,
        modelContext: ModelContext,
        forceRemote: Bool = false,
        referenceDate: Date = Date()
    ) {
        guard let userId else {
            clearRank()
            return
        }

        leaderboardService.configure(modelContext: modelContext)

        guard let localStats = try? leaderboardService.getLocalStats(for: userId, timeFrame: .weekly),
              localStats.hasActivity else {
            clearRank()
            return
        }

        let localSnapshot = LeaderboardStatsSnapshot(
            localStats: localStats,
            userId: userId,
            displayName: displayName,
            photoURLString: photoURL?.absoluteString
        )
        let request = RankRequest(
            userId: userId,
            periodKey: localSnapshot.periodKey,
            totalSteps: localSnapshot.totalSteps,
            totalDuration: localSnapshot.totalDuration,
            lastUpdated: localSnapshot.lastUpdated
        )

        if shouldSkipRankRefresh(request: request, forceRemote: forceRemote, referenceDate: referenceDate) {
            return
        }

        lastRankRequest = request
        rankTask?.cancel()
        isRankLoading = weeklyRank == nil

        rankTask = Task { [leaderboardRepository, leaderboardSessionCache] in
            if !forceRemote,
               let cachedStats = await leaderboardSessionCache.detailEntries(for: .climb, timeFrame: .weekly),
               applyRank(from: cachedStats, localSnapshot: localSnapshot) {
                isRankLoading = false
                return
            }

            do {
                let remoteStats = try await withLeaderboardTimeout(
                    seconds: LeaderboardRefreshPolicy.networkTimeoutSeconds
                ) {
                    try await leaderboardRepository.fetchLeaderboard(
                        metric: .climb,
                        timeFrame: .weekly,
                        limit: 1_000,
                        source: .default
                    )
                }
                guard !Task.isCancelled else { return }

                let reconciledStats = Self.reconciledStats(remoteStats, localSnapshot: localSnapshot)
                await leaderboardSessionCache.setDetailEntries(
                    reconciledStats,
                    for: .climb,
                    timeFrame: .weekly
                )
                _ = applyRank(from: reconciledStats, localSnapshot: localSnapshot, alreadyReconciled: true)
                lastRankRefreshAt = referenceDate
            } catch {
                guard !Task.isCancelled else { return }
            }

            isRankLoading = false
        }
    }

    private func fetchWeeklyStats(modelContext: ModelContext, referenceDate: Date) -> HomeWeeklyStats {
        let calendar = WeekConfiguration.calendar()
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) ??
            DateInterval(start: referenceDate, duration: 7 * 24 * 60 * 60)
        let startDate = weekInterval.start
        let endDate = min(referenceDate, weekInterval.end)
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.date >= startDate && workout.date <= endDate
            }
        )

        guard let workouts = try? modelContext.fetch(descriptor) else {
            return .zero
        }

        return HomeWeeklyStats.make(from: workouts)
    }

    private func fetchCompletedClimbCount(modelContext: ModelContext) -> Int {
        let completedStatus = ClimbAttemptStatus.completed.rawValue
        let descriptor = FetchDescriptor<ClimbAttempt>(
            predicate: #Predicate<ClimbAttempt> { attempt in
                attempt.statusRawValue == completedStatus
            }
        )

        guard let attempts = try? modelContext.fetch(descriptor) else {
            return 0
        }

        return Set(attempts.map(\.climbId)).count
    }

    private func fetchWorkoutCount(modelContext: ModelContext) -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<Workout>())) ?? 0
    }

    private func fetchRecentPersonalRecords(
        modelContext: ModelContext,
        referenceDate: Date
    ) -> [HomeRecentPRRecord] {
        let rankOne = 1
        let entryDescriptor = FetchDescriptor<BestEffortCacheEntry>(
            predicate: #Predicate<BestEffortCacheEntry> { entry in
                entry.rank == rankOne
            }
        )

        guard let entries = try? modelContext.fetch(entryDescriptor),
              !entries.isEmpty,
              let workouts = try? modelContext.fetch(FetchDescriptor<Workout>()),
              !workouts.isEmpty else {
            return []
        }

        let snapshot = BestEffortCacheSnapshot(entries: entries, workouts: workouts)
        let sevenDaysAgo = referenceDate.addingTimeInterval(-7 * 24 * 60 * 60)

        return BestEffortMetric.workoutRecordDefinitions.compactMap { metric -> HomeRecentPRRecord? in
            guard let top = snapshot.rankedEfforts(for: metric).first else { return nil }
            return HomeRecentPRRecord(
                id: metric.id,
                metric: metric,
                label: Self.shortLabel(for: metric),
                value: Self.compactValue(for: top),
                isNew: top.workout.date >= sevenDaysAgo
            )
        }
    }

    private static func shortLabel(for metric: BestEffortMetric) -> String {
        switch metric {
        case .mostSteps:
            return "MOST STEPS"
        case .longestClimb:
            return "LONGEST CLIMB"
        case .highestAverageSPM:
            return "HIGHEST SPM"
        case .mostStepsInTime(let minutes):
            return "BEST \(minutes) MIN"
        case .fastestStepTarget(let steps):
            let formatted = steps >= 1000 ? "\(steps / 1000)K" : "\(steps)"
            return "FASTEST \(formatted)"
        }
    }

    private static func compactValue(for effort: RankedBestEffort) -> String {
        switch effort.metric {
        case .longestClimb, .fastestStepTarget:
            return BestEffortFormatting.clockTime(effort.performance.value)
        case .mostSteps, .mostStepsInTime, .highestAverageSPM:
            return effort.compactValueText
        }
    }

    private func shouldSkipRankRefresh(
        request: RankRequest,
        forceRemote: Bool,
        referenceDate: Date
    ) -> Bool {
        guard request == lastRankRequest else { return false }

        if forceRemote {
            guard let lastRankRefreshAt else { return false }
            return referenceDate.timeIntervalSince(lastRankRefreshAt) < Self.rankRefreshMinimumInterval
        }

        return true
    }

    private func applyRank(
        from stats: [FirestoreLeaderboardStats],
        localSnapshot: LeaderboardStatsSnapshot,
        alreadyReconciled: Bool = false
    ) -> Bool {
        let resolvedStats = alreadyReconciled ? stats : Self.reconciledStats(stats, localSnapshot: localSnapshot)
        guard let result = Self.rankResult(from: resolvedStats, userId: localSnapshot.userId) else {
            weeklyRank = nil
            rankPercentile = nil
            return false
        }

        weeklyRank = result.rank
        rankPercentile = Self.percentile(rank: result.rank, total: result.total)
        return true
    }

    private func clearRank() {
        rankTask?.cancel()
        weeklyRank = nil
        rankPercentile = nil
        isRankLoading = false
        lastRankRequest = nil
        lastRankRefreshAt = nil
    }

    private static func reconciledStats(
        _ stats: [FirestoreLeaderboardStats],
        localSnapshot: LeaderboardStatsSnapshot
    ) -> [FirestoreLeaderboardStats] {
        var resolved = stats

        if let index = resolved.firstIndex(where: { $0.userId == localSnapshot.userId }) {
            let existing = resolved[index]
            resolved[index] = localSnapshot.firestoreStats(existing: existing)
        } else {
            resolved.append(localSnapshot.firestoreStats(existing: nil))
        }

        resolved.sort { lhs, rhs in
            let lhsValue = lhs.value(for: .climb)
            let rhsValue = rhs.value(for: .climb)
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
            return lhs.userId < rhs.userId
        }

        return resolved
    }

    private static func rankResult(
        from stats: [FirestoreLeaderboardStats],
        userId: String
    ) -> (rank: Int, total: Int)? {
        guard let index = stats.firstIndex(where: { $0.userId == userId }) else {
            return nil
        }

        return (rank: index + 1, total: stats.count)
    }

    private static func percentile(rank: Int, total: Int) -> Int? {
        guard total > 0 else { return nil }
        let percentile = Int(ceil((Double(rank) / Double(total)) * 100))
        return min(max(percentile, 1), 100)
    }

    private static let rankRefreshMinimumInterval: TimeInterval = 5 * 60

    private struct RankRequest: Equatable {
        let userId: String
        let periodKey: String
        let totalSteps: Int
        let totalDuration: TimeInterval
        let lastUpdated: Date
    }

    private struct LeaderboardStatsSnapshot: Sendable {
        let userId: String
        let displayName: String
        let photoURLString: String?
        let timeFrame: String
        let schemaVersion: Int
        let periodKey: String
        let periodStartAt: Date
        let totalSteps: Int
        let totalFloors: Int
        let totalWorkouts: Int
        let totalDuration: TimeInterval
        let stepsPerMinute: Double
        let lastUpdated: Date

        init(
            localStats: LeaderboardStats,
            userId: String,
            displayName: String,
            photoURLString: String?
        ) {
            self.userId = userId
            self.displayName = displayName
            self.photoURLString = photoURLString
            self.timeFrame = localStats.timeFrameEnum.rawValue
            self.schemaVersion = localStats.schemaVersion
            self.periodKey = localStats.periodKey
            self.periodStartAt = localStats.periodStartAt
            self.totalSteps = localStats.totalSteps
            self.totalFloors = localStats.totalFloors
            self.totalWorkouts = localStats.totalWorkouts
            self.totalDuration = localStats.totalDuration
            self.stepsPerMinute = localStats.stepsPerMinute
            self.lastUpdated = localStats.lastUpdated
        }

        func firestoreStats(existing: FirestoreLeaderboardStats?) -> FirestoreLeaderboardStats {
            FirestoreLeaderboardStats(
                userId: userId,
                displayName: displayName.isEmpty ? (existing?.displayName ?? "You") : displayName,
                photoURL: photoURLString ?? existing?.photoURL,
                timeFrame: timeFrame,
                schemaVersion: schemaVersion,
                periodKey: periodKey,
                periodStartAt: periodStartAt,
                totalSteps: totalSteps,
                totalFloors: totalFloors,
                totalWorkouts: totalWorkouts,
                totalDuration: totalDuration,
                stepsPerMinute: stepsPerMinute,
                lastUpdated: max(existing?.lastUpdated ?? lastUpdated, lastUpdated)
            )
        }
    }
}
