import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// Skipping intervals burns the routine clock without taking steps. A skipped session must not
/// finish as `.targetReached`, because that is the stop reason the replay indexer treats as a
/// publishable completion.
@MainActor
struct ActiveRoutineSkipEligibilityTests {
    @Test
    func untouchedSessionCompletesAsTargetReached() {
        let viewModel = makeViewModel()

        #expect(viewModel.skippedIntervalCount == 0)
        #expect(viewModel.didSkipInterval == false)
        #expect(viewModel.completionStopReason == .targetReached)
        #expect(viewModel.countsAsCompletion)
    }

    @Test
    func skippingEveryIntervalDoesNotEmitTargetReached() {
        let viewModel = makeViewModel()

        for _ in 0..<3 {
            viewModel.skipInterval()
        }

        #expect(viewModel.completionStopReason != .targetReached)
        #expect(viewModel.completionStopReason == .skipped)
        #expect(viewModel.countsAsCompletion == false)
        #expect(viewModel.skippedIntervalCount == 3)
    }

    @Test
    func skippingASingleIntervalTaintsTheWholeSession() {
        let viewModel = makeViewModel()

        viewModel.skipInterval()

        #expect(viewModel.didSkipInterval)
        #expect(viewModel.completionStopReason == .skipped)
        #expect(viewModel.countsAsCompletion == false)
    }

    @Test
    func skippingAdvancesToTheNextIntervalAndTimeline() {
        let viewModel = makeViewModel()

        viewModel.skipInterval()

        #expect(viewModel.currentIntervalIndex == 1)
        #expect(viewModel.currentInterval?.intensityValue == 12)
        #expect(viewModel.elapsedInInterval == 0)
        #expect(viewModel.timelineElapsed == 60)

        viewModel.skipInterval()

        #expect(viewModel.currentIntervalIndex == 2)
        #expect(viewModel.currentInterval?.intensityValue == 16)
        #expect(viewModel.timelineElapsed == 150)
    }

    @Test
    func skippingPastTheFinalIntervalStopsAdvancing() {
        let viewModel = makeViewModel()

        for _ in 0..<5 {
            viewModel.skipInterval()
        }

        #expect(viewModel.currentIntervalIndex == 3)
        #expect(viewModel.currentInterval == nil)
        #expect(viewModel.skippedIntervalCount == 3)
        #expect(viewModel.completionStopReason == .skipped)
    }

    @Test
    func skippedSessionMetadataCarriesSkippedStopReason() throws {
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 0,
            trackingMode: .routine,
            climbId: nil,
            routineId: UUID().uuidString,
            targetStepCount: 900,
            stopReason: .skipped
        )

        let json = try #require(metadata.jsonString)
        let decoded = try JSONDecoder().decode(
            HeadphoneMotionWorkoutMetadata.self,
            from: Data(json.utf8)
        )

