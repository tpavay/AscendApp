import Foundation

struct LeaderboardSyncPayload: Equatable, Sendable {
    enum Operation: Equatable, Sendable {
        case upsert
        case delete
    }

    let localStatID: UUID
    let snapshotLastUpdated: Date
    let userId: String
    let displayName: String
    let photoURL: URL?
    let timeFrame: LeaderboardTimeFrame
    let schemaVersion: Int
    let periodKey: String
    let periodStartAt: Date
    let totalSteps: Int
    let totalFloors: Int
    let totalWorkouts: Int
    let totalDuration: Double
    let stepsPerMinute: Double
    let operation: Operation
}
