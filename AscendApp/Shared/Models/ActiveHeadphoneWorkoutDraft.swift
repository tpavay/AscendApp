import Foundation
import SwiftData

enum ActiveHeadphoneWorkoutDraftKind: String, Codable, Sendable {
    case liveClimb = "live_climb"
    case justClimb = "just_climb"
    case routine = "routine"
}

enum ActiveHeadphoneWorkoutDraftStatus: String, Codable, Sendable {
    case recording = "recording"
    case stopped = "stopped"
}

@Model
final class ActiveHeadphoneWorkoutDraft {
    var id: UUID
    var sessionID: String
    var kindRawValue: String
    var statusRawValue: String
    var createdAt: Date
    var startedAt: Date
    var lastCheckpointAt: Date
    var title: String
    var subtitle: String
    var workoutName: String
    var steps: Int
    var durationSeconds: TimeInterval
    var sampleCount: Int
    var targetStepCount: Int?
    var targetDurationSeconds: TimeInterval?
    var climbId: String?
    var justClimbGoalKindRawValue: String?
    var justClimbDurationMinutes: Int?
    var justClimbStepCount: Int?
    var routineId: UUID?
    var routineSourceRawValue: String?
    var routineTemplateId: String?
    var routineDifficulty: Int?
    var routineIntervalCount: Int?
    /// Checkpointed so a session resumed from this draft cannot launder away skips it already
    /// made and finish as a clean completion.
    var routineSkippedIntervalCount: Int?
    var routineWeightConfigurationData: Data?
    var splitCurveData: Data?
    var trackingIntegrityData: Data?
    var stepCorrectionsData: Data?
    var heartRateData: Data?

    var kind: ActiveHeadphoneWorkoutDraftKind {
        get { ActiveHeadphoneWorkoutDraftKind(rawValue: kindRawValue) ?? .justClimb }
        set { kindRawValue = newValue.rawValue }
    }

    var status: ActiveHeadphoneWorkoutDraftStatus {
        get { ActiveHeadphoneWorkoutDraftStatus(rawValue: statusRawValue) ?? .recording }
        set { statusRawValue = newValue.rawValue }
    }

    var splitCurve: LiveReplaySplitCurve? {
        get { Self.decode(LiveReplaySplitCurve.self, from: splitCurveData) }
        set { splitCurveData = Self.encode(newValue) }
    }

    var trackingIntegrity: HeadphoneMotionTrackingIntegrity {
        get { Self.decode(HeadphoneMotionTrackingIntegrity.self, from: trackingIntegrityData) ?? .verified }
        set { trackingIntegrityData = Self.encode(newValue) }
    }

    var stepCorrections: [HeadphoneMotionStepCorrection] {
        get { Self.decode([HeadphoneMotionStepCorrection].self, from: stepCorrectionsData) ?? [] }
        set { stepCorrectionsData = Self.encode(newValue.isEmpty ? nil : newValue) }
    }

    var routineWeightConfiguration: WeightConfiguration? {
        get { WeightConfiguration.decode(from: routineWeightConfigurationData) }
        set { routineWeightConfigurationData = newValue?.encoded }
    }

    var heartRateSamples: [HeartRateDataPoint] {
        get { Self.decode([HeartRateDataPoint].self, from: heartRateData) ?? [] }
        set { heartRateData = Self.encode(newValue.isEmpty ? nil : newValue) }
    }

    var resumeState: HeadphoneMotionSessionResumeState {
        HeadphoneMotionSessionResumeState(
            startedAt: startedAt,
            duration: durationSeconds,
            steps: steps,
            sampleCount: sampleCount,
            trackingIntegrity: trackingIntegrity,
            stepCorrections: stepCorrections
        )
    }

