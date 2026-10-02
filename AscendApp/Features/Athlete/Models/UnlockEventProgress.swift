import Foundation

/// How far a climber has come in one event: the climbs they finished during it and the steps
/// those climbs added up to, and which of its items that has earned. Pure, so the ladder is
/// tested without a store.
struct UnlockEventProgress: Equatable, Sendable {
    let event: UnlockEvent
    /// The event's live items, in the catalogue's order.
    let items: [UnlockItem]
    let climbs: Int
    let steps: Int
    /// Different calendar days with a finished climb.
    let days: Int
    /// Whether the climber has opened Ascend during the event.
    let visited: Bool

    /// One climb as an event counts it.
    struct Climb: Equatable, Sendable {
        let id: UUID
        let date: Date
        let steps: Int
    }

    init(event: UnlockEvent, items: [UnlockItem], climbs: Int, steps: Int, days: Int, visited: Bool) {
        self.event = event
        self.items = items
        self.climbs = climbs
        self.steps = steps
        self.days = days
        self.visited = visited
    }

    /// Counts the climbs inside the event's days. A climb in the event is also a visit.
    init(event: UnlockEvent, items: [UnlockItem], climbs: [Climb], visited: Bool, calendar: Calendar = .current) {
        let counted = climbs.filter { event.contains($0.date, calendar: calendar) }
        self.init(
            event: event,
            items: items,
            climbs: counted.count,
            steps: counted.reduce(0) { $0 + max($1.steps, 0) },
            days: Set(counted.map { calendar.startOfDay(for: $0.date) }).count,
            visited: visited || !counted.isEmpty
        )
    }

    func value(of metric: UnlockItem.Earn.Metric) -> Int {
        switch metric {
        case .visits: visited ? 1 : 0
        case .climbs: climbs
        case .days: days
        case .steps: steps
        }
    }

    /// The items this event's climbing has earned.
    var earned: [AthleteGear] {
        items.filter { value(of: $0.earn.metric) >= $0.earn.threshold }.map(\.shape)
    }

    /// The next item on each climbing ladder and how much is left to earn it, climbs first.
    var nextItems: [(item: UnlockItem, remaining: Int)] {
        [UnlockItem.Earn.Metric.climbs, .days, .steps].compactMap { metric in
            items
                .filter { $0.earn.metric == metric && value(of: metric) < $0.earn.threshold }
                .min { $0.earn.threshold < $1.earn.threshold }
                .map { ($0, $0.earn.threshold - value(of: metric)) }
        }
    }

    /// What the climb that brought the climber from `before` to here earned.
    func newlyEarned(since before: UnlockEventProgress?) -> [AthleteGear] {
        let had = Set(before?.earned ?? [])
        return earned.filter { !had.contains($0) }
    }
}
