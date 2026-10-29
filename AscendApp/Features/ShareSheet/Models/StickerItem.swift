import Foundation

/// One tile in the Stickers grid: a standard sticker, or a seasonal one during its window.
enum StickerItem: Identifiable, Hashable, Sendable {
    case standard(StickerKind)
    case seasonal(SeasonalStickerKind)

    var id: String {
        switch self {
        case .standard(let kind): return "standard.\(kind.rawValue)"
        case .seasonal(let kind): return "seasonal.\(kind.rawValue)"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .standard(let kind): return kind.accessibilityLabel
        case .seasonal(let kind): return kind.accessibilityLabel
        }
    }
}
