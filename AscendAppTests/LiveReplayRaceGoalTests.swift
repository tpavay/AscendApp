import Foundation
import Testing
@testable import AscendApp

/// The client half of the race-best rule the captain settled on 2026-09-22.
///
/// The server decides which of a climber's runs is their best for each goal
/// and writes the answer onto every Just Climb entry; the client's whole job is
/// to ask for the right one - the `isBestForUser` flag with no goal, the goal
/// key inside `bestForGoals` otherwise - and to draw the answer as the `BEST`
/// marker and nothing else. A key spelled differently from the server matches
/// nothing, and the board reads as empty rather than wrong, so the spelling and
/// the goal space are held against the same vector the server and the seeds
/// read: `SharedTestVectors/live-replay-race-best-vector.json`.
struct LiveReplayRaceGoalTests {
    private struct RaceBestVector: Decodable {
        struct GoalKeys: Decodable {
            let stepIncrement: Int
            let stepMin: Int
            let stepMax: Int
            let durationIncrementSeconds: Int
            let durationMinSeconds: Int
            let durationMaxSeconds: Int
        }

        struct Goal: Decodable {
            let kind: String
            let steps: Int?
            let seconds: Int?
        }

        struct KeyCase: Decodable {
            let name: String
            let goal: Goal
            let key: String?
        }

        let goalKeys: GoalKeys
        let keyCases: [KeyCase]
    }

    // MARK: - The key the window filters on

    @Test
    func everyGoalKeyIsSpelledTheWayTheServerWritesIt() throws {
        let vector = try Self.sharedVector()
        #expect(vector.keyCases.count >= 7)

        for testCase in vector.keyCases {
            let goal = try #require(Self.raceGoal(for: testCase.goal), Comment(rawValue: testCase.name))
            #expect(goal.entryFilterKey == testCase.key, "\(testCase.name)")
        }
    }

    /// The goal space the server writes keys for is exactly what the setup
    /// sheet can produce, so no goal a climber can pick asks for a key nobody
    /// wrote - and no key is written for a goal nobody can pick.
    @Test
    func theGoalSpaceIsTheSetupSheets() throws {
        let vector = try Self.sharedVector()

        #expect(JustClimbGoal.minimumStepCount == vector.goalKeys.stepMin)
        #expect(JustClimbGoal.maximumStepCount == vector.goalKeys.stepMax)
        #expect(JustClimbGoal.stepCountIncrement == vector.goalKeys.stepIncrement)
        #expect(JustClimbGoal.minimumDurationMinutes * 60 == vector.goalKeys.durationMinSeconds)
        #expect(JustClimbGoal.maximumDurationMinutes * 60 == vector.goalKeys.durationMaxSeconds)
        #expect(JustClimbGoal.durationMinutesIncrement * 60 == vector.goalKeys.durationIncrementSeconds)
    }

