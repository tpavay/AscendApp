import SwiftUI

/// The climber's Font and Color choice, resolved once so every sticker draws text and line work
/// the same way. Sizes are fixed points on purpose: a sticker is exported as an image and must
/// not change with the reader's Dynamic Type.
struct StickerInk {
    let font: PresetFont
    let color: Color
    /// Black stickers flip their shadows and their filled-cell text to white.
    let isDark: Bool
    let markColor: Color

    init(style: StickerStyle) {
        font = style.font.presetFont
        color = Color(shareHex: style.color.hex)
        isDark = style.color == .black
        markColor = Color(shareHex: style.color.wordmarkMarkHex)
    }

    /// One line of sticker text. `lineHeight` is a CSS-style multiple of `size`; Text's natural
    /// line box is taller than the design's tight 0.9 to 1.0 stacks, so it is pinned here.
    func text(
        _ string: String,
        size: CGFloat,
        trackingEm: CGFloat = 0,
        opacity: Double = 1,
        lineHeight: CGFloat? = nil,
        weight: Int = 900
    ) -> some View {
        Text(string)
            .font(font.cardFont(size: size, weight: weight))
            .tracking((trackingEm + CGFloat(font.tracking)) * size)
            .foregroundStyle(color)
            .opacity(opacity)
            .fixedSize()
            .frame(height: lineHeight.map { $0 * size })
    }

    /// The small tracked-caps label above or below a number.
    func caption(_ string: String, size: CGFloat = 7, trackingEm: CGFloat = 0.16, opacity: Double = 0.8) -> some View {
        text(string, size: size, trackingEm: trackingEm, opacity: opacity)
    }

    /// Text on a filled cell: dark on a light fill, white on the Black sticker's dark fill.
    var filledCellTextColor: Color {
        isDark ? .white : Color(shareHex: 0x0B0B0B)
    }

    /// Numerals the design always sets in Montserrat ExtraBold, whatever the chosen face, so a
    /// calendar cell or a week-dot letter stays legible at 6 to 7 points.
    func numeral(_ string: String, size: CGFloat, color: Color? = nil, opacity: Double = 1) -> some View {
        Text(string)
            .font(.custom(PresetFont.bold.postScriptName(weight: 800), fixedSize: size))
            .foregroundStyle(color ?? self.color)
            .opacity(opacity)
            .fixedSize()
    }
}
