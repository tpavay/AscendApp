import Foundation
import simd

/// Another athlete on the climber's staircase: their own best, a pacer they set, or a rival.
///
/// A ghost is a function of the climb's elapsed time, never of the last frame drawn, so after a
/// pause in rendering it reappears exactly where its record says (backgrounding requirement).
struct MountainGhost: Sendable {
    enum Kind: Equatable, Sendable {
        case personalBest
        case pacer
        case rival
    }

    let id: String
    let kind: Kind
    /// Short words shown over the ghost's head.
    let label: String
    /// How a rival's athlete looks, once read from their account; nil draws a stand-in.
    var look: AthleteLook?
    /// Where the ghost is on the course, in steps, at `elapsed` seconds into the climb.
    let steps: @Sendable (_ elapsed: TimeInterval) -> Double

    init(
        id: String,
        kind: Kind,
        label: String,
        look: AthleteLook? = nil,
        steps: @escaping @Sendable (_ elapsed: TimeInterval) -> Double
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.look = look
        self.steps = steps
    }

    /// A pacer holding one cadence from the first second.
    static func pacer(stepsPerMinute: Double, id: String = "pacer") -> MountainGhost {
        MountainGhost(id: id, kind: .pacer, label: "PACER · \(Int(stepsPerMinute.rounded())) SPM") { elapsed in
            max(elapsed, 0) * stepsPerMinute / 60
        }
    }
}

/// A ghost as the renderer should draw it this frame.
struct MountainGhostFrame: Equatable, Sendable {
    let id: String
    let kind: MountainGhost.Kind
    let label: String
    let kinematics: MountainAthleteKinematics
    /// Steps ahead of the climber; negative when the ghost is behind.
    let lead: Double
}

/// A ghost's position this frame, sampled from its record by the caller.
struct MountainGhostSample: Equatable, Sendable {
    let id: String
    let kind: MountainGhost.Kind
    let label: String
    let steps: Double
    let stepsPerMinute: Double

    init(ghost: MountainGhost, elapsed: TimeInterval) {
        id = ghost.id
        kind = ghost.kind
        label = ghost.label
        steps = ghost.steps(elapsed)
        // Cadence from the record itself, over the last two seconds.
        stepsPerMinute = max(ghost.steps(elapsed) - ghost.steps(max(elapsed - 2, 0)), 0) * 60 / min(max(elapsed, 0.001), 2)
    }

    init(id: String, kind: MountainGhost.Kind, label: String, steps: Double, stepsPerMinute: Double) {
        self.id = id
        self.kind = kind
        self.label = label
        self.steps = steps
        self.stepsPerMinute = stepsPerMinute
    }
}
