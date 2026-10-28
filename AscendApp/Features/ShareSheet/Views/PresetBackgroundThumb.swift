import SwiftUI

/// A small swatch of a background for the bar and the panel's tiles.
struct PresetBackgroundThumb: View {
    let background: PresetCardBackground
    let accent: PresetAccent

    var body: some View {
        let accentColor = Color(shareHex: accent.hex)
        let ink = Color(shareHex: 0x0B0B0B)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill(accentColor: accentColor, ink: ink))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(.white.opacity(0.35), lineWidth: 0.5)
            )
    }

    private func fill(accentColor: Color, ink: Color) -> AnyShapeStyle {
        switch background {
        case .flat(let flat):
            switch flat {
            case .black, .dots: return AnyShapeStyle(ink)
            case .white: return AnyShapeStyle(Color(shareHex: 0xF5F5F4))
            case .accent: return AnyShapeStyle(accentColor)
            case .glow, .aurora, .hex, .grid, .stairs:
                return AnyShapeStyle(RadialGradient(colors: [accentColor.opacity(0.6), ink], center: .topTrailing, startRadius: 0, endRadius: 24))
            case .fade:
                return AnyShapeStyle(LinearGradient(colors: [accentColor, accentColor.opacity(0.2), ink], startPoint: .top, endPoint: .bottom))
            case .grain:
                return AnyShapeStyle(LinearGradient(colors: [Color(shareHex: 0x1A1A1A), ink, accentColor.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        case .tower, .photo:
            return AnyShapeStyle(Color(shareHex: 0x333333))
        case .seasonal:
            return AnyShapeStyle(LinearGradient(colors: [Color(shareHex: 0xB45309), Color(shareHex: 0x7C2D12)], startPoint: .top, endPoint: .bottom))
        }
    }
}
