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
    /// Which of the event's days, counted from 1, had a finished climb.
    let climbedDays: Set<Int>
    /// Different calendar days with a finished climb.
    var days: Int { climbedDays.count }
    /// Whether the climber has opened Ascend during the event.
    let visited: Bool

    /// One climb as an event counts it.
    struct Climb: Equatable, Sendable {
        let id: UUID
        let date: Date
        let steps: Int
    }

    init(event: UnlockEvent, items: [UnlockItem], climbs: Int, steps: Int, climbedDays: Set<Int>, visited: Bool) {
        self.event = event
        self.items = items
        self.climbs = climbs
        self.steps = steps
        self.climbedDays = climbedDays
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
            climbedDays: Set(counted.compactMap { climb in
                event.interval(in: calendar).flatMap { calendar.dateComponents([.day], from: $0.start, to: calendar.startOfDay(for: climb.date)).day }.map { $0 + 1 }
            }),
            visited: visited || !counted.isEmpty
        )
    }

    func value(of metric: UnlockItem.Earn.Metric) -> Int {
        switch metric {
        case .visits: visited ? 1 : 0
        case .climbs: climbs
        case .days: days
        case .steps: steps
        case .onDay: 0
        }
    }

    func isEarned(_ item: UnlockItem) -> Bool {
        switch item.earn.metric {
        case .onDay: climbedDays.contains(item.earn.threshold)
        default: value(of: item.earn.metric) >= item.earn.threshold
        }
    }

    /// The items this event's climbing has earned.
    var earned: [AthleteGear] {
        items.filter(isEarned).map(\.shape)
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
