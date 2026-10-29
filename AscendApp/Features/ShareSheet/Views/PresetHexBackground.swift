import SwiftUI

/// A hex grid stroked in the accent, fading to black from the top right.
struct PresetHexBackground: View {
    let accent: Color

    // The mockup's pattern tile: pointy-top hexagons of side 14, 24.24 wide, repeating every 42.
    private static let hexWidth: CGFloat = 24.24
    private static let rowPitch: CGFloat = 42

    var body: some View {
        let side = PresetCardView.designSize
        ZStack {
            Canvas { context, _ in
                context.stroke(Self.gridPath(), with: .color(accent.opacity(0.22)), lineWidth: 1)
            }
            RadialGradient(
                colors: [Color(share: .ink).opacity(0), Color(share: .ink).opacity(0.96)],
                center: UnitPoint(x: 0.85, y: 0.1),
                startRadius: 0,
                endRadius: 0.95 * side
            )
        }
        .frame(width: side, height: side)
    }

    /// Every hexagon in one path so a shared edge is stroked once, not twice.
    private static func gridPath() -> Path {
        let half = hexWidth / 2
        var path = Path()
        for row in -1...7 {
            let y = CGFloat(row) * rowPitch
            for column in -1...13 {
                let x = CGFloat(column) * hexWidth
                addHexagon(to: &path, centerX: x + half, centerY: y + 14, half: half)
                addHexagon(to: &path, centerX: x, centerY: y + 35, half: half)
            }
        }
        return path
    }

    private static func addHexagon(to path: inout Path, centerX: CGFloat, centerY: CGFloat, half: CGFloat) {
        path.move(to: CGPoint(x: centerX, y: centerY - 14))
        path.addLine(to: CGPoint(x: centerX + half, y: centerY - 7))
        path.addLine(to: CGPoint(x: centerX + half, y: centerY + 7))
        path.addLine(to: CGPoint(x: centerX, y: centerY + 14))
        path.addLine(to: CGPoint(x: centerX - half, y: centerY + 7))
        path.addLine(to: CGPoint(x: centerX - half, y: centerY - 7))
        path.closeSubpath()
    }
}
