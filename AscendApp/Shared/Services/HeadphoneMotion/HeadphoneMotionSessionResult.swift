import Foundation

enum HeadphoneMotionSessionStopReason: String, Codable, Sendable {
    case userStopped = "user_stopped"
    case targetReached = "target_reached"
    /// The session ran to the end of its plan, but the climber skipped ahead of at least one
    /// segment instead of stepping through it, so it logs the steps really taken without
    /// standing as a completion. See `earnsCompetitiveCredit`.
    case skipped = "skipped"
    case discarded = "discarded"
    case interrupted = "interrupted"

    /// The single definition of whether a routine session counted, so the participation record
    /// and the summary UI must both read this rather than re-deriving a verdict that could
    /// disagree. A climb attempt does not use it: `LiveClimbCompletionPolicy` owns that finish
    /// and reads steps against the target, never a stop reason.
    var earnsCompetitiveCredit: Bool {
        self == .targetReached
    }
}

enum HeadphoneMotionWorkoutTrackingMode: String, Codable, Sendable {
    case liveClimb = "live_climb"
    case justClimb = "just_climb"
    case routine = "routine"
}

struct HeadphoneMotionSessionResumeState: Equatable, Sendable {
    let startedAt: Date
    let duration: TimeInterval
    let steps: Int
    let sampleCount: Int
    let trackingIntegrity: HeadphoneMotionTrackingIntegrity
    let stepCorrections: [HeadphoneMotionStepCorrection]

    init(
        startedAt: Date,
        duration: TimeInterval,
        steps: Int,
        sampleCount: Int,
        trackingIntegrity: HeadphoneMotionTrackingIntegrity = .verified,
        stepCorrections: [HeadphoneMotionStepCorrection] = []
    ) {
        self.startedAt = startedAt
        self.duration = max(duration, 0)
        self.steps = max(steps, 0)
        self.sampleCount = max(sampleCount, 0)
        self.trackingIntegrity = trackingIntegrity
        self.stepCorrections = stepCorrections
    }
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
        // Rounded to a hundredth of a second: `Workout.sourceMetadata` is bounded to 4000 chars
        // server-side (`firestore.rules`), and an unrounded `TimeInterval` from date/interval
        // math can carry a dozen-plus insignificant digits - real budget lost to precision
        // nobody reads.
        self.trackingGapDurationSeconds = (max(trackingGapDurationSeconds, 0) * 100).rounded() / 100
        self.totalUnavailableDurationSeconds = (max(totalUnavailableDurationSeconds, 0) * 100).rounded() / 100
        self.interruptionCount = max(interruptionCount, 0)
    }
}

struct HeadphoneMotionResolvedTrackingGap: Equatable, Sendable {
    let duration: TimeInterval
    let interruptionCount: Int

    init(duration: TimeInterval, interruptionCount: Int) {
        self.duration = max(duration, 0)
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
    /// Every raw motion sample and detected step the algorithm saw this session, for step-
    /// accuracy debugging - see `HeadphoneMotionRawCapture` and
    /// `StepAccuracyRawCaptureRetentionPolicy`. `nil` only when the session produced no motion
    /// samples at all (e.g. a session that never started recording).
    let rawCapture: HeadphoneMotionRawCapture?

    init(
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        steps: Int,
        sampleCount: Int,
        stopReason: HeadphoneMotionSessionStopReason,
        trackingIntegrity: HeadphoneMotionTrackingIntegrity = .verified,
        stepCorrections: [HeadphoneMotionStepCorrection] = [],
        rawCapture: HeadphoneMotionRawCapture? = nil
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.steps = steps
        self.sampleCount = sampleCount
        self.stopReason = stopReason
        self.trackingIntegrity = trackingIntegrity
        self.stepCorrections = stepCorrections
        self.rawCapture = rawCapture
    }

    var hasRecordedSteps: Bool {
        steps > 0
    }
}

struct HeadphoneMotionWorkoutMetadata: Codable, Equatable, Sendable {
    /// The `source` marker every headphone-motion workout carries. Shared with the legacy-completion
    /// predicate so both read the same constant instead of a scattered literal.
    static let headphoneMotionSource = "headphone_motion"

    let source: String
    let algorithmVersion: Int
    let sampleRateAssumptionHz: Int
    let sampleCount: Int
    let trackingMode: HeadphoneMotionWorkoutTrackingMode?
    let climbId: String?
    let routineId: String?
    let routineTemplateId: String?
    /// How many intervals the routine held when this session ran, frozen here so
    /// a later edit to the routine cannot rewrite what the session did.
    let routineIntervalCount: Int?
    let targetStepCount: Int?
    let climbTargetStepCount: Int?
    let targetDurationSeconds: TimeInterval?
    /// Normalized against the step target once a session is saved. See `LiveClimbCompletionPolicy`.
    var stopReason: HeadphoneMotionSessionStopReason
    let splitIntervalSeconds: Int?
    let splitSteps: [Int]?
    let trackingUnavailableDurationSeconds: TimeInterval?
    let longestTrackingUnavailableDurationSeconds: TimeInterval?
    let trackingInterruptionCount: Int?
    private(set) var stepCorrections: [HeadphoneMotionStepCorrection]?
    let heartRateCoverage: HeartRateTraceCoverage?

