import Foundation

struct JustClimbAnalyticsContext: Sendable, Hashable {
    let goalKind: String
    let entryPoint: String
    let targetStepCount: Int?
    let targetDurationSeconds: Int?

    init(goal: JustClimbGoal, entryPoint: LiveClimbAnalyticsEvent.EntryPoint) {
        self.goalKind = goal.kind.rawValue
        self.entryPoint = entryPoint.rawValue
        self.targetStepCount = goal.targetStepCount
        self.targetDurationSeconds = goal.targetDuration.map { Int($0.rounded(.down)) }
    }
}

struct RoutineSessionAnalyticsContext: Sendable, Hashable {
    let routineID: String
    let routineSource: String
    let templateID: String?
    let hasDefaultWeights: Bool
    let difficulty: Int?
    let intervalCount: Int
    let targetDurationSeconds: Int
    let targetSteps: Int

    @MainActor
    init(routine: Routine, targetSteps: Int) {
        self.routineID = routine.id.uuidString
        self.routineSource = routine.source.rawValue
        self.templateID = routine.templateId
        self.hasDefaultWeights = routine.hasDefaultWeights
        self.difficulty = routine.difficulty
        self.intervalCount = routine.intervalCount
        self.targetDurationSeconds = Int(routine.totalDuration.rounded(.down))
        self.targetSteps = targetSteps
    }
}

enum WorkoutSessionAnalyticsEvent: TelemetryEvent {
    case justClimbStarted(context: JustClimbAnalyticsContext)
    case justClimbSaved(
        context: JustClimbAnalyticsContext,
        durationSeconds: Int,
        steps: Int,
        progressFraction: Double,
        stopReason: String,
        correctionCount: Int,
        trackingUnavailableSeconds: Int
    )
    case justClimbDiscarded(
        context: JustClimbAnalyticsContext,
        durationSeconds: Int,
        steps: Int,
        progressFraction: Double
    )
    case routineStarted(context: RoutineSessionAnalyticsContext)
    case routineCompleted(
        context: RoutineSessionAnalyticsContext,
        durationSeconds: Int,
        steps: Int,
        progressFraction: Double
    )
    case routineLogTapped(
        context: RoutineSessionAnalyticsContext,
        surface: RoutineSurface,
        durationSeconds: Int,
        steps: Int,
        progressFraction: Double
    )
    case routineSaved(
        context: RoutineSessionAnalyticsContext,
        durationSeconds: Int,
        steps: Int,
        progressFraction: Double
    )
    case routineDiscarded(
        context: RoutineSessionAnalyticsContext,
        surface: RoutineSurface,
        durationSeconds: Int,
        steps: Int,
        progressFraction: Double
    )

