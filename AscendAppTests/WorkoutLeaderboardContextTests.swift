import Foundation
import Testing
@testable import AscendApp

/// Which leaderboard a finished session ranks on. A workout that lost its leaderboard here had no
/// rank to show, and the summary filled the gap with the word "Complete" - a status word standing
/// where a rank belongs, which reads as a load that never finished.
struct WorkoutLeaderboardContextTests {
    /// `trackingMode` shipped after the first Live Climbs, so an early workout decodes with a `nil`
    /// mode while still naming its climb. That workout still ranks on that climb's board.
    @Test
    func aLiveClimbSavedBeforeTrackingModeExistedStillRanksOnItsClimbBoard() throws {
        let legacyJSON = """
        {
          "source": "headphone_motion",
          "algorithmVersion": 1,
          "sampleRateAssumptionHz": 50,
          "sampleCount": 2400,
          "climbId": "burj-khalifa",
          "targetStepCount": 4554,
          "stopReason": "target_reached"
        }
        """
        let metadata = try JSONDecoder().decode(
            HeadphoneMotionWorkoutMetadata.self,
            from: Data(legacyJSON.utf8)
        )

        #expect(metadata.trackingMode == nil)

        let context = LiveClimbWorkoutSummaryData.leaderboardContext(
            metadata: metadata,
            resolvedClimbId: "burj-khalifa",
            climbTargetSteps: 4_554,
            workoutSteps: 4_554
        )

        #expect(context?.type == .liveClimb)
        #expect(context?.id == "burj-khalifa")
    }

    @Test
    func aLiveClimbWhoseCatalogEntryIsMissingRanksNowhereRatherThanOnTheOpenBoard() throws {
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 2_400,
            trackingMode: .liveClimb,
            climbId: "retired-climb",
            targetStepCount: 4_554,
            stopReason: .targetReached
        )

        let context = LiveClimbWorkoutSummaryData.leaderboardContext(
            metadata: metadata,
            resolvedClimbId: nil,
            climbTargetSteps: nil,
            workoutSteps: 4_554
        )

        #expect(context == nil)
    }

    @Test
    func anOpenSessionWithNoClimbRanksOnTheGlobalBoard() {
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 900,
            trackingMode: .justClimb,
            climbId: nil,
            targetStepCount: 2_000,
            stopReason: .userStopped
        )

        let context = LiveClimbWorkoutSummaryData.leaderboardContext(
            metadata: metadata,
            resolvedClimbId: nil,
            climbTargetSteps: nil,
            workoutSteps: 1_686
        )

        #expect(context?.type == .justClimb)
        #expect(context?.id == "global")
    }

    @Test
    func aRoutineSessionRanksOnItsTemplateBoard() {
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 900,
            trackingMode: .routine,
            climbId: nil,
            routineTemplateId: "pyramid-intervals",
            targetStepCount: 2_400,
            stopReason: .targetReached
        )

        let context = LiveClimbWorkoutSummaryData.leaderboardContext(
            metadata: metadata,
            resolvedClimbId: nil,
            climbTargetSteps: nil,
            workoutSteps: 2_400
        )

        #expect(context?.type == .routineTemplate)
        #expect(context?.id == "pyramid-intervals")
    }

    @Test
    func aUserAuthoredRoutineWithNoTemplateRanksNowhere() {
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 900,
            trackingMode: .routine,
            climbId: nil,
            routineTemplateId: "",
            targetStepCount: 2_400,
            stopReason: .targetReached
        )

        let context = LiveClimbWorkoutSummaryData.leaderboardContext(
            metadata: metadata,
            resolvedClimbId: nil,
            climbTargetSteps: nil,
            workoutSteps: 2_400
        )

        #expect(context == nil)
    }

    @Test
    func aWorkoutWithNoInAppSessionMetadataRanksNowhere() {
        #expect(
            LiveClimbWorkoutSummaryData.leaderboardContext(
                metadata: nil,
                resolvedClimbId: "burj-khalifa",
                climbTargetSteps: 4_554,
                workoutSteps: 4_554
            ) == nil
        )
    }
}
