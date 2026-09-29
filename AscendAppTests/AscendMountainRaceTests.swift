import Foundation
import Testing
@testable import AscendApp

struct AscendMountainRaceCurveTests {
    @Test
    func aClimbIsDrawnThroughEveryCheckpointItPublished() {
        var curve = MountainRivalCurve(finalSteps: 1_200, finishSeconds: 600)
        curve.record(steps: 20, atSeconds: 10)
        curve.record(steps: 50, atSeconds: 20)

        #expect(curve.steps(at: 0) == 0)
        #expect(curve.steps(at: 5) == 10)
        #expect(curve.steps(at: 10) == 20)
        #expect(curve.steps(at: 15) == 35)
        #expect(curve.steps(at: 20) == 50)
    }

    @Test
    func pastTheLastCheckpointTheClimberHeadsForTheirFinish() {
        var curve = MountainRivalCurve(finalSteps: 1_050, finishSeconds: 520)
        curve.record(steps: 50, atSeconds: 20)

        // A straight line from the last known point to the finish, then held there.
        #expect(curve.steps(at: 270) == 550)
        #expect(curve.steps(at: 520) == 1_050)
        #expect(curve.steps(at: 5_000) == 1_050)
    }

    @Test
    func aGhostNeverWalksBackwards() {
        var curve = MountainRivalCurve(finalSteps: 500, finishSeconds: 300)
        curve.record(steps: 100, atSeconds: 30)
        curve.record(steps: 80, atSeconds: 40)
        curve.record(steps: 900, atSeconds: 50)

        let path = stride(from: 0.0, through: 300, by: 1).map { curve.steps(at: $0) }
        #expect(zip(path, path.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(curve.steps(at: 40) == 100)
        #expect(curve.steps(at: 50) == 500)
    }

    @Test
    func readingTheSameBucketTwiceChangesNothing() {
        var once = MountainRivalCurve(finalSteps: 400, finishSeconds: 200)
        once.record(steps: 60, atSeconds: 30)
        var twice = once
        twice.record(steps: 60, atSeconds: 30)

        #expect(once == twice)
    }

    @Test
    func aClimbWithNoFinishTimeKeepsItsPaceUpToItsLastStep() {
        var curve = MountainRivalCurve(finalSteps: 300, finishSeconds: nil)
        curve.record(steps: 100, atSeconds: 60)

        #expect(curve.steps(at: 120) == 200)
        #expect(curve.steps(at: 600) == 300)
    }
}

struct AscendMountainRaceFieldTests {
    private let context = LiveReplayLeaderboardContext.justClimbGlobal()

    @Test
    func aRunningRivalGainsACheckpointAtTheEndOfTheBucketTheWindowRead() throws {
        var field = MountainRaceField()
        field.ingest(window(bucket: 2, rows: [rival("maya", steps: 45, final: 900, duration: 600)]))

        let curve = try #require(field.climbers["maya"]?.curve)
        #expect(curve.checkpoints == [.init(seconds: 30, steps: 45)])
    }

    @Test
    func aRivalAlreadyHomeAddsNothingItsFinishDidNotSay() throws {
        var field = MountainRaceField()
        field.ingest(window(bucket: 40, rows: [rival("sam", steps: 300, final: 300, duration: 200)]))

        let curve = try #require(field.climbers["sam"]?.curve)
        #expect(curve.checkpoints.isEmpty)
        #expect(curve.steps(at: 410) == 300)
    }

    @Test
    func theClimbersOwnRowsAreNeverOnTheirStairsAsRivals() {
        var field = MountainRaceField()
        let own = row(id: "own-earlier", userId: "me", steps: 80, final: 500, duration: 400, isCurrentUser: true)
        field.ingest(window(bucket: 3, rows: [own]))

        #expect(field.climbers.isEmpty)
        #expect(field.yourBest == nil)
    }

    @Test
    func theClimbersPreviousBestIsKeptApartAsTheirBest() throws {
        var field = MountainRaceField()
        let best = row(id: "own-best", userId: "me", steps: 70, final: 1_776, duration: 1_200, isCurrentUser: true)
        field.ingest(window(bucket: 4, rows: [], ownPreviousCompletionRow: best))
        field.ingest(window(bucket: 5, rows: [], ownPreviousCompletionRow: best.updating(stepsAtBucket: 90)))

        let curve = try #require(field.yourBest)
        #expect(field.climbers.isEmpty)
        #expect(curve.checkpoints.map(\.seconds) == [50, 60])
        #expect(curve.steps(at: 60) == 90)
    }

