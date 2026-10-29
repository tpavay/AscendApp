import Foundation

/// Which seasonal stickers are on offer. A theme is live for its whole calendar month, and outside
/// every window the Stickers tab shows none of them.
enum SeasonalStickerCatalog {
    /// The live theme's stickers on `date`, in the order the tab shows them.
    static func stickers(on date: Date, calendar: Calendar = .current) -> [SeasonalStickerKind] {
        guard let theme = SeasonalTheme.active(on: date, calendar: calendar) else { return [] }
        return SeasonalStickerKind.allCases.filter { $0.theme == theme }
    }
}
