import Foundation
import SwiftData

enum WorkoutParticipationContextType: String, CaseIterable, Codable, Sendable {
    case routineTemplate = "routine_template"
    case routine = "routine"
    case climbAttempt = "climb_attempt"
    case challenge = "challenge"
    case groupChallenge = "group_challenge"
    case programSession = "program_session"
    case achievement = "achievement"
}

enum WorkoutParticipationRole: String, CaseIterable, Codable, Sendable {
    case primary = "primary"
    case secondary = "secondary"
    case passiveEarned = "passive_earned"
}

enum WorkoutParticipationVerificationTier: String, CaseIterable, Codable, Sendable {
    case unverified = "unverified"
    case providerVerified = "provider_verified"
    case sensorVerified = "sensor_verified"
}

struct WorkoutParticipationMetricsSnapshot: Codable, Equatable, Sendable {
    let startedAt: Date
    let durationSeconds: Double
    let steps: Int
    let floors: Int
    let stepsPerMinute: Double

    init(workout: Workout) {
        startedAt = workout.date
        durationSeconds = workout.duration
        steps = workout.steps
        floors = workout.floors
        stepsPerMinute = workout.duration > 0
            ? Double(workout.steps) / (workout.duration / 60.0)
            : 0
    }
}

@Model
final class WorkoutParticipation {
    var id: UUID
    var workoutId: UUID
    var userId: String?
    var contextTypeRawValue: String
    var contextId: String
    var contextVersion: Int
    var rulesVersion: Int
    var roleRawValue: String
    var leaderboardEligible: Bool
    var verificationTierRawValue: String
    var metricsSnapshotData: Data?
    var createdAt: Date
    var workout: Workout?

    var contextType: WorkoutParticipationContextType {
        get { WorkoutParticipationContextType(rawValue: contextTypeRawValue) ?? .routine }
        set { contextTypeRawValue = newValue.rawValue }
    }

    var role: WorkoutParticipationRole {
        get { WorkoutParticipationRole(rawValue: roleRawValue) ?? .primary }
        set { roleRawValue = newValue.rawValue }
    }

    var verificationTier: WorkoutParticipationVerificationTier {
        get { WorkoutParticipationVerificationTier(rawValue: verificationTierRawValue) ?? .unverified }
        set { verificationTierRawValue = newValue.rawValue }
    }

    var metricsSnapshot: WorkoutParticipationMetricsSnapshot? {
        get {
            guard let metricsSnapshotData else { return nil }
            return try? JSONDecoder().decode(WorkoutParticipationMetricsSnapshot.self, from: metricsSnapshotData)
        }
        set {
            if let newValue {
                metricsSnapshotData = try? JSONEncoder().encode(newValue)
            } else {
                metricsSnapshotData = nil
            }
        }
    }

    init(
        id: UUID = UUID(),
        workout: Workout,
        userId: String?,
        contextType: WorkoutParticipationContextType,
        contextId: String,
        contextVersion: Int = 1,
        rulesVersion: Int = 1,
        role: WorkoutParticipationRole = .primary,
        leaderboardEligible: Bool,
        verificationTier: WorkoutParticipationVerificationTier,
        metricsSnapshot: WorkoutParticipationMetricsSnapshot? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workoutId = workout.id
        self.userId = userId
        self.contextTypeRawValue = contextType.rawValue
        self.contextId = contextId
        self.contextVersion = contextVersion
        self.rulesVersion = rulesVersion
        self.roleRawValue = role.rawValue
        self.leaderboardEligible = leaderboardEligible
        self.verificationTierRawValue = verificationTier.rawValue
        self.createdAt = createdAt
        self.workout = workout
        self.metricsSnapshot = metricsSnapshot ?? WorkoutParticipationMetricsSnapshot(workout: workout)
    }
}

extension WorkoutParticipationVerificationTier {
    static func sourceDefault(for source: WorkoutSource) -> WorkoutParticipationVerificationTier {
        switch source {
        case .manual:
            return .unverified
        case .headphoneMotion:
            return .sensorVerified
        case .appleHealth, .garmin, .strava, .fitbit, .hevy:
            return .providerVerified
        }
    }
}
