import Foundation

/// The two events that make a lost session visible within minutes: one when a launch finds a
/// draft the previous process never finished, one when the climber settles the gap.
///
/// Named `live_climb_session_*` for every mode, with `mode` as a property, so one Mixpanel alert
/// covers Live Climb, Just Climb and Routines alike.
enum HeadphoneSessionRecoveryAnalyticsEvent: TelemetryEvent {
    enum ResumeAction: String, Sendable {
        case save
        case keepCounting = "keep_counting"
        /// The climber chose the recovery screen's Resume Live rather than an inline notice.
        case promptResume = "prompt_resume"
        case promptSave = "prompt_save"
        case promptDiscard = "prompt_discard"
    }

    case sessionLost(
        mode: ActiveHeadphoneWorkoutDraftKind,
        draftAgeSeconds: Int,
        steps: Int,
        durationSeconds: Int,
        lastWorkoutSessionState: String,
        availableMemoryMB: Int?,
        memoryWarningCount: Int?,
        lossReason: HeadphoneSessionLossReason,
        plan: HeadphoneSessionRecoveryPlan
    )
    /// `gapSeconds` is the gap measured; `gapCreditedSeconds` is how much of it the climb was
    /// actually credited, and `source` names where that credit came from - `none` when nothing was.
    case sessionResumed(
        mode: ActiveHeadphoneWorkoutDraftKind,
        gapSeconds: Int,
        gapCreditedSeconds: Int,
        lossReason: HeadphoneSessionLossReason,
        source: HeadphoneSessionResumeNotice.GapSource,
        deltaSteps: Int,
        action: ResumeAction
    )

    var record: TelemetryRecord {
        switch self {
        case .sessionLost(
            let mode, let draftAgeSeconds, let steps, let durationSeconds,
            let lastWorkoutSessionState, let availableMemoryMB, let memoryWarningCount,
            let lossReason, let plan
        ):
            var parameters: [String: TelemetryValue] = [
                "mode": .string(mode.rawValue),
                "draft_age_seconds": .int(draftAgeSeconds),
                "steps": .int(steps),
                "duration_seconds": .int(durationSeconds),
                "last_hk_session_state": .string(lastWorkoutSessionState),
                "loss_reason": .string(lossReason.rawValue),
                "plan": .string(plan == .autoResume ? "auto_resume" : "prompt")
            ]
            if let availableMemoryMB {
                parameters["available_memory_mb"] = .int(availableMemoryMB)
            }
            if let memoryWarningCount {
                parameters["memory_warning_count"] = .int(memoryWarningCount)
            }
            return TelemetryRecord(name: "live_climb_session_lost", parameters: parameters)

        case .sessionResumed(
            let mode, let gapSeconds, let gapCreditedSeconds, let lossReason, let source, let deltaSteps, let action
        ):
            return TelemetryRecord(
                name: "live_climb_session_resumed",
                parameters: [
                    "mode": .string(mode.rawValue),
                    "gap_seconds": .int(gapSeconds),
                    "gap_credited_seconds": .int(gapCreditedSeconds),
                    "loss_reason": .string(lossReason.rawValue),
                    "gap_source": .string(gapCreditedSeconds > 0 ? source.rawValue : "none"),
                    "delta_steps": .int(deltaSteps),
                    "action": .string(action.rawValue)
                ]
            )
        }
    }
}
