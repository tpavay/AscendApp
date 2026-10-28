import SwiftUI

/// A 22 point line grid in the accent, fading to black away from the top right.
struct PresetGridBackground: View {
    let accent: Color

    private static let cell: CGFloat = 22

    var body: some View {
        let side = PresetCardView.designSize
        ZStack {
            Canvas { context, size in
                var verticals = Path()
                var horizontals = Path()
                var position: CGFloat = 0
                while position < size.width {
                    verticals.addRect(CGRect(x: position, y: 0, width: 1, height: size.height))
                    horizontals.addRect(CGRect(x: 0, y: position, width: size.width, height: 1))
                    position += Self.cell
                }
                // Two fills, not one union: the mockup layers two gradients, so a crossing is
                // drawn twice and reads slightly brighter.
                context.fill(horizontals, with: .color(accent.opacity(0.2)))
                context.fill(verticals, with: .color(accent.opacity(0.2)))
            }
            RadialGradient(
                colors: [Color(shareHex: 0x0B0B0B, opacity: 0), Color(shareHex: 0x0B0B0B, opacity: 0.97)],
                center: UnitPoint(x: 0.88, y: 0.12),
                startRadius: 0,
                endRadius: 0.78 * PresetGradientGeometry.farthestCornerRadius(x: 0.88, y: 0.12, side: side)
            )
        }
        .frame(width: side, height: side)
    }
}
