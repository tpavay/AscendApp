import Foundation

/// Every seasonal sticker, grouped by theme in the order the Stickers tab shows them.
enum SeasonalStickerKind: String, CaseIterable, Identifiable, Sendable {
    // November
    case turkey, leaves, pie, legDay, preFeast
    // December
    case snowflake, cocoa, pine, gift, lights
    // New Year's
    case newPR, yearBurst, firstClimb, resolutions
    // October
    case ghostDuo, ghostSolo, spookySzn

    var id: String { rawValue }

    var theme: SeasonalTheme {
        switch self {
        case .turkey, .leaves, .pie, .legDay, .preFeast: return .november
        case .snowflake, .cocoa, .pine, .gift, .lights: return .december
        case .newPR, .yearBurst, .firstClimb, .resolutions: return .newYear
        case .ghostDuo, .ghostSolo, .spookySzn: return .october
        }
    }

    /// The short name VoiceOver reads for the tile.
    var title: String {
        switch self {
        case .turkey: return "Earned my turkey"
        case .leaves: return "Falling for steps"
        case .pie: return "Earned the pie"
        case .legDay: return "Thankful for leg day"
        case .preFeast: return "Pre-feast steps banked"
        case .snowflake: return "Sleighed it"
        case .cocoa: return "Cocoa earned"
        case .pine: return "Tree-mendous"
        case .gift: return "The gift of gains"
        case .lights: return "Merry and bright"
        case .newPR: return "New year, new PR"
        case .yearBurst: return "New year firework"
        case .firstClimb: return "First climb of the year"
        case .resolutions: return "Resolutions checklist"
        case .ghostDuo: return "Ghosted the stairs"
        case .ghostSolo: return "Ghost with steps"
        case .spookySzn: return "Spooky season"
        }
    }

    var accessibilityLabel: String {
        "\(title) sticker. Tap to copy, hold to save"
    }
}
