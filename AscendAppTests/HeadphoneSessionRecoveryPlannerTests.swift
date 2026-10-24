import Foundation
import Testing
@testable import AscendApp

/// The decision table behind "what happens to a draft the previous process never finished":
/// resume by itself inside the hour, ask past it, and name the reason the launch can prove.
struct HeadphoneSessionRecoveryPlannerTests {
    private static let lastCheckpointAt = Date(timeIntervalSince1970: 1_792_754_516)

    private func inputs(
        gap: TimeInterval,
        systemUptime: TimeInterval = 7 * 24 * 3_600,
        crashedLastRun: Bool = false,
        autoResumeEnabled: Bool = true,
        climberEndedSession: Bool = false,
        diagnostics: HeadphoneSessionCheckpointDiagnostics? = nil
    ) -> HeadphoneSessionRecoveryPlanner.Inputs {
        HeadphoneSessionRecoveryPlanner.Inputs(
            lastCheckpointAt: Self.lastCheckpointAt,
            diagnostics: diagnostics,
            now: Self.lastCheckpointAt.addingTimeInterval(gap),
            systemUptime: systemUptime,
            crashedLastRun: crashedLastRun,
            autoResumeEnabled: autoResumeEnabled,
            climberEndedSession: climberEndedSession
        )
    }

    private func diagnostics(
        availableMemoryBytes: Int64? = 1_000 * 1_048_576,
        freeDiskBytes: Int64? = 10 * 1_024 * 1_048_576,
        memoryWarningCount: Int = 0
    ) -> HeadphoneSessionCheckpointDiagnostics {
        HeadphoneSessionCheckpointDiagnostics(
            availableMemoryBytes: availableMemoryBytes,
            freeDiskBytes: freeDiskBytes,
            memoryWarningCount: memoryWarningCount,
            batteryLevel: 0.84,
            batteryState: "unplugged",
            workoutSessionState: "running",
            motionStatus: "recording",
            systemUptimeSeconds: 500_000,
            processUptimeSeconds: 90,
            recordedAt: Self.lastCheckpointAt
        )
    }

