import SwiftUI

/// The CSS gradient rules the approved mockup relies on, restated for SwiftUI so the numbers can
/// be copied across from the design unchanged.
enum PresetGradientGeometry {
    /// Endpoints for a CSS `linear-gradient(<angle>deg, ...)` on a square. CSS sizes the gradient
    /// line so the corners land exactly on the 0% and 100% stops, which is what `half` computes.
    static func cssLinearEndpoints(angleDegrees: Double) -> (start: UnitPoint, end: UnitPoint) {
        let radians = angleDegrees * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        let half = (abs(dx) + abs(dy)) / 2
        return (
            UnitPoint(x: 0.5 - dx * half, y: 0.5 - dy * half),
            UnitPoint(x: 0.5 + dx * half, y: 0.5 + dy * half)
        )
    }

    /// The radius of a CSS `radial-gradient(circle at x y, ...)` whose 100% is `farthest-corner`.
    /// `x` and `y` are fractions of a square of `side` points.
    static func farthestCornerRadius(x: Double, y: Double, side: Double) -> Double {
        let dx = max(x, 1 - x) * side
        let dy = max(y, 1 - y) * side
        return (dx * dx + dy * dy).squareRoot()
    }
}
