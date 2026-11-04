import Foundation

/// The text and rule colours a Presets card draws with, decided from the accent and what is behind
/// the card. Mirrors the approved mockup: light backgrounds switch to dark text and a darker
/// accent, the Accent background paints its own text in ink, and a bright-topped background
/// switches the top row to dark.
struct PresetCardPalette: Equatable, Sendable {
    let base: ShareColor
    let foreground: ShareColor
    let secondary: ShareColor
    /// Colour of accented text such as `STEPS` and the rank mark.
    let accentText: ShareColor
    let rule: ShareColor
    /// The wordmark's letters (S C E N D).
    let wordmarkLetters: ShareColor
    /// The wordmark's angular A.
    let wordmarkMark: ShareColor
    let topSecondary: ShareColor
    let isLight: Bool

    /// Direct construction, for a seasonal theme that brings its own colours.
    init(
        base: ShareColor,
        foreground: ShareColor,
        secondary: ShareColor,
        accentText: ShareColor,
        rule: ShareColor,
        wordmarkLetters: ShareColor,
        wordmarkMark: ShareColor,
        topSecondary: ShareColor,
        isLight: Bool
    ) {
        self.base = base
        self.foreground = foreground
        self.secondary = secondary
        self.accentText = accentText
        self.rule = rule
        self.wordmarkLetters = wordmarkLetters
        self.wordmarkMark = wordmarkMark
        self.topSecondary = topSecondary
        self.isLight = isLight
    }

    init(accent: PresetAccent, background: PresetCardBackground) {
        if case .seasonal(let seasonal) = background {
            self = seasonal.cardPalette
            return
        }
        let flat: PresetFlatBackground?
        if case .flat(let value) = background { flat = value } else { flat = nil }
        let light = flat?.isLight ?? false
        let topDark = flat?.topRowIsDark ?? false
        let accentFills = flat == .accent

        isLight = light
        switch flat {
        case .white?: base = ShareColor(0xF5F5F4)
        case .accent?: base = ShareColor(accent.hex)
        default: base = ShareColor.ink
        }
        foreground = light ? .ink : .paper
        secondary = light ? ShareColor(0x0B0B0B, alpha: 0.62) : ShareColor(0xFFFFFF, alpha: 0.72)
        if accentFills {
            accentText = .ink
        } else if light {
            accentText = ShareColor(accent.onLightHex)
        } else {
            accentText = ShareColor(accent.hex)
        }
        rule = light ? ShareColor(0x0B0B0B, alpha: 0.18) : ShareColor(0xFFFFFF, alpha: 0.22)
        wordmarkLetters = (topDark || light) ? .ink : .paper
        wordmarkMark = (topDark || accentFills) ? .ink : ShareColor(accent.hex)
        topSecondary = topDark ? ShareColor(0x0B0B0B, alpha: 0.7) : secondary
    }
}
