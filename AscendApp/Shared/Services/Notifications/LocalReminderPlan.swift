import Foundation

/// One local notification Ascend asks iOS to deliver, already worded and dated.
struct LocalReminderRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
}

/// What the local reminders say and when they fire, decided from facts alone.
///
/// Pure on purpose: a reminder's wording and moment depend on the climber's target, the days they
/// have already climbed this week and the clock, and none of that needs a notification center to
/// reason about. ``LocalReminderScheduler`` carries the plan out.
enum LocalReminderPlan {
    static let weeklyTargetIdentifierPrefix = "ascend.reminder.weekly-target."
    static let thisWeekIdentifier = weeklyTargetIdentifierPrefix + "this-week"
    static let nextWeekIdentifier = weeklyTargetIdentifierPrefix + "next-week"
    static let trialEndingIdentifier = "ascend.reminder.trial-ending"

    /// Every identifier the weekly-target reminder may hold, so a reschedule clears all of them.
    static let weeklyTargetIdentifiers = [thisWeekIdentifier, nextWeekIdentifier]

    /// The hour of day, in the climber's own time zone, the weekly nudge arrives at: after work,
    /// before the evening is spent.
    static let weeklyReminderHour = 18

    /// The day of the gift's seven free days the trial reminder lands on, which is two days of the
    /// trial still to run.
    static let trialReminderDay = 5

    /// The climb length quoted when the climber has not told Ascend a usual one.
    static let defaultMinutes = 20

    // MARK: - Weekly target

    /// The nudges for a climber's weekly target: one for this week if they are behind, one for
    /// next week that assumes nothing is climbed in between.
    ///
    /// A nudge fires on the last day a week can still be saved: the day the days left, today
    /// included, equal the days still owed. Earlier than that it would nag a climber who is on
    /// pace; later, nothing could still be done about it. A week that is already met, or whose
    /// last day has passed, gets no nudge. Next week's exists because a climber who does not open
    /// the app again would otherwise never hear from it, and it is replaced by the real one the
    /// next time anything reconciles.
    ///
    /// - Parameters:
    ///   - targetDays: The climber's days a week, 1 to 7. Nil, or out of range, schedules nothing.
    ///   - climbDates: When the climber climbed. Only this week's count, and each day counts once.
    ///   - usualClimbMinutes: Quoted in the body. Nil quotes ``defaultMinutes``.
    static func weeklyTarget(
        targetDays: Int?,
        climbDates: [Date],
        usualClimbMinutes: Int?,
        now: Date,
        calendar: Calendar = WeekConfiguration.calendar()
    ) -> [LocalReminderRequest] {
        guard let targetDays, (1...7).contains(targetDays),
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return []
        }

        let minutes = quotedMinutes(usualClimbMinutes)
        let daysDoneThisWeek = Set(
            climbDates
                .filter { thisWeek.contains($0) }
                .map { calendar.startOfDay(for: $0) }
        ).count

        var requests: [LocalReminderRequest] = []
        for weekOffset in 0...1 {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: thisWeek.start) else {
                continue
            }

            let daysDone = weekOffset == 0 ? daysDoneThisWeek : 0
            let daysOwed = targetDays - daysDone
            guard daysOwed > 0,
                  let day = calendar.date(byAdding: .day, value: 7 - daysOwed, to: weekStart),
                  let fireDate = calendar.date(bySettingHour: weeklyReminderHour, minute: 0, second: 0, of: day),
                  fireDate > now else {
                continue
            }

            requests.append(
                LocalReminderRequest(
                    identifier: weekOffset == 0 ? thisWeekIdentifier : nextWeekIdentifier,
                    title: weeklyTitle(daysOwed: daysOwed, daysDone: daysDone),
                    body: weeklyBody(targetDays: targetDays, daysDone: daysDone, minutes: minutes),
                    fireDate: fireDate
                )
            )
        }

        return requests
    }

    static func weeklyTitle(daysOwed: Int, daysDone: Int) -> String {
        if daysOwed == 1 {
            return "One climb from your target"
        }
        return daysDone == 0 ? "Your week is still open" : "\(daysOwed) climbs from your target"
    }

    static func weeklyBody(targetDays: Int, daysDone: Int, minutes: Int) -> String {
        if daysDone == 0 {
            let days = targetDays == 1 ? "1 day" : "\(targetDays) days"
            return "Your target is \(days) a week. \(minutes) minutes gets you started."
        }
        return "\(daysDone) of \(targetDays) days done this week. \(minutes) minutes gets it done."
    }

    static func quotedMinutes(_ usualClimbMinutes: Int?) -> Int {
        guard let usualClimbMinutes, (5...120).contains(usualClimbMinutes) else { return defaultMinutes }
        return usualClimbMinutes
    }

    // MARK: - Trial ending

    /// The reminder two days before a free trial ends, or nothing when no trial started.
    ///
    /// It fires exactly 5 days after the trial began, the same time of day the climber started it,
    /// so it never claims a precision the trial does not have. A trial that began long enough ago
    /// for that moment to have passed gets nothing.
    static func trialEnding(
        trialStartedAt: Date?,
        now: Date,
        calendar: Calendar = WeekConfiguration.calendar()
    ) -> LocalReminderRequest? {
        guard let trialStartedAt,
              let fireDate = calendar.date(byAdding: .day, value: trialReminderDay, to: trialStartedAt),
              fireDate > now else {
            return nil
        }

        return LocalReminderRequest(
            identifier: trialEndingIdentifier,
            title: "Your free week ends in 2 days",
            body: "No surprise charges. Cancel any time in Settings.",
            fireDate: fireDate
        )
    }
}
