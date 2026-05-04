import Foundation

enum HeadphoneMotionSessionStopReason: String, Codable, Sendable {
    case userStopped = "user_stopped"
    case targetReached = "target_reached"
    case discarded = "discarded"
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
    let climbId: String?
    let targetStepCount: Int?
    let stopReason: HeadphoneMotionSessionStopReason
    let splitIntervalSeconds: Int?
    let splitSteps: [Int]?

    init(
        sampleCount: Int,
        climbId: String?,
        targetStepCount: Int?,
        stopReason: HeadphoneMotionSessionStopReason,
        splitCurve: LiveReplaySplitCurve? = nil
    ) {
        self.source = "headphone_motion"
        self.algorithmVersion = HeadphoneMotionStepDetector.algorithmVersion
        self.sampleRateAssumptionHz = 50
        self.sampleCount = sampleCount
        self.climbId = climbId
        self.targetStepCount = targetStepCount
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
