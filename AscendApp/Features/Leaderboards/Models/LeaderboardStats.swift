import Foundation
import SwiftData

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
