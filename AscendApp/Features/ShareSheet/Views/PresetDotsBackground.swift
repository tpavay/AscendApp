import SwiftUI

/// A white dot grid, one dot at the centre of every 14 point cell.
struct PresetDotsBackground: View {
    private static let cell: CGFloat = 14
    // The mockup's dot is solid to 1pt and feathers out to 1.4pt; this is the equivalent area.
    private static let radius: CGFloat = 1.15

    var body: some View {
        let side = PresetCardView.designSize
        Canvas { context, size in
            var dots = Path()
            var y = Self.cell / 2
            while y < size.height {
                var x = Self.cell / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(
                        x: x - Self.radius,
                        y: y - Self.radius,
                        width: Self.radius * 2,
                        height: Self.radius * 2
                    ))
                    x += Self.cell
                }
                y += Self.cell
            }
            context.fill(dots, with: .color(.white.opacity(0.18)))
        }
        .frame(width: side, height: side)
    }
}
