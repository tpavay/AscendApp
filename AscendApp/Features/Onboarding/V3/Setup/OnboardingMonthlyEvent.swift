import Foundation

/// What screen 11 shows, decided from the unlock catalogue and the date.
///
/// Three versions and no fourth: the event that is on right now, an event that starts within a
/// week, or a neutral screen with no gear and nothing dated. An event that has ended is never
/// shown - a month nobody added an event for reads neutral, so nothing on the screen can be stale.
/// An event with no live item this build can draw is no event at all, as it is for `UnlockStore`.
enum OnboardingMonthlyEvent: Equatable {
    case running(Running)
    case comingSoon(Upcoming)
    case neutral

    /// How many days ahead a coming event is announced.
    static let announcementWindowDays = 7

    /// One piece of gear in the showcase row.
    struct Piece: Equatable, Identifiable {
        let id: String
        let gear: AthleteGear
        let name: String
        /// What it takes, or when it opens: "YOURS TODAY", "5 CLIMBS", "OPENS DEC 1".
        let label: String
    }

    struct Running: Equatable {
        let event: UnlockEvent
        let pieces: [Piece]
        /// The event's pieces this build can draw. Never more than the climber can actually see.
        let piecesToEarn: Int
        let daysLeft: Int
        /// The event's last day, for "Ends Nov 30."
        let lastDay: Date?
    }

    struct Upcoming: Equatable {
        let event: UnlockEvent
        let pieces: [Piece]
        let startsOn: Date
    }

    /// The bundled art behind the screen: a themed event's own, else the screen's photograph.
    var heroImageName: String {
        if case .running(let running) = self, running.event.theme?.style == .haunted {
            return "Seasonal/HauntedStairwell"
        }
        return "OnboardingEventHero"
    }

    /// The version for `now`.
    static func resolve(
        catalog: UnlockCatalog,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> OnboardingMonthlyEvent {
        let offered = catalog.events.filter { !catalog.items(earnedIn: $0).isEmpty }

        if let event = offered.first(where: { $0.contains(now, calendar: calendar) }) {
            return .running(running(event, in: catalog, now: now, calendar: calendar))
        }

        let today = calendar.startOfDay(for: now)
        let soonest = offered
            .compactMap { event -> (event: UnlockEvent, start: Date, days: Int)? in
                guard let start = event.interval(in: calendar)?.start, start > now,
                      let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: start)).day,
                      (1...announcementWindowDays).contains(days) else { return nil }
                return (event, start, days)
            }
            .min { $0.start < $1.start }

        guard let soonest else { return .neutral }

        let opens = shortDate(soonest.start, calendar: calendar)
        return .comingSoon(Upcoming(
            event: soonest.event,
            pieces: pieces(for: soonest.event, in: catalog) { _ in "OPENS \(opens.uppercased())" },
            startsOn: soonest.start
        ))
    }

    private static func running(_ event: UnlockEvent, in catalog: UnlockCatalog, now: Date, calendar: Calendar) -> Running {
        let lastDay = event.interval(in: calendar).flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) }

        return Running(
            event: event,
            pieces: pieces(for: event, in: catalog) { item in
                // The item for opening Ascend is the climber's the moment they have it.
                item.earn.metric == .visits
                    ? "YOURS TODAY"
                    : UnlockCopy.threshold(item, in: event).uppercased()
            },
            piecesToEarn: catalog.items(earnedIn: event).count,
            daysLeft: event.daysLeft(now: now, calendar: calendar),
            lastDay: lastDay
        )
    }

    private static func pieces(
        for event: UnlockEvent,
        in catalog: UnlockCatalog,
        label: (UnlockItem) -> String
    ) -> [Piece] {
        catalog.showcase(of: event).map { item in
            Piece(id: item.id, gear: item.shape, name: item.shape.title, label: label(item))
        }
    }

    static func shortDate(_ date: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, calendar: calendar, timeZone: calendar.timeZone)
        style = style.month(.abbreviated).day()
        return date.formatted(style)
    }
}
