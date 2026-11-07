import Foundation

/// One of the sample notifications the primer slides in: what Ascend will actually send.
struct NotificationPrimerExample: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case weeklyTarget
        case gearDrop
        case climbDrop
    }

    let kind: Kind
    let title: String
    /// The time label iOS would show: "now", a date, "Today".
    let when: String
    let body: String
    /// The gear image the notification carries, by asset name.
    let thumbnailName: String?

    var id: Kind { kind }
}

/// Everything screen 12 says, decided from what the climber has told Ascend and the unlock
/// catalogue, so the copy is testable without a view.
///
/// The primer promises only what Ascend sends. The weekly-target nudge exists only for a climber
/// who set a target, so without one its example and its clause leave the screen. The design's
/// "That's it." is gone because it is untrue next to the climb-drop and champion pushes. The
/// design's trial example is replaced by the climb-drop one, and nothing here mentions a trial,
/// because whether a paywall offers one is a Superwall setting and no trial reminder is scheduled.
struct NotificationPrimerContent: Equatable, Sendable {
    static let headlineLead = ["We'll keep you"]
    static let headlineAccent = ["on track."]

    let body: String
    let examples: [NotificationPrimerExample]

    var accessibilityHeadline: String {
        (Self.headlineLead + Self.headlineAccent).joined(separator: " ")
    }

    static func make(
        weeklyTargetDays: Int?,
        usualClimbMinutes: Int?,
        catalog: UnlockCatalog,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NotificationPrimerContent {
        let target = weeklyTargetDays.flatMap { (1...7).contains($0) ? $0 : nil }

        var examples: [NotificationPrimerExample] = []
        if let target {
            examples.append(weeklyTargetExample(target: target, usualClimbMinutes: usualClimbMinutes))
        }
        if let gear = gearDropExample(catalog: catalog, now: now, calendar: calendar) {
            examples.append(gear)
        }
        examples.append(climbDropExample)

        return NotificationPrimerContent(body: body(hasTarget: target != nil), examples: examples)
    }

    static func body(hasTarget: Bool) -> String {
        hasTarget ?
            "A nudge when you're short of your weekly target, when new gear drops, and when new climbs open." :
            "A nudge when new gear drops and when new climbs open."
    }

    // MARK: - Examples

    private static func weeklyTargetExample(target: Int, usualClimbMinutes: Int?) -> NotificationPrimerExample {
        let done = target - 1
        let minutes = LocalReminderPlan.quotedMinutes(usualClimbMinutes)
        return NotificationPrimerExample(
            kind: .weeklyTarget,
            title: LocalReminderPlan.weeklyTitle(daysOwed: 1, daysDone: done),
            when: "now",
            body: LocalReminderPlan.weeklyBody(targetDays: target, daysDone: done, minutes: minutes),
            thumbnailName: nil
        )
    }

    /// The event that is on now, else the most recent one that has opened, so the example always
    /// names a real drop. A catalogue with no opened event leaves the example out.
    private static func gearDropExample(
        catalog: UnlockCatalog,
        now: Date,
        calendar: Calendar
    ) -> NotificationPrimerExample? {
        let opened = catalog.openedEvents(by: now, calendar: calendar)
        let event = opened.first { $0.contains(now, calendar: calendar) }
            ?? opened.max { ($0.startsOn.start(in: calendar) ?? .distantPast) < ($1.startsOn.start(in: calendar) ?? .distantPast) }
        guard let event else { return nil }

        let earnsOnFirstClimb = catalog.items(earnedIn: event).contains {
            $0.earn.metric == .climbs && $0.earn.threshold == 1
        }

        return NotificationPrimerExample(
            kind: .gearDrop,
            title: "\(event.monthName) gear just dropped",
            when: shortDate(of: event.startsOn),
            body: earnsOnFirstClimb ?
                "New items for your athlete. Your first climb this month unlocks one." :
                "New items for your athlete. Climb this month to earn them.",
            thumbnailName: catalog.showcase(of: event).first?.shape.thumbnailName
        )
    }

    /// "Nov 1", read off the catalogue's own calendar day. Going through a `Date` and a formatter
    /// would shift the day by the phone's time zone, which is not the zone the catalogue named it in.
    private static func shortDate(of day: UnlockEvent.Day) -> String {
        // Ascend ships in English only, and a bare calendar has no locale to name its months.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        let months = formatter.shortMonthSymbols ?? []
        guard months.indices.contains(day.month - 1) else { return "" }
        return "\(months[day.month - 1]) \(day.day)"
    }

    private static let climbDropExample = NotificationPrimerExample(
        kind: .climbDrop,
        title: "New climb open",
        when: "Today",
        body: "Burj Khalifa just opened. Be the first to the top.",
        thumbnailName: nil
    )
}
