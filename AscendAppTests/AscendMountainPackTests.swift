import Foundation
import Testing
@testable import AscendApp

/// The pack drawn on the stairs: a small, steady set chosen fresh every frame, however many
/// hundreds are racing.
struct AscendMountainPackTests {
    private static func rival(_ id: String, _ lead: Double) -> MountainPack.Candidate {
        MountainPack.Candidate(id: id, kind: .rival, lead: lead)
    }

    @Test
    func thePackIsTheNearestFewAheadAndBehindPlusYourBestAndThePacer() {
        let candidates = (1...40).map { Self.rival("ahead-\($0)", Double($0)) }
            + (1...40).map { Self.rival("behind-\($0)", -Double($0)) }
            + [MountainPack.Candidate(id: "your-best", kind: .personalBest, lead: 30),
               MountainPack.Candidate(id: "pacer", kind: .pacer, lead: -20)]

        let chosen = MountainPack.choose(candidates, limits: .init(), keeping: [])

        #expect(chosen == Set((1...6).map { "ahead-\($0)" } + (1...4).map { "behind-\($0)" } + ["your-best", "pacer"]))
    }

    /// The captain's worst case: every one of 896 climbers on the start line together.
    @Test
    func eightHundredAtTheStartLineStillDrawAPackOfTen() {
        var pack = MountainPack()
        let crowd = (0..<896).map { Self.rival("climber-\($0)", Double($0 % 7) * 0.1 - 0.3) }

        for _ in 0..<120 {
            pack.update(crowd, deltaTime: 1.0 / 60)
        }

        #expect(pack.chosen.count == 10)
        #expect(pack.presence.count == 10, "the start line holds still: nobody fading in or out")
    }

    @Test
    func aDrawnClimberKeepsTheirPlaceAgainstSomeoneOnlyBarelyCloser() {
        let limits = MountainPack.Limits(ahead: 1, behind: 0, hysteresisSteps: 3, minimumDwellSeconds: 0)
        let drawn: Set<String> = ["held"]

        let barely = MountainPack.choose([Self.rival("held", 5), Self.rival("newcomer", 3)], limits: limits, keeping: drawn)
        let clearly = MountainPack.choose([Self.rival("held", 5), Self.rival("newcomer", 1)], limits: limits, keeping: drawn)

        #expect(barely == ["held"])
        #expect(clearly == ["newcomer"])
    }

    /// In a crowd the nearest climbers change every moment; someone who has just joined stays long
    /// enough to be seen rather than flickering out.
    @Test
    func aClimberStaysAWhileAfterJoiningHoweverTheCrowdShifts() {
        var pack = MountainPack(limits: .init(ahead: 1, behind: 0, hysteresisSteps: 0, minimumDwellSeconds: 1.5))
        pack.update([Self.rival("first", 2)], deltaTime: 0.1)
        #expect(pack.chosen == ["first"])

        let crowd = [Self.rival("first", 9)] + (1...5).map { Self.rival("closer-\($0)", Double($0) * 0.5) }
        pack.update(crowd, deltaTime: 1.0)
        #expect(pack.chosen.contains("first"), "a second after joining, they still hold their place")

        pack.update(crowd, deltaTime: 1.0)
        #expect(!pack.chosen.contains("first"), "past the dwell, the nearest takes over")
    }

    @Test
    func climbersFadeInAndOutRatherThanPopping() {
        var pack = MountainPack(limits: .init(ahead: 1, behind: 0, hysteresisSteps: 0, minimumDwellSeconds: 0))
        let step = MountainPack.fadeSeconds / 4

        pack.update([Self.rival("a", 1)], deltaTime: step)
        #expect(abs((pack.presence["a"] ?? 0) - 0.25) < 1e-9)
        for _ in 0..<3 { pack.update([Self.rival("a", 1)], deltaTime: step) }
        #expect(pack.presence["a"] == 1)

        pack.update([Self.rival("a", 5), Self.rival("b", 1)], deltaTime: step)
        #expect(abs((pack.presence["a"] ?? 0) - 0.75) < 1e-9, "a leaves gradually")
        #expect(abs((pack.presence["b"] ?? 0) - 0.25) < 1e-9, "as b arrives")
    }

    /// Anyone standing between the camera and the climber, or right beside them, thins out, so the
    /// climber's own athlete always reads.
    @Test
    func climbersOverYouThinOutAndEveryoneElseIsSolid() {
        #expect(MountainPack.clearance(lead: 6) == 1)
        #expect(MountainPack.clearance(lead: -8) == 1)
        #expect(MountainPack.clearance(lead: -2) < 0.4)
        #expect(MountainPack.clearance(lead: 0) < 0.4)
        let ramp = stride(from: -6.5, through: 1.8, by: 0.1).map { MountainPack.clearance(lead: $0) }
        #expect(zip(ramp, ramp.dropFirst()).allSatisfy { abs($0 - $1) < 0.1 }, "no step anywhere")
    }

    /// Someone level with you climbs beside you, not through you; further off they keep their lane.
    @Test
    func aClimberLevelWithYouStepsToTheirSide() {
        #expect(MountainSceneDirector.passingLane(0.05, lead: 0) == 0.5)
        #expect(MountainSceneDirector.passingLane(-0.1, lead: -1) == -0.5)
        #expect(MountainSceneDirector.passingLane(0.05, lead: 6) == 0.05)
        let drift = stride(from: 0.0, through: 6.0, by: 0.1).map { MountainSceneDirector.passingLane(0.1, lead: $0) }
        #expect(zip(drift, drift.dropFirst()).allSatisfy { abs($0 - $1) < 0.05 }, "a gradual drift, never a hop")
    }

    @Test
    func namesGoOnlyToClimbersAheadAndNeverOnTopOfEachOther() {
        let named = MountainSceneController.named(
            [("level", 0.1), ("behind", -2), ("a", 1.0), ("b", 1.5), ("c", 2.4), ("d", 4.0), ("e", 6.0)],
            limit: 3
        )
        #expect(named == ["a", "c", "d"])
    }

    /// A correction from the board bends a racer's path ahead of them; where they stand does not move.
    @Test
    func aCorrectionFromTheBoardNeverMakesARacerJump() {
        var curve = MountainRivalCurve(finalSteps: 2_000, finishSeconds: 1_000)
        curve.record(steps: 100, atSeconds: 50)
        let before = curve.steps(at: 55)

        curve.pin(atSeconds: 55)
        curve.record(steps: 180, atSeconds: 60)

        #expect(abs(curve.steps(at: 55) - before) < 1e-9)
        #expect(curve.steps(at: 60) == 180)
    }

    @Test
    func aTagIsDrawnOffTheMainActor() async throws {
        let image = await Task.detached {
            MountainAthleteRig.tagImage("MAYA", accent: MountainColor(red: 0.53, green: 0.83, blue: 0.04))
        }.value
        let drawn = try #require(image)
        #expect(drawn.height == 224)
        #expect(drawn.width > drawn.height)
    }
}
