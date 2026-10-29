import Foundation

/// The periods the Totals stickers can summarise. Only the current week, month and year, as
/// decided: no past periods.
enum SharePeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case year

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .week: return "This week"
        case .month: return "This month"
        case .year: return "This year"
        }
    }
}
