import Foundation

enum HeadphoneMotionSessionStopReason: String, Codable, Sendable {
    case userStopped = "user_stopped"
    case targetReached = "target_reached"
    case discarded = "discarded"
}

enum HeadphoneMotionWorkoutTrackingMode: String, Codable, Sendable {
    case liveClimb = "live_climb"
    case legacyOpenTracking = "just_climb"
}

struct HeadphoneMotionSessionResult: Equatable, Sendable {
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let steps: Int
    let sampleCount: Int
    let stopReason: HeadphoneMotionSessionStopReason

    var hasRecordedSteps: Bool {
        steps > 0
    }
}

struct HeadphoneMotionWorkoutMetadata: Codable, Equatable, Sendable {
    let source: String
    let algorithmVersion: Int
    let sampleRateAssumptionHz: Int
    let sampleCount: Int
    let trackingMode: HeadphoneMotionWorkoutTrackingMode?
    let climbId: String?
    let targetStepCount: Int?
    let climbTargetStepCount: Int?
    let stopReason: HeadphoneMotionSessionStopReason
    let splitIntervalSeconds: Int?
    let splitSteps: [Int]?

    init(
        sampleCount: Int,
        trackingMode: HeadphoneMotionWorkoutTrackingMode = .liveClimb,
        climbId: String?,
        targetStepCount: Int?,
        climbTargetStepCount: Int? = nil,
        stopReason: HeadphoneMotionSessionStopReason,
        splitCurve: LiveReplaySplitCurve? = nil
    ) {
        self.source = "headphone_motion"
        self.algorithmVersion = HeadphoneMotionStepDetector.algorithmVersion
        self.sampleRateAssumptionHz = 50
        self.sampleCount = sampleCount
        self.trackingMode = trackingMode
        self.climbId = climbId
        self.targetStepCount = targetStepCount
        self.climbTargetStepCount = climbTargetStepCount
        self.stopReason = stopReason
        self.splitIntervalSeconds = splitCurve?.intervalSeconds
        self.splitSteps = splitCurve?.steps
    }

    var jsonString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
