import Foundation

/// One approved seasonal card background. Each uses its own colours, ignores the accent, and
/// supplies a caption that replaces the climb label.
enum SeasonalBackground: String, CaseIterable, Codable, Identifiable, Sendable {
    case leafFall
    case flannel
    case snowfall
    case snowyPines
    case twinkleLights
    case giftWrap
    case cocoa
    case fireworks
    case confetti
    case yearGold
    case bubblyGold
    case ghosts

    var id: String { rawValue }

    var theme: SeasonalTheme {
        switch self {
        case .leafFall, .flannel: return .november
        case .snowfall, .snowyPines, .twinkleLights, .giftWrap, .cocoa: return .december
        case .fireworks, .confetti, .yearGold, .bubblyGold: return .newYear
        case .ghosts: return .october
        }
    }

    var title: String {
        switch self {
        case .leafFall: return "Leaf fall"
        case .flannel: return "Flannel"
        case .snowfall: return "Snowfall"
        case .snowyPines: return "Snowy pines"
        case .twinkleLights: return "Twinkle lights"
        case .giftWrap: return "Gift wrap"
        case .cocoa: return "Cocoa"
        case .fireworks: return "Fireworks"
        case .confetti: return "Confetti"
        case .yearGold: return "Year"
        case .bubblyGold: return "Bubbly gold"
        case .ghosts: return "Ghosts"
        }
    }

    /// The caption that replaces the climb label. The year is generated, never stored.
    func caption(year: Int) -> String {
        switch self {
        case .leafFall: return "FALLING FOR STAIRS"
        case .flannel: return "SWEATER WEATHER"
        case .snowfall: return "SLEIGHED IT"
        case .snowyPines: return "TREE-MENDOUS CLIMB"
        case .twinkleLights: return "MERRY & BRIGHT"
        case .giftWrap: return "THE GIFT OF GAINS"
        case .cocoa: return "COCOA EARNED"
        case .fireworks: return "NEW YEAR, NEW PR"
        case .confetti: return "FIRST CLIMB OF \(year)"
        case .yearGold: return "HAPPY NEW YEAR"
        case .bubblyGold: return "GOLDEN START"
        case .ghosts: return "GHOSTED THE STAIRS"
        }
    }

    /// The backgrounds live on `date`, first in the Background row.
    static func available(on date: Date, calendar: Calendar = .current) -> [SeasonalBackground] {
        guard let theme = SeasonalTheme.active(on: date, calendar: calendar) else { return [] }
        return allCases.filter { $0.theme == theme }
    }

    /// Whether a saved seasonal background may still be used on `date`.
    func isAvailable(on date: Date, calendar: Calendar = .current) -> Bool {
        SeasonalTheme.active(on: date, calendar: calendar) == theme
    }
}
