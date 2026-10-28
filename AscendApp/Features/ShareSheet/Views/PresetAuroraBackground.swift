import SwiftUI

/// Three soft accent blobs on black. The mockup blurs a layer 20pt larger than the card so the
/// blur never reveals a hard edge; the same overscan is kept here.
struct PresetAuroraBackground: View {
    let accent: Color

    private static let overscan: CGFloat = 20

    var body: some View {
        let card = PresetCardView.designSize
        let side = card + Self.overscan * 2
        ZStack {
            // Drawn bottom-up: the mockup lists the top blob first, so it is last here.
            blob(x: 0.55, y: 1.05, alpha: 0x33, stop: 0.48, side: side)
            blob(x: 0.86, y: 0.38, alpha: 0x44, stop: 0.38, side: side)
            blob(x: 0.22, y: 0.28, alpha: 0x77, stop: 0.40, side: side)
        }
        .frame(width: side, height: side)
        .blur(radius: 10)
        .frame(width: card, height: card)
    }

    private func blob(x: Double, y: Double, alpha: Int, stop: Double, side: CGFloat) -> some View {
        let radius = PresetGradientGeometry.farthestCornerRadius(x: x, y: y, side: side) * stop
        return RadialGradient(
            colors: [accent.opacity(Double(alpha) / 255), accent.opacity(0)],
            center: UnitPoint(x: x, y: y),
            startRadius: 0,
            endRadius: radius
        )
    }
}