    @Test
    func aJustClimbGoalBecomesTheRaceGoalTheBoardIsRunAgainst() {
        #expect(JustClimbGoal(kind: .open).raceGoal == .open)
        #expect(JustClimbGoal(kind: .steps, stepCount: 3_000).raceGoal == .steps(3_000))
        #expect(
            JustClimbGoal(kind: .duration, durationMinutes: 30).raceGoal == .duration(seconds: 1_800)
        )
        #expect(JustClimbGoal(kind: .steps, stepCount: 3_000).raceGoal.entryFilterKey == "steps:3000")
        #expect(
            JustClimbGoal(kind: .duration, durationMinutes: 30).raceGoal.entryFilterKey == "duration:1800"
        )
    }

    /// The open goal reads `isBestForUser`; it never has a `bestForGoals` key,
    /// and its cache key never collides with a goal's.
    @Test
    func theOpenGoalHasNoEntryKeyAndItsOwnCacheKey() {
        #expect(LiveReplayRaceGoal.open.entryFilterKey == nil)
        #expect(LiveReplayRaceGoal.open.cacheKey == "open")
        #expect(LiveReplayRaceGoal.steps(3_000).cacheKey == "steps:3000")
        #expect(LiveReplayRaceGoal.duration(seconds: 1_800).cacheKey == "duration:1800")
    }

    // MARK: - Which boards carry a goal

    /// A tower fixes its own target and a routine its own clock, so a goal
    /// there would name entries the server never flags and the board would
    /// read as empty. Only the global Just Climb board keeps one.
    @Test(arguments: LiveReplayLeaderboardContextType.allCases)
    func onlyAJustClimbBoardCarriesAGoal(type: LiveReplayLeaderboardContextType) {
        let context = LiveReplayLeaderboardContext(
            type: type,
            id: "board",
            targetSteps: 2_000,
            raceGoal: .steps(3_000)
        )

        #expect(context.raceGoal == (type == .justClimb ? .steps(3_000) : .open))
    }

    /// The goal changes which entries a session reads, never which board.
    @Test
    func theRaceGoalNeverChangesWhichBoardTheContextNames() {
        let open = LiveReplayLeaderboardContext.justClimbGlobal(targetSteps: 2_000)
        let stepGoal = LiveReplayLeaderboardContext.justClimbGlobal(
            targetSteps: 3_000,
            raceGoal: .steps(3_000)
        )

        #expect(open.contextKey == stepGoal.contextKey)
        #expect(open.contextKey == "just_climb__global")
        #expect(open != stepGoal)
    }

    // MARK: - The marker, never a row

    /// Settled by the captain on 2026-09-22 after the board drew his 149-step
    /// climb as a second `YOU` row beneath his live one: on every board, the
    /// previous best is the `BEST` marker inside the live row and never a row
    /// of its own. The arithmetic is untouched - the rank the window was
    /// fetched with is the rank it renders - and the marker still has its
    /// position.
    @Test(arguments: LiveReplayLeaderboardContextType.allCases)
    func aPreviousBestIsNeverRenderedAsARowOnAnyBoard(type: LiveReplayLeaderboardContextType) throws {
        let ownBest = Self.ownPreviousBest(stepsAtBucket: 1_776)
        let window = LiveReplayLeaderboardWindow(
            context: LiveReplayLeaderboardContext(type: type, id: "board", targetSteps: 2_000),
            bucketIndex: 30,
            currentSteps: 390,
            fetchedAt: Date(timeIntervalSince1970: 1_790_000_000),
            rows: [
                Self.rival(id: "rival", stepsAtBucket: 2_000),
                ownBest
            ],
            currentUserRank: 2,
            totalClimbers: 2,
            ownPreviousCompletionRow: ownBest
        )

        let rows = window.locallyRankedRows(
            currentSteps: 390,
            currentElapsedSeconds: 300,
            displayName: "Tyler Pavay"
        )

        #expect(rows.map(\.id) == ["rival", "current-user"])
        #expect(rows.contains(where: \.isViewerGhost) == false)
        #expect(rows.filter(\.isCurrentUser).map(\.id) == ["current-user"])
        #expect(rows.map(\.rank) == [1, 2])
        #expect(try #require(window.previousBestStepsAtBucket(currentElapsedSeconds: 300)) == 1_776)
    }

    /// The captain's own morning, at the moment he saw it: an open Just Climb,
    /// his live run at 390 and his previous best - now his most steps, 1,776,
    /// rather than his shortest climb - drawn as the marker alone.
    @Test
    func theCaptainsOpenJustClimbDrawsOneRowOfHisAndTheMarkerAtHisMostSteps() throws {
        let ownBest = Self.ownPreviousBest(stepsAtBucket: 1_776)
        let window = LiveReplayLeaderboardWindow(
            context: .justClimbGlobal(targetSteps: 2_000),
            bucketIndex: 25,
            currentSteps: 390,
            fetchedAt: Date(timeIntervalSince1970: 1_790_000_000),
            rows: [ownBest],
            currentUserRank: 1,
            totalClimbers: 1,
            ownPreviousCompletionRow: ownBest
        )

        let rows = window.locallyRankedRows(
            currentSteps: 390,
            currentElapsedSeconds: 250,
            displayName: "Tyler Pavay"
        )

        #expect(rows.map(\.id) == ["current-user"])
        #expect(rows.first?.rank == 1)
        #expect(try #require(window.previousBestStepsAtBucket(currentElapsedSeconds: 250)) == 1_776)
        #expect(window.needsFreshWindow(currentSteps: 390, currentElapsedSeconds: 250) == false)
    }

    // MARK: - Helpers

    private static func sharedVector() throws -> RaceBestVector {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let vectorURL = repoRoot.appending(path: "SharedTestVectors/live-replay-race-best-vector.json")
        return try JSONDecoder().decode(RaceBestVector.self, from: Data(contentsOf: vectorURL))
    }

    private static func raceGoal(for goal: RaceBestVector.Goal) -> LiveReplayRaceGoal? {
        switch goal.kind {
        case "open":
            return .open
        case "steps":
            return goal.steps.map { .steps($0) }
        case "duration":
            return goal.seconds.map { .duration(seconds: $0) }
        default:
            return nil
        }
    }

    private static func ownPreviousBest(stepsAtBucket: Int) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: "own-best",
            rank: nil,
            displayName: "Tyler Pavay",
            avatarToken: "TP",
            photoURL: nil,
            stepsAtBucket: stepsAtBucket,
            finalSteps: stepsAtBucket,
            deltaFromUser: 0,
            isCurrentUser: true,
            isLiveAttempt: false,
            isPersonalBest: true,
            completionDurationSeconds: 1_201,
            userId: "climber-self"
        )
    }

    private static func rival(id: String, stepsAtBucket: Int) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: id,
            rank: nil,
            displayName: "M. Okafor",
            avatarToken: "MO",
            photoURL: nil,
            stepsAtBucket: stepsAtBucket,
            finalSteps: stepsAtBucket,
            deltaFromUser: 0,
            isCurrentUser: false,
            isPersonalBest: false,
            completionDurationSeconds: nil,
            userId: "climber-\(id)"
        )
    }
}
