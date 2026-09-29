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
        let candidates = (1...40).map { Self.rival("ahead-\($0)", Double($0) * 2) }
            + (1...40).map { Self.rival("behind-\($0)", -Double($0) * 2) }
            + [MountainPack.Candidate(id: "your-best", kind: .personalBest, lead: 30),
               MountainPack.Candidate(id: "pacer", kind: .pacer, lead: -20)]

        let chosen = MountainPack.choose(candidates, limits: .init(), keeping: [])

        #expect(chosen == Set((1...6).map { "ahead-\($0)" } + (1...4).map { "behind-\($0)" } + ["your-best", "pacer"]))
    }

    /// `count` climbers spread evenly between two leads, each standing where the stairs put them.
    private static func crowd(_ count: Int, from low: Double, to high: Double) -> [MountainPack.Candidate] {
        (0..<count).map { index in
            let id = "climber-\(index)"
            let lead = low + (high - low) * Double(index) / Double(max(count - 1, 1))
            let lane = MountainSceneDirector.passingLane(MountainSceneDirector.lane(for: id), lead: lead)
            return MountainPack.Candidate(id: id, kind: .rival, lead: lead, lane: lane)
        }
    }

    /// No two drawn climbers stand in the same place on the stairs.
    private static func standApart(_ chosen: Set<String>, in candidates: [MountainPack.Candidate]) -> Bool {
        let drawn = candidates.filter { chosen.contains($0.id) }
        return drawn.indices.allSatisfy { first in
            drawn.indices.allSatisfy { second in
                first == second
                    || abs(drawn[first].lead - drawn[second].lead) >= MountainPack.Limits().spacingSteps
                    || abs(drawn[first].lane - drawn[second].lane) >= MountainPack.shoulderWidth
            }
        }
    }

    /// The captain's worst case: every one of 896 climbers on the start line together. Only as
    /// many are drawn as can stand there - one at each shoulder - and the start line holds still.
    @Test
    func eightHundredAtTheStartLineDrawOnlyAsManyAsFitAndHoldStill() {
        var pack = MountainPack()
        let crowd = Self.crowd(896, from: -1.2, to: 1.3)

        for _ in 0..<60 {
            pack.update(crowd, deltaTime: 1.0 / 60)
        }
        let settled = pack.chosen
        for _ in 0..<60 {
            pack.update(crowd, deltaTime: 1.0 / 60)
        }

        #expect(pack.chosen.count >= 2, "someone at each shoulder")
        #expect(Self.standApart(pack.chosen, in: crowd))
        #expect(pack.chosen == settled && pack.presence.count == pack.chosen.count, "nobody fading in or out")
    }

    /// Mid-pack dozens of climbers share each stair. The pack is strung up the stairs ahead of
    /// you in two files, not stacked on your own step.
    @Test
    func aDenseFieldIsDrawnStrungUpTheStairs() {
        let crowd = Self.crowd(900, from: -15, to: 15)

        let chosen = MountainPack.choose(crowd, limits: .init(), keeping: [])
        let ahead = crowd.filter { chosen.contains($0.id) && $0.lead > 0 }.map(\.lead)

        #expect(chosen.count == 10)
        #expect(Self.standApart(chosen, in: crowd))
        #expect((ahead.max() ?? 0) > 2.5, "the furthest drawn ahead is \(ahead.max() ?? 0) steps up")
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
    /// climber's own athlete always reads; anyone closing on the camera fades away before a body
    /// can fill the lens.
    @Test
    func climbersOverYouThinOutAndNobodyFillsTheLens() {
        #expect(MountainPack.clearance(lead: 6) == 1)
        #expect(MountainPack.clearance(lead: -8) == 1, "the chasers just behind you are solid")
        #expect(MountainPack.clearance(lead: -2) < 0.4)
        #expect(MountainPack.clearance(lead: 0) < 0.4)
        #expect(MountainPack.clearance(lead: -13) == 0)
        let ramp = stride(from: -14, through: 1.8, by: 0.1).map { MountainPack.clearance(lead: $0) }
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
