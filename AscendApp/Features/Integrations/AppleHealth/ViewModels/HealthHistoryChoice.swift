import Foundation
import Observation

/// The one choice a history screen offers: how far back to bring workouts in from.
///
/// Holds what Health was found to hold and the range picked, and derives everything the screen
/// says from the two, so the count, the hours, the steps, the comparison and the button's number
/// can never disagree with the workouts an import is then handed. Shared by onboarding's "We
/// found your climbs" and Settings' Import older workouts.
@MainActor
@Observable
final class HealthHistoryChoice {
    /// The ranges the picker lists above its date row.
    static let presets: [HealthHistoryRange] = [.everything, .lastYear, .last90Days]

    let history: HealthHistory
    private(set) var range: HealthHistoryRange = .everything
    private(set) var summary: HealthHistorySummary
    private(set) var comparison: HealthHistoryComparison?

    @ObservationIgnored private let climbs: [Climb]
    @ObservationIgnored let now: Date
    @ObservationIgnored let calendar: Calendar

    init(history: HealthHistory, climbs: [Climb], now: Date, calendar: Calendar = .current) {
        self.history = history
        self.climbs = climbs
        self.now = now
        self.calendar = calendar
        let summary = history.summary(now: now, calendar: calendar)
        self.summary = summary
        comparison = HealthHistoryComparison.make(knownSteps: summary.knownSteps, climbs: climbs)
    }

    func select(_ range: HealthHistoryRange) {
        guard range != self.range else { return }
        self.range = range
        summary = history.summary(in: range, now: now, calendar: calendar)
        comparison = HealthHistoryComparison.make(knownSteps: summary.knownSteps, climbs: climbs)
    }

    func count(in range: HealthHistoryRange) -> Int {
        history.count(in: range, now: now, calendar: calendar)
    }

    /// The days the picker's date row can land on: the first workout's to the last one's, so every
    /// day it offers leaves at least one workout to bring in.
    var pickableDays: ClosedRange<Date>? {
        guard let oldest = history.oldestStart, let newest = history.newestStart else { return nil }
        return calendar.startOfDay(for: oldest)...newest
    }

    /// The range row's words.
    var rangeLabel: String {
        switch range {
        case .everything:
            guard let oldest = history.oldestStart else { return "Everything" }
            return "Everything since \(oldest.formatted(Self.monthAndYear(calendar)))"
        case .lastYear:
            return "Last year"
        case .last90Days:
            return "Last 90 days"
        case .since(let day):
            return "Since \(day.formatted(Self.dayMonthAndYear(calendar)))"
        }
    }

    /// The primary button's words. Its number is the number of workouts the import is handed.
    var primaryTitle: String {
        "Add \(summary.workoutCount.formatted()) to my history"
    }

    static func monthAndYear(_ calendar: Calendar) -> Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month(.wide).year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }

    static func dayMonthAndYear(_ calendar: Calendar) -> Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }
}
