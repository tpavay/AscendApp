import Foundation
import simd
import Testing
@testable import AscendApp

/// The journey: a climb stands on the mountain where the climber's earlier climbs left off, and
/// only the scenery moves (captain, round 16: "the journey decides the scenery; racing always
/// starts from your start line").
struct AscendMountainJourneyTests {
    private static let seed = MountainCourse.ascendMountainSeed

    /// Round 11: "Victor has climbed 15,000 in total, so his climb today happens around 15,000."
    @Test(arguments: [0, 15_000, 31_400])
    func aClimbStandsOnTheMountainWhereTheJourneyLeftOff(journey: Int) throws {
        var director = MountainSceneDirector(seed: Self.seed, world: try MountainWorld.bundled(), journeyStart: journey)

        let frame = director.advance(logicalSteps: 40, time: 0, deltaTime: 0)

        #expect(frame.logicalSteps == 40, "the count is this climb's own")
        #expect(frame.visualSteps == 40)
        #expect(frame.courseSteps == Double(journey + 40))
        var course = MountainCourse(seed: Self.seed)
        #expect(frame.progress.pose == course.progress(atSteps: Double(journey + 40)).pose)
        // The posts ahead read the mountain's own numbers from here.
        let steps = frame.markers.map(\.marker.step)
        #expect(steps.contains(journey + 100))
        #expect(steps.allSatisfy { $0 >= journey + 40 - Int(MountainWorld.markersBehind) })
    }

    /// Everyone this climber races starts from their start line, wherever on the mountain that is:
    /// a ghost's lead is counted in this climb's steps, and it stands that far up from the start.
    @Test
    func aGhostRacesFromTheClimbersStartLineOnTheJourney() {
        var director = MountainSceneDirector(seed: Self.seed, journeyStart: 15_000)
        let pacer = MountainGhostSample(id: "pacer", kind: .pacer, label: "PACER", steps: 30, stepsPerMinute: 90)

        let frame = director.advance(logicalSteps: 10, time: 0, deltaTime: 0, ghosts: [pacer])

        let ghost = frame.ghosts[0]
        #expect(abs(ghost.lead - 20) < 1e-9)
        var course = MountainCourse(seed: Self.seed)
        #expect(simd_distance(ghost.kinematics.bodyPose.position, course.progress(atSteps: 15_030).pose.position) < 1)
    }

    /// The line of the climber's best is where their best ended in this climb's steps, stood on
    /// the journey's stair for it, and still says the steps of the best.
    @Test
    func aClimbsOwnLineStandsOnTheJourneyAndKeepsItsWords() throws {
        var director = MountainSceneDirector(seed: Self.seed, journeyStart: 15_000)
        let line = MountainMarker(id: "your-best-line-120", step: 120, kind: .line, title: "YOUR BEST", subtitle: "120 STEPS")

        let frame = director.advance(logicalSteps: 40, time: 0, deltaTime: 0, extraMarkers: [line])

        let placed = try #require(frame.markers.first { $0.marker.id == line.id })
        #expect(placed.marker.step == 15_120)
        #expect(placed.marker.subtitle == "120 STEPS")
        var course = MountainCourse(seed: Self.seed)
        let expected = course.progress(atSteps: 15_120).pose.position - frame.renderOrigin
        #expect(simd_distance(SIMD3<Double>(placed.renderPosition), expected) < 1e-3)
    }

    /// A journey total that lands while the climber is still on the start line moves the whole
    /// start line there, without climbing the difference on screen.
    @Test
    func aTotalThatArrivesOnTheStartLineMovesTheStartLine() {
        var director = MountainSceneDirector(seed: Self.seed)
        _ = director.advance(logicalSteps: 0, time: 0, deltaTime: 0)

        director.rebase(journeyStart: 15_400)
        let frame = director.advance(logicalSteps: 0, time: 1.0 / 60, deltaTime: 1.0 / 60)

        #expect(director.journeyStart == 15_400)
        #expect(frame.visualSteps == 0)
        #expect(frame.courseSteps == 15_400)
        #expect(frame.followerVelocity == 0)
    }

    // MARK: - Summits

    @Test(arguments: [
        (0.0, 10_000), (9_999, 10_000), (10_000, 25_000), (15_000, 25_000), (31_400, 50_000),
        (99_999, 100_000), (100_000, 250_000), (250_000, 500_000), (600_000, 750_000)
    ])
    func theNextSummitIsTheFirstAboveTheClimber(steps: Double, summit: Int) throws {
        #expect(try MountainWorld.bundled().nextSummit(above: steps) == summit)
    }

