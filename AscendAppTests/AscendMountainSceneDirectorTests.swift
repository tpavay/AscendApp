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

    /// "The mountain is a renderer of the state" (captain, 2026-09-28): steps taken while the app
    /// was in the background are not climbed again on screen when the climber comes back.
    @Test
    func returningFromTheBackgroundShowsTheLiveStairWithoutReplayingTheMissedSteps() {
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed)
        var time = 0.0
        for _ in 0..<30 {
            time += Self.frameSeconds
            _ = director.advance(logicalSteps: 1_200, time: time, deltaTime: Self.frameSeconds)
        }

        // Eighteen steps were climbed off screen - within the follower's normal catch-up range,
        // so without a resynchronization the athlete would visibly climb them again.
        var replaying = director
        let replayed = replaying.advance(logicalSteps: 1_218, time: time + 20, deltaTime: Self.frameSeconds)
        #expect(replayed.visualSteps < 1_218)

        director.resynchronize()
        let frame = director.advance(logicalSteps: 1_218, time: time + 20, deltaTime: Self.frameSeconds)
        #expect(frame.visualSteps == 1_218)
        #expect(frame.progress.totalSteps == 1_218)
        #expect(frame.followerVelocity == 0, "standing on the stair the count says, not climbing to it")
    }

    @Test
    func aRebuiltSceneResumesOnTheLiveStairInsteadOfReclimbing() {
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed)

        let frame = director.advance(logicalSteps: 5_000, time: 0, deltaTime: 0)

        #expect(frame.visualSteps == 5_000)
        #expect(frame.progress.totalSteps == 5_000)
    }

    @Test
    func aLongClimbKeepsItsFixedWindowOfChunksAroundTheAthlete() {
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

        // Every piece that entered the window took over a slot; no slot was ever added, and with
        // no gate to rise over, the slots kept for the camera lift's wider reach stood idle.
        #expect(director.pool.slotCount == MountainChunkPool.Reach.lift.size)
        #expect(director.pool.activeSlotCount == MountainChunkPool.windowSize)
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

        let knee = MountainAthletePoser.knee(root: hip, end: foot, upper: 0.46, lower: 0.46, bendToward: SIMD3(0, 0, -1))

        #expect(abs(simd_distance(hip, knee) - 0.46) < 1e-9)
        #expect(abs(simd_distance(knee, foot) - 0.46) < 1e-9)
        #expect(knee.z < -0.1, "the knee bends forward, over the stairs")
    }

    /// A ghost stands on the stair its record says for the climb's elapsed time, and one far up
    /// or down the mountain is left to the HUD rather than drawn.
    @Test
    func aGhostStandsOnItsOwnStairAndOnlyWhenNear() {
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed)
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        let pacer = MountainGhost.pacer(stepsPerMinute: 90)
        let near = MountainGhostSample(ghost: pacer, elapsed: 20)
        let far = MountainGhostSample(id: "far", kind: .rival, label: "FAR", steps: 900, stepsPerMinute: 80)

        let frame = director.advance(logicalSteps: 10, time: 0, deltaTime: 0, ghosts: [near, far])

        #expect(near.steps == 30, "90 steps a minute for 20 seconds")
        #expect(abs(near.stepsPerMinute - 90) < 1e-9)
        #expect(frame.ghosts.map(\.id) == ["pacer"], "the far ghost is only a number")
        let ghost = frame.ghosts[0]
        #expect(abs(ghost.lead - 20) < 1e-9)
        #expect(simd_distance(ghost.kinematics.bodyPose.position, course.progress(atSteps: 30).pose.position) < 1)
    }

    /// The athlete rides a little behind the live count so the climb looks continuous. Racers
    /// are drawn back by the same distance, so the stairs agree with the rank: someone on your
    /// count climbs level with you, and a leader never sees the climber they lead ahead of them.
    @Test
    func theStairsAgreeWithTheRankWhileTheAthleteTrailsTheCount() throws {
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed)
        let stepsPerSecond = 130.0 / 60
        var onYourCount: [Double] = []
        var justBehind: [Double] = []

        for tick in 0...(12 * 60) {
            let time = Double(tick) * Self.frameSeconds
            let climbed = stepsPerSecond * time
            let count = Int(climbed)
            let ghosts = [
                MountainGhostSample(id: "level", kind: .rival, label: "", steps: Double(count), stepsPerMinute: 130),
                MountainGhostSample(id: "behind", kind: .rival, label: "", steps: climbed - 1.5, stepsPerMinute: 130)
            ]
            let frame = director.advance(logicalSteps: count, time: time, deltaTime: tick == 0 ? 0 : Self.frameSeconds, ghosts: ghosts)
            guard time > 5 else { continue }
            #expect(count - Int(frame.visualSteps) >= 1, "the athlete trails the count, as it is meant to")
            onYourCount.append(try #require(frame.ghosts.first { $0.id == "level" }).lead)
            justBehind.append(try #require(frame.ghosts.first { $0.id == "behind" }).lead)
        }

        #expect(onYourCount.allSatisfy { abs($0) < 0.75 }, "level with you, not a stride ahead")
        #expect(justBehind.allSatisfy { $0 < 0 }, "behind you on the stairs as on the board")
    }

    /// A climb's own mark - the line of the climber's best - stands on its exact stair when it is
    /// near, beside the world's markers, and is let go when it is not.
    @Test
    func aClimbsOwnLineStandsOnItsExactStairWhenNear() throws {
        var director = MountainSceneDirector(seed: MountainCourse.ascendMountainSeed)
        let line = MountainMarker(id: "your-best-line-120", step: 120, kind: .line, title: "YOUR BEST", subtitle: "120 STEPS")
        let far = MountainMarker(id: "your-best-line-900", step: 900, kind: .line, title: "YOUR BEST", subtitle: "900 STEPS")

        let frame = director.advance(logicalSteps: 40, time: 0, deltaTime: 0, extraMarkers: [line, far])

        let placed = try #require(frame.markers.first { $0.marker.id == line.id })
        #expect(!frame.markers.contains { $0.marker.id == far.id })
        var course = MountainCourse(seed: MountainCourse.ascendMountainSeed)
        let expected = course.progress(atSteps: 120).pose.position - frame.renderOrigin
        #expect(simd_distance(SIMD3<Double>(placed.renderPosition), expected) < 1e-3)
    }

    /// A start line full of climbers spreads across the stairs: each keeps its own lane, on the
    /// stairs, the same every time.
    @Test
    func ghostsKeepTheirOwnLaneOnTheStairs() {
        let lanes = (1...30).map { MountainSceneDirector.lane(for: "climber\($0)") }

        #expect(lanes.allSatisfy { abs($0) <= 0.5 }, "inside the kerbs of a 1.6 m stair")
        #expect(Set(lanes.map { ($0 * 100).rounded() }).count > 20, "spread, not queued")
        #expect(MountainSceneDirector.lane(for: "climber7") == lanes[6], "fixed by id")
    }
}