    private func window(
        bucket: Int,
        rows: [LiveReplayLeaderboardRow],
        ownPreviousCompletionRow: LiveReplayLeaderboardRow? = nil
    ) -> LiveReplayLeaderboardWindow {
        LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: bucket,
            currentSteps: 0,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: rows,
            currentUserRank: 1,
            totalClimbers: max(rows.count + 1, 1),
            ownPreviousCompletionRow: ownPreviousCompletionRow
        )
    }
}

@MainActor
struct AscendMountainRaceGhostTests {
    private let context = LiveReplayLeaderboardContext.justClimbGlobal()

    @Test
    func everyClimbStartsWithEveryoneOnTheStairsAndNothingElse() {
        let race = raceWithField()

        #expect(race.ghosts.map(\.kind) == [.rival, .rival])
        #expect(Set(race.ghosts.map(\.id)) == ["climber-maya", "climber-sam"])
    }

    @Test
    func justYouHidesEveryoneAndTurningItOffBringsBackTheSameField() {
        let race = raceWithField()
        race.selection.yourBest = true
        race.selection.pacer = true
        let before = race.ghosts.map(\.id)

        race.selection.justYou = true
        #expect(race.ghosts.isEmpty)

        race.selection.justYou = false
        #expect(race.ghosts.map(\.id) == before)
        #expect(before.contains("your-best"))
        #expect(before.contains("pacer"))
    }

    @Test
    func yourBestAppearsOnlyWhereTheBoardHoldsOne() {
        let race = AscendMountainRace()
        race.selection.yourBest = true

        #expect(!race.hasYourBest)
        #expect(race.ghosts.isEmpty)
    }

    @Test
    func thePacerHoldsThePaceTheClimberSet() throws {
        let race = AscendMountainRace()
        race.selection.everyone = false
        race.selection.pacer = true
        race.selection.stepPacer(by: 3)

        let pacer = try #require(race.ghosts.first)
        #expect(race.selection.pacerStepsPerMinute == 105)
        #expect(pacer.steps(60) == 105)
        #expect(pacer.label == "PACER · 105 SPM")
    }

    @Test
    func thePacerStaysInsideAClimbablePace() {
        var selection = MountainRaceSelection()
        selection.stepPacer(by: -100)
        #expect(selection.pacerStepsPerMinute == MountainRaceSelection.pacerRange.lowerBound)
        selection.stepPacer(by: 100)
        #expect(selection.pacerStepsPerMinute == MountainRaceSelection.pacerRange.upperBound)
    }

    @Test
    func aTagCarriesTheModeratedFirstNameAndAHiddenClimberWearsNone() {
        let maya = rival("maya", steps: 45, final: 900, duration: 600, displayName: "Maya Chen")
        let blocked = rival("sam", steps: 60, final: 700, duration: 500, displayName: "Sam Rivera")
        let race = AscendMountainRace()
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 40,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: [maya, blocked],
            currentUserRank: 2,
            totalClimbers: 3
        )
        let identities = [maya, blocked].map {
            CrossUserIdentityAdapter.replayRow($0, blockedUserIds: ["climber-sam"], isBlockListHydrated: true)
        }

        race.ingest(window, identities: identities)