    // MARK: - Step accuracy telemetry
    //
    // All optional (rather than defaulted non-optionals) so a `sourceMetadata` string persisted
    // before these fields existed still decodes cleanly - Swift's synthesized `Decodable`
    // requires a key to be present only when the property is non-optional.

    /// The connected audio output when recording began - the headphone that actually drove step
    /// detection for a session with no mid-climb change. `nil` only for a `sourceMetadata`
    /// payload written before this field existed.
    private(set) var headphoneRouteAtStart: HeadphoneAudioRouteSnapshot?
    /// The connected audio output at the moment this climb was saved. Captured a second time,
    /// alongside `headphoneRouteAtStart` rather than instead of it, because a save-time-only read
    /// misattributes exactly the climbs this telemetry most needs to explain - one where
    /// headphones disconnected or switched mid-climb reports whatever was connected at the end,
    /// not what produced the motion samples.
    private(set) var headphoneRouteAtSave: HeadphoneAudioRouteSnapshot?
    /// Apple's own signal (`CMHeadphoneMotionManager.isDeviceMotionAvailable`) for whether a
    /// motion-capable headphone was connected when recording began, read via
    /// `HeadphoneMotionReadinessService`.
    let isMotionCapableHeadphoneConnectedAtStart: Bool?
    /// The same signal read again at save time, for the same reason `headphoneRouteAtSave` is
    /// captured alongside `headphoneRouteAtStart`.
    let isMotionCapableHeadphoneConnectedAtSave: Bool?
    /// Whether headphone motion samples actually arrived during the session - the strongest
    /// quality signal, since availability alone doesn't guarantee data flowed.
    let didHeadphoneMotionDataFlow: Bool?
    /// Whether the classified family differs between start and save - a mid-climb disconnect or
    /// swap surfaced as its own signal, rather than left implicit in two separate fields a reader
    /// has to compare by hand. Computed, not stored: it can never drift out of sync with the two
    /// snapshots it derives from, and costs nothing in `jsonString`.
    var didHeadphoneChangeDuringClimb: Bool? {
        guard let start = headphoneRouteAtStart?.family, let save = headphoneRouteAtSave?.family else {
            return nil
        }
        return start != save
    }
    /// The step count the climber's stair-stepper machine displayed, entered through the
    /// optional post-climb calibration prompt. Set after the workout is first saved, so this
    /// is the one field on this struct mutated post-hoc (`var`, like `stopReason`).
    var machineReportedSteps: Int?
    /// `abs(machineReportedSteps - <app steps at calibration time>)`.
    var stepDiscrepancyAbs: Int?
    /// `stepDiscrepancyAbs / machineReportedSteps * 100`, signed by which side over-counted -
    /// positive means the app counted more than the machine, negative means it undercounted.
    var stepDiscrepancyPercent: Double?

    /// Whether headphone motion tracked without a single interruption for the whole climb - the
    /// signal that separates a genuine algorithm miss from a disconnection-explained one. `nil`
    /// for a payload written before tracking-integrity fields existed, which
    /// `StepAccuracyRawCaptureRetentionPolicy` treats as "not proven connected" rather than
    /// guessing either way.
    var wasHeadphoneConnectedThroughoutClimb: Bool? {
        guard let trackingInterruptionCount, let didHeadphoneMotionDataFlow else { return nil }
        return trackingInterruptionCount == 0 && didHeadphoneMotionDataFlow
    }