        #expect(decoded.stopReason == .skipped)
        #expect(decoded.stopReason != .targetReached)
        #expect(json.contains("\"stopReason\":\"skipped\""))
    }

    @Test
    func resumedDraftRestoresSkippedIntervalCount() throws {
        let container = try ModelContainer(
            for: ActiveHeadphoneWorkoutDraft.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let routine = makeRoutine()

        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: "session-1",
            kind: .routine,
            title: routine.name,
            subtitle: "",
            workoutName: routine.name,
            targetStepCount: 900,
            targetDurationSeconds: routine.totalDuration,
            routineId: routine.id,
            routineSource: routine.source,
            routineTemplateId: routine.templateId
        )
        modelContext.insert(draft)
        draft.applyCheckpoint(
            steps: 0,
            durationSeconds: 60,
            sampleCount: 0,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: [],
            skippedIntervalCount: 2
        )

        #expect(draft.routineSkippedIntervalCount == 2)

        let viewModel = ActiveRoutineViewModel(routine: routine, recoveredDraft: draft)
        viewModel.startSession(modelContext: modelContext)
        viewModel.stopTimer()

        #expect(viewModel.skippedIntervalCount == 2)
        #expect(viewModel.completionStopReason == .skipped)
        #expect(viewModel.countsAsCompletion == false)
    }

    /// A recovered draft is a session the climber never finished in the app, so it can never be
    /// saved as a completion regardless of whether it had already skipped intervals.
    @Test(arguments: [nil, 0, 2] as [Int?])
    func recoveredRoutineDraftIsNeverLeaderboardEligible(skippedIntervalCount: Int?) throws {
        let container = try ModelContainer(
            for: ActiveHeadphoneWorkoutDraft.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let routine = makeRoutine()

        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: "session-recovered",
            kind: .routine,
            title: routine.name,
            subtitle: "",
            workoutName: routine.name,
            targetStepCount: 900,
            targetDurationSeconds: routine.totalDuration,
            routineId: routine.id,
            routineSource: routine.source,
            routineTemplateId: routine.templateId
        )
        modelContext.insert(draft)
        draft.applyCheckpoint(
            steps: 1_200,
            durationSeconds: 600,
            sampleCount: 0,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: [],
            skippedIntervalCount: skippedIntervalCount
        )

        let attribution = try #require(ActiveHeadphoneWorkoutDraftSaver.routineAttribution(for: draft))

        #expect(attribution.contextType == .routineTemplate)
        #expect(attribution.origin == .liveSession(stopReason: .interrupted))
        #expect(attribution.isLeaderboardEligible == false)
    }

    @Test
    func targetReachedSessionSummaryClaimsTheCompletionAndItsRank() {
        let presentation = RoutineCompletionSummaryPresentation(
            stopReason: .targetReached,
            hasRoutineLeaderboard: true
        )

        #expect(presentation.rankingLabel == "ROUTINE RANK")
        #expect(presentation.ranksOnLeaderboard)

        // No override: the achievement card keeps the summary's own completion copy and seal.
        #expect(presentation.achievementTitleOverride == nil)
        #expect(presentation.achievementIconNameOverride == nil)
    }

    /// The summary reads the same stop reason the participation record is built from, so a session
    /// that forfeited credit can never be told it completed.
    @Test(arguments: [
        HeadphoneMotionSessionStopReason.skipped,
        .userStopped,
        .interrupted,
        .discarded
    ])
    func forfeitedSessionSummaryNeverClaimsACompletionOrRank(
        stopReason: HeadphoneMotionSessionStopReason
    ) {
        let presentation = RoutineCompletionSummaryPresentation(
            stopReason: stopReason,
            hasRoutineLeaderboard: true
        )

        #expect(presentation.rankingLabel == "ROUTINE")
        #expect(presentation.rankingLabel != "ROUTINE RANK")
        #expect(presentation.ranksOnLeaderboard == false)

        // The achievement card sits directly under the ranking card, so it has to forfeit too.
        #expect(presentation.achievementTitleOverride == "SESSION ENDED")
        #expect(presentation.achievementIconNameOverride != nil)
    }

    /// Both cards resolve from one stop reason, so neither can drift into contradicting the other.
    /// Asserting each card alone is what let the achievement card keep claiming a completion the
    /// ranking card had already denied.
    @Test(arguments: [
        HeadphoneMotionSessionStopReason.targetReached,
        .skipped,
        .userStopped,
        .interrupted,
        .discarded
    ])
    func bothSummaryCardsAgreeOnWhetherTheSessionCounted(
        stopReason: HeadphoneMotionSessionStopReason
    ) {
        let presentation = RoutineCompletionSummaryPresentation(
            stopReason: stopReason,
            hasRoutineLeaderboard: true
        )

        // A nil override leaves the achievement card on its "CLIMB COMPLETE" default, which is the
        // claim; supplying one replaces it.
        let achievementCardClaimsCompletion = presentation.achievementTitleOverride == nil
        let rankingCardClaimsCompletion = presentation.ranksOnLeaderboard

        #expect(achievementCardClaimsCompletion == rankingCardClaimsCompletion)
        #expect(rankingCardClaimsCompletion == stopReason.earnsCompetitiveCredit)
    }

    /// The funnel reads the stop reason off the record, so a session the record calls forfeited can
    /// never be reported as a completion. A skip taints the session before anything is recorded.
    @Test
    func skippedSessionTracksTheSkippedStopReason() {
        let viewModel = makeViewModel()
        viewModel.skipInterval()

        let parameters = viewModel.sessionCompletionAnalyticsEvent.record.parameters

        #expect(parameters["stop_reason"]?.stringValue == viewModel.resolvedStopReason.rawValue)
        #expect(parameters["stop_reason"]?.stringValue == "skipped")
    }

    /// The climber taps Stop while the final interval is still running, so the recorded result says
    /// `.userStopped` even though the unskipped interval list would derive `.targetReached`. The
    /// funnel must follow the record, not re-derive.
    @Test
    func stoppedSessionTracksTheRecordedStopReasonNotTheDerivedOne() async throws {
        let container = try ModelContainer(
            for: ActiveHeadphoneWorkoutDraft.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let routine = makeRoutine()

        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: "session-stopped",
            kind: .routine,
            title: routine.name,
            subtitle: "",
            workoutName: routine.name,
            targetStepCount: 900,
            targetDurationSeconds: routine.totalDuration,
            routineId: routine.id,
            routineSource: routine.source,
            routineTemplateId: routine.templateId
        )
        modelContext.insert(draft)

        let viewModel = ActiveRoutineViewModel(routine: routine, recoveredDraft: draft)
        viewModel.startSession(modelContext: modelContext)
        viewModel.stopTimer()

        #expect(viewModel.completionStopReason == .targetReached)

        await #expect(throws: ActiveRoutineSessionError.self) {
            _ = try await viewModel.saveRecordedWorkout(
                modelContext: modelContext,
                reason: .userStopped
            )
        }

        #expect(viewModel.recordedResult?.stopReason == .userStopped)
        #expect(viewModel.resolvedStopReason == .userStopped)
        #expect(viewModel.countsAsCompletion == false)

        let parameters = viewModel.sessionCompletionAnalyticsEvent.record.parameters

        #expect(parameters["stop_reason"]?.stringValue == viewModel.resolvedStopReason.rawValue)
        #expect(parameters["stop_reason"]?.stringValue == "user_stopped")
        #expect(parameters["stop_reason"]?.stringValue != "target_reached")
    }

    @Test
    func skippedSessionSuppressesStandingOnTheViewModel() {
        let viewModel = makeViewModel()
        viewModel.skipInterval()

        #expect(viewModel.resolvedStopReason == .skipped)
        #expect(viewModel.countsAsCompletion == false)
        #expect(viewModel.completionSummaryPresentation.rankingLabel == "ROUTINE")
        #expect(viewModel.completionLeaderboardContext == nil)
        #expect(viewModel.completionLeaderboardRank == nil)
        #expect(viewModel.completionLeaderboardTotal == nil)
        #expect(viewModel.completionSummaryPresentation.ranksOnLeaderboard == false)
    }

    /// Only `.targetReached` earns credit, and both the record and the UI read that one rule.
    @Test
    func targetReachedIsTheOnlyStopReasonEarningCredit() {
        #expect(HeadphoneMotionSessionStopReason.targetReached.earnsCompetitiveCredit)

        for stopReason: HeadphoneMotionSessionStopReason in [.skipped, .userStopped, .interrupted, .discarded] {
            #expect(stopReason.earnsCompetitiveCredit == false)
        }
    }

    private func makeViewModel() -> ActiveRoutineViewModel {
        ActiveRoutineViewModel(routine: makeRoutine())
    }

    private func makeRoutine() -> Routine {
        Routine(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "Pyramid Climb",
            source: .builtin,
            intervals: [
                RoutineInterval(duration: 60, intensityValue: 8, order: 0),
                RoutineInterval(duration: 90, intensityValue: 12, order: 1),
                RoutineInterval(duration: 60, intensityValue: 16, order: 2)
            ],
            templateId: "pyramid_climb"
        )
    }
}
