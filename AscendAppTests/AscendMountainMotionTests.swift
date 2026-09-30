import Foundation
import Testing
@testable import AscendApp

/// Simulates the scene's frame loop against a stream of real-looking steps.
private struct ClimbSimulation {
    static let frameSeconds = 1.0 / 60

    var follower = MountainStepFollower(visualSteps: 0)
    var cadence = MountainCadenceEstimator()
    var time = 0.0
    var steps = 0
    var nextStepAt: Double?

    /// Runs `seconds` of frames, taking a step every `stepInterval` seconds (nil: standing still).
    /// Calls `inspect` after each frame with the live count before the follower moved.
    mutating func run(
        seconds: Double,
        stepInterval: Double?,
        inspect: (_ target: Int, _ before: Double, _ follower: MountainStepFollower) -> Void = { _, _, _ in }
    ) {
        if let stepInterval {
            nextStepAt = nextStepAt ?? (time + stepInterval)
        } else {
            nextStepAt = nil
        }
        let end = time + seconds
        while time < end {
            time += Self.frameSeconds
            if let stepAt = nextStepAt, let stepInterval, time >= stepAt {
                steps += 1
                nextStepAt = stepAt + stepInterval
            }
            cadence.observe(stepCount: steps, at: time)
            let before = follower.visualSteps
            follower.advance(
                toward: Double(steps),
                cadence: cadence.stepsPerSecond(at: time),
                deltaTime: Self.frameSeconds
            )
            inspect(steps, before, follower)
        }
    }
}

struct AscendMountainStepFollowerTests {
    @Test
    func neverRunsAheadOfTheWorkoutsCount() {
        var simulation = ClimbSimulation()

        for interval in [1.0, 0.5, 0.4, 0.75] {
            simulation.run(seconds: 8, stepInterval: interval) { target, _, follower in
                #expect(follower.visualSteps <= Double(target) + 1e-9)
            }
        }
    }

    @Test
    func neverSlidesBackWhileClimbing() {
        var simulation = ClimbSimulation()

        simulation.run(seconds: 20, stepInterval: 0.5) { _, before, follower in
            #expect(follower.visualSteps >= before)
        }
    }

    @Test
    func theFirstStepFromStandingStartsMovingOnTheNextFrame() {
        var simulation = ClimbSimulation()
        simulation.run(seconds: 1, stepInterval: nil)

        simulation.steps = 1
        simulation.run(seconds: ClimbSimulation.frameSeconds, stepInterval: nil)

        #expect(simulation.follower.visualSteps > 0)
        #expect(simulation.follower.velocity > 0)
    }

    @Test(arguments: [60.0, 90.0, 120.0, 150.0])
    func aSteadyCadenceClimbsContinuouslyAtThatPace(stepsPerMinute: Double) {
        var simulation = ClimbSimulation()
        let interval = 60 / stepsPerMinute
        simulation.run(seconds: 6, stepInterval: interval)

        var speeds: [Double] = []
        var lags: [Double] = []
        simulation.run(seconds: 10, stepInterval: interval) { target, _, follower in
            speeds.append(follower.velocity)
            lags.append(Double(target) - follower.visualSteps)
        }

        let cadence = stepsPerMinute / 60
        let averageSpeed = speeds.reduce(0, +) / Double(speeds.count)
        #expect(abs(averageSpeed - cadence) / cadence < 0.05, "tracks the real pace on average")
        #expect(speeds.min()! > 0.4 * cadence, "never stalls between steps")
        #expect(speeds.max()! < 1.7 * cadence, "never lurches")
        #expect(lags.max()! < 2.2, "stays within about two stairs of the live count")
    }

    @Test(arguments: [60.0, 120.0, 150.0])
    func stoppingFinishesTheStairAndStandsStillWithinASecond(stepsPerMinute: Double) {
        var simulation = ClimbSimulation()
        simulation.run(seconds: 8, stepInterval: 60 / stepsPerMinute)
        let finalCount = Double(simulation.steps)

        simulation.run(seconds: 1.2, stepInterval: nil)

        #expect(simulation.follower.visualSteps == finalCount)
        #expect(simulation.follower.velocity == 0)
    }

    @Test
    func resumingAfterAStopClimbsAgain() {
        var simulation = ClimbSimulation()
        simulation.run(seconds: 5, stepInterval: 0.5)
        simulation.run(seconds: 4, stepInterval: nil)
        let standing = simulation.follower.visualSteps

        simulation.run(seconds: 2, stepInterval: 0.5)

        #expect(simulation.follower.visualSteps > standing + 2)
        #expect(simulation.follower.velocity > 0)
    }

    @Test
    func aLargeCorrectionJumpsInsteadOfSprinting() {
        var follower = MountainStepFollower(visualSteps: 100)

        follower.advance(toward: 400, cadence: 2, deltaTime: 1.0 / 60)

        #expect(follower.visualSteps == 400)
    }

    @Test
    func aSmallDownwardCorrectionEasesBackWithoutPassingTheCount() {
        var follower = MountainStepFollower(visualSteps: 100)

        for _ in 0..<120 {
            let before = follower.visualSteps
            follower.advance(toward: 95, cadence: 0, deltaTime: 1.0 / 60)
            #expect(follower.visualSteps <= before)
            #expect(follower.visualSteps >= 95)
        }
        #expect(follower.visualSteps == 95)
    }

    @Test
    func aSmallUpwardCorrectionIsClimbedBrisklyAndCompletely() {
        var follower = MountainStepFollower(visualSteps: 0)
        let tuning = MountainStepFollower.Tuning.standard

        // A machine sync adds ten steps at once; the estimator reports no cadence for a jump.
        for _ in 0..<(4 * 60) {
            follower.advance(toward: 10, cadence: 0, deltaTime: 1.0 / 60)
            #expect(follower.velocity <= tuning.catchUpStepsPerSecond + 1e-9)
        }

        #expect(follower.visualSteps == 10)
    }