    init(
        sampleCount: Int,
        trackingMode: HeadphoneMotionWorkoutTrackingMode = .liveClimb,
        climbId: String?,
        routineId: String? = nil,
        routineTemplateId: String? = nil,
        routineIntervalCount: Int? = nil,
        targetStepCount: Int?,
        climbTargetStepCount: Int? = nil,
        targetDurationSeconds: TimeInterval? = nil,
        stopReason: HeadphoneMotionSessionStopReason,
        splitCurve: LiveReplaySplitCurve? = nil,
        trackingIntegrity: HeadphoneMotionTrackingIntegrity = .verified,
        stepCorrections: [HeadphoneMotionStepCorrection] = [],
        heartRateCoverage: HeartRateTraceCoverage? = nil,
        headphoneRouteAtStart: HeadphoneAudioRouteSnapshot? = nil,
        headphoneRouteAtSave: HeadphoneAudioRouteSnapshot? = nil,
        isMotionCapableHeadphoneConnectedAtStart: Bool? = nil,
        isMotionCapableHeadphoneConnectedAtSave: Bool? = nil,
        didHeadphoneMotionDataFlow: Bool? = nil
    ) {
        self.source = HeadphoneMotionWorkoutMetadata.headphoneMotionSource
        self.algorithmVersion = HeadphoneMotionStepDetector.algorithmVersion
        self.sampleRateAssumptionHz = 50
        self.sampleCount = sampleCount
        self.trackingMode = trackingMode
        self.climbId = climbId
        self.routineId = routineId
        self.routineTemplateId = routineTemplateId
        self.routineIntervalCount = routineIntervalCount
        self.targetStepCount = targetStepCount
        self.climbTargetStepCount = climbTargetStepCount
        self.targetDurationSeconds = targetDurationSeconds.map { (($0 * 100).rounded()) / 100 }
        self.stopReason = stopReason
        self.splitIntervalSeconds = splitCurve?.intervalSeconds
        self.splitSteps = splitCurve?.steps
        self.trackingUnavailableDurationSeconds = ((trackingIntegrity.totalUnavailableDuration * 100).rounded()) / 100
        self.longestTrackingUnavailableDurationSeconds =
            ((trackingIntegrity.longestUnavailableDuration * 100).rounded()) / 100
        self.trackingInterruptionCount = trackingIntegrity.interruptionCount
        // `sourceMetadata` is bounded to 4000 chars server-side (`firestore.rules`), and a
        // session with a flaky Bluetooth connection can accumulate many corrections - keeping
        // only the most recent bounds the worst case without losing what happened near the end
        // of the climb, the part most relevant to how it actually finished.
        self.stepCorrections = stepCorrections.isEmpty ? nil : Array(stepCorrections.suffix(20))
        self.heartRateCoverage = heartRateCoverage
        self.headphoneRouteAtStart = headphoneRouteAtStart
        self.headphoneRouteAtSave = headphoneRouteAtSave
        self.isMotionCapableHeadphoneConnectedAtStart = isMotionCapableHeadphoneConnectedAtStart
        self.isMotionCapableHeadphoneConnectedAtSave = isMotionCapableHeadphoneConnectedAtSave
        self.didHeadphoneMotionDataFlow = didHeadphoneMotionDataFlow
        self.machineReportedSteps = nil
        self.stepDiscrepancyAbs = nil
        self.stepDiscrepancyPercent = nil
    }

    /// The encoded form stored in `Workout.sourceMetadata`. `firestore.rules` refuses a string
    /// longer than `WorkoutRemoteSyncLimits.maximumSourceMetadataLength`, so an oversized payload
    /// sheds its least essential detail first - the start-time raw headphone name, then the
    /// save-time one, then the oldest step corrections - rather than producing a workout the
    /// server rejects forever. The classified `family` on each snapshot survives every round, so
    /// `didHeadphoneChangeDuringClimb` still resolves even once both raw names are gone.
    var jsonString: String? {
        var candidate = self
        while true {
            guard let encoded = candidate.encodedJSONString else { return nil }
            if encoded.utf8.count <= WorkoutRemoteSyncLimits.maximumSourceMetadataLength {
                return encoded
            }
            if let route = candidate.headphoneRouteAtStart, route.rawPortName != nil {
                candidate.headphoneRouteAtStart = route.withoutRawPortName
            } else if let route = candidate.headphoneRouteAtSave, route.rawPortName != nil {
                candidate.headphoneRouteAtSave = route.withoutRawPortName
            } else if let corrections = candidate.stepCorrections, !corrections.isEmpty {
                let remaining = corrections.dropFirst()
                candidate.stepCorrections = remaining.isEmpty ? nil : Array(remaining)
            } else {
                return encoded
            }
        }
    }

    private var encodedJSONString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The symmetric read for `jsonString`, tolerant of a payload written before any of the
    /// step-accuracy fields existed - every field added since is optional for exactly that
    /// reason. Returns `nil` for a workout that never carried headphone-motion metadata at all
    /// (a legacy source, or a malformed string).
    static func decode(from jsonString: String?) -> HeadphoneMotionWorkoutMetadata? {
        guard let jsonString, let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HeadphoneMotionWorkoutMetadata.self, from: data)
    }

    /// Applies a machine-entered step count read after the climb was already saved, computing
    /// the discrepancy against the app's own count at that moment. Never touches `Workout.steps`
    /// itself - this is calibration data for the algorithm, not a correction to the climber's
    /// recorded result.
    mutating func applyMachineStepCalibration(machineReportedSteps: Int, appSteps: Int) {
        self.machineReportedSteps = machineReportedSteps
        let discrepancy = appSteps - machineReportedSteps
        self.stepDiscrepancyAbs = abs(discrepancy)
        guard machineReportedSteps > 0 else {
            self.stepDiscrepancyPercent = nil
            return
        }
        let percent = (Double(discrepancy) / Double(machineReportedSteps)) * 100
        self.stepDiscrepancyPercent = (percent * 10).rounded() / 10
    }
}