struct AscendMountainChunkPoolTests {
    @Test
    func startingFillsTheWindowOnceWithoutRecycling() {
        var pool = MountainChunkPool()

        let assignments = pool.update(currentChunk: 0)

        #expect(assignments.map(\.chunkIndex).sorted() == Array(-2...6))
        #expect(pool.activeSlotCount == MountainChunkPool.windowSize)
        #expect(pool.idleSlotCount == 0)
        #expect(pool.recycleCount == 0)
    }

    @Test
    func movingOnOnePieceRecyclesOnlyTheOldestSlot() {
        var pool = MountainChunkPool()
        _ = pool.update(currentChunk: 0)
        let oldestSlot = pool.slotChunkIndices.firstIndex(of: -2)

        let assignments = pool.update(currentChunk: 1)

        #expect(assignments == [MountainChunkPool.Assignment(slot: oldestSlot!, chunkIndex: 7)])
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

        #expect(assignments.count == MountainChunkPool.windowSize)
        #expect(pool.slotCount == MountainChunkPool.windowSize)
        #expect(Set(pool.slotChunkIndices.compactMap(\.self)) == Set(MountainChunkPool.window(around: 94_000)))
    }

    /// The camera lift's wider reach takes the spare slots; once it narrows again the pieces it
    /// built stay standing, and a step on recycles the piece furthest behind, never a spare.
    @Test
    func aWiderReachTakesTheSpareSlotsAndLeavesItsPiecesStanding() {
        var pool = MountainChunkPool(slotCount: MountainChunkPool.Reach.lift.size)
        _ = pool.update(currentChunk: 0)
        #expect(pool.activeSlotCount == MountainChunkPool.windowSize)

        let widened = pool.update(currentChunk: 0, reach: .lift)
        #expect(widened.map(\.chunkIndex).sorted() == [-5, -4, -3] + Array(7...18))
        #expect(pool.idleSlotCount == 0)

        #expect(pool.update(currentChunk: 1).isEmpty, "the next piece ahead was already built")
        let stepped = pool.update(currentChunk: 18)
        #expect(stepped.count == 6)
        #expect(Set(pool.slotChunkIndices.compactMap(\.self)).isSuperset(of: Set(MountainChunkPool.window(around: 18))))
    }

    @Test
    func goingBackDownAPieceReclaimsTheSlotAhead() {
        var pool = MountainChunkPool()
        _ = pool.update(currentChunk: 10)

        let assignments = pool.update(currentChunk: 9)

        #expect(assignments.map(\.chunkIndex) == [7])
        #expect(!pool.slotChunkIndices.contains(16))
    }
}

struct AscendMountainChunkGeometryTests {
    @Test(arguments: [MountainChunkKind.shortFlight, .mediumFlight, .longFlight])
    func aFlightLaysOneStoneBlockAndTwoKerbsPerStep(kind: MountainChunkKind) {
        let geometry = MountainChunkGeometry(kind: kind)

        #expect(geometry.pieceCount == kind.stepCount * 3)
        #expect(geometry.positions.count == geometry.indices.count, "flat shading: every triangle owns its corners")
        #expect(geometry.normals.count == geometry.positions.count)
        #expect(geometry.uvs.count == geometry.positions.count)
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

    @Test(arguments: [(MountainChunkKind.mediumFlight, 7), (.mediumFlight, 16), (.longFlight, 1)])
    func everyTreadTopSitsAtItsStairsHeight(kind: MountainChunkKind, stair: Int) {
        let geometry = MountainChunkGeometry(kind: kind)
        let stone = MountainChunkGeometry.Surface.stone.rawValue
        let treadCentre = kind.localPose(atStep: stair).position

        // The upward-facing stone face over the tread centre is at exactly the stair's height.
        var found = false
        for (triangle, surface) in geometry.triangleSurfaces.enumerated() where surface == stone {
            let corners = (0..<3).map { geometry.positions[Int(geometry.indices[triangle * 3 + $0])] }
            guard geometry.normals[Int(geometry.indices[triangle * 3])].y > 0.99,
                  corners.allSatisfy({ abs(Double($0.y) - treadCentre.y) < 1e-4 }) else { continue }
            let zs = corners.map { Double($0.z) }
            if zs.min()! <= treadCentre.z && zs.max()! >= treadCentre.z { found = true }
        }
        #expect(found)
    }

    @Test(arguments: MountainChunkKind.allCases)
    func facesPointTheWayTheirNormalsSay(kind: MountainChunkKind) {
        let geometry = MountainChunkGeometry(kind: kind)

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