    var record: TelemetryRecord {
        switch self {
        case .justClimbStarted(let context):
            return TelemetryRecord(
                name: "just_climb_started",
                parameters: justClimbParameters(context)
            )

        case .justClimbSaved(
            let context,
            let durationSeconds,
            let steps,
            let progressFraction,
            let stopReason,
            let correctionCount,
            let trackingUnavailableSeconds
        ):
            var parameters = justClimbParameters(context)
            parameters["duration_bucket"] = .string(DurationBucket(durationSeconds).rawValue)
            parameters["steps_bucket"] = .string(CountBucket(steps).rawValue)
            parameters["progress_bucket"] = .string(ProgressBucket(progressFraction).rawValue)
            parameters["stop_reason"] = .string(stopReason)
            parameters["correction_count_bucket"] = .string(CountBucket(correctionCount).rawValue)
            parameters["had_step_corrections"] = .bool(correctionCount > 0)
            parameters["tracking_unavailable_bucket"] = .string(DurationBucket(trackingUnavailableSeconds).rawValue)
            return TelemetryRecord(
                name: "just_climb_saved",
                parameters: parameters
            )

        case .justClimbDiscarded(let context, let durationSeconds, let steps, let progressFraction):
            var parameters = justClimbParameters(context)
            parameters["duration_bucket"] = .string(DurationBucket(durationSeconds).rawValue)
            parameters["steps_bucket"] = .string(CountBucket(steps).rawValue)
            parameters["progress_bucket"] = .string(ProgressBucket(progressFraction).rawValue)
            return TelemetryRecord(
                name: "just_climb_discarded",
                parameters: parameters
            )

        case .routineStarted(let context):
            return TelemetryRecord(
                name: "routine_started",
                parameters: routineParameters(context)
            )

        case .routineCompleted(let context, let durationSeconds, let steps, let progressFraction):
            var parameters = routineParameters(context)
            parameters["duration_bucket"] = .string(DurationBucket(durationSeconds).rawValue)
            parameters["steps_bucket"] = .string(CountBucket(steps).rawValue)
            parameters["progress_bucket"] = .string(ProgressBucket(progressFraction).rawValue)
            return TelemetryRecord(
                name: "routine_completed",
                parameters: parameters
            )

        case .routineLogTapped(let context, let surface, let durationSeconds, let steps, let progressFraction):
            var parameters = routineParameters(context)
            parameters["surface"] = .string(surface.rawValue)
            parameters["duration_bucket"] = .string(DurationBucket(durationSeconds).rawValue)
            parameters["steps_bucket"] = .string(CountBucket(steps).rawValue)
            parameters["progress_bucket"] = .string(ProgressBucket(progressFraction).rawValue)
            return TelemetryRecord(
                name: "routine_log_tapped",
                parameters: parameters
            )

        case .routineSaved(let context, let durationSeconds, let steps, let progressFraction):
            var parameters = routineParameters(context)
            parameters["duration_bucket"] = .string(DurationBucket(durationSeconds).rawValue)
            parameters["steps_bucket"] = .string(CountBucket(steps).rawValue)
            parameters["progress_bucket"] = .string(ProgressBucket(progressFraction).rawValue)
            return TelemetryRecord(
                name: "routine_saved",
                parameters: parameters
            )

        case .routineDiscarded(let context, let surface, let durationSeconds, let steps, let progressFraction):
            var parameters = routineParameters(context)
            parameters["surface"] = .string(surface.rawValue)
            parameters["duration_bucket"] = .string(DurationBucket(durationSeconds).rawValue)
            parameters["steps_bucket"] = .string(CountBucket(steps).rawValue)
            parameters["progress_bucket"] = .string(ProgressBucket(progressFraction).rawValue)
            return TelemetryRecord(
                name: "routine_discarded",
                parameters: parameters
            )
        }
    }

    private func justClimbParameters(_ context: JustClimbAnalyticsContext) -> [String: TelemetryValue] {
        var parameters: [String: TelemetryValue] = [
            "session_type": .string("just_climb"),
            "goal_kind": .string(context.goalKind),
            "entry_point": .string(context.entryPoint)
        ]

        if let targetStepCount = context.targetStepCount {
            parameters["target_steps_bucket"] = .string(CountBucket(targetStepCount).rawValue)
        }

        if let targetDurationSeconds = context.targetDurationSeconds {
            parameters["target_duration_bucket"] = .string(DurationBucket(targetDurationSeconds).rawValue)
        }

        return parameters
    }

    private func routineParameters(_ context: RoutineSessionAnalyticsContext) -> [String: TelemetryValue] {
        var parameters: [String: TelemetryValue] = [
            "session_type": .string("routine"),
            "routine_id": .string(context.routineID),
            "routine_source": .string(context.routineSource),
            "has_default_weights": .bool(context.hasDefaultWeights),
            "interval_count_bucket": .string(CountBucket(context.intervalCount).rawValue),
            "target_duration_bucket": .string(DurationBucket(context.targetDurationSeconds).rawValue),
            "target_steps_bucket": .string(CountBucket(context.targetSteps).rawValue)
        ]

        if let templateID = context.templateID {
            parameters["template_id"] = .string(templateID)
        }

        if let difficulty = context.difficulty {
            parameters["difficulty_bucket"] = .string(DifficultyBucket(difficulty).rawValue)
        }

        return parameters
    }
}

