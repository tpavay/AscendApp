import Foundation
import SwiftData

@MainActor
final class LeaderboardService {
    static let shared = LeaderboardService()

    private var modelContext: ModelContext?

    /// Callers reach the app-wide instance through `shared`. A separate instance exists so a
    /// caller that owns its own `ModelContext` - a test, chiefly - is not racing every other
    /// holder of the singleton's single context.
    init() {}

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func rebuildCurrentStatsIfNeeded(
        for userId: String,
        workouts: [Workout],
        referenceDate: Date = Date()
    ) throws -> Bool {
        if try needsCurrentSchemaRebuild(for: userId, referenceDate: referenceDate) == false {
            return false
        }

        try rebuildCurrentStats(for: userId, workouts: workouts, referenceDate: referenceDate)
        return true
    }

    func rebuildCurrentStats(
        for userId: String,
        workouts: [Workout],
        referenceDate: Date = Date()
    ) throws {
        let context = try requireContext()
        let existingStats = try fetchUserStats(for: userId)
        let ownedWorkouts = workouts.filter { $0.ownerUserId == userId }

        for stat in existingStats {
            context.delete(stat)
        }

        for timeFrame in LeaderboardTimeFrame.allCases {
            let period = timeFrame.currentPeriod(referenceDate: referenceDate)
            let aggregate = aggregate(for: timeFrame, workouts: ownedWorkouts, referenceDate: referenceDate)
            let stats = LeaderboardStats(userId: userId, timeFrame: timeFrame, period: period)
            stats.replaceTotals(with: aggregate, period: period, updatedAt: referenceDate)
            context.insert(stats)
        }

        try context.save()
    }

    func applyMutationImpact(
        _ impact: LeaderboardMutationImpact,
        for userId: String,
        referenceDate: Date = Date()
    ) throws -> Bool {
        guard impact != .none else { return false }

        let context = try requireContext()
        if impact == .rebuildAll {
            let workouts = try fetchWorkouts(for: userId)
            try rebuildCurrentStats(for: userId, workouts: workouts, referenceDate: referenceDate)
            return true
        }

        if try needsCurrentSchemaRebuild(for: userId, referenceDate: referenceDate) {
            let workouts = try fetchWorkouts(for: userId)
            try rebuildCurrentStats(for: userId, workouts: workouts, referenceDate: referenceDate)
            return true
        }

        let statsByTimeFrame = try currentStatsByTimeFrame(for: userId)
        var touchedStats = false

        if case .incremental(let changes) = impact {
            for timeFrame in LeaderboardTimeFrame.allCases {
                let period = timeFrame.currentPeriod(referenceDate: referenceDate)
                let stats = try ensureCurrentStats(
                    for: userId,
                    timeFrame: timeFrame,
                    period: period,
                    existing: statsByTimeFrame[timeFrame],
                    context: context,
                    updatedAt: referenceDate
                )

                var delta = LeaderboardAggregate.zero
                for change in changes {
                    if let before = change.before, period.contains(before.date, referenceDate: referenceDate) {
                        delta = delta - before.aggregate
                    }
                    if let after = change.after, period.contains(after.date, referenceDate: referenceDate) {
                        delta = delta + after.aggregate
                    }
                }

                // Only a real change counts. This used to also report "true" for a
                // stat still flagged `needsSync`, so the caller would run the publish
                // loop for it; nothing publishes from the device any more, so that
                // branch bought a Firestore refresh for an aggregate that had not
                // moved.
                if delta != .zero {
                    stats.apply(delta: delta, period: period, updatedAt: referenceDate)
                    touchedStats = true
                }
            }
        }

        if touchedStats {
            try context.save()
        }
        return touchedStats
    }

    func getLocalStats(
        for userId: String,
        timeFrame: LeaderboardTimeFrame
    ) throws -> LeaderboardStats? {
        let currentStats = try currentStatsByTimeFrame(for: userId)
        return currentStats[timeFrame]
    }

    // Publication used to live here. Standings are derived server-side now
    // (functions/src/leaderboardStats.ts) from the canonical workouts the app
    // already backs up, so what remains is the local display cache above.

    private func aggregate(
        for timeFrame: LeaderboardTimeFrame,
        workouts: [Workout],
        referenceDate: Date
    ) -> LeaderboardAggregate {
        workouts.reduce(into: .zero) { aggregate, workout in
            guard timeFrame.contains(workout.date, referenceDate: referenceDate) else { return }
            aggregate = aggregate + LeaderboardWorkoutSnapshot(workout: workout).aggregate
        }
    }

    private func needsCurrentSchemaRebuild(
        for userId: String,
        referenceDate: Date
    ) throws -> Bool {
        let stats = try fetchUserStats(for: userId)
        guard stats.count == LeaderboardTimeFrame.allCases.count else { return true }

        let grouped = Dictionary(grouping: stats, by: \.timeFrame)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { return true }

        for timeFrame in LeaderboardTimeFrame.allCases {
            guard let stat = stats.first(where: { $0.timeFrame == timeFrame.rawValue }) else {
                return true
            }

            let period = timeFrame.currentPeriod(referenceDate: referenceDate)
            if stat.schemaVersion != LeaderboardStats.currentSchemaVersion ||
                stat.periodKey != period.key ||
                stat.periodStartAt != period.startAt {
                return true
            }
        }

        return false
    }

    private func currentStatsByTimeFrame(for userId: String) throws -> [LeaderboardTimeFrame: LeaderboardStats] {
        let stats = try fetchUserStats(for: userId)
        var mapped: [LeaderboardTimeFrame: LeaderboardStats] = [:]

        for stat in stats {
            guard let timeFrame = LeaderboardTimeFrame(rawValue: stat.timeFrame) else { continue }
            mapped[timeFrame] = stat
        }

        return mapped
    }

    private func ensureCurrentStats(
        for userId: String,
        timeFrame: LeaderboardTimeFrame,
        period: LeaderboardPeriod,
        existing: LeaderboardStats?,
        context: ModelContext,
        updatedAt: Date
    ) throws -> LeaderboardStats {
        if let existing {
            if existing.schemaVersion != LeaderboardStats.currentSchemaVersion ||
                existing.periodKey != period.key ||
                existing.periodStartAt != period.startAt {
                existing.reset(for: period, updatedAt: updatedAt)
            }
            return existing
        }

        let stats = LeaderboardStats(userId: userId, timeFrame: timeFrame, period: period)
        stats.reset(for: period, updatedAt: updatedAt)
        context.insert(stats)
        return stats
    }

    private func fetchUserStats(for userId: String) throws -> [LeaderboardStats] {
        let context = try requireContext()
        let predicate = #Predicate<LeaderboardStats> { stats in
            stats.userId == userId
        }
        return try context.fetch(FetchDescriptor<LeaderboardStats>(predicate: predicate))
    }

    private func fetchWorkouts(for userId: String) throws -> [Workout] {
        let context = try requireContext()
        return try context.fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.ownerUserId == userId
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )
    }

    private func requireContext() throws -> ModelContext {
        guard let modelContext else {
            throw LeaderboardError.notConfigured
        }

        return modelContext
    }
}

enum LeaderboardError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Leaderboard service not configured with model context"
        }
    }
}