    @Test
    func invalidInputLeavesTheAvatarWhereItIs() {
        var follower = MountainStepFollower(visualSteps: 12)

        follower.advance(toward: .nan, cadence: 2, deltaTime: 1.0 / 60)
        follower.advance(toward: 20, cadence: 2, deltaTime: 0)
        follower.advance(toward: 20, cadence: 2, deltaTime: -1)

        #expect(follower.visualSteps == 12)
    }
}

struct AscendMountainCadenceEstimatorTests {
    @Test
    func measuresASteadyCadence() {
        var estimator = MountainCadenceEstimator()
        estimator.observe(stepCount: 0, at: 0)
        for step in 1...12 {
            estimator.observe(stepCount: step, at: Double(step) * 0.5)
        }

        #expect(abs(estimator.stepsPerMinute(at: 6.0) - 120) < 0.5)
    }

    @Test
    func theFirstStepAfterStandingAssumesANormalClimb() {
        var estimator = MountainCadenceEstimator()
        estimator.observe(stepCount: 0, at: 0)
        estimator.observe(stepCount: 1, at: 10)

        #expect(estimator.stepsPerSecond(at: 10) == MountainCadenceEstimator.nominalStepsPerSecond)
    }

    @Test
    func decaysOnceTheNextStepIsOverdueAndReachesZero() {
        var estimator = MountainCadenceEstimator()
        estimator.observe(stepCount: 0, at: 0)
        for step in 1...8 {
            estimator.observe(stepCount: step, at: Double(step) * 0.5)
        }
        let lastStepAt = 4.0

        #expect(abs(estimator.stepsPerSecond(at: lastStepAt + 0.4) - 2) < 0.01)
        #expect(estimator.stepsPerSecond(at: lastStepAt + 1.0) <= 1.0)
        #expect(estimator.stepsPerSecond(at: lastStepAt + 1.6) < estimator.stepsPerSecond(at: lastStepAt + 1.0))
        #expect(estimator.stepsPerSecond(at: lastStepAt + MountainCadenceEstimator.restGapSeconds) == 0)
    }

    @Test
    func aStepCorrectionIsNotMistakenForASprint() {
        var estimator = MountainCadenceEstimator()
        estimator.observe(stepCount: 0, at: 0)
        estimator.observe(stepCount: 1, at: 0.5)
        estimator.observe(stepCount: 2, at: 1.0)

        estimator.observe(stepCount: 250, at: 1.1)

        #expect(estimator.stepsPerSecond(at: 1.1) == 0)
    }

    @Test
    func aDownwardCorrectionRestartsTheEstimate() {
        var estimator = MountainCadenceEstimator()
        estimator.observe(stepCount: 10, at: 0)
        estimator.observe(stepCount: 11, at: 0.5)
        estimator.observe(stepCount: 5, at: 0.6)

        #expect(estimator.stepsPerSecond(at: 0.6) == 0)
    }

    @Test
    func implausiblyFastStepsAreCapped() {
        var estimator = MountainCadenceEstimator()
        estimator.observe(stepCount: 0, at: 0)
        for step in 1...6 {
            estimator.observe(stepCount: step, at: Double(step) * 0.06)
        }

        #expect(estimator.stepsPerSecond(at: 0.36) == MountainCadenceEstimator.maximumStepsPerSecond)
    }
}

struct AscendMountainAnimationPacingTests {
    @Test(arguments: [
        (0.0, 0.0, 0.0),
        (60.0, 60.0 / 90, 0.25),
        (90.0, 1.0, 0.5),
        (120.0, 120.0 / 90, 0.75),
        (150.0, 150.0 / 90, 1.0)
    ])
    func followsTheSpecsCadenceTable(stepsPerMinute: Double, playbackRate: Double, intensity: Double) {
        let pacing = MountainAnimationPacing(stepsPerMinute: stepsPerMinute)

        #expect(pacing.gait == (stepsPerMinute == 0 ? .idle : .climbing))
        #expect(abs(pacing.playbackRate - playbackRate) < 1e-9)
        #expect(abs(pacing.intensity - intensity) < 1e-9)
    }

    @Test
    func extremeCadencesAreClampedToABelievableStride() {
        let frantic = MountainAnimationPacing(stepsPerMinute: 600)
        let crawling = MountainAnimationPacing(stepsPerMinute: 25)

        #expect(frantic.playbackRate == MountainAnimationPacing.maximumPlaybackRate)
        #expect(frantic.intensity == 1)
        #expect(crawling.gait == .climbing)
        #expect(crawling.playbackRate == MountainAnimationPacing.minimumPlaybackRate)
        #expect(crawling.intensity == 0)
    }

    @Test(arguments: [Double.nan, -40, 10, .infinity])
    func nonsenseOrNearZeroCadenceIsIdle(stepsPerMinute: Double) {
        let pacing = MountainAnimationPacing(stepsPerMinute: stepsPerMinute)

        #expect(pacing.gait == .idle)
        #expect(pacing.playbackRate == 0)
        #expect(pacing.intensity == 0)
    }

    @Test
    func theFollowersTopSpeedIsTheFastestStride() {
        #expect(MountainStepFollower.Tuning.standard.maximumStepsPerSecond == MountainAnimationPacing.maximumStepsPerSecond)
        #expect(abs(MountainAnimationPacing.maximumStepsPerSecond * 60 - 198) < 1e-9)
    }
}
