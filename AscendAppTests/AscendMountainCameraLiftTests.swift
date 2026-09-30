import Foundation
import simd
import Testing
@testable import AscendApp

/// The camera lift at each gate (captain, board 4: "Camera lifts at each gate"; round 16: build
/// it): the mountain comes into view without a touch, and the climber never leaves the frame.
struct AscendMountainCameraLiftTests {
    private static let seed = MountainCourse.ascendMountainSeed

    @Test
    func theLiftRisesHoldsAndSettles() {
        let lift = MountainCameraLift(startedAt: 10)
        let rise = MountainCameraLift.riseSeconds, hold = MountainCameraLift.holdSeconds

        #expect(lift.amount(at: 10) == 0)
        #expect(lift.amount(at: 10 + rise / 2) == 0.5)
        #expect(lift.amount(at: 10 + rise) == 1)
        #expect(lift.amount(at: 10 + rise + hold / 2) == 1)
        #expect(lift.amount(at: 10 + MountainCameraLift.duration) == 0)
        #expect(!lift.isFinished(at: 10 + MountainCameraLift.duration - 0.01))
        #expect(lift.isFinished(at: 10 + MountainCameraLift.duration))

        let samples = stride(from: 10.0, through: 10 + rise, by: 0.05).map(lift.amount(at:))
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 }, "the rise never dips")
    }

    /// Climbs from `from` at 120 steps a minute for `seconds`, returning every frame.
    private static func climb(
        _ director: inout MountainSceneDirector,
        from: Int,
        seconds: Double,
        fps: Double = 60
    ) -> [MountainSceneFrame] {
        (0..<Int(seconds * fps)).map { tick in
            let time = Double(tick) / fps
            return director.advance(logicalSteps: from + Int(time * 2), time: time, deltaTime: tick == 0 ? 0 : 1 / fps)
        }
    }

    @Test
    func walkingThroughAGateLiftsTheCameraOnceAndSettlesItBack() throws {
        var director = MountainSceneDirector(seed: Self.seed, world: try MountainWorld.bundled())
        var course = MountainCourse(seed: Self.seed)
        let gate = Double(course.markerStep(for: 500))

        let frames = Self.climb(&director, from: 470, seconds: 40)

        let passed = try #require(frames.firstIndex { $0.courseSteps > gate })
        let first = try #require(frames.firstIndex { $0.cameraLift > 0 })
        #expect(first == passed + 1, "rises from the frame the climber passes the gate")
        let settled = try #require(frames[first...].firstIndex { $0.cameraLift == 0 })
        #expect(abs(Double(settled - first) / 60 - MountainCameraLift.duration) < 0.05)
        #expect(frames.map(\.cameraLift).max() == 1)
        #expect(frames[settled...].allSatisfy { $0.cameraLift == 0 }, "one gate, one lift")
    }

    /// Risen, the camera stands well above the climber, and the climber's whole body stays on a
    /// portrait iPhone's screen (402 by 874 points) through every turn: the lens is 60 degrees
    /// tall, which leaves it about 14.9 degrees either side. Checked from a tenth of the way up;
    /// below that the view is still the follow camera's.
    @Test(arguments: [500, 1_000, 2_000, 3_000, 4_000, 10_000, 25_000])
    func theRisenCameraKeepsTheClimberInFrame(gate: Int) throws {
        var director = MountainSceneDirector(seed: Self.seed, world: try MountainWorld.bundled())
        let halfHeight = Float(30)
        let halfWidth = atan(tan(halfHeight * .pi / 180) * 402 / 874) * 180 / .pi

        let frames = Self.climb(&director, from: gate - 20, seconds: 25, fps: 30)

        let risen = frames.filter { $0.cameraLift >= 0.1 }
        #expect(risen.count > 100)
        for frame in risen {
            let look = simd_normalize(frame.cameraTarget - frame.cameraPosition)
            let right = simd_normalize(simd_cross(look, SIMD3<Float>(0, 1, 0)))
            let up = simd_cross(right, look)
            let toClimber = frame.athleteRenderHipCentre - frame.cameraPosition
            let distance = simd_length(toClimber)
            let across = atan2(simd_dot(toClimber, right), simd_dot(toClimber, look)) * 180 / .pi
            let down = atan2(simd_dot(toClimber, up), simd_dot(toClimber, look)) * 180 / .pi
            // Half a body's width and height either side of the hips.
            let halfBody = atan(0.35 / distance) * 180 / .pi
            let halfTall = atan(0.95 / distance) * 180 / .pi
            #expect(abs(across) + halfBody < halfWidth, "\(across) degrees to the side at lift \(frame.cameraLift)")
            #expect(abs(down) + halfTall < halfHeight, "\(down) degrees down at lift \(frame.cameraLift)")
        }
        let top = try #require(risen.first { $0.cameraLift == 1 })
        #expect(top.cameraPosition.y - top.athleteRenderHipCentre.y > 10)
    }

    /// A climber who has asked their phone for reduced motion is never lifted.
    @Test
    func reducedMotionKeepsTheCameraBehindTheClimber() throws {
        var director = MountainSceneDirector(seed: Self.seed, world: try MountainWorld.bundled())
        director.liftsAtGates = false

        let frames = Self.climb(&director, from: 470, seconds: 30)

        #expect(frames.allSatisfy { $0.cameraLift == 0 })
    }

    /// Coming back from the background past a gate, or any other jump in the count, puts the
    /// climber on their stair; it is not them walking through the gate, and lifts nothing.
    @Test
    func aJumpPastAGateLiftsNothing() throws {
        var director = MountainSceneDirector(seed: Self.seed, world: try MountainWorld.bundled())
        _ = Self.climb(&director, from: 480, seconds: 1)

        director.resynchronize()
        let frames = (0..<120).map { tick in
            director.advance(logicalSteps: 530, time: 5 + Double(tick) / 60, deltaTime: 1.0 / 60)
        }

        #expect(frames.allSatisfy { $0.cameraLift == 0 })
    }

    /// The stairs are built out to the lift's reach before the gate, so the risen camera looks
    /// along finished stairs; with no gate near, the usual reach holds.
    @Test
    func theStairsAreBuiltOutBeforeTheCameraRises() throws {
        let world = try MountainWorld.bundled()
        var near = MountainSceneDirector(seed: Self.seed, world: world)
        var far = MountainSceneDirector(seed: Self.seed, world: world)

        let approaching = near.advance(logicalSteps: 480, time: 0, deltaTime: 0)
        let between = far.advance(logicalSteps: 700, time: 0, deltaTime: 0)

        let reach = MountainChunkPool.window(around: approaching.progress.chunkIndex, reach: .lift)
        #expect(Set(approaching.slots.map(\.chunkIndex)).isSuperset(of: Set(reach)))
        #expect(between.slots.count == MountainChunkPool.windowSize)
    }
}
