import Foundation

/// A seasonal set of card backgrounds and stickers that is offered only during its window.
///
/// Windows are on the climber's local calendar date and return every year. Outside its window a
/// theme is hidden entirely, and a saved seasonal background falls back to Black.
enum SeasonalTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case november
    case december
    case newYear
    case october

    var id: String { rawValue }

    var title: String {
        switch self {
        case .november: return "November"
        case .december: return "December"
        case .newYear: return "New Year's"
        case .october: return "October"
        }
    }

    /// The calendar months a theme is live in: November, December, January and October.
    var month: Int {
        switch self {
        case .november: return 11
        case .december: return 12
        case .newYear: return 1
        case .october: return 10
        }
    }

    /// The theme live on `date`, if any. Every day of each of those four months belongs to one theme.
    static func active(on date: Date, calendar: Calendar = .current) -> SeasonalTheme? {
        let month = calendar.component(.month, from: date)
        return allCases.first { $0.month == month }
    }

    /// The year New Year's copy names, generated from the date so it is never hard-coded.
    static func copyYear(on date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: date)
    }
}
