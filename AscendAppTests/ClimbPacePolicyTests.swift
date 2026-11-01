import Foundation
import Testing

@testable import AscendApp

/// The automatic plausibility check on a climb Ascend did not measure.
///
/// The boundaries are the product: a typed climb at exactly 200 steps a minute ranks, one step
/// more is saved and kept off the boards, and 300 is refused. The shared vector pins the same
/// cases against the server derivation and the Firestore rules, so the number the phone shows and
/// the number the board ranks on cannot drift apart.
struct ClimbPacePolicyTests {
    private struct Vector: Decodable {
        let leaderboardCeilingStepsPerMinute: Double
        let absurdStepsPerMinute: Double
        let liveSensorCeilingStepsPerMinute: Double
        let cases: [Case]

        struct Case: Decodable {
            let name: String
            let source: String
            let steps: Int
            let durationSeconds: Double
            let verdict: String
            let saveable: Bool
            let deviceLeaderboardStatus: String
            let serverCountsOnLeaderboards: Bool
        }
    }

    private static func vector() throws -> Vector {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appending(path: "SharedTestVectors/climb-pace-policy-vector.json")
        return try JSONDecoder().decode(Vector.self, from: Data(contentsOf: url))
    }

    private static func verdictName(_ verdict: ClimbPacePolicy.Verdict) -> String {
        switch verdict {
        case .withinCeiling: return "withinCeiling"
        case .aboveCeiling: return "aboveCeiling"
        case .absurd: return "absurd"
        }
    }

    @Test
    func theThresholdsMatchTheSharedVector() throws {
        let vector = try Self.vector()

        #expect(ClimbPacePolicy.leaderboardCeilingStepsPerMinute == vector.leaderboardCeilingStepsPerMinute)
        #expect(ClimbPacePolicy.absurdStepsPerMinute == vector.absurdStepsPerMinute)
        #expect(WorkoutPlausibilityPolicy.maximumAverageStepsPerMinute == vector.liveSensorCeilingStepsPerMinute)
    }

