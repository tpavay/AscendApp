import Foundation

/// Why the process that was counting stopped, as far as the next launch can tell.
enum HeadphoneSessionLossReason: String, Codable, Sendable, CaseIterable {
    /// The phone rebooted between the last checkpoint and now: the battery ran out or it was
    /// switched off. The one reason a launch can prove, from the system uptime.
    case phoneOff = "phone_off"
    /// The previous process crashed, as the crash reporter saw it.
    case crashed
    /// The last checkpoint found the phone's volume under the floor Firestore's disk guard
    /// treats as full (`FirestoreDiskPolicy.lowDiskFloorBytes`). A full volume is the one
    /// condition that both kills the process - a LevelDB commit assertion, a refused store write -
    /// and keeps every crash reporter from writing its report, so it is named from the reading
    /// rather than waited for from a reporter that cannot speak.
    case outOfDiskSpace = "out_of_disk_space"
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
        case .outOfDiskSpace:
            return "Your phone ran out of space"
        case .closedByIOS:
            return "iOS closed Ascend in the background"
        case .unknown:
            return "Ascend was closed"
        }
    }

    /// The clause with the reading that proved it, where there is one: "Your phone ran out of
    /// space (12 MB free)". Every other reason reads the same with or without a reading.
    func climberFacingClause(freeDiskBytes: Int64?) -> String {
        guard self == .outOfDiskSpace, let freeDiskBytes else { return climberFacingClause }
        return "\(climberFacingClause) (\(Self.megabytesText(freeDiskBytes)) free)"
    }

    static func megabytesText(_ bytes: Int64) -> String {
        "\(max(bytes, 0) / 1_048_576) MB"
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
    /// The climber had already ended the session (the draft is `.stopped`) and the process died
    /// before the save finished. Such a draft is never restarted: the screen offers to save it.
    let climberEndedSession: Bool
    /// What a write could still use on the volume at the last checkpoint (`statfs`), so a loss
    /// named `.outOfDiskSpace` can show the number it was named from. Nil for a checkpoint written
    /// before that reading was recorded.
    let freeDiskBytesAtLastCheckpoint: Int64?

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

    /// Below this much writable on the volume at the last checkpoint, the loss reads as the phone
    /// being out of space. The same floor, on the same `statfs` figure, the Firestore disk guard
    /// refuses writes at, so the sheet names the condition the guard exists for and no other
    /// number has to be kept in step with it.
    static let lowDiskFloorBytes: Int64 = FirestoreDiskPolicy.lowDiskFloorBytes

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
        /// The draft's status was `.stopped`: the finish path wrote it before saving.
        var climberEndedSession: Bool
    }

    static func assess(_ inputs: Inputs) -> HeadphoneSessionRecoveryAssessment {
        let gap = max(inputs.now.timeIntervalSince(inputs.lastCheckpointAt), 0)
        let reason = lossReason(gap: gap, inputs: inputs)
        let creditable = gap <= ActiveHeadphoneWorkoutDraftStore.maximumCreditableTrackingGap
        let plan: HeadphoneSessionRecoveryPlan = inputs.autoResumeEnabled
            && !inputs.climberEndedSession
            && gap <= automaticResumeWindow
            ? .autoResume
            : .prompt
        return HeadphoneSessionRecoveryAssessment(
            gap: gap,
            lossReason: reason,
            plan: plan,
            gapIsCreditable: creditable,
            climberEndedSession: inputs.climberEndedSession,
            freeDiskBytesAtLastCheckpoint: inputs.diagnostics?.writableDiskBytes
        )
    }

    private static func lossReason(gap: TimeInterval, inputs: Inputs) -> HeadphoneSessionLossReason {
        // A phone that has been up for less time than the gap booted after the checkpoint.
        if inputs.systemUptime + rebootTolerance < gap {
            return .phoneOff
        }
        // A crash report that exists proves a crash, and proves the volume could still take a
        // file when the process died; the disk reading is for the crash that leaves no report.
        if inputs.crashedLastRun {
            return .crashed
        }
        if let diagnostics = inputs.diagnostics {
            // A `statfs` reading is required: an unanswered volume is unknown, not full, and the
            // important-usage figure counts purgeable space a failed write never got.
            if let writableDisk = diagnostics.writableDiskBytes, writableDisk < lowDiskFloorBytes {
                return .outOfDiskSpace
            }
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
