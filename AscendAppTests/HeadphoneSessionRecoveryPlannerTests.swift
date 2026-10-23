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
        diagnostics: HeadphoneSessionCheckpointDiagnostics? = nil
    ) -> HeadphoneSessionRecoveryPlanner.Inputs {
        HeadphoneSessionRecoveryPlanner.Inputs(
            lastCheckpointAt: Self.lastCheckpointAt,
            diagnostics: diagnostics,
            now: Self.lastCheckpointAt.addingTimeInterval(gap),
            systemUptime: systemUptime,
            crashedLastRun: crashedLastRun,
            autoResumeEnabled: autoResumeEnabled
        )
    }

    private func diagnostics(
        availableMemoryBytes: Int64? = 1_000 * 1_048_576,
        memoryWarningCount: Int = 0
    ) -> HeadphoneSessionCheckpointDiagnostics {
        HeadphoneSessionCheckpointDiagnostics(
            availableMemoryBytes: availableMemoryBytes,
            freeDiskBytes: 10 * 1_024 * 1_048_576,
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

    @Test("Every reason has words a climber can read")
    func climberFacingClauses() {
        #expect(HeadphoneSessionLossReason.phoneOff.climberFacingClause == "Your phone was off")
        #expect(HeadphoneSessionLossReason.crashed.climberFacingClause == "Ascend crashed")
        #expect(HeadphoneSessionLossReason.closedByIOS.climberFacingClause == "iOS closed Ascend in the background")
        #expect(HeadphoneSessionLossReason.unknown.climberFacingClause == "Ascend was closed")
        for reason in HeadphoneSessionLossReason.allCases {
            #expect(!reason.climberFacingClause.isEmpty)
        }
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
