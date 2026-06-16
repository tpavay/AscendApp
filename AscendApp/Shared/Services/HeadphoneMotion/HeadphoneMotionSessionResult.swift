import Foundation

enum HeadphoneMotionSessionStopReason: String, Codable, Sendable {
    case userStopped = "user_stopped"
    case targetReached = "target_reached"
    case discarded = "discarded"
}

enum HeadphoneMotionWorkoutTrackingMode: String, Codable, Sendable {
    case liveClimb = "live_climb"
    case justClimb = "just_climb"
}

struct HeadphoneMotionStepCorrection: Codable, Equatable, Sendable {
    let elapsedSeconds: Int
    let detectedSteps: Int
    let correctedSteps: Int
    let deltaSteps: Int
    let trackingGapDurationSeconds: TimeInterval
    let totalUnavailableDurationSeconds: TimeInterval
    let interruptionCount: Int

    init(
        elapsedSeconds: Int,
        detectedSteps: Int,
        correctedSteps: Int,
        deltaSteps: Int,
        trackingGapDurationSeconds: TimeInterval,
        totalUnavailableDurationSeconds: TimeInterval,
        interruptionCount: Int
    ) {
        self.elapsedSeconds = max(elapsedSeconds, 0)
        self.detectedSteps = max(detectedSteps, 0)
        self.correctedSteps = max(correctedSteps, 0)
        self.deltaSteps = deltaSteps
        self.trackingGapDurationSeconds = max(trackingGapDurationSeconds, 0)
        self.totalUnavailableDurationSeconds = max(totalUnavailableDurationSeconds, 0)
        self.interruptionCount = max(interruptionCount, 0)
    }
}

struct HeadphoneMotionSessionResult: Equatable, Sendable {
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let steps: Int
    let sampleCount: Int
    let stopReason: HeadphoneMotionSessionStopReason
    let trackingIntegrity: HeadphoneMotionTrackingIntegrity
    let stepCorrections: [HeadphoneMotionStepCorrection]

    init(
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        steps: Int,
        sampleCount: Int,
        stopReason: HeadphoneMotionSessionStopReason,
        trackingIntegrity: HeadphoneMotionTrackingIntegrity = .verified,
        stepCorrections: [HeadphoneMotionStepCorrection] = []
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.steps = steps
        self.sampleCount = sampleCount
        self.stopReason = stopReason
        self.trackingIntegrity = trackingIntegrity
        self.stepCorrections = stepCorrections
    }

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
    let targetDurationSeconds: TimeInterval?
    let stopReason: HeadphoneMotionSessionStopReason
    let splitIntervalSeconds: Int?
    let splitSteps: [Int]?
    let trackingUnavailableDurationSeconds: TimeInterval?
    let longestTrackingUnavailableDurationSeconds: TimeInterval?
    let trackingInterruptionCount: Int?
    let stepCorrections: [HeadphoneMotionStepCorrection]?

    init(
        sampleCount: Int,
        trackingMode: HeadphoneMotionWorkoutTrackingMode = .liveClimb,
        climbId: String?,
        targetStepCount: Int?,
        climbTargetStepCount: Int? = nil,
        targetDurationSeconds: TimeInterval? = nil,
        stopReason: HeadphoneMotionSessionStopReason,
        splitCurve: LiveReplaySplitCurve? = nil,
        trackingIntegrity: HeadphoneMotionTrackingIntegrity = .verified,
        stepCorrections: [HeadphoneMotionStepCorrection] = []
    ) {
        self.source = "headphone_motion"
        self.algorithmVersion = HeadphoneMotionStepDetector.algorithmVersion
        self.sampleRateAssumptionHz = 50
        self.sampleCount = sampleCount
        self.trackingMode = trackingMode
        self.climbId = climbId
        self.targetStepCount = targetStepCount
        self.climbTargetStepCount = climbTargetStepCount
        self.targetDurationSeconds = targetDurationSeconds
        self.stopReason = stopReason
        self.splitIntervalSeconds = splitCurve?.intervalSeconds
        self.splitSteps = splitCurve?.steps
        self.trackingUnavailableDurationSeconds = trackingIntegrity.totalUnavailableDuration
        self.longestTrackingUnavailableDurationSeconds = trackingIntegrity.longestUnavailableDuration
        self.trackingInterruptionCount = trackingIntegrity.interruptionCount
        self.stepCorrections = stepCorrections.isEmpty ? nil : stepCorrections
    }

    var jsonString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
