import Foundation
import SwiftData

/// The device's own aggregate for each open board window.
///
/// This is a **display-only optimistic cache**, not a standing. The standing lives in
/// `leaderboard_stats`, is derived server-side from the backed-up workouts
/// (`functions/src/leaderboardStats.ts`), and no client can write it. What this buys is
/// that a climber sees the session they just finished immediately, before the derivation
/// has run - `LeaderboardCurrentUserReconciler` overlays it onto the fetched board.
@Model
final class LeaderboardStats {
    static let currentSchemaVersion = 2

    var id: UUID
    var userId: String
    var timeFrame: String
    var periodIdentifier: String
    var periodStartAt: Date
    var schemaVersion: Int

    var totalSteps: Int
    var totalFloors: Int
    var totalWorkouts: Int
    var totalDuration: TimeInterval
    var averageStepsPerMinute: Double
    var averageFloorsPerMinute: Double

    var lastUpdated: Date

    /// Vestigial: bookkeeping for the device-side publish path that issue #307 removed.
    /// Still written, never read. Dropping them is a stored-shape change, so it needs a
    /// `VersionedSchema` and a stage in `AscendMigrationPlan` (see `ascend-data-migration`)
    /// - deliberately not folded into a security fix. Remove by 2026-11-01, or with the
    /// next migration that touches this model, whichever comes first.
    var lastSyncedToFirestore: Date?
    var needsSync: Bool

    init(
        userId: String,
        timeFrame: LeaderboardTimeFrame,
        period: LeaderboardPeriod,
        totalSteps: Int = 0,
        totalFloors: Int = 0,
        totalWorkouts: Int = 0,
        totalDuration: TimeInterval = 0,
        stepsPerMinute: Double = 0
    ) {
        self.id = UUID()
        self.userId = userId
        self.timeFrame = timeFrame.rawValue
        self.periodIdentifier = period.key
        self.periodStartAt = period.startAt
        self.schemaVersion = Self.currentSchemaVersion
        self.totalSteps = totalSteps
        self.totalFloors = totalFloors
        self.totalWorkouts = totalWorkouts
        self.totalDuration = totalDuration
        self.averageStepsPerMinute = stepsPerMinute
        self.averageFloorsPerMinute = 0
        self.lastUpdated = Date()
        self.lastSyncedToFirestore = nil
        self.needsSync = true
    }

    var timeFrameEnum: LeaderboardTimeFrame {
        LeaderboardTimeFrame(rawValue: timeFrame) ?? .allTime
    }

    var periodKey: String {
        get { periodIdentifier }
        set { periodIdentifier = newValue }
    }

    var stepsPerMinute: Double {
        get { averageStepsPerMinute }
        set { averageStepsPerMinute = newValue }
    }

    var hasActivity: Bool {
        totalWorkouts > 0 || totalSteps > 0 || totalFloors > 0 || totalDuration > 0
    }

    func replaceTotals(with aggregate: LeaderboardAggregate, period: LeaderboardPeriod, updatedAt: Date = Date()) {
        periodKey = period.key
        periodStartAt = period.startAt
        schemaVersion = Self.currentSchemaVersion
        totalSteps = aggregate.totalSteps
        totalFloors = aggregate.totalFloors
        totalWorkouts = aggregate.totalWorkouts
        totalDuration = aggregate.totalDuration
        stepsPerMinute = aggregate.stepsPerMinute
        averageFloorsPerMinute = aggregate.floorsPerMinute
        lastUpdated = updatedAt
        needsSync = true
    }

    func reset(for period: LeaderboardPeriod, updatedAt: Date = Date()) {
        replaceTotals(with: .zero, period: period, updatedAt: updatedAt)
    }

    func apply(delta: LeaderboardAggregate, period: LeaderboardPeriod, updatedAt: Date = Date()) {
        periodKey = period.key
        periodStartAt = period.startAt
        schemaVersion = Self.currentSchemaVersion
        totalSteps = max(0, totalSteps + delta.totalSteps)
        totalFloors = max(0, totalFloors + delta.totalFloors)
        totalWorkouts = max(0, totalWorkouts + delta.totalWorkouts)
        totalDuration = max(0, totalDuration + delta.totalDuration)

        let recalculated = LeaderboardAggregate(
            totalSteps: totalSteps,
            totalFloors: totalFloors,
            totalWorkouts: totalWorkouts,
            totalDuration: totalDuration
        )
        stepsPerMinute = recalculated.stepsPerMinute
        averageFloorsPerMinute = recalculated.floorsPerMinute
        lastUpdated = updatedAt
        needsSync = true
    }

    func value(for metric: LeaderboardMetric) -> Double {
        switch metric {
        case .climb:
            return Double(totalSteps)
        case .workouts:
            return Double(totalWorkouts)
        case .duration:
            return totalDuration
        case .pace:
            return stepsPerMinute
        }
    }
}
