import Foundation

struct FirestoreWorkoutParticipationMetricsSnapshot: Codable, Equatable, Sendable {
    let startedAt: Date
    let durationSeconds: Double
    let steps: Int
    let floors: Int
    let stepsPerMinute: Double
}

struct FirestoreWorkoutParticipation: Codable, Equatable, Sendable {
    let id: String
    let workoutId: String
    let userId: String
    let contextType: String
    let contextId: String
    let contextVersion: Int
    let rulesVersion: Int
    let role: String
    let leaderboardEligible: Bool
    let verificationTier: String
    let metricsSnapshot: FirestoreWorkoutParticipationMetricsSnapshot
    let createdAt: Date
}
