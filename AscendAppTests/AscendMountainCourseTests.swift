import Foundation
import simd
import Testing
@testable import AscendApp

struct AscendMountainCourseTests {
    private let rise = MountainStairGeometry.rise
    private let run = MountainStairGeometry.run

    @Test
    func stepZeroIsTheBottomOfTheFirstFlight() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)

        let progress = course.progress(atSteps: 0)

        #expect(progress.chunkIndex == 0)
        #expect(progress.virtualAltitude == 0)
        #expect(progress.progressWithinChunk == 0)
        #expect(progress.pose == .origin)
        #expect(course.placement(at: 0).kind == .mediumFlight)
    }

    @Test
    func everyFlightStepClimbsExactlyOneStair() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)

        for step in 0...MountainChunkKind.mediumFlight.stepCount {
            let progress = course.progress(atSteps: Double(step))
            #expect(abs(progress.virtualAltitude - Double(step) * rise) < 1e-9)
            #expect(abs(progress.pose.position.y - Double(step) * rise) < 1e-9)
            #expect(abs(progress.pose.position.z + Double(step) * run) < 1e-9)
        }
    }

    @Test
    func fractionalStepsSitBetweenTheirStairs() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)

        let progress = course.progress(atSteps: 2.5)

        #expect(abs(progress.virtualAltitude - 2.5 * rise) < 1e-9)
        #expect(abs(progress.progressWithinChunk - 2.5 / 16) < 1e-9)
    }

    @Test
    func piecesJoinWithoutAGap() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)

        for index in 0..<400 {
            let placement = course.placement(at: index)
            let next = course.placement(at: index + 1)
            #expect(next.firstStep == placement.endStep)
            #expect(simd_distance(next.entry.position, placement.exit.position) < 1e-9)
            #expect(abs(next.entry.heading - placement.exit.heading) < 1e-9)
            #expect(abs(next.entryAltitude - placement.exitAltitude) < 1e-9)

            // The pose just before a boundary runs into the pose at it.
            let before = course.progress(atSteps: Double(placement.endStep) - 1e-6).pose
            let at = course.progress(atSteps: Double(placement.endStep)).pose
            #expect(simd_distance(before.position, at.position) < 1e-5)
        }
    }

    @Test
    func onlyFlightsGainAltitude() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)

        for index in 0..<300 {
            let placement = course.placement(at: index)
            let gain = placement.exitAltitude - placement.entryAltitude
            if placement.kind.isFlight {
                #expect(abs(gain - Double(placement.stepCount) * rise) < 1e-9)
            } else {
                #expect(gain == 0)
                #expect(abs(placement.exit.position.y - placement.entry.position.y) < 1e-9)
            }
        }
    }

    @Test
    func theSameSeedAlwaysBuildsTheSameMountain() {
        var first = MountainCourse(seed: 42)
        var second = MountainCourse(seed: 42)
        var other = MountainCourse(seed: 43)

        let firstKinds = (0..<200).map { first.placement(at: $0).kind }
        let secondKinds = (0..<200).map { second.placement(at: $0).kind }
        let otherKinds = (0..<200).map { other.placement(at: $0).kind }

        #expect(firstKinds == secondKinds)
        #expect(firstKinds != otherKinds)
    }

    @Test
    func theSequenceReadsAsAMountainPathNotRandomNoise() {
        var generator = MountainCourseGenerator(seed: MountainCourse.ascendMountainSeed)
        var previous: MountainChunkKind?
        var consecutiveFlights = 0
        var netQuarterTurns = 0
        var counts: [MountainChunkKind: Int] = [:]

        for _ in 0..<20_000 {
            let kind = generator.next()
            counts[kind, default: 0] += 1

            if let previous, !previous.isFlight {
                #expect(kind.isFlight, "a break is always followed by a flight")
            }
            consecutiveFlights = kind.isFlight ? consecutiveFlights + 1 : 0
            #expect(consecutiveFlights <= 2, "at most two flights run back to back")

            if kind == .leftTurn { netQuarterTurns += 1 }
            if kind == .rightTurn { netQuarterTurns -= 1 }
            #expect((-1...1).contains(netQuarterTurns), "the path never curls back on itself")
            previous = kind
        }

        for kind in MountainChunkKind.allCases {
            #expect((counts[kind] ?? 0) > 500, "\(kind) appears")
        }
    }

    @Test
    func theCourseNeverHeadsBackDownTheMountain() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        var furthest = 0.0

        for index in 0..<2_000 {
            let placement = course.placement(at: index)
            // Heading 0 climbs toward -Z; turns only ever swing a quarter either way and back.
            #expect(cos(placement.entry.heading) > -1e-9)
            let progressAlongStart = -placement.exit.position.z
            #expect(progressAlongStart >= furthest - 1e-9)
            furthest = max(furthest, progressAlongStart)
        }
    }

    @Test
    func stepsBelowZeroStandOnTheLeadInFlight() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)

        let halfStepBelow = course.progress(atSteps: -0.5)
        let wellBelow = course.progress(atSteps: -40)

        #expect(halfStepBelow.chunkIndex == -1)
        #expect(abs(halfStepBelow.virtualAltitude + 0.5 * rise) < 1e-9)
        #expect(wellBelow.chunkIndex == -3)
        #expect(abs(wellBelow.pose.position.y + 40 * rise) < 1e-9)
        #expect(simd_distance(course.placement(at: -1).exit.position, MountainPose.origin.position) < 1e-9)
    }

    @Test
    func goingBackBehindTheWindowRebuildsTheSameCourse() {
        var travelled = MountainCourse(seed: 7)
        var fresh = MountainCourse(seed: 7)

        _ = travelled.progress(atSteps: 50_000)
        let rewound = travelled.progress(atSteps: 1_234.5)

        #expect(rewound == fresh.progress(atSteps: 1_234.5))
    }

    @Test
    func memoryStaysFlatHoweverFarTheClimbGoes() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)

        let progress = course.progress(atSteps: 1_000_000)

        #expect(progress.totalSteps == 1_000_000)
        #expect(progress.virtualAltitude > 100_000)
        #expect(course.retainedPlacementCount <= MountainCourse.retainedPlacementsBehind * 8)
    }

    @Test
    func aTurnCarriesTheClimberRoundAQuarterTurnOntoTheNextFlight() {
        for kind in [MountainChunkKind.leftTurn, .rightTurn] {
            let exit = kind.exitPose
            let side: Double = kind == .leftTurn ? -1 : 1
            let firstTreadOfNextFlight = exit.composed(with: MountainChunkKind.shortFlight.localPose(atStep: 1))

            #expect(abs(exit.heading - kind.headingChange) < 1e-9)
            #expect(exit.position.y == 0)
            // The next flight's first riser sits exactly on the platform's open side.
            let riserX = exit.position.x + exit.forward.x * MountainStairGeometry.run / 2
            #expect(abs(riserX - side * MountainStairGeometry.width / 2) < 1e-9)
            #expect(firstTreadOfNextFlight.position.y == MountainStairGeometry.rise)
        }
    }
}
