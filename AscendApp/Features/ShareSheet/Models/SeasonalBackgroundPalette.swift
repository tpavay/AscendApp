import Foundation

/// The card text colours each seasonal background brings, read from the approved board. Every
/// seasonal card ignores the climber's Accent: its accent, rule and wordmark A are the theme's own.
extension SeasonalBackground {
    var cardPalette: PresetCardPalette {
        switch self {
        case .leafFall:
            return darkArt(base: 0x1C120C, accent: 0xF59E0B)
        case .flannel:
            return darkArt(base: 0x7C2D12, accent: 0xFDE68A, date: 0.8)
        case .snowfall:
            return darkArt(base: 0x0B1426, accent: 0x93C5FD)
        case .snowyPines:
            return darkArt(base: 0x0B1426, accent: 0x86EFAC)
        case .twinkleLights:
            return darkArt(base: 0x0A0F0D, accent: 0xFBBF24)
        case .giftWrap:
            return darkArt(base: 0xB91C1C, accent: 0xFDE68A, label: 0.85, rule: 0.25, date: 0.85)
        case .cocoa:
            return darkArt(base: 0x2B1710, accent: 0xFCA5A5)
        case .fireworks:
            return darkArt(base: 0x070B1A, accent: 0xFBBF24)
        case .confetti:
            return darkArt(base: 0x0B0B0B, accent: 0xF472B6)
        case .yearGold:
            return darkArt(base: 0x111111, accent: 0xFBBF24)
        case .bubblyGold:
            // The gold is bright at the top, so the wordmark and date go to ink there while the
            // stats keep white on the darkened lower band.
            return PresetCardPalette(
                base: ShareColor(0xD97706),
                foreground: .paper,
                secondary: ShareColor(0xFFFFFF, alpha: 0.85),
                accentText: ShareColor(0xFDE68A),
                rule: ShareColor(0xFFFFFF, alpha: 0.25),
                wordmarkLetters: ShareColor(0x1C1917),
                wordmarkMark: ShareColor(0x1C1917),
                topSecondary: ShareColor(0x1C1917, alpha: 0.75),
                isLight: false
            )
        case .ghosts:
            return darkArt(base: 0x0E0B16, accent: 0xA3E635)
        }
    }

    /// White type on dark art with one seasonal accent for the `STEPS` word, the wordmark's A and
    /// the label line colour as the board draws it.
    private func darkArt(
        base: UInt32,
        accent: UInt32,
        label: Double = 0.78,
        rule: Double = 0.22,
        date: Double = 0.75
    ) -> PresetCardPalette {
        PresetCardPalette(
            base: ShareColor(base),
            foreground: .paper,
            secondary: ShareColor(0xFFFFFF, alpha: label),
            accentText: ShareColor(accent),
            rule: ShareColor(0xFFFFFF, alpha: rule),
            wordmarkLetters: .paper,
            wordmarkMark: ShareColor(accent),
            topSecondary: ShareColor(0xFFFFFF, alpha: date),
            isLight: false
        )
    }
}
