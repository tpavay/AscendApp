import Foundation

/// The card layouts, in swipe order.
enum PresetLayout: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic
    case rank
    case curve
    case splits
    case splitTable
    case centered
    case grid
    case stackRight
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .rank: return "Rank"
        case .curve: return "Curve"
        case .splits: return "Splits"
        case .splitTable: return "Split table"
        case .centered: return "Centered"
        case .grid: return "Grid"
        case .stackRight: return "Stack right"
        case .minimal: return "Minimal"
        }
    }

    /// The layouts a climb can swipe through. Rank and Curve need a finish rank and the Rank stat
    /// on; the two split layouts need recorded splits.
    static func available(hasRank: Bool, rankStatOn: Bool, hasSplits: Bool) -> [PresetLayout] {
        allCases.filter { layout in
            switch layout {
            case .rank, .curve: return hasRank && rankStatOn
            case .splits, .splitTable: return hasSplits
            default: return true
            }
        }
    }
}
