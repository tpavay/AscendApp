import Foundation
import simd
import Testing
@testable import AscendApp

struct AscendMountainSceneDirectorTests {
    private static let frameSeconds = 1.0 / 60

    /// Everything handed to RealityKit, as distances from the render origin.
    private static func renderDistances(_ frame: MountainSceneFrame) -> [Float] {
        frame.slots.map { simd_length($0.renderPosition) } + [
            simd_length(frame.athleteRenderHipCentre),
            simd_length(frame.athleteRenderLeftFoot),
            simd_length(frame.athleteRenderRightFoot),
            simd_length(frame.cameraPosition),
            simd_length(frame.cameraTarget)
        ]
    }

    @Test(arguments: [10_000, 100_000, 1_000_000])
    func aHugeClimbStillRendersBesideTheOrigin(steps: Int) {
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed)
        var time = 0.0
        var frame = director.advance(logicalSteps: steps, time: time, deltaTime: 0)

        // Keep climbing at 120 SPM for twenty seconds past the jump.
        for tick in 1...(20 * 60) {
            time += Self.frameSeconds
            frame = director.advance(logicalSteps: steps + tick / 30, time: time, deltaTime: Self.frameSeconds)
            #expect(Self.renderDistances(frame).allSatisfy { $0 < 100 })
        }

        #expect(frame.logicalSteps == steps + 40)
        #expect(frame.progress.virtualAltitude > Double(steps) * MountainStairGeometry.rise * 0.5)
        #expect(frame.slots.count == MountainChunkPool.windowSize)
        #expect(director.course.retainedPlacementCount <= MountainCourse.retainedPlacementsBehind * 8)
    }

    @Test
    func aRebuiltSceneResumesOnTheLiveStairInsteadOfReclimbing() {
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed)

        let frame = director.advance(logicalSteps: 5_000, time: 0, deltaTime: 0)

        #expect(frame.visualSteps == 5_000)
        #expect(frame.progress.totalSteps == 5_000)
    }

    @Test
    func aLongClimbKeepsExactlySixChunksAroundTheAthlete() {
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed)
        var time = 0.0
        var reassignments = 0

        // Ten minutes at 120 SPM, at 30 frames a second to keep the test quick.
        for tick in 0..<(10 * 60 * 30) {
            time += 1.0 / 30
            let frame = director.advance(logicalSteps: tick / 15, time: time, deltaTime: 1.0 / 30)
            reassignments += frame.reassignedSlots.count

            let window = MountainChunkPool.window(around: frame.progress.chunkIndex)
            #expect(frame.slots.count == MountainChunkPool.windowSize)
            #expect(Set(frame.slots.map(\.chunkIndex)) == Set(window))
        }

        // Every piece that entered the window took over a slot; no slot was ever added.
        #expect(director.pool.slotCount == MountainChunkPool.windowSize)
        #expect(director.pool.recycleCount == reassignments - MountainChunkPool.windowSize)
        #expect(director.pool.recycleCount > 50)
    }

    @Test
    func theAthleteStandsOnTwoTreadsWhenStill() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        let rise = MountainStairGeometry.rise

        let athlete = MountainAthleteKinematics(
            visualSteps: 7,
            intensity: 0,
            movement: 0,
            time: 0,
            pose: { course.progress(atSteps: $0).pose }
        )

        // Stair 7 takes the right foot, stair 6 the left; both sit on their treads.
        #expect(abs(athlete.rightFoot.y - 7 * rise) < 1e-9)
        #expect(abs(athlete.leftFoot.y - 6 * rise) < 1e-9)
        #expect(abs(athlete.bodyPose.position.y - 6.5 * rise) < 1e-9)
    }

    @Test
    func aStepCarriesTheTrailingFootTwoStairsUp() {
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        let rise = MountainStairGeometry.rise
        let pose: (Double) -> MountainPose = { course.progress(atSteps: $0).pose }

        let start = MountainAthleteKinematics(visualSteps: 4, intensity: 0.5, movement: 1, time: 0, pose: pose)
        let midStride = MountainAthleteKinematics(visualSteps: 4.5, intensity: 0.5, movement: 1, time: 0, pose: pose)
        let landed = MountainAthleteKinematics(visualSteps: 4.999_999, intensity: 0.5, movement: 1, time: 0, pose: pose)

        // Stair 4 is the left foot's; the right foot swings from stair 3 to stair 5.
        #expect(abs(start.leftFoot.y - 4 * rise) < 1e-9)
        #expect(abs(start.rightFoot.y - 3 * rise) < 1e-9)
        #expect(midStride.rightFoot.y > 4 * rise, "the swinging foot lifts clear of the stair it passes")
        #expect(abs(landed.rightFoot.y - 5 * rise) < 1e-4)
        #expect(abs(midStride.leftFoot.y - 4 * rise) < 1e-9, "the planted foot does not slide")
    }

    @Test
    func theKneeKeepsBothLegSegmentsTheirLength() {
        let hip = SIMD3<Double>(0, 0.9, 0)
        let foot = SIMD3<Double>(0.05, 0.25, -0.3)

        let knee = MountainAthleteKinematics.knee(hip: hip, foot: foot, forward: SIMD3(0, 0, -1))

        #expect(abs(simd_distance(hip, knee) - MountainAthleteKinematics.thighLength) < 1e-9)
        #expect(abs(simd_distance(knee, foot) - MountainAthleteKinematics.shinLength) < 1e-9)
        #expect(knee.z < -0.1, "the knee bends forward, over the stairs")
    }
}