    @Test
    func everySharedVectorCaseGetsTheSameAnswerOnTheDevice() throws {
        let vector = try Self.vector()
        #expect(vector.cases.count >= 10, "the vector should carry every boundary")

        for testCase in vector.cases {
            let source = try #require(WorkoutSource(rawValue: testCase.source), "\(testCase.name)")
            let verdict = ClimbPacePolicy.verdict(steps: testCase.steps, duration: testCase.durationSeconds)

            #expect(Self.verdictName(verdict) == testCase.verdict, "\(testCase.name): verdict")
            #expect(verdict.isSaveable == testCase.saveable, "\(testCase.name): saveable")
            #expect(
                ClimbPacePolicy.leaderboardStatus(
                    origin: source.climbOrigin,
                    steps: testCase.steps,
                    duration: testCase.durationSeconds
                ).rawValue == testCase.deviceLeaderboardStatus,
                "\(testCase.name): device status"
            )
        }
    }

    // MARK: - Boundaries, written out

    @Test
    func aClimbAtExactlyTheCeilingRanks() {
        // 6,000 steps in 30 minutes is 200 a minute.
        #expect(ClimbPacePolicy.verdict(steps: 6_000, duration: 1_800) == .withinCeiling)
    }

    @Test
    func aClimbOneStepOverTheCeilingIsSavedAndKeptOffTheBoards() {
        let verdict = ClimbPacePolicy.verdict(steps: 6_001, duration: 1_800)

        guard case .aboveCeiling(let pace) = verdict else {
            Issue.record("expected aboveCeiling, got \(verdict)")
            return
        }
        #expect(pace > 200 && pace < 201)
        #expect(verdict.isSaveable)
        #expect(verdict.leaderboardStatus == .excluded)
    }

    @Test
    func aClimbAtTheAbsurdLineIsRefused() {
        // 9,000 steps in 30 minutes is exactly 300 a minute.
        let verdict = ClimbPacePolicy.verdict(steps: 9_000, duration: 1_800)

        guard case .absurd = verdict else {
            Issue.record("expected absurd, got \(verdict)")
            return
        }
        #expect(!verdict.isSaveable)
    }

    @Test
    func justUnderTheAbsurdLineStillSaves() {
        #expect(ClimbPacePolicy.verdict(steps: 8_999, duration: 1_800).isSaveable)
    }

    @Test
    func theMocksImpossibleClimbIsRefusedWithItsPace() {
        // 49,120 steps in 40:00, the screen the product owner drew: 1,228 a minute.
        guard case .absurd(let pace) = ClimbPacePolicy.verdict(steps: 49_120, duration: 2_400) else {
            Issue.record("expected absurd")
            return
        }
        #expect(Int(pace.rounded()) == 1_228)
    }

    @Test
    func aClimbWithNoStepsOrNoTimeHasNoPaceToJudge() {
        #expect(ClimbPacePolicy.stepsPerMinute(steps: 0, duration: 1_800) == nil)
        #expect(ClimbPacePolicy.stepsPerMinute(steps: 3_000, duration: 0) == nil)
        #expect(ClimbPacePolicy.verdict(steps: 0, duration: 1_800) == .withinCeiling)
        #expect(ClimbPacePolicy.verdict(steps: 3_000, duration: 0) == .withinCeiling)
    }

    @Test
    func anEntryWaitingForItsStepsIsNeverOnTheBoards() {
        #expect(ClimbPacePolicy.leaderboardStatus(origin: .manual, steps: 0, duration: 1_800) == .excluded)
        #expect(ClimbPacePolicy.leaderboardStatus(origin: .healthImport, steps: 0, duration: 1_800) == .excluded)
        // A live climb's zero is a finished measurement and keeps today's behaviour.
        #expect(ClimbPacePolicy.leaderboardStatus(origin: .live, steps: 0, duration: 1_800) == .eligible)
    }

    @Test
    func aLiveClimbIsNeverExcludedOnTheDeviceWhateverItsPace() {
        #expect(ClimbPacePolicy.leaderboardStatus(origin: .live, steps: 6_600, duration: 1_800) == .eligible)
        #expect(ClimbPacePolicy.leaderboardStatus(origin: .live, steps: 8_000, duration: 1_800) == .eligible)
    }

    @Test
    func theCeilingSitsAboveTheFastestMachineSettingAndTheMeasuredClimbers() {
        // StairMaster's top console setting, and the fastest of the 104 production climbs
        // measured on 2026-10-30. An honest climber at either must never be excluded.
        let fastestMachineSetting = Double(SPMMappingService.levelToSPM.last ?? 0)
        #expect(ClimbPacePolicy.leaderboardCeilingStepsPerMinute > fastestMachineSetting)
        #expect(ClimbPacePolicy.leaderboardCeilingStepsPerMinute > 127)
        // And the refusal line sits above the ceiling by a real band, so a saved-but-excluded
        // climb exists to be told about.
        #expect(ClimbPacePolicy.absurdStepsPerMinute > ClimbPacePolicy.leaderboardCeilingStepsPerMinute)
    }

    // MARK: - Stored climbs

    @Test
    func aLiveClimbKeepsTheSensorGateAndATypedOneTheRefusalLine() {
        // 250 a minute: past the 220 sensor gate, under the 300 line.
        #expect(
            WorkoutPlausibilityPolicy.hasPlausibleTotals(origin: .live, steps: 7_500, duration: 1_800) == false
        )
        #expect(
            WorkoutPlausibilityPolicy.hasPlausibleTotals(origin: .manual, steps: 7_500, duration: 1_800)
        )
        #expect(
            WorkoutPlausibilityPolicy.hasPlausibleTotals(origin: .manual, steps: 9_000, duration: 1_800) == false
        )
        #expect(
            WorkoutPlausibilityPolicy.hasPlausibleTotals(origin: .manual, steps: 3_000, duration: 0) == false
        )
    }

    @Test
    func aStoredClimbFlipsOnAndOffTheBoardsWhenItsStepsAreEdited() {
        let workout = Workout(
            name: "Stair Stepper",
            duration: 1_800,
            steps: 6_001,
            floors: Workout.stepsToFloors(6_001),
            source: .manual
        )
        #expect(workout.refreshLeaderboardStatus())
        #expect(workout.leaderboardStatus == .excluded)
        #expect(workout.exceedsPaceCeiling)

        workout.steps = 6_000
        workout.floors = Workout.stepsToFloors(6_000)
        #expect(workout.refreshLeaderboardStatus())
        #expect(workout.leaderboardStatus == .eligible)
        #expect(!workout.exceedsPaceCeiling)

        workout.duration = 1_700
        #expect(workout.refreshLeaderboardStatus())
        #expect(workout.leaderboardStatus == .excluded)

        // Nothing moved, so nothing flips: the check is not a thing that happens on a schedule.
        #expect(!workout.refreshLeaderboardStatus())
    }
}