extension WorkoutSessionAnalyticsEvent {
    enum RoutineSurface: String, Sendable {
        case stopAlert = "stop_alert"
        case completionSheet = "completion_sheet"
    }

    enum CountBucket: String {
        case zero
        case one
        case twoToFive = "2_5"
        case sixToTen = "6_10"
        case elevenToTwentyFive = "11_25"
        case twentySixToFifty = "26_50"
        case fiftyOneToOneHundred = "51_100"
        case oneHundredToTwoFifty = "101_250"
        case twoFiftyOneToFiveHundred = "251_500"
        case fiveHundredToOneThousand = "501_1000"
        case oneThousandToTwoThousand = "1001_2000"
        case twoThousandPlus = "2000_plus"

        init(_ count: Int) {
            switch count {
            case ..<1:
                self = .zero
            case 1:
                self = .one
            case 2...5:
                self = .twoToFive
            case 6...10:
                self = .sixToTen
            case 11...25:
                self = .elevenToTwentyFive
            case 26...50:
                self = .twentySixToFifty
            case 51...100:
                self = .fiftyOneToOneHundred
            case 101...250:
                self = .oneHundredToTwoFifty
            case 251...500:
                self = .twoFiftyOneToFiveHundred
            case 501...1_000:
                self = .fiveHundredToOneThousand
            case 1_001...2_000:
                self = .oneThousandToTwoThousand
            default:
                self = .twoThousandPlus
            }
        }
    }

    enum DurationBucket: String {
        case none
        case underFiveSeconds = "under_5_sec"
        case fiveToTwentySeconds = "5_20_sec"
        case twentyToSixtySeconds = "20_60_sec"
        case underFiveMinutes = "under_5_min"
        case fiveToTenMinutes = "5_10_min"
        case tenToTwentyMinutes = "10_20_min"
        case twentyToFortyFiveMinutes = "20_45_min"
        case fortyFiveToNinetyMinutes = "45_90_min"
        case ninetyPlusMinutes = "90_plus_min"

        init(_ durationSeconds: Int) {
            switch max(durationSeconds, 0) {
            case 0:
                self = .none
            case ..<5:
                self = .underFiveSeconds
            case 5..<20:
                self = .fiveToTwentySeconds
            case 20..<60:
                self = .twentyToSixtySeconds
            case 60..<300:
                self = .underFiveMinutes
            case 300..<600:
                self = .fiveToTenMinutes
            case 600..<1_200:
                self = .tenToTwentyMinutes
            case 1_200..<2_700:
                self = .twentyToFortyFiveMinutes
            case 2_700..<5_400:
                self = .fortyFiveToNinetyMinutes
            default:
                self = .ninetyPlusMinutes
            }
        }
    }

    enum ProgressBucket: String {
        case zero
        case underTwentyFive = "under_25"
        case twentyFiveToFifty = "25_50"
        case fiftyToSeventyFive = "50_75"
        case seventyFiveToNinetyNine = "75_99"
        case complete

        init(_ fraction: Double) {
            switch max(0, fraction) {
            case 0:
                self = .zero
            case ..<0.25:
                self = .underTwentyFive
            case ..<0.5:
                self = .twentyFiveToFifty
            case ..<0.75:
                self = .fiftyToSeventyFive
            case ..<1:
                self = .seventyFiveToNinetyNine
            default:
                self = .complete
            }
        }
    }

    enum DifficultyBucket: String {
        case unknown
        case easy
        case moderate
        case hard

        init(_ difficulty: Int) {
            switch difficulty {
            case ..<1:
                self = .unknown
            case 1...2:
                self = .easy
            case 3:
                self = .moderate
            default:
                self = .hard
            }
        }
    }
}