    @Test("Inside the hour the draft resumes by itself; past it the climber is asked")
    func automaticResumeWindow() {
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 19.5 * 60)).plan == .autoResume)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 59 * 60)).plan == .autoResume)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 61 * 60)).plan == .prompt)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 61 * 60)).gapIsCreditable == false)
        #expect(HeadphoneSessionRecoveryPlanner.automaticResumeWindow == ActiveHeadphoneWorkoutDraftStore.maximumCreditableTrackingGap)
    }

    @Test("A session the climber already ended is offered for saving, never restarted")
    func endedSessionIsNeverAutoResumed() {
        let assessment = HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 30, climberEndedSession: true))
        #expect(assessment.plan == .prompt)
        #expect(assessment.climberEndedSession)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 30)).climberEndedSession == false)
    }

    @Test("The kill switch turns every draft into a prompt without touching it")
    func killSwitchForcesThePrompt() {
        let assessment = HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 5 * 60, autoResumeEnabled: false))
        #expect(assessment.plan == .prompt)
        #expect(assessment.gapIsCreditable, "the credit is still available to the prompt's own actions")
    }

    @Test("A phone that has been up for less time than the gap rebooted: the phone was off")
    func rebootReadsAsPhoneOff() {
        let rebooted = HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 2 * 3_600, systemUptime: 20 * 60))
        #expect(rebooted.lossReason == .phoneOff)
        #expect(rebooted.plan == .prompt)

        let shortRebootInsideTheHour = HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 10 * 60, systemUptime: 2 * 60))
        #expect(shortRebootInsideTheHour.lossReason == .phoneOff)
        #expect(shortRebootInsideTheHour.plan == .autoResume, "a quick reboot still resumes; the reason is just named")

        let clockDrift = HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 10 * 60, systemUptime: 10 * 60 - 3))
        #expect(clockDrift.lossReason != .phoneOff, "three seconds of drift is not a reboot")
    }

    @Test("A crash the reporter saw outranks a memory reading; memory warnings read as iOS closing the app")
    func reasonsFromDiagnostics() {
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, crashedLastRun: true, diagnostics: diagnostics(memoryWarningCount: 3))).lossReason == .crashed)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: diagnostics(memoryWarningCount: 2))).lossReason == .closedByIOS)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: diagnostics(availableMemoryBytes: 150 * 1_048_576))).lossReason == .closedByIOS)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: diagnostics())).lossReason == .unknown)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60)).lossReason == .unknown, "a draft from before V5 has no diagnostics and says so")
    }

    @Test("A volume under the Firestore disk floor at the last checkpoint names the phone being out of space, ahead of unknown")
    func outOfDiskSpaceFromTheLastCheckpoint() {
        let twelveMB: Int64 = 12 * 1_048_576
        let full = HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: diagnostics(freeDiskBytes: twelveMB)))
        #expect(full.lossReason == .outOfDiskSpace)
        #expect(full.freeDiskBytesAtLastCheckpoint == twelveMB, "the reading travels with the reason so the sheet can show it")
        #expect(full.plan == .autoResume, "a full phone still resumes inside the hour; the reason is just named")

        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: diagnostics(freeDiskBytes: 0))).lossReason == .outOfDiskSpace, "zero free is a reading, and the fullest one")
        #expect(HeadphoneSessionRecoveryPlanner.lowDiskFloorBytes == FirestoreDiskPolicy.lowDiskFloorBytes, "one floor, the disk guard's")
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: diagnostics(freeDiskBytes: FirestoreDiskPolicy.lowDiskFloorBytes - 1))).lossReason == .outOfDiskSpace)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: diagnostics(freeDiskBytes: FirestoreDiskPolicy.lowDiskFloorBytes))).lossReason == .unknown, "at the floor the guard still writes, so the phone was not out of space")
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: diagnostics(freeDiskBytes: nil))).lossReason == .unknown, "a volume that was never read is unknown, not full")

        let unread = HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: diagnostics(freeDiskBytes: nil)))
        #expect(unread.freeDiskBytesAtLastCheckpoint == nil)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60)).freeDiskBytesAtLastCheckpoint == nil, "a draft from before V5 has no reading")
    }

    @Test("Out of space sits between the proven reasons and the memory guess: a reboot or a written crash report outranks it, a memory warning does not")
    func outOfDiskSpacePrecedence() {
        let fullDisk = diagnostics(availableMemoryBytes: 150 * 1_048_576, freeDiskBytes: 12 * 1_048_576, memoryWarningCount: 3)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 2 * 3_600, systemUptime: 20 * 60, diagnostics: fullDisk)).lossReason == .phoneOff)
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, crashedLastRun: true, diagnostics: fullDisk)).lossReason == .crashed, "a crash report that exists proves the volume could still take a file")
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: fullDisk)).lossReason == .outOfDiskSpace, "memory warnings on a full phone are the phone being full")
        #expect(HeadphoneSessionRecoveryPlanner.assess(inputs(gap: 60, diagnostics: diagnostics(availableMemoryBytes: 150 * 1_048_576, freeDiskBytes: 12 * 1_048_576))).lossReason == .outOfDiskSpace)
    }

    @Test("Every reason has words a climber can read")
    func climberFacingClauses() {
        #expect(HeadphoneSessionLossReason.phoneOff.climberFacingClause == "Your phone was off")
        #expect(HeadphoneSessionLossReason.crashed.climberFacingClause == "Ascend crashed")
        #expect(HeadphoneSessionLossReason.outOfDiskSpace.climberFacingClause == "Your phone ran out of space")
        #expect(HeadphoneSessionLossReason.closedByIOS.climberFacingClause == "iOS closed Ascend in the background")
        #expect(HeadphoneSessionLossReason.unknown.climberFacingClause == "Ascend was closed")
        for reason in HeadphoneSessionLossReason.allCases {
            #expect(!reason.climberFacingClause.isEmpty)
            #expect(reason.climberFacingClause(freeDiskBytes: nil) == reason.climberFacingClause, "no reading, no number")
            if reason != .outOfDiskSpace {
                #expect(reason.climberFacingClause(freeDiskBytes: 12 * 1_048_576) == reason.climberFacingClause, "only the disk reason shows the disk")
            }
        }
        #expect(HeadphoneSessionLossReason.outOfDiskSpace.climberFacingClause(freeDiskBytes: 12 * 1_048_576) == "Your phone ran out of space (12 MB free)")
        #expect(HeadphoneSessionLossReason.outOfDiskSpace.climberFacingClause(freeDiskBytes: 0) == "Your phone ran out of space (0 MB free)")
        #expect(HeadphoneSessionLossReason.outOfDiskSpace.rawValue == "out_of_disk_space", "the analytics value `loss_reason` carries")
    }

    @Test("The resume notice for a full phone says how full: the gap in the headline, the reading in the explanation")
    func resumeNoticeNamesTheDiskReading() {
        let notice = HeadphoneSessionResumeNotice(
            gap: 1_165,
            lossReason: .outOfDiskSpace,
            detectedSteps: 66,
            freeDiskBytes: 12 * 1_048_576
        )
        #expect(notice.headline == "Ascend stopped counting for 19 minutes.")
        #expect(notice.explanation.hasPrefix("Your phone ran out of space (12 MB free) and the climb kept going without it."))

        let unread = HeadphoneSessionResumeNotice(gap: 1_165, lossReason: .outOfDiskSpace, detectedSteps: 66)
        #expect(unread.explanation.hasPrefix("Your phone ran out of space and the climb kept going without it."))

        let crashed = HeadphoneSessionResumeNotice(gap: 1_165, lossReason: .crashed, detectedSteps: 66, freeDiskBytes: 12 * 1_048_576)
        #expect(crashed.explanation.hasPrefix("Ascend crashed and the climb kept going without it."), "a reading is shown only for the reason it proved")
    }

    @Test("The resume notice leads with the gap, prefers the phone's own count, and never calls it the machine's")
    func resumeNoticeWording() {
        var notice = HeadphoneSessionResumeNotice(gap: 1_165, lossReason: .closedByIOS, detectedSteps: 66)
        #expect(notice.gapMinutes == 19)
        #expect(notice.headline == "Ascend stopped counting for 19 minutes.")
        #expect(notice.explanation.hasPrefix("iOS closed Ascend in the background and the climb kept going without it."))
        #expect(notice.suggestedSteps == 66)
        #expect(notice.suggestedStepsSource == .wallClock)

        notice.phoneEstimateSteps = 0
        #expect(notice.suggestedSteps == 66, "a powered-off phone counted nothing and offers nothing")
        notice.phoneEstimateSteps = 1_400
        #expect(notice.suggestedSteps == 1_466)
        #expect(notice.suggestedStepsSource == .pedometer)

        let brief = HeadphoneSessionResumeNotice(gap: 20, lossReason: .unknown, detectedSteps: 10)
        #expect(brief.gapMinutes == 1, "never zero minutes")
        #expect(brief.headline == "Ascend stopped counting for 1 minute.")
    }
}
