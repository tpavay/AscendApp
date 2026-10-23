import Foundation

/// Why the process that was counting stopped, as far as the next launch can tell.
enum HeadphoneSessionLossReason: String, Codable, Sendable, CaseIterable {
    /// The phone rebooted between the last checkpoint and now: the battery ran out or it was
    /// switched off. The one reason a launch can prove, from the system uptime.
    case phoneOff = "phone_off"
    /// The previous process crashed, as the crash reporter saw it.
    case crashed
    /// iOS reclaimed the process in the background: the last checkpoint saw memory warnings or
    /// almost no headroom left.
    case closedByIOS = "closed_by_ios"
    /// Nothing distinguishes a force-quit from a quiet jetsam here.
    case unknown

    /// The plain-language half of "Ascend was not counting for N minutes".
    var climberFacingClause: String {
        switch self {
        case .phoneOff:
            return "Your phone was off"
        case .crashed:
            return "Ascend crashed"
        case .closedByIOS:
            return "iOS closed Ascend in the background"
        case .unknown:
            return "Ascend was closed"
        }
    }
}

/// What the launch that finds a draft should do with it.
enum HeadphoneSessionRecoveryPlan: Equatable, Sendable {
    /// Restart the session for its mode now, credit the gap, and ask for the machine's number
    /// over the running session.
    case autoResume
    /// Show the recovery screen first: machine count and Save lead, Resume second, Discard last.
    case prompt
}

struct HeadphoneSessionRecoveryAssessment: Equatable, Sendable {
    /// Wall clock between the draft's last checkpoint and now - how long nothing was counted.
    let gap: TimeInterval
    let lossReason: HeadphoneSessionLossReason
    let plan: HeadphoneSessionRecoveryPlan
    /// Whether `gap` is inside `ActiveHeadphoneWorkoutDraftStore.maximumCreditableTrackingGap`.
    let gapIsCreditable: Bool

    var gapMinutes: Int {
        Int((gap / 60).rounded())
    }
}

/// Decides, from facts alone, how a recovered draft is handled. Pure, so every branch is a test.
enum HeadphoneSessionRecoveryPlanner {
    /// A draft younger than this resumes without asking. The same hour that bounds the wall-clock
    /// credit: inside it the climber is plausibly still on the machine, past it they have gone home.
    static let automaticResumeWindow: TimeInterval = ActiveHeadphoneWorkoutDraftStore.maximumCreditableTrackingGap

    /// Below this much headroom at the last checkpoint, a death in the background reads as jetsam.
    static let lowMemoryThresholdBytes: Int64 = 200 * 1_048_576

    /// Tolerance on the reboot comparison, so clock drift cannot invent a reboot.
    static let rebootTolerance: TimeInterval = 5

    struct Inputs: Equatable, Sendable {
        var lastCheckpointAt: Date
        var diagnostics: HeadphoneSessionCheckpointDiagnostics?
        var now: Date
        /// `ProcessInfo.systemUptime` at assessment: seconds since this phone last booted.
        var systemUptime: TimeInterval
        var crashedLastRun: Bool
        var autoResumeEnabled: Bool
    }

    static func assess(_ inputs: Inputs) -> HeadphoneSessionRecoveryAssessment {
        let gap = max(inputs.now.timeIntervalSince(inputs.lastCheckpointAt), 0)
        let reason = lossReason(gap: gap, inputs: inputs)
        let creditable = gap <= ActiveHeadphoneWorkoutDraftStore.maximumCreditableTrackingGap
        let plan: HeadphoneSessionRecoveryPlan = inputs.autoResumeEnabled && gap <= automaticResumeWindow
            ? .autoResume
            : .prompt
        return HeadphoneSessionRecoveryAssessment(
            gap: gap,
            lossReason: reason,
            plan: plan,
            gapIsCreditable: creditable
        )
    }

    private static func lossReason(gap: TimeInterval, inputs: Inputs) -> HeadphoneSessionLossReason {
        // A phone that has been up for less time than the gap booted after the checkpoint.
        if inputs.systemUptime + rebootTolerance < gap {
            return .phoneOff
        }
        if inputs.crashedLastRun {
            return .crashed
        }
        if let diagnostics = inputs.diagnostics {
            if diagnostics.memoryWarningCount > 0 {
                return .closedByIOS
            }
            if let available = diagnostics.availableMemoryBytes, available < lowMemoryThresholdBytes {
                return .closedByIOS
            }
        }
        return .unknown
    }
}
