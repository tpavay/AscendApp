import Foundation
import simd

/// A position and heading on the mountain course.
///
/// Course space is metres with +Y up. A heading of zero faces -Z, and a positive heading turns
/// the climber left (counter-clockwise seen from above), matching RealityKit's convention for a
/// rotation about +Y. Positions are `Double` because a long climb accumulates hundreds of
/// kilometres of course; only small differences between nearby poses are ever handed to the
/// renderer as `Float`.
struct MountainPose: Equatable, Sendable {
    var position: SIMD3<Double>
    var heading: Double

    static let origin = MountainPose(position: .zero, heading: 0)

    init(position: SIMD3<Double>, heading: Double) {
        self.position = position
        self.heading = heading
    }

    /// The unit vector this pose faces along, on the ground plane.
    var forward: SIMD3<Double> {
        SIMD3(-sin(heading), 0, -cos(heading))
    }

    /// The unit vector to this pose's right, on the ground plane.
    var right: SIMD3<Double> {
        SIMD3(cos(heading), 0, -sin(heading))
    }

    /// Rotates an offset expressed in this pose's own frame into course space.
    func rotate(_ local: SIMD3<Double>) -> SIMD3<Double> {
        let cosine = cos(heading)
        let sine = sin(heading)
        return SIMD3(
            local.x * cosine + local.z * sine,
            local.y,
            -local.x * sine + local.z * cosine
        )
    }

    /// Places a pose expressed in this pose's own frame into course space.
    func composed(with local: MountainPose) -> MountainPose {
        MountainPose(
            position: position + rotate(local.position),
            heading: heading + local.heading
        )
    }

    /// Straight-line position and shortest-arc heading between two poses.
    static func interpolate(_ start: MountainPose, _ end: MountainPose, fraction: Double) -> MountainPose {
        let t = min(max(fraction, 0), 1)
        var headingDelta = (end.heading - start.heading).truncatingRemainder(dividingBy: 2 * .pi)
        if headingDelta > .pi { headingDelta -= 2 * .pi }
        if headingDelta < -.pi { headingDelta += 2 * .pi }
        return MountainPose(
            position: start.position + (end.position - start.position) * t,
            heading: start.heading + headingDelta * t
        )
    }
}
