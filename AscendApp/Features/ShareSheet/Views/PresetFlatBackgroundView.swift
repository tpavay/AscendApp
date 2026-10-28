import SwiftUI

/// The backgrounds that need no photograph, built from the accent exactly as the approved mockup
/// builds them. The palette's base colour sits underneath every one of them.
struct PresetFlatBackgroundView: View {
    let flat: PresetFlatBackground
    let model: PresetCardModel

    private var accentHex: UInt32 { model.accent.hex }
    private var accent: Color { Color(shareHex: accentHex) }
    private static let inkHex: UInt32 = 0x0B0B0B

    /// The mockup writes translucency as a hex alpha suffix (`33`, `AA`); this reads the same.
    private func accentTint(alpha: Int) -> Color {
        accent.opacity(Double(alpha) / 255)
    }

    var body: some View {
        let side = PresetCardView.designSize
        ZStack {
            Color(share: model.palette.base)
            content
        }
        .frame(width: side, height: side)
        .clipped()
    }

    @ViewBuilder
    private var content: some View {
        switch flat {
        case .black, .white:
            EmptyView()
        case .accent:
            stepsWatermark
        case .glow:
            glow
        case .fade:
            fade
        case .aurora:
            PresetAuroraBackground(accent: accent)
        case .grain:
            PresetGrainBackground(accentHex: accentHex)
        case .hex:
            PresetHexBackground(accent: accent)
        case .stairs:
            PresetStairsBackground(accent: accent)
        case .grid:
            PresetGridBackground(accent: accent)
        case .dots:
            PresetDotsBackground()
        }
    }

    /// The step count, oversized and almost invisible, behind the real layout.
    private var stepsWatermark: some View {
        let fontSize: CGFloat = 128
        return ZStack(alignment: .topLeading) {
            Color.clear
            Text(model.subject.stepsText)
                .presetText(model.font, size: fontSize, weight: 900, trackingEm: -0.07, color: Color(share: .ink).opacity(0.1))
                .lineLimit(1)
                .fixedSize()
                // The mockup's line-height is 0.82, so the glyphs are centred in a box shorter
                // than the font's natural line.
                .frame(height: fontSize * 0.82, alignment: .leading)
                .offset(x: -8, y: 34)
        }
    }

    /// `radial-gradient(ellipse 75% 65% at 100% 42%, a88 0%, a33 45%, transparent 78%)`. SwiftUI
    /// has no elliptical radial gradient, so a circular one is stretched to the ellipse's radii.
    private var glow: some View {
        let side = PresetCardView.designSize
        let unit: CGFloat = 100
        return RadialGradient(
            stops: [
                .init(color: accentTint(alpha: 0x88), location: 0),
                .init(color: accentTint(alpha: 0x33), location: 0.45),
                .init(color: accent.opacity(0), location: 0.78)
            ],
            center: .center,
            startRadius: 0,
            endRadius: unit
        )
        .frame(width: unit * 2, height: unit * 2)
        .scaleEffect(x: side * 0.75 / unit, y: side * 0.65 / unit)
        .position(x: side, y: side * 0.42)
    }

    private var fade: some View {
        LinearGradient(
            stops: [
                .init(color: accent, location: 0),
                .init(color: Color(shareHex: accentHex, opacity: 0xAA / 255, over: Self.inkHex), location: 0.14),
                .init(color: Color(shareHex: accentHex, opacity: 0x33 / 255, over: Self.inkHex), location: 0.44),
                .init(color: Color(share: .ink), location: 0.74)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
