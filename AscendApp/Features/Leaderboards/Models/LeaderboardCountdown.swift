import Foundation

/// How long a board has left, as every board's window line and Home's rank tile say it:
/// `ENDS IN 2D 14H`, hours and minutes on the last day, and days only on the yearly
/// board until its last day. The last day turns gold - the crown is on the line.
///
/// All-time never ends, so it has no countdown.
struct LeaderboardCountdown: Equatable, Sendable {
    /// `ENDS IN 2D 14H`
    let text: String
    /// `4H 12M LEFT`, for the pinned row's chase line on the last day.
    let remainingText: String
    let isLastDay: Bool
    let endsAt: Date

    static func make(period: LeaderboardPeriod, now: Date) -> LeaderboardCountdown? {
        guard period.timeFrame != .allTime, let endsAt = period.endAt else { return nil }
        let remaining = endsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }

        let totalMinutes = Int((remaining / 60).rounded(.up))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        let isLastDay = remaining < 24 * 60 * 60

        let span: String
        if isLastDay {
            let lastDayHours = totalMinutes / 60
            span = lastDayHours > 0 ? "\(lastDayHours)H \(minutes)M" : "\(max(minutes, 1))M"
        } else if period.timeFrame == .yearly {
            span = "\(days)D"
        } else {
            span = "\(days)D \(hours)H"
        }

        return LeaderboardCountdown(
            text: "ENDS IN \(span)",
            remainingText: "\(span) LEFT",
            isLastDay: isLastDay,
            endsAt: endsAt
        )
    }

    /// The end in the climber's own time, for VoiceOver: "Ends Sunday at 7:00 PM", with the
    /// date as well once the end is more than a week out.
    func accessibilityLabel(
        now: Date = .now,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let base = Date.FormatStyle(locale: locale, timeZone: timeZone)
        let dayStyle = endsAt.timeIntervalSince(now) > 6 * 24 * 60 * 60
            ? base.weekday(.wide).month(.wide).day()
            : base.weekday(.wide)
        return "Ends \(endsAt.formatted(dayStyle)) at \(endsAt.formatted(base.hour().minute()))"
    }
}