    init(
        id: UUID = UUID(),
        sessionID: String,
        kind: ActiveHeadphoneWorkoutDraftKind,
        startedAt: Date = Date(),
        title: String,
        subtitle: String,
        workoutName: String,
        targetStepCount: Int?,
        targetDurationSeconds: TimeInterval?,
        climbId: String? = nil,
        justClimbGoalKind: JustClimbGoalKind? = nil,
        justClimbDurationMinutes: Int? = nil,
        justClimbStepCount: Int? = nil,
        routineId: UUID? = nil,
        routineSource: RoutineSource? = nil,
        routineTemplateId: String? = nil,
        routineDifficulty: Int? = nil,
        routineIntervalCount: Int? = nil,
        routineWeightConfiguration: WeightConfiguration? = nil
    ) {
        let now = Date()
        self.id = id
        self.sessionID = sessionID
        self.kindRawValue = kind.rawValue
        self.statusRawValue = ActiveHeadphoneWorkoutDraftStatus.recording.rawValue
        self.createdAt = now
        self.startedAt = startedAt
        self.lastCheckpointAt = now
        self.title = title
        self.subtitle = subtitle
        self.workoutName = workoutName
        self.steps = 0
        self.durationSeconds = 0
        self.sampleCount = 0
        self.targetStepCount = targetStepCount
        self.targetDurationSeconds = targetDurationSeconds
        self.climbId = climbId
        self.justClimbGoalKindRawValue = justClimbGoalKind?.rawValue
        self.justClimbDurationMinutes = justClimbDurationMinutes
        self.justClimbStepCount = justClimbStepCount
        self.routineId = routineId
        self.routineSourceRawValue = routineSource?.rawValue
        self.routineTemplateId = routineTemplateId
        self.routineDifficulty = routineDifficulty
        self.routineIntervalCount = routineIntervalCount
        self.routineSkippedIntervalCount = nil
        self.routineWeightConfiguration = routineWeightConfiguration
        self.heartRateData = nil
        self.trackingIntegrity = .verified
        self.stepCorrections = []
    }

    func applyCheckpoint(
        steps: Int,
        durationSeconds: TimeInterval,
        sampleCount: Int,
        splitCurve: LiveReplaySplitCurve?,
        trackingIntegrity: HeadphoneMotionTrackingIntegrity,
        stepCorrections: [HeadphoneMotionStepCorrection],
        heartRateSamples: [HeartRateDataPoint]? = nil,
        status: ActiveHeadphoneWorkoutDraftStatus = .recording,
        skippedIntervalCount: Int? = nil,
        checkpointedAt: Date = Date()
    ) {
        self.steps = max(steps, 0)
        self.durationSeconds = max(durationSeconds, 0)
        self.sampleCount = max(sampleCount, 0)
        self.splitCurve = splitCurve
        self.trackingIntegrity = trackingIntegrity
        self.stepCorrections = stepCorrections
        if let heartRateSamples {
            self.heartRateSamples = heartRateSamples
        }
        self.status = status
        if let skippedIntervalCount {
            self.routineSkippedIntervalCount = max(skippedIntervalCount, 0)
        }
        self.lastCheckpointAt = checkpointedAt
    }

    private static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension ActiveHeadphoneWorkoutDraft {
    var diagnosticDetails: [String: String] {
        var details: [String: String] = [
            "draft_id": id.uuidString,
            "session_id": sessionID,
            "kind": kind.rawValue,
            "status": status.rawValue,
            "steps": String(steps),
            "duration_seconds": String(Int(durationSeconds.rounded(.down))),
            "sample_count": String(sampleCount),
            "heart_rate_sample_count": String(heartRateSamples.count),
            "checkpoint_age_seconds": String(max(0, Int(Date().timeIntervalSince(lastCheckpointAt).rounded(.down))))
        ]

        if let climbId {
            details["climb_id"] = climbId
        }
        if let routineId {
            details["routine_id"] = routineId.uuidString
        }
        if let targetStepCount {
            details["target_steps"] = String(targetStepCount)
        }
        if let targetDurationSeconds {
            details["target_duration_seconds"] = String(Int(targetDurationSeconds.rounded(.down)))
        }

        return details
    }
}
