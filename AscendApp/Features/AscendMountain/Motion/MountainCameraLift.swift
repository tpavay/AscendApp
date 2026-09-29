import Foundation

/// The camera's rise as the climber passes through a gate (captain, board 4: "Camera lifts at
/// each gate"), so the mountain and their place on it come into view without a touch - their
/// hands are on the rails. It rises, holds long enough to take in, and settles back behind the
/// climber, who never leaves the frame.
struct MountainCameraLift: Equatable, Sendable {
    static let riseSeconds = 2.0
    static let holdSeconds = 2.6
    static let settleSeconds = 2.2
    static var duration: Double { riseSeconds + holdSeconds + settleSeconds }

    /// Scene time the climber passed the gate.
    let startedAt: Double

    /// How far risen the camera is at `time`: 0 behind the climber, 1 at the top of the lift.
    func amount(at time: Double) -> Double {
        let elapsed = time - startedAt
        switch elapsed {
        case ..<0:
            return 0
        case ..<Self.riseSeconds:
            return Self.ease(elapsed / Self.riseSeconds)
        case ..<(Self.riseSeconds + Self.holdSeconds):
            return 1
        case ..<Self.duration:
            return 1 - Self.ease((elapsed - Self.riseSeconds - Self.holdSeconds) / Self.settleSeconds)
        default:
            return 0
        }
    }

    func isFinished(at time: Double) -> Bool {
        time - startedAt >= Self.duration
    }

    /// Smootherstep: starts and stops with no jolt in speed or acceleration.
    static func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return min(max(x * x * x * (x * (x * 6 - 15) + 10), 0), 1)
    }
}
