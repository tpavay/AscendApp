import Foundation

/// Maps climbing cadence to how the athlete animates (spec 8).
///
/// | Steps per minute | Gait | Intensity |
/// |---|---|---|
/// | under 20 | idle | 0 |
/// | 60 | slow climbing | 0.25 |
/// | 90 | normal climbing | 0.5 |
/// | 120 | fast climbing | 0.75 |
/// | 150 and up | very fast climbing | 1 |
///
/// Playback rate is the stride speed relative to the 90 SPM reference, clamped so a burst or a
/// miscount can never spin the legs faster than a person can move them. Intensity scales the
/// secondary motion - arm swing, knee lift, forward lean - so a fast climber looks like they are
/// working, not just moving the same pose faster.
struct MountainAnimationPacing: Equatable, Sendable {
    enum Gait: Equatable, Sendable {
        case idle
        case climbing
    }

    static let referenceStepsPerMinute = 90.0
    static let climbingThresholdStepsPerMinute = 20.0
    static let minimumPlaybackRate = 0.5
    static let maximumPlaybackRate = 2.2
    /// The fastest believable stride, as a step rate: 198 steps per minute.
    static var maximumStepsPerSecond: Double {
        referenceStepsPerMinute * maximumPlaybackRate / 60
    }

    let stepsPerMinute: Double
    let gait: Gait
    let playbackRate: Double
    let intensity: Double

    init(stepsPerMinute: Double) {
        let spm = stepsPerMinute.isFinite ? max(stepsPerMinute, 0) : 0
        self.stepsPerMinute = spm

        guard spm >= Self.climbingThresholdStepsPerMinute else {
            gait = .idle
            playbackRate = 0
            intensity = 0
            return
        }

        gait = .climbing
        playbackRate = min(
            max(spm / Self.referenceStepsPerMinute, Self.minimumPlaybackRate),
            Self.maximumPlaybackRate
        )
        intensity = min(max((spm - 30) / 120, 0), 1)
    }
}
