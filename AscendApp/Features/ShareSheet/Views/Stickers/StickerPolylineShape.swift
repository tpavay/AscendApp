import SwiftUI

/// A polyline through points already expressed in the shape's own coordinate space, optionally
/// closed down to a baseline so it can be filled as an area.
struct StickerPolylineShape: Shape {
    let points: [CGPoint]
    /// When set, the path runs down to this y at both ends and closes.
    var closedToBaseline: CGFloat?

    init(points: [CGPoint], closedToBaseline: CGFloat? = nil) {
        self.points = points
        self.closedToBaseline = closedToBaseline
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        if let baseline = closedToBaseline {
            path.move(to: CGPoint(x: first.x, y: baseline))
            path.addLine(to: first)
        } else {
            path.move(to: first)
        }
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        if let baseline = closedToBaseline {
            path.addLine(to: CGPoint(x: last.x, y: baseline))
            path.closeSubpath()
        }
        return path
    }
}
