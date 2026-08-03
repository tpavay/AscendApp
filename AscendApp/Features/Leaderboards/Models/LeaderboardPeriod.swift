import Foundation

struct LeaderboardPeriod: Equatable, Hashable, Sendable {
    let timeFrame: LeaderboardTimeFrame
    let key: String
    let startAt: Date
    let endAt: Date?

    func contains(_ date: Date, referenceDate: Date = Date()) -> Bool {
        if let endAt {
            return date >= startAt && date < endAt
        }

        return date <= referenceDate
    }

    /// The concrete window this board covers, e.g. `Jul 27 - Aug 2` or `August`.
    ///
    /// Every board must name its own window. A week is not contained by a month: the
    /// week starting Mon Jul 27 2026 runs into Aug 2, so on Aug 1 the weekly board
    /// legitimately carries steps that the freshly-reset monthly board does not. With
    /// both windows unnamed, that correct state reads as lost data.
    ///
    /// Rendered in the canonical time zone and calendar the window is *defined* in, not
    /// the viewer's. A UTC-Monday window labelled with local dates would name days it does
    /// not cover, and a window keyed `2026-M08` labelled on the viewer's calendar would
    /// read "2569 BE" or "صفر" - naming a month the board does not cover.
    var windowLabel: String {
        switch timeFrame {
        case .daily:
            return "Today"
        case .weekly:
            guard let lastDay = inclusiveEndDate else { return Self.dayStyle.format(startAt) }
            return "\(Self.dayStyle.format(startAt)) - \(Self.dayStyle.format(lastDay))"
        case .monthly:
            return Self.monthStyle.format(startAt)
        case .yearly:
            return Self.yearStyle.format(startAt)
        case .allTime:
            return "All time"
        }
    }

    /// The window as the subject of a sentence, for copy that states the condition
    /// before it commands - "August is empty. Take the first spot."
    ///
    /// A date range does not read as a subject, so the weekly frame says "This week"
    /// while `windowLabel` still carries the dates alongside it.
    var windowSubject: String {
        switch timeFrame {
        case .daily:
            return "Today"
        case .weekly:
            return "This week"
        case .monthly, .yearly:
            return windowLabel
        case .allTime:
            return "This board"
        }
    }

    /// Last day the window includes. `endAt` is exclusive, so the label would otherwise
    /// name the Monday that belongs to the *next* week.
    private var inclusiveEndDate: Date? {
        guard let endAt else { return nil }
        return endAt.addingTimeInterval(-1)
    }

    /// Every window is *computed* through `WeekConfiguration.calendar`, which is Gregorian,
    /// and stored under a Gregorian key. Labelling it on `Calendar.autoupdatingCurrent`
    /// would let the device's calendar rename a board its own key contradicts.
    static let labelCalendar = WeekConfiguration.calendar(timeZone: LeaderboardTimeFrame.canonicalTimeZone)

    /// The app ships en-US only, so the label reads the same everywhere the window does.
    static let labelLocale = Locale(identifier: "en_US")

    static let dayStyle = Date.FormatStyle(
        locale: labelLocale,
        calendar: labelCalendar,
        timeZone: LeaderboardTimeFrame.canonicalTimeZone
    )
    .month(.abbreviated)
    .day()

    static let monthStyle = Date.FormatStyle(
        locale: labelLocale,
        calendar: labelCalendar,
        timeZone: LeaderboardTimeFrame.canonicalTimeZone
    )
    .month(.wide)

    static let yearStyle = Date.FormatStyle(
        locale: labelLocale,
        calendar: labelCalendar,
        timeZone: LeaderboardTimeFrame.canonicalTimeZone
    )
    .year()
}
