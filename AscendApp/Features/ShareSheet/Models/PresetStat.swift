import Foundation

/// The stats a climber can switch on or off. Steps is always on and is not in this list.
enum PresetStat: String, CaseIterable, Codable, Identifiable, Sendable {
    case time
    case stepsPerMinute
    case floors
    case averageHeartRate
    case rank
    case bestEfforts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: return "Time"
        case .stepsPerMinute: return "SPM"
        case .floors: return "Floors"
        case .averageHeartRate: return "Avg HR"
        case .rank: return "Rank"
        case .bestEfforts: return "Best efforts"
        }
    }

    /// Stats that appear as columns of the card's stat row. Best efforts has its own spot in the
    /// card's top row, so it never crowds the row.
    var isRowStat: Bool {
        self != .bestEfforts
    }
}