struct AscendMountainChunkPoolTests {
    @Test
    func startingFillsTheWindowOnceWithoutRecycling() {
        var pool = MountainChunkPool()

        let assignments = pool.update(currentChunk: 0)

        #expect(assignments.map(\.chunkIndex).sorted() == Array(-2...3))
        #expect(pool.activeSlotCount == 6)
        #expect(pool.idleSlotCount == 0)
        #expect(pool.recycleCount == 0)
    }

    @Test
    func movingOnOnePieceRecyclesOnlyTheOldestSlot() {
        var pool = MountainChunkPool()
        _ = pool.update(currentChunk: 0)
        let oldestSlot = pool.slotChunkIndices.firstIndex(of: -2)

        let assignments = pool.update(currentChunk: 1)

        #expect(assignments == [MountainChunkPool.Assignment(slot: oldestSlot!, chunkIndex: 4)])
        #expect(pool.recycleCount == 1)
    }

    @Test
    func standingStillTouchesNothing() {
        var pool = MountainChunkPool()
        _ = pool.update(currentChunk: 12)

        #expect(pool.update(currentChunk: 12).isEmpty)
    }

    @Test
    func aJumpReusesEverySlotWithoutGrowingThePool() {
        var pool = MountainChunkPool()
        _ = pool.update(currentChunk: 0)

        let assignments = pool.update(currentChunk: 94_000)

        #expect(assignments.count == 6)
        #expect(pool.slotCount == 6)
        #expect(Set(pool.slotChunkIndices.compactMap(\.self)) == Set(MountainChunkPool.window(around: 94_000)))
    }

    @Test
    func goingBackDownAPieceReclaimsTheSlotAhead() {
        var pool = MountainChunkPool()
        _ = pool.update(currentChunk: 10)

        let assignments = pool.update(currentChunk: 9)

        #expect(assignments.map(\.chunkIndex) == [7])
        #expect(!pool.slotChunkIndices.contains(13))
    }
}

struct AscendMountainChunkGeometryTests {
    @Test(arguments: [MountainChunkKind.shortFlight, .mediumFlight, .longFlight])
    func aFlightBuildsOneStairPerStep(kind: MountainChunkKind) {
        let geometry = MountainChunkGeometry(kind: kind)

        // Each stair is a block, a nosing strip and a curb either side.
        #expect(geometry.boxCount == kind.stepCount * 4)
        #expect(geometry.positions.count == geometry.boxCount * 24)
        #expect(geometry.normals.count == geometry.positions.count)
        #expect(geometry.indices.count == geometry.boxCount * 36)
        #expect(geometry.triangleSurfaces.count == geometry.indices.count / 3)
    }

    @Test(arguments: MountainChunkKind.allCases)
    func theWalkingSurfaceMeetsTheStepPath(kind: MountainChunkKind) {
        let geometry = MountainChunkGeometry(kind: kind)
        let stone = MountainChunkGeometry.Surface.stone.rawValue

        // The highest stone surface is where the last step lands.
        var highestStone = -Float.infinity
        for (triangle, surface) in geometry.triangleSurfaces.enumerated() where surface == stone {
            for corner in 0..<3 {
                highestStone = max(highestStone, geometry.positions[Int(geometry.indices[triangle * 3 + corner])].y)
            }
        }
        #expect(abs(Double(highestStone) - kind.exitPose.position.y) < 1e-4)
    }

    @Test
    func facesPointOutOfTheirBoxes() {
        let geometry = MountainChunkGeometry(kind: .landing)

        for triangle in 0..<(geometry.indices.count / 3) {
            let a = geometry.positions[Int(geometry.indices[triangle * 3])]
            let b = geometry.positions[Int(geometry.indices[triangle * 3 + 1])]
            let c = geometry.positions[Int(geometry.indices[triangle * 3 + 2])]
            let wound = simd_normalize(simd_cross(b - a, c - a))
            let declared = geometry.normals[Int(geometry.indices[triangle * 3])]
            #expect(simd_dot(wound, declared) > 0.99, "counter-clockwise from outside, matching its normal")
        }
    }
}
