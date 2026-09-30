import Foundation

/// Stair dimensions shared by every chunk, so a flight and the landing after it meet exactly.
enum MountainStairGeometry {
    /// Height of one stair: one real step raises the climber this far.
    static let rise = 0.17
    /// Depth of one tread.
    static let run = 0.30
    /// Width of every flight and landing.
    static let width = 1.6
    /// How far one real step carries the climber across flat ground.
    static let flatStride = 0.5
}

/// The reusable pieces an endless course is assembled from (spec 9).
///
/// Every piece is walked in whole real steps: a flight climbs one stair per step, a landing
/// crosses flat ground, and a turn carries the climber round a corner platform. Scenic
/// landings, cliff sections and bridges arrive with the environment art as variations of these
/// same paths, so the step model never changes when the scenery does.
enum MountainChunkKind: String, CaseIterable, Sendable {
    case shortFlight
    case mediumFlight
    case longFlight
    case landing
    case leftTurn
    case rightTurn

    var isFlight: Bool {
        switch self {
        case .shortFlight, .mediumFlight, .longFlight:
            return true
        case .landing, .leftTurn, .rightTurn:
            return false
        }
    }

    var isTurn: Bool {
        self == .leftTurn || self == .rightTurn
    }

    /// The real steps it takes to cross this piece.
    var stepCount: Int {
        switch self {
        case .shortFlight:
            return 10
        case .mediumFlight:
            return 16
        case .longFlight:
            return 24
        case .landing, .leftTurn, .rightTurn:
            return 3
        }
    }

    /// Heading change from entry to exit; positive turns left.
    var headingChange: Double {
        switch self {
        case .leftTurn:
            return .pi / 2
        case .rightTurn:
            return -.pi / 2
        case .shortFlight, .mediumFlight, .longFlight, .landing:
            return 0
        }
    }

    /// Where the climber stands after `step` whole steps into this piece, relative to its entry.
    ///
    /// Step zero is the entry, which is the centre of the previous piece's last tread, and
    /// `stepCount` is the exit, where the next piece begins.
    func localPose(atStep step: Int) -> MountainPose {
        let clamped = min(max(step, 0), stepCount)
        let rise = MountainStairGeometry.rise
        let run = MountainStairGeometry.run

        switch self {
        case .shortFlight, .mediumFlight, .longFlight:
            return MountainPose(
                position: SIMD3(0, Double(clamped) * rise, -Double(clamped) * run),
                heading: 0
            )
        case .landing:
            return MountainPose(
                position: SIMD3(0, 0, -Double(clamped) * MountainStairGeometry.flatStride),
                heading: 0
            )
        case .leftTurn, .rightTurn:
            return turnPose(fraction: Double(clamped) / Double(stepCount))
        }
    }

    /// Fractional steps interpolate between the neighbouring whole-step poses, so the path a
    /// renderer follows is exactly the path the steps define.
    func localPose(atProgress steps: Double) -> MountainPose {
        let clamped = min(max(steps, 0), Double(stepCount))
        let whole = min(Int(clamped.rounded(.down)), stepCount)
        guard whole < stepCount else { return localPose(atStep: stepCount) }

        return MountainPose.interpolate(
            localPose(atStep: whole),
            localPose(atStep: whole + 1),
            fraction: clamped - Double(whole)
        )
    }

    /// Height gained after `steps` into this piece. Only flights climb.
    func altitudeGain(atProgress steps: Double) -> Double {
        guard isFlight else { return 0 }
        return min(max(steps, 0), Double(stepCount)) * MountainStairGeometry.rise
    }

    /// The exit relative to the entry: where the next piece starts.
    var exitPose: MountainPose {
        localPose(atStep: stepCount)
    }

    /// A turn crosses a square platform whose near edge meets the previous tread and whose side
    /// edge meets the next flight's first tread. The climber follows a quadratic curve through the
    /// platform's centre, so the heading swings smoothly instead of pivoting on the spot.
    private func turnPose(fraction: Double) -> MountainPose {
        let run = MountainStairGeometry.run
        let width = MountainStairGeometry.width
        let side: Double = self == .leftTurn ? -1 : 1
        let start = SIMD3<Double>(0, 0, 0)
        let corner = SIMD3<Double>(0, 0, -run / 2 - width / 2)
        let end = SIMD3<Double>(side * (width / 2 - run / 2), 0, -run / 2 - width / 2)

        let t = min(max(fraction, 0), 1)
        let oneMinus = 1 - t
        let position = start * (oneMinus * oneMinus) + corner * (2 * oneMinus * t) + end * (t * t)

        return MountainPose(position: position, heading: headingChange * t)
    }
}
