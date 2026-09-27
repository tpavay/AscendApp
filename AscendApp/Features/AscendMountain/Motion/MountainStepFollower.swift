import Foundation

/// Turns the workout's discrete step count into smooth, continuous climbing (spec 7).
///
/// Steps arrive as whole-number jumps; snapping the avatar up a stair on each one would stutter.
/// The follower keeps a separate `visualSteps` that chases the authoritative count at the pace
/// the steps are arriving, trailing by a fraction of a stride that grows with cadence. At a
/// steady cadence each new step lands just as the avatar finishes the last one, so it climbs
/// without pausing; when steps stop, the trailing distance falls to zero and the avatar finishes
/// the stair it is on and stands still.
///
/// It only ever reads the workout's count - nothing here can add, remove or infer a step.
struct MountainStepFollower: Equatable, Sendable {
    struct Tuning: Equatable, Sendable {
        /// How far behind the live count the avatar rides, in seconds of the current cadence.
        var latencySeconds = 0.5
        /// Steps per second of correction for each step the avatar is off its trailing distance.
        /// Kept at or below `1 / latencySeconds`, so the avatar always moves forward while it is
        /// behind and so always finishes its last stair.
        var lagGain = 0.8
        /// The fastest the avatar climbs in normal following: `MountainAnimationPacing`'s
        /// fastest stride.
        var maximumStepsPerSecond = MountainAnimationPacing.maximumStepsPerSecond
        /// Once this far behind, the avatar may climb faster than a believable stride to catch up.
        var catchUpLagSteps = 4.0
        var catchUpStepsPerSecond = 6.0
        /// A gap this large is a correction or a rebuilt scene, not climbing: jump rather than
        /// sprint up dozens of stairs.
        var snapLagSteps = 24.0
        /// Rate at which the avatar eases back down after a small downward correction.
        var retreatRate = 8.0
        /// The slowest the avatar climbs while it is behind, so the last fraction of a stair is
        /// finished at a walk instead of creeping in forever once cadence has fallen to zero.
        var minimumSettleStepsPerSecond = 0.6
        /// With no cadence at all - a correction, or steps that arrived after a long stand - the
        /// avatar closes this fraction of its remaining lag each second.
        var settleRate = 1.5

        static let standard = Tuning()
    }

    let tuning: Tuning
    private(set) var visualSteps: Double
    /// The current climbing speed in steps per second.
    private(set) var velocity: Double = 0

    init(visualSteps: Double, tuning: Tuning = .standard) {
        self.visualSteps = visualSteps
        self.tuning = tuning
    }

    /// Advances one frame toward `targetSteps`, given the current cadence in steps per second.
    mutating func advance(toward targetSteps: Double, cadence: Double, deltaTime: Double) {
        guard targetSteps.isFinite, deltaTime.isFinite, deltaTime > 0 else { return }

        let lag = targetSteps - visualSteps
        guard abs(lag) <= tuning.snapLagSteps else {
            snap(to: targetSteps)
            return
        }

        guard lag > 0 else {
            // At the target, or a small correction moved the count down: ease back, never past it.
            visualSteps += lag * (1 - exp(-tuning.retreatRate * deltaTime))
            if abs(targetSteps - visualSteps) < 0.001 { visualSteps = targetSteps }
            velocity = 0
            return
        }

        let safeCadence = cadence.isFinite ? max(cadence, 0) : 0
        let trailingSteps = safeCadence * tuning.latencySeconds
        let speedLimit = lag > tuning.catchUpLagSteps
            ? max(tuning.catchUpStepsPerSecond, tuning.maximumStepsPerSecond)
            : tuning.maximumStepsPerSecond
        let cruise = safeCadence > 0
            ? safeCadence + tuning.lagGain * (lag - trailingSteps)
            : tuning.settleRate * lag
        let speed = min(max(cruise, tuning.minimumSettleStepsPerSecond), speedLimit)

        let advance = min(speed * deltaTime, lag)
        visualSteps += advance
        velocity = advance / deltaTime
        if targetSteps - visualSteps < 0.001 {
            visualSteps = targetSteps
        }
    }

    mutating func snap(to steps: Double) {
        guard steps.isFinite else { return }
        visualSteps = steps
        velocity = 0
    }
}