        let labels = Dictionary(uniqueKeysWithValues: race.ghosts.map { ($0.id, $0.label) })
        #expect(labels["climber-maya"] == "MAYA")
        #expect(labels["climber-sam"] == "")
    }

    @Test
    func aTagNeverRunsWiderThanTwelveLetters() {
        let row = rival("long", steps: 10, final: 100, duration: 100, displayName: "Bartholomewandrew Smith")
        let identity = CrossUserIdentityAdapter.replayRow(row, blockedUserIds: [], isBlockListHydrated: true).identity

        #expect(AscendMountainRace.tagLabel(for: identity) == "BARTHOLOMEW…")
    }

    @Test
    func namesAreForTheClimbersAroundYouAndFadeFarAhead() {
        #expect(MountainSceneController.tagOpacity(lead: -40) == 1)
        #expect(MountainSceneController.tagOpacity(lead: MountainSceneController.tagFullLead) == 1)
        #expect(MountainSceneController.tagOpacity(lead: 7.5) == 0.5)
        #expect(MountainSceneController.tagOpacity(lead: MountainSceneController.tagHiddenLead) == 0)
        #expect(MountainSceneController.tagOpacity(lead: 90) == 0)
    }

    @Test
    func yourBestLeavesAGoldLineWhereItEndedWhenYouRaceIt() throws {
        let race = raceWithField()
        #expect(race.markers.isEmpty, "only while your best is racing")

        race.selection.yourBest = true
        let line = try #require(race.markers.first)
        #expect(line.kind == .line)
        #expect(line.step == 1_000)
        #expect(line.subtitle == "\(1_000.formatted()) STEPS")

        race.selection.justYou = true
        #expect(race.markers.isEmpty)
    }

    @Test
    func theLineFollowsTheGoalOfTheClimb() throws {
        var best = MountainRivalCurve(finalSteps: 3_000, finishSeconds: 2_400)
        best.record(steps: 1_500, atSeconds: 1_200)

        let open = try #require(AscendMountainRace.bestLine(for: best, goal: JustClimbGoal(kind: .open)))
        let timed = try #require(AscendMountainRace.bestLine(for: best, goal: JustClimbGoal(kind: .duration, durationMinutes: 20)))
        #expect(open.step == 3_000)
        #expect(timed.step == 1_500, "how far the best had come by twenty minutes")
        #expect(AscendMountainRace.bestLine(for: best, goal: JustClimbGoal(kind: .steps, stepCount: 2_000)) == nil)
    }

    private func raceWithField() -> AscendMountainRace {
        let race = AscendMountainRace()
        let rows = [
            rival("maya", steps: 45, final: 900, duration: 600),
            rival("sam", steps: 60, final: 700, duration: 500)
        ]
        let best = row(id: "own-best", userId: "me", steps: 50, final: 1_000, duration: 700, isCurrentUser: true)
        let window = LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 2,
            currentSteps: 40,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: rows,
            currentUserRank: 2,
            totalClimbers: 3,
            ownPreviousCompletionRow: best
        )
        race.ingest(window, identities: rows.map {
            CrossUserIdentityAdapter.replayRow($0, blockedUserIds: [], isBlockListHydrated: true)
        })
        return race
    }
}

struct AscendMountainRacePillWordingTests {
    @Test
    func thePillStatesExactlyWhatTheLockScreenStates() {
        let placing = LiveReplayPersonalPlacing(placing: 2, total: 5)
        let standing = LiveReplayLiveStanding.racing(field: nil, ownClimbs: placing)
        let text = LiveClimbStandingText(rank: 3, rankTotal: 22, standing: standing)
        let lockScreen = LiveClimbActivityAttributes.ContentState(
            steps: 1_240,
            rank: text.rank,
            rankTotal: text.rankTotal,
            ownClimbs: text.ownClimbs,
            board: text.board,
            durationSeconds: 812,
            progress: 0.4,
            status: .recording,
            climbPhotoURLString: nil,
            updatedAt: Date(timeIntervalSince1970: 1_777_777_777)
        )

        #expect(text.detailLabel == "#3 of 22 climbers")
        #expect(lockScreen.standingDetailLabel == text.detailLabel)
        #expect(lockScreen.standingSecondaryLabel == text.secondaryLabel)
    }

    @Test
    func aClimberAloneOnTheBoardIsGivenNoLeaderboardPlacing() {
        let placing = LiveReplayPersonalPlacing(placing: 2, total: 3)
        let text = LiveClimbStandingText(rank: 1, rankTotal: 1, standing: .alone(ownClimbs: placing))

        #expect(text.rank == nil)
        #expect(text.detailLabel == "2nd of your 3 climbs")
    }
}

private func rival(
    _ name: String,
    steps: Int,
    final: Int,
    duration: TimeInterval,
    displayName: String = "Rival"
) -> LiveReplayLeaderboardRow {
    row(id: name, userId: "climber-\(name)", steps: steps, final: final, duration: duration, displayName: displayName)
}

private func row(
    id: String,
    userId: String,
    steps: Int,
    final: Int,
    duration: TimeInterval,
    isCurrentUser: Bool = false,
    displayName: String = "Rival"
) -> LiveReplayLeaderboardRow {
    LiveReplayLeaderboardRow(
        id: id,
        rank: nil,
        displayName: displayName,
        avatarToken: "RV",
        photoURL: nil,
        stepsAtBucket: steps,
        finalSteps: final,
        deltaFromUser: 0,
        isCurrentUser: isCurrentUser,
        isLiveAttempt: false,
        isPersonalBest: isCurrentUser,
        completionDurationSeconds: duration,
        userId: userId
    )
}
