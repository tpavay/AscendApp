import SwiftUI

/// The outlined pencil on the Climb sheet's Log it button, drawn from the handoff's 20-point
/// artboard. Stroked, not filled, which is what separates it from the solid SF Symbol.
struct HomeStartPencilShape: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 20
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }

        var path = Path()
        path.addLines([point(4, 16), point(5, 12), point(13, 4), point(16, 7), point(8, 15)])
        path.closeSubpath()
        path.move(to: point(11.5, 5.5))
        path.addLine(to: point(14.5, 8.5))
        return path
    }
}
