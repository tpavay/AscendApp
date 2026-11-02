import SwiftUI

/// The three marks on the Climb sheet's tiles, drawn from the design handoff's 32-point artboard
/// so they stay sharp at any size and never depend on an SF Symbol the design did not choose.
enum HomeStartGlyph {
    case stairs
    case tower
    case bars
}

struct HomeStartGlyphShape: Shape {
    let glyph: HomeStartGlyph

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 32
        let xOffset = rect.minX + (rect.width - 32 * unit) / 2
        let yOffset = rect.minY + (rect.height - 32 * unit) / 2
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: xOffset + x * unit, y: yOffset + y * unit)
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: xOffset + x * unit, y: yOffset + y * unit, width: width * unit, height: height * unit)
        }

        var path = Path()
        switch glyph {
        case .stairs:
            path.addLines([
                point(5, 28), point(5, 22), point(11, 22), point(11, 16), point(17, 16),
                point(17, 10), point(23, 10), point(23, 4), point(29, 4), point(29, 28)
            ])
            path.closeSubpath()
        case .tower:
            path.addRect(box(15, 2, 2, 6))
            path.addLines([point(12, 8), point(20, 8), point(19, 13), point(13, 13)])
            path.closeSubpath()
            path.addLines([point(14, 13), point(18, 13), point(19.5, 26), point(12.5, 26)])
            path.closeSubpath()
            path.addRect(box(9, 26, 14, 3))
            path.addLines([point(17, 2), point(23, 4.5), point(17, 7)])
            path.closeSubpath()
        case .bars:
            for bar in [(4.0, 19.0, 9.0), (10.5, 8.0, 20.0), (17.0, 17.0, 11.0), (23.5, 4.0, 24.0)] {
                path.addRoundedRect(
                    in: box(CGFloat(bar.0), CGFloat(bar.1), 5, CGFloat(bar.2)),
                    cornerSize: CGSize(width: 1.5 * unit, height: 1.5 * unit)
                )
            }
        }
        return path
    }
}