    @Test(arguments: [(0.0, 0), (9_999, 0), (15_000, 10_000), (31_400, 25_000), (260_000, 250_000)])
    func theClimbTowardASummitBeganAtTheOneBelow(steps: Double, summit: Int) throws {
        #expect(try MountainWorld.bundled().previousSummit(atOrBelow: steps) == summit)
    }

    /// The summits the captain proposed in round 16 - 10,000, 25,000, 50,000, 100,000 and
    /// 250,000, then on every 250,000 - stand as summit gates, and 20,000 keeps its grand gate.
    @Test
    func everySummitStandsAsItsOwnGate() throws {
        let world = try MountainWorld.bundled()

        for summit in [10_000, 25_000, 50_000, 100_000, 250_000, 500_000] {
            let gate = try #require(world.markers(near: Double(summit), behind: 0, ahead: 0).first)
            #expect(gate.kind == .gate && gate.design == MountainMarker.summitDesign, "\(summit)")
            #expect(gate.title == summit.formatted() && gate.subtitle == "SUMMIT", "\(summit)")
        }
        let grand = try #require(world.markers(near: 20_000, behind: 0, ahead: 0).first)
        #expect(grand.design == "gate_grand")
    }
}

// MARK: - The journey total

@MainActor
private final class FakeJourneyTotals: MountainJourneyTotalSource {
    let local: Int?
    let server: Result<Int, any Error>

    init(local: Int?, server: Result<Int, any Error>) {
        self.local = local
        self.server = server
    }

    func localTotalSteps(userId: String?) -> Int? { local }

    func serverTotalSteps(userId: String) async throws -> Int {
        try server.get()
    }
}

/// A server read that answers only when the test says so.
@MainActor
private final class HeldJourneyTotals: MountainJourneyTotalSource {
    private(set) var pending: CheckedContinuation<Int, any Error>?

    func localTotalSteps(userId: String?) -> Int? { nil }

    func serverTotalSteps(userId: String) async throws -> Int {
        try await withCheckedThrowingContinuation { pending = $0 }
    }

    func answer(_ steps: Int) {
        pending?.resume(returning: steps)
        pending = nil
    }
}

private struct Offline: Error {}

@MainActor
struct AscendMountainJourneyTotalTests {
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "journey-tests-\(UUID().uuidString)"))
    }

    @Test
    func aClimberWithNoReadingStartsAtTheFoot() async {
        let journey = MountainJourney(source: FakeJourneyTotals(local: nil, server: .failure(Offline())), defaults: defaults)

        await journey.load(userId: "victor")

        #expect(journey.startSteps == 0)
    }

    /// The phone has a climb the moment it is saved; the server has every phone's climbs. Each
    /// lags in its own way, so the larger is the truer.
    @Test(arguments: [(12_000, 15_400, 15_400), (16_000, 15_400, 16_000)])
    func theLargerOfThePhoneAndTheServerWins(local: Int, server: Int, start: Int) async {
        let journey = MountainJourney(source: FakeJourneyTotals(local: local, server: .success(server)), defaults: defaults)

        await journey.load(userId: "victor")

        #expect(journey.startSteps == start)
    }

    @Test
    func anOfflineClimbStartsFromTheLastServerTotalRemembered() async {
        await MountainJourney(source: FakeJourneyTotals(local: 3_000, server: .success(15_400)), defaults: defaults)
            .load(userId: "victor")

        let offline = MountainJourney(source: FakeJourneyTotals(local: 3_000, server: .failure(Offline())), defaults: defaults)
        await offline.load(userId: "victor")

        #expect(offline.startSteps == 15_400)
    }

    @Test
    func aRememberedTotalBelongsToItsClimberAlone() async {
        await MountainJourney(source: FakeJourneyTotals(local: nil, server: .success(15_400)), defaults: defaults)
            .load(userId: "victor")

        let someoneElse = MountainJourney(source: FakeJourneyTotals(local: nil, server: .failure(Offline())), defaults: defaults)
        await someoneElse.load(userId: "maya")

        #expect(someoneElse.startSteps == 0)
    }

    /// The climb never waits on the network: the start is set from what the phone knows before
    /// the server is asked, and moves only when the answer arrives.
    @Test
    func theClimbNeverWaitsForTheServer() async throws {
        defaults.set(15_400, forKey: MountainJourney.rememberedKey(userId: "victor"))
        let totals = HeldJourneyTotals()
        let journey = MountainJourney(source: totals, defaults: defaults)

        let loading = Task { await journey.load(userId: "victor") }
        while totals.pending == nil { await Task.yield() }

        #expect(journey.startSteps == 15_400)
        totals.answer(15_900)
        await loading.value
        #expect(journey.startSteps == 15_900)
        #expect(journey.remembered(userId: "victor") == 15_900)
    }
}
