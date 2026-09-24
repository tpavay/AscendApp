import Foundation

/// Step-counting accuracy telemetry: which headphone was connected, whether headphone motion
/// data actually flowed, and - when a climber chooses to help calibrate the algorithm - how the
/// app's counted steps compared to what their stair-stepper machine displayed.
///
/// Raw headphone names never reach analytics: a Bluetooth accessory's name commonly carries the
/// climber's own name (iOS defaults to "<Owner>'s AirPods Pro"), so only the bucketed
/// `HeadphoneFamily` and a connected/not boolean are logged here. The raw name is persisted only
/// with the climb record (`Workout.sourceMetadata`, private to its owner) for the captain's own
/// review - see `ascend-analytics` (low-cardinality parameter rule) and `ascend-privacy-manifest`.
enum WorkoutStepAccuracyAnalyticsEvent: TelemetryEvent {
    /// Emitted once for every climb saved through the headphone-motion session flow, whatever
    /// the connected output turned out to be. Carries both a start-time and a save-time read of
    /// the connected headphone - a save-time-only read would misattribute exactly the climbs
    /// this telemetry most needs to explain: one where headphones disconnected or switched
    /// mid-climb reports whatever was connected at the end, not what drove the motion samples.
    case recorded(
        headphoneFamilyAtStart: HeadphoneFamily,
        isHeadphoneClassOutputConnectedAtStart: Bool,
        isMotionCapableHeadphoneConnectedAtStart: Bool,
        headphoneFamilyAtSave: HeadphoneFamily,
        isHeadphoneClassOutputConnectedAtSave: Bool,
        isMotionCapableHeadphoneConnectedAtSave: Bool,
        didHeadphoneChangeDuringClimb: Bool,
        didHeadphoneMotionDataFlow: Bool,
        steps: Int,
        trackingMode: HeadphoneMotionWorkoutTrackingMode
    )
    case calibrationSkipped
    case calibrationSubmitted(
        appSteps: Int,
        machineSteps: Int,
        discrepancyAbs: Int,
        discrepancyPercent: Double
    )

    var record: TelemetryRecord {
        switch self {
        case .recorded(
            let headphoneFamilyAtStart,
            let isHeadphoneClassOutputConnectedAtStart,
            let isMotionCapableHeadphoneConnectedAtStart,
            let headphoneFamilyAtSave,
            let isHeadphoneClassOutputConnectedAtSave,
            let isMotionCapableHeadphoneConnectedAtSave,
            let didHeadphoneChangeDuringClimb,
            let didHeadphoneMotionDataFlow,
            let steps,
            let trackingMode
        ):
            return TelemetryRecord(
                name: "step_accuracy_telemetry_recorded",
                parameters: [
                    "headphone_family_at_start": .string(headphoneFamilyAtStart.rawValue),
                    "headphone_output_connected_at_start": .bool(isHeadphoneClassOutputConnectedAtStart),
                    "motion_capable_headphone_connected_at_start": .bool(isMotionCapableHeadphoneConnectedAtStart),
                    "headphone_family_at_save": .string(headphoneFamilyAtSave.rawValue),
                    "headphone_output_connected_at_save": .bool(isHeadphoneClassOutputConnectedAtSave),
                    "motion_capable_headphone_connected_at_save": .bool(isMotionCapableHeadphoneConnectedAtSave),
                    "headphone_changed_during_climb": .bool(didHeadphoneChangeDuringClimb),
                    "headphone_motion_data_flowed": .bool(didHeadphoneMotionDataFlow),
                    "steps_bucket": .string(LiveClimbAnalyticsEvent.CountBucket(steps).rawValue),
                    "session_type": .string(trackingMode.rawValue)
                ],
                destinations: [.analytics]
            )

        case .calibrationSkipped:
            return TelemetryRecord(name: "step_accuracy_calibration_skipped", destinations: [.analytics])

        case .calibrationSubmitted(let appSteps, let machineSteps, let discrepancyAbs, let discrepancyPercent):
            return TelemetryRecord(
                name: "step_accuracy_calibration_submitted",
                parameters: [
                    "app_steps_bucket": .string(LiveClimbAnalyticsEvent.CountBucket(appSteps).rawValue),
                    "machine_steps_bucket": .string(LiveClimbAnalyticsEvent.CountBucket(machineSteps).rawValue),
                    "discrepancy_abs_bucket": .string(LiveClimbAnalyticsEvent.CountBucket(discrepancyAbs).rawValue),
                    "discrepancy_percent_bucket": .string(DiscrepancyPercentBucket(discrepancyPercent).rawValue)
                ],
                destinations: [.analytics]
            )
        }
    }
}

extension WorkoutStepAccuracyAnalyticsEvent {
    /// Mirrors `LiveClimbAnalyticsEvent.CountBucket`'s bucketing idiom for a signed percent value.
    enum DiscrepancyPercentBucket: String {
        case zero
        case underFive = "under_5"
        case fiveToTen = "5_10"
        case tenToTwentyFive = "10_25"
        case twentyFiveToFifty = "25_50"
        case fiftyPlus = "50_plus"

        init(_ percent: Double) {
            switch abs(percent) {
            case 0: self = .zero
            case ..<5: self = .underFive
            case ..<10: self = .fiveToTen
            case ..<25: self = .tenToTwentyFive
            case ..<50: self = .twentyFiveToFifty
            default: self = .fiftyPlus
            }
        }
    }
}
